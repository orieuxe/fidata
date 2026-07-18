--! Previous: sha1:7ba04edebb5e2661166dbcdb84d59346517fb6a1
--! Hash: sha1:abcb1b21eb40be364121d3a25f2e9761d5b31b7f

-- Male/female filter (see TODO.md) -- ratings.sex was already scraped, just
-- not exposed as a p_sex param anywhere. rating_change_snapshots is a frozen
-- copy of ratings columns per (bucket, fideid, rating_type) (see 000009.sql),
-- so it needs its own sex column, backfilled once here since the 'rolling'
-- bucket is the only one the scraper ever rewrites -- frozen year buckets
-- would otherwise carry a null sex forever.
alter table rating_change_snapshots add column if not exists sex text;

update rating_change_snapshots s
set sex = r.sex
from (
    select distinct on (fideid, rating_type) fideid, rating_type, sex
    from ratings
    where sex is not null
    order by fideid, rating_type, period desc
) r
where r.fideid = s.fideid and r.rating_type = s.rating_type and s.sex is null;

-- p_sex is inserted mid-signature (next to p_country) rather than appended,
-- so `create or replace` doesn't overload the old signature -- Postgres
-- resolves overloads by argument list, and the old one would otherwise stay
-- callable and ambiguous with the new one for any named-param PostgREST call.
drop function if exists public.top_players(integer, text, rating_type, text[], integer, integer, integer);
drop function if exists public.rating_change(date, date, text, rating_type, text[], integer, integer, text, integer, integer);
drop function if exists public.most_active_players(date, date, text, rating_type, text[], integer, integer, integer, integer);

--! Included functions/top_players.sql
-- Top N players by rating, filterable by year/country/time-control/title/age.
-- Exposed at /rpc/top_players.
--
-- p_year null or the current year -> reads latest_ratings (small, indexed
-- materialized view, see 000001.sql) instead of a live DISTINCT ON over the
-- full ratings table, which was the same ~35s-class scan latest_ratings was
-- introduced to avoid. Only a genuinely historical p_year (a past year's
-- leaderboard) falls back to scanning ratings directly.
-- Both branches' WHERE conditions are constant (don't reference table
-- columns), so Postgres proves one side always-false and skips scanning it
-- entirely instead of paying for both.
create or replace function public.top_players(p_year integer default null::integer, p_country text default null::text, p_sex text default null::text, p_rating_type rating_type default 'standard'::rating_type, p_titles text[] default null::text[], p_min_age integer default null::integer, p_max_age integer default null::integer, p_limit integer default 25)
 returns table(fideid integer, name text, country text, title text, rating integer, age integer)
 language sql
 stable
as $function$
    with filtered as (
        select fideid, name, country, title, birthday, rating
        from latest_ratings
        where rating_type = p_rating_type
          and (p_year is null or p_year >= extract(year from current_date)::int)
          and coalesce(flag, '') not like '%i%'
          and (p_country is null or country = p_country)
          and (p_sex is null or sex = p_sex)
          and (
              p_titles is null or cardinality(p_titles) = 0
              or title = any(p_titles)
              or ('UNTITLED' = any(p_titles) and (title is null or title = ''))
          )
        union all
        select r.fideid, r.name, r.country, r.title, r.birthday, r.rating
        from (
            select distinct on (r.fideid)
                r.fideid, r.name, r.country, r.title, r.birthday, r.rating
            from ratings r
            where p_year is not null and p_year < extract(year from current_date)::int
              and r.rating_type = p_rating_type
              and r.period <= make_date(p_year, 12, 1)
              and coalesce(r.flag, '') not like '%i%'
              and (p_country is null or r.country = p_country)
              and (p_sex is null or r.sex = p_sex)
              and (
                  p_titles is null or cardinality(p_titles) = 0
                  or r.title = any(p_titles)
                  or ('UNTITLED' = any(p_titles) and (r.title is null or r.title = ''))
              )
            order by r.fideid, r.period desc
        ) r
    )
    select fideid, name, country, title, rating,
           coalesce(p_year, extract(year from current_date)::int) - birthday as age
    from filtered
    where rating is not null
      and (p_min_age is null or (coalesce(p_year, extract(year from current_date)::int) - birthday) >= p_min_age)
      and (p_max_age is null or (coalesce(p_year, extract(year from current_date)::int) - birthday) <= p_max_age)
    order by rating desc
    limit p_limit;
