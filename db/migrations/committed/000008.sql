--! Previous: sha1:74d845a2991da439ba561d09660a73029188655b
--! Hash: sha1:4f60512d9f8e4c3ddeea23c3cfbde4e442705435

-- Perf fix: PostgREST calls RPC functions through a LATERAL + json_to_record
-- wrapper (SELECT ... FROM json_to_record($1) AS _(...), LATERAL fn(...)),
-- which turns p_year into a correlated lateral reference instead of a
-- plan-time constant. With the "p_year is null or (period >= .. and period
-- < ..)" OR-branch, Postgres can no longer prove the period range is
-- sargable in that context and falls back to a full seq scan of the whole
-- ratings table (confirmed via EXPLAIN on the exact query PostgREST sends:
-- Seq Scan removing 62M+ of 64M rows) -- 8s+ instead of the <2s a direct
-- literal-parameter query gets. Rewriting the optional-year filter as a
-- single always-applicable range (coalescing to -infinity/infinity when
-- p_year is null) keeps it index-sargable no matter how the parameter is
-- bound.
drop function if exists most_active_players(integer, text, rating_type, text[], integer, integer, integer);

create function most_active_players(
    p_year        integer     default null,
    p_country     text        default null,
    p_rating_type rating_type default null,
    p_titles      text[]      default null,
    p_min_age     integer     default null,
    p_max_age     integer     default null,
    p_limit       integer     default 50
)
returns table (
    fideid      integer,
    name        text,
    country     text,
    title       text,
    total_games bigint,
    rating      integer,
    age         integer
)
language sql stable
as $$
    with active as (
        select
            r.fideid,
            max(r.name)     as name,
            max(r.country)  as country,
            max(r.title)    as title,
            max(r.birthday) as birthday,
            sum(coalesce(r.games, 0)) as total_games
        from ratings r
        where r.period >= coalesce(make_date(p_year, 1, 1), '-infinity'::date)
          and r.period <  coalesce(make_date(p_year + 1, 1, 1), 'infinity'::date)
          and (p_country is null or r.country = p_country)
          and (p_rating_type is null or r.rating_type = p_rating_type)
          and (
              p_titles is null or cardinality(p_titles) = 0
              or r.title = any(p_titles)
              or ('UNTITLED' = any(p_titles) and (r.title is null or r.title = ''))
          )
          and (p_min_age is null or (
                  extract(year from r.period)::int - r.birthday
              ) >= p_min_age)
          and (p_max_age is null or (
                  extract(year from r.period)::int - r.birthday
              ) <= p_max_age)
        group by r.fideid
        order by total_games desc
        limit p_limit
    )
    select
        a.fideid, a.name, a.country, a.title, a.total_games,
        (
            select r2.rating
            from ratings r2
            where r2.fideid = a.fideid
              and r2.rating_type = coalesce(p_rating_type, 'standard')
              and r2.period <= least(make_date(p_year, 12, 1), current_date)
            order by r2.period desc
            limit 1
        ) as rating,
        coalesce(p_year, extract(year from current_date)::int) - a.birthday as age
    from active a
    order by a.total_games desc;
$$;
