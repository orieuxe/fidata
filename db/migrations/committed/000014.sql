--! Previous: sha1:5b8feee0467021518f3cae7a919baa730535fb94
--! Hash: sha1:1f8056857844036f807ee6da6ef999f1b9549981

-- Enter migration here

-- Precomputed top_players() leaderboard per past calendar year (see
-- top_players.sql) -- same "latest rating as of year end" the live
-- DISTINCT ON fallback computes, but done once here instead of per
-- request. Only includes players who played at least one game in the two
-- years leading up to that year end (per-year equivalent of the flag='i'
-- 2-year-inactive filter the live/current-year branches use, which is
-- itself relative to today and so can't be reused for a past year).
create table if not exists top_players_snapshots (
    bucket       text not null,
    fideid       integer not null,
    rating_type  rating_type not null,
    name         text not null,
    country      text,
    sex          text,
    title        text,
    birthday     integer,
    rating       integer,
    primary key (bucket, fideid, rating_type)
);

create index if not exists top_players_snapshots_type_rating_idx
    on top_players_snapshots (bucket, rating_type, rating desc);
create index if not exists top_players_snapshots_type_country_rating_idx
    on top_players_snapshots (bucket, rating_type, country, rating desc);

grant select on top_players_snapshots to web_anon;

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
          and (
              p_titles is null or cardinality(p_titles) = 0
              or title = any(p_titles)
              or ('UNTITLED' = any(p_titles) and (title is null or title = ''))
          )
        union all
        select s.fideid, s.name, s.country, s.title, s.birthday, s.rating
        from top_players_snapshots s
        where p_year is not null and p_year < extract(year from current_date)::int
          and s.bucket = p_year::text
          and s.rating_type = p_rating_type
          and (p_country is null or s.country = p_country)
          and (p_sex is null or s.sex = p_sex)
          and (
              p_titles is null or cardinality(p_titles) = 0
              or s.title = any(p_titles)
              or ('UNTITLED' = any(p_titles) and (s.title is null or s.title = ''))
          )
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

-- One-time backfill, every year from 2001 to last year, all three rating
-- types (75 combos) -- top_players_snapshots starts empty, and unlike
-- rating_change_snapshots there's no existing per-year data to build on.
do $$
declare
    rt rating_type;
    y int;
    current_y int := extract(year from current_date)::int;
begin
    foreach rt in array enum_range(null::rating_type) loop
        for y in 2001..(current_y - 1) loop
            insert into top_players_snapshots
              (bucket, fideid, rating_type, name, country, sex, title, birthday, rating)
            with latest as (
                select distinct on (fideid)
                    fideid, name, country, sex, title, birthday, rating
                from ratings
                where rating_type = rt and period <= make_date(y, 12, 1)
                order by fideid, period desc
            ),
            active as (
                select distinct fideid
                from ratings
                where rating_type = rt
                  and games > 0
                  and period > make_date(y, 12, 1) - interval '2 years'
                  and period <= make_date(y, 12, 1)
            )
            select y::text, l.fideid, rt, l.name, l.country, l.sex, l.title, l.birthday, l.rating
            from latest l
            join active a using (fideid)
            where l.rating is not null
            on conflict (bucket, fideid, rating_type) do nothing;
        end loop;
    end loop;
end $$;
