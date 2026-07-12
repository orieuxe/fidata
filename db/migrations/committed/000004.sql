--! Previous: sha1:6cf32ac4250429c9e7ac022a5e70fed729deb7eb
--! Hash: sha1:c62022657c56a0f5d042fa396ad53dc56e94aad2

-- Show each player's rating as of December of the searched year, not their
-- latest/current rating (title already came from rows filtered to p_year, so
-- it was already "title within that year" — only rating needs this fix).
-- For the current year (no December list yet) or no year filter at all, falls
-- back to the latest period available (least() ignores a null p_year).
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
        ) as rating
    from active a
    order by a.total_games desc;
$$;
