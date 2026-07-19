--! Previous: sha1:0e57ddea8b184f61c45887456d474ba3385199f9
--! Hash: sha1:99f7989a02ce7bcaa8c4cd832c331800a89201d4

-- Enter migration here

--! Included functions/title_matches.sql
-- Shared title-filter predicate for most_active_players/rating_change/top_players
-- (each repeats this OR-chain 2-3x per query, once per source table). Plain SQL
-- + immutable so Postgres inlines it -- verified via EXPLAIN that it produces
-- the exact same index scan on ratings_title_idx as the literal expression.
create or replace function public.title_matches(p_title text, p_titles text[])
 returns boolean
 language sql
 immutable
as $function$
    select p_titles is null or cardinality(p_titles) = 0
        or p_title = any(p_titles)
        or ('UNTITLED' = any(p_titles) and (p_title is null or p_title = ''))
$function$
;
--! EndIncluded functions/title_matches.sql
--! Included functions/most_active_players.sql
-- Most active players by games played ("active" page). Exposed at
-- /rpc/most_active_players.
--
-- Reads rating_change_snapshots (see 000009.sql, 000010.sql, 000013.sql)
-- when p_from/p_to match one of the shapes the frontend actually sends
-- (all time, rolling 12 months, or a full calendar year) and that bucket
-- has been precomputed -- same table rating_change already uses,
-- total_games is just another column off the same GROUP BY fideid,
-- rating_type. Falls back to the original live scan otherwise: a custom
-- range via direct API use, or an unfrozen year.
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
    if p_rating_type is not null and p_from is null and p_to is null then
        v_bucket := 'all';
    elsif p_rating_type is not null and p_from = v_today_from and p_to = v_today_to then
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
              and title_matches(s.title, p_titles)
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
              and title_matches(r.title, p_titles)
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
              and title_matches(s.title, p_titles)
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
              and title_matches(r.title, p_titles)
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
--! Included functions/top_players.sql
-- Top N players by rating, filterable by year/country/time-control/title/age.
-- Exposed at /rpc/top_players.
--
-- p_year null or the current year -> reads latest_ratings (small, indexed
-- materialized view, see 000001.sql) instead of a live DISTINCT ON over the
-- full ratings table, which was the same ~35s-class scan latest_ratings was
-- introduced to avoid.
-- A past year with a precomputed top_players_snapshots bucket (see
-- 000014.sql -- every year from 2001 to last year, backfilled once) reads
-- that instead: same DISTINCT ON scan, done once at scrape time rather than
-- per request. Only a past year that hasn't been backfilled (shouldn't
-- happen in practice) falls back to scanning ratings live.
-- The first two branches' WHERE conditions are constant (don't reference
-- table columns), so Postgres proves whichever doesn't apply is
-- always-false and skips it. The live-fallback branch's extra `not exists`
-- guard only depends on p_year/p_rating_type too (not on r.*), so Postgres
-- evaluates it once as a one-time filter rather than per row -- it's
-- skipped just as cheaply once a bucket exists for that year.
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
          and title_matches(title, p_titles)
        union all
        select s.fideid, s.name, s.country, s.title, s.birthday, s.rating
        from top_players_snapshots s
        where p_year is not null and p_year < extract(year from current_date)::int
          and s.bucket = p_year::text
          and s.rating_type = p_rating_type
          and (p_country is null or s.country = p_country)
          and (p_sex is null or s.sex = p_sex)
          and title_matches(s.title, p_titles)
        union all
        select r.fideid, r.name, r.country, r.title, r.birthday, r.rating
        from (
            select distinct on (r.fideid)
                r.fideid, r.name, r.country, r.title, r.birthday, r.rating
            from ratings r
            where p_year is not null and p_year < extract(year from current_date)::int
              and not exists (
                  select 1 from top_players_snapshots s
                  where s.bucket = p_year::text and s.rating_type = p_rating_type
              )
              and r.rating_type = p_rating_type
              and r.period <= make_date(p_year, 12, 1)
              and coalesce(r.flag, '') not like '%i%'
              and (p_country is null or r.country = p_country)
              and (p_sex is null or r.sex = p_sex)
              and title_matches(r.title, p_titles)
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
