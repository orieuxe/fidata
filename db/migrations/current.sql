-- Enter migration here

-- Revert the p_name experiment on top_players: search now has its own
-- function below (needs all 3 cadences per row + offset pagination, which
-- doesn't fit top_players' single-rating-type shape). Restores the original
-- signature so PostgREST only ever sees one top_players overload.
drop function if exists top_players(integer, text, rating_type, text[], integer, integer, integer, text);

create or replace function top_players(
    p_year        integer     default null,
    p_country     text        default null,
    p_rating_type rating_type default 'standard',
    p_titles      text[]      default null,
    p_min_age     integer     default null,
    p_max_age     integer     default null,
    p_limit       integer     default 25
)
returns table (
    fideid  integer,
    name    text,
    country text,
    title   text,
    rating  integer,
    age     integer
)
language sql stable
as $$
    with filtered as (
        select distinct on (r.fideid)
            r.fideid, r.name, r.country, r.title, r.birthday, r.rating
        from ratings r
        where r.rating_type = p_rating_type
          and r.period <= least(make_date(p_year, 12, 1), current_date)
          and coalesce(r.flag, '') not like '%i%'
          and (p_country is null or r.country = p_country)
          and (
              p_titles is null or cardinality(p_titles) = 0
              or r.title = any(p_titles)
              or ('UNTITLED' = any(p_titles) and (r.title is null or r.title = ''))
          )
        order by r.fideid, r.period desc
    )
    select fideid, name, country, title, rating,
           coalesce(p_year, extract(year from current_date)::int) - birthday as age
    from filtered
    where rating is not null
      and (p_min_age is null or (coalesce(p_year, extract(year from current_date)::int) - birthday) >= p_min_age)
      and (p_max_age is null or (coalesce(p_year, extract(year from current_date)::int) - birthday) <= p_max_age)
    order by rating desc
    limit p_limit;
$$;

-- Player search: `name ilike '%term%'` can't use a btree index, and this
-- table is 9.5M rows -- a seq scan takes several seconds. pg_trgm's GIN
-- index turns that into single-digit milliseconds.
create extension if not exists pg_trgm;

create index if not exists ratings_name_trgm_idx on ratings using gin (name gin_trgm_ops);

-- Search by name, one row per player with all 3 cadences (standard/rapid/
-- blitz) side by side rather than a single rating_type -- there's no time
-- control picker on the search page. Offset-paginated for infinite scroll,
-- like most_active_players/rating movers.
--
-- `p_name` needs at least 2 characters: this is a public, unauthenticated
-- endpoint (web_anon), and `ilike '%%'` on an empty/1-char term would scan
-- and return a huge fraction of the table.
create or replace function search_players(
    p_name   text,
    p_limit  integer default 25,
    p_offset integer default 0
)
returns table (
    fideid          integer,
    name            text,
    country         text,
    title           text,
    rating_standard integer,
    rating_rapid    integer,
    rating_blitz    integer,
    age             integer
)
language sql stable
as $$
    with matches as (
        select distinct on (r.fideid)
            r.fideid, r.name, r.country, r.title, r.birthday
        from ratings r
        where char_length(btrim(p_name)) >= 2
          and r.name ilike '%' || p_name || '%'
          and coalesce(r.flag, '') not like '%i%'
        order by r.fideid, r.period desc
    ),
    pivoted as (
        select m.fideid, m.name, m.country, m.title, m.birthday,
            (select r2.rating from ratings r2
             where r2.fideid = m.fideid and r2.rating_type = 'standard'
             order by r2.period desc limit 1) as rating_standard,
            (select r2.rating from ratings r2
             where r2.fideid = m.fideid and r2.rating_type = 'rapid'
             order by r2.period desc limit 1) as rating_rapid,
            (select r2.rating from ratings r2
             where r2.fideid = m.fideid and r2.rating_type = 'blitz'
             order by r2.period desc limit 1) as rating_blitz
        from matches m
    )
    select fideid, name, country, title, rating_standard, rating_rapid, rating_blitz,
           extract(year from current_date)::int - birthday as age
    from pivoted
    order by coalesce(rating_standard, rating_rapid, rating_blitz, 0) desc, name
    limit p_limit offset p_offset;
$$;
