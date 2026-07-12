--! Previous: sha1:48c94afc437e9b8b05394527e38d1c19a2f1806d
--! Hash: sha1:9e859d1596d9cd426a382d1dd96c47540af2e0c0

-- Fix most_active_players: joining against the latest_ratings view forced Postgres
-- to materialize the whole view (full-table DISTINCT ON, sorting 20M+ rows to disk,
-- ~26s) before joining it against the tiny `active` result. Replaced with a
-- correlated subquery that runs only p_limit times, each a sub-ms indexed lookup.
create index if not exists ratings_fideid_type_period_idx
    on ratings (fideid, rating_type, period desc);

drop function if exists most_active_players(integer, text, rating_type, boolean, integer, integer, integer);

create function most_active_players(
    p_year        integer     default null,
    p_country     text        default null,
    p_rating_type rating_type default null,
    p_titled      boolean     default null,
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
    rating      integer
)
language sql stable
as $$
    with active as (
        select
            r.fideid,
            max(r.name)    as name,
            max(r.country) as country,
            max(r.title)   as title,
            sum(coalesce(r.games, 0)) as total_games
        from ratings r
        where (p_year is null or (
                  r.period >= make_date(p_year, 1, 1)
                  and r.period < make_date(p_year + 1, 1, 1)
              ))
          and (p_country is null or r.country = p_country)
          and (p_rating_type is null or r.rating_type = p_rating_type)
          and (p_titled is null or (r.title is not null and r.title <> '') = p_titled)
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
            order by r2.period desc
            limit 1
        ) as rating
    from active a
    order by a.total_games desc;
$$;
