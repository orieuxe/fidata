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
