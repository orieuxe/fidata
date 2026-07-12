--! Previous: sha1:b48d09b35bad3331936eb369c8bd8e4eed96ce7c
--! Hash: sha1:599cf47e25a7b85608f5c3c3b4c1f1f7b24e5efd

-- Add age to most_active_players and rating_change outputs.
-- Age = the reference year already used for age filtering minus birthday
-- (year for rating_change; p_year, or current year when unfiltered, for
-- most_active_players) — same expression the filters already compute.
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
        ) as rating,
        coalesce(p_year, extract(year from current_date)::int) - a.birthday as age
    from active a
    order by a.total_games desc;
$$;

drop function if exists rating_change(integer, text, rating_type, text[], integer, integer, text, integer);

create function rating_change(
    p_year        integer,
    p_country     text        default null,
    p_rating_type rating_type default null,
    p_titles      text[]      default null,
    p_min_age     integer     default null,
    p_max_age     integer     default null,
    p_direction   text        default 'gain',
    p_limit       integer     default 50
)
returns table (
    fideid       integer,
    name         text,
    country      text,
    title        text,
    start_rating integer,
    end_rating   integer,
    delta        integer,
    age          integer
)
language sql stable
as $$
    with candidates as (
        select
            r.fideid,
            max(r.name)     as name,
            max(r.country)  as country,
            max(r.title)    as title,
            max(r.birthday) as birthday
        from ratings r
        where r.period >= make_date(p_year, 1, 1)
          and r.period < make_date(p_year + 1, 1, 1)
          and r.games > 0
          and (p_country is null or r.country = p_country)
          and (p_rating_type is null or r.rating_type = p_rating_type)
          and (
              p_titles is null or cardinality(p_titles) = 0
              or r.title = any(p_titles)
              or ('UNTITLED' = any(p_titles) and (r.title is null or r.title = ''))
          )
          and (p_min_age is null or (p_year - r.birthday) >= p_min_age)
          and (p_max_age is null or (p_year - r.birthday) <= p_max_age)
        group by r.fideid
    ),
    changes as materialized (
        select
            c.fideid, c.name, c.country, c.title, c.birthday,
            (
                select r2.rating from ratings r2
                where r2.fideid = c.fideid
                  and r2.rating_type = coalesce(p_rating_type, 'standard')
                  and r2.period >= make_date(p_year, 1, 1)
                  and r2.period < make_date(p_year + 1, 1, 1)
                order by r2.period asc
                limit 1
            ) as start_rating,
            (
                select r2.rating from ratings r2
                where r2.fideid = c.fideid
                  and r2.rating_type = coalesce(p_rating_type, 'standard')
                  and r2.period >= make_date(p_year, 1, 1)
                  and r2.period <= least(make_date(p_year, 12, 1), current_date)
                order by r2.period desc
                limit 1
            ) as end_rating
        from candidates c
    )
    select fideid, name, country, title, start_rating, end_rating,
           end_rating - start_rating as delta,
           p_year - birthday as age
    from changes
    where start_rating is not null and end_rating is not null
    order by (case when p_direction = 'loss' then end_rating - start_rating
                   else start_rating - end_rating end) asc
    limit p_limit;
$$;