$function$
;
--! EndIncluded functions/top_players.sql
--! Included functions/rating_change.sql
-- Biggest rating gainers/losers over a period ("movers" page). Exposed at
-- /rpc/rating_change.
--
-- Reads rating_change_snapshots (see 000009.sql) when p_from/p_to match one
-- of the two shapes the frontend actually sends (rolling 12 months, or a
-- full calendar year) and that bucket has been precomputed. Falls back to
-- the original live scan otherwise -- a custom range via direct API use, or
-- a year that hasn't been frozen yet (the current in-progress year before
-- December, or a year older than this feature).
create or replace function public.rating_change(p_from date, p_to date, p_country text default null::text, p_sex text default null::text, p_rating_type rating_type default null::rating_type, p_titles text[] default null::text[], p_min_age integer default null::integer, p_max_age integer default null::integer, p_direction text default 'gain'::text, p_limit integer default 50, p_offset integer default 0)
 returns table(fideid integer, name text, country text, title text, start_rating integer, end_rating integer, delta integer, age integer)
 language plpgsql
 stable
as $function$
declare
    v_bucket text;
    v_today_to date := (date_trunc('month', current_date) + interval '1 month')::date;
    v_today_from date := (date_trunc('month', current_date) + interval '1 month' - interval '12 months')::date;
    v_age_year int := extract(year from p_to - interval '1 day')::int;
begin
    if p_rating_type is not null and p_from = v_today_from and p_to = v_today_to then
        v_bucket := 'rolling';
    elsif p_rating_type is not null
          and extract(month from p_from) = 1 and extract(day from p_from) = 1
          and p_to = p_from + interval '1 year' then
        v_bucket := extract(year from p_from)::text;
    end if;

    if v_bucket is not null and exists (
        select 1 from rating_change_snapshots where bucket = v_bucket and rating_type = p_rating_type limit 1
    ) then
        return query
            select
                s.fideid, s.name, s.country, s.title, s.start_rating, s.end_rating,
                s.end_rating - s.start_rating as delta,
                v_age_year - s.birthday as age
            from rating_change_snapshots s
            where s.bucket = v_bucket
              and s.rating_type = p_rating_type
              and (p_country is null or s.country = p_country)
              and (p_sex is null or s.sex = p_sex)
              and (
                  p_titles is null or cardinality(p_titles) = 0
                  or s.title = any(p_titles)
                  or ('UNTITLED' = any(p_titles) and (s.title is null or s.title = ''))
              )
              and (p_min_age is null or (v_age_year - s.birthday) >= p_min_age)
              and (p_max_age is null or (v_age_year - s.birthday) <= p_max_age)
            order by (case when p_direction = 'loss' then s.end_rating - s.start_rating
                           else s.start_rating - s.end_rating end) asc
            limit p_limit
            offset p_offset;
        return;
    end if;

    return query
        with candidates as (
            select
                r.fideid,
                max(r.name)     as name,
                max(r.country)  as country,
                max(r.title)    as title,
                max(r.birthday) as birthday
            from ratings r
            where r.period >= p_from
              and r.period < p_to
              and r.games > 0
              and (p_country is null or r.country = p_country)
              and (p_sex is null or r.sex = p_sex)
              and (p_rating_type is null or r.rating_type = p_rating_type)
              and (
                  p_titles is null or cardinality(p_titles) = 0
                  or r.title = any(p_titles)
                  or ('UNTITLED' = any(p_titles) and (r.title is null or r.title = ''))
              )
              and (p_min_age is null or (v_age_year - r.birthday) >= p_min_age)
              and (p_max_age is null or (v_age_year - r.birthday) <= p_max_age)
            group by r.fideid
        ),
        changes as materialized (
            select
                c.fideid, c.name, c.country, c.title, c.birthday,
                (
                    select r2.rating from ratings r2
                    where r2.fideid = c.fideid
                      and r2.rating_type = coalesce(p_rating_type, 'standard')
                      and r2.period >= p_from
                      and r2.period < p_to
                    order by r2.period asc
                    limit 1
                ) as start_rating,
                (
                    select r2.rating from ratings r2
                    where r2.fideid = c.fideid
                      and r2.rating_type = coalesce(p_rating_type, 'standard')
                      and r2.period < p_to
                      and r2.period <= current_date
                    order by r2.period desc
                    limit 1
                ) as end_rating
            from candidates c
        )
        select changes.fideid, changes.name, changes.country, changes.title, changes.start_rating, changes.end_rating,
               changes.end_rating - changes.start_rating as delta,
               v_age_year - changes.birthday as age
        from changes
        where changes.start_rating is not null and changes.end_rating is not null
        order by (case when p_direction = 'loss' then changes.end_rating - changes.start_rating
                       else changes.start_rating - changes.end_rating end) asc
        limit p_limit
        offset p_offset;
end;
$function$
;
--! EndIncluded functions/rating_change.sql
--! Included functions/most_active_players.sql
-- Most active players by games played ("active" page). Exposed at
-- /rpc/most_active_players.
--
-- Reads rating_change_snapshots (see 000009.sql, 000010.sql) when
-- p_from/p_to match one of the two shapes the frontend actually sends
-- (rolling 12 months, or a full calendar year) and that bucket has been
-- precomputed -- same table rating_change already uses, total_games is
-- just another column off the same GROUP BY fideid, rating_type. Falls
-- back to the original live scan otherwise: a custom range via direct API
-- use, an unfrozen year, or the "all time" (p_from/p_to both null) case,
-- which stays a genuinely live O(whole table) aggregate -- see the
-- ponytail note this function used to carry (~75s, upgrade to a rollup
-- table if that becomes a real access pattern -- it isn't the default and
-- isn't covered here).
create or replace function public.most_active_players(p_from date default null::date, p_to date default null::date, p_country text default null::text, p_sex text default null::text, p_rating_type rating_type default null::rating_type, p_titles text[] default null::text[], p_min_age integer default null::integer, p_max_age integer default null::integer, p_limit integer default 50, p_offset integer default 0)
 returns table(fideid integer, name text, country text, title text, total_games bigint, rating integer, age integer)
 language plpgsql
 stable
as $function$
declare
    v_bucket text;
    v_today_to date := (date_trunc('month', current_date) + interval '1 month')::date;
    v_today_from date := (date_trunc('month', current_date) + interval '1 month' - interval '12 months')::date;
    v_age_year int := extract(year from coalesce(p_to - interval '1 day', current_date))::int;
begin
    if p_rating_type is not null and p_from = v_today_from and p_to = v_today_to then
        v_bucket := 'rolling';
    elsif p_rating_type is not null and p_from is not null and p_to is not null
          and extract(month from p_from) = 1 and extract(day from p_from) = 1
          and p_to = p_from + interval '1 year' then
        v_bucket := extract(year from p_from)::text;
    end if;

    if v_bucket is not null and exists (
        select 1 from rating_change_snapshots where bucket = v_bucket and rating_type = p_rating_type limit 1
    ) then
        return query
            select
                s.fideid, s.name, s.country, s.title, s.total_games, s.end_rating,
                v_age_year - s.birthday as age
            from rating_change_snapshots s
            where s.bucket = v_bucket
              and s.rating_type = p_rating_type
              and (p_country is null or s.country = p_country)
              and (p_sex is null or s.sex = p_sex)
              and (
                  p_titles is null or cardinality(p_titles) = 0
                  or s.title = any(p_titles)
                  or ('UNTITLED' = any(p_titles) and (s.title is null or s.title = ''))
              )
              and (p_min_age is null or (v_age_year - s.birthday) >= p_min_age)
              and (p_max_age is null or (v_age_year - s.birthday) <= p_max_age)
            order by s.total_games desc
            limit p_limit
            offset p_offset;
        return;
    end if;

    return query
        with active as (
            select
                r.fideid,
                max(r.name)     as name,
                max(r.country)  as country,
                max(r.title)    as title,
                max(r.birthday) as birthday,
                sum(coalesce(r.games, 0)) as total_games
            from ratings r
            where r.period >= coalesce(p_from, '-infinity'::date)
              and r.period <  coalesce(p_to, 'infinity'::date)
              and (p_country is null or r.country = p_country)
              and (p_sex is null or r.sex = p_sex)
              and (p_rating_type is null or r.rating_type = p_rating_type)
              and (
                  p_titles is null or cardinality(p_titles) = 0
                  or r.title = any(p_titles)
                  or ('UNTITLED' = any(p_titles) and (r.title is null or r.title = ''))
              )
              and (p_min_age is null or (v_age_year - r.birthday) >= p_min_age)
              and (p_max_age is null or (v_age_year - r.birthday) <= p_max_age)
            group by r.fideid
            order by total_games desc
            limit p_limit
            offset p_offset
        )
        select
            a.fideid, a.name, a.country, a.title, a.total_games,
            (
                select r2.rating
                from ratings r2
                where r2.fideid = a.fideid
                  and r2.rating_type = coalesce(p_rating_type, 'standard')
                  and r2.period < coalesce(p_to, 'infinity'::date)
                  and r2.period <= current_date
                order by r2.period desc
                limit 1
            ) as rating,
            v_age_year - a.birthday as age
        from active a
        order by a.total_games desc;
end;
$function$
;
--! EndIncluded functions/most_active_players.sql
