--! Previous: sha1:d341346ba95be3dcb37835696da2c26524c6b9b3
--! Hash: sha1:34ed70f1ec65c6b18fe5e3f1e216f88587a198b7

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

-- Player detail page: one row with all 3 cadences (current + all-time max)
-- plus country/world rank in standard. Exposed at /rpc/player_profile.
--
-- Sourced from latest_ratings (small, indexed, refreshed once a month by the
-- scraper) rather than ratings directly -- a rank needs "how many players
-- are rated above this one", and latest_ratings_type_rating_idx (rating_type,
-- rating desc) makes that a cheap index range count instead of a full-table
-- sort. Country rank has no matching index (rating_type, country, rating),
-- so it scans the type partition down to this player's rating -- fine for a
-- single-player lookup, would need a new index if this became a bulk query.
--
-- max_* pulls from ratings (not latest_ratings, which only has the latest
-- snapshot): still cheap, ratings_fideid_type_period_idx scopes the scan to
-- just this player's rows.
--
-- Rank counts only active players (flag not like '%i%'), same convention as
-- top_players/search_players -- inactive/withdrawn players shouldn't inflate
-- everyone else's rank.
create or replace function player_profile(p_fideid integer)
returns table (
    fideid                integer,
    name                  text,
    country               text,
    title                 text,
    age                   integer,
    rating_standard       integer,
    rating_rapid          integer,
    rating_blitz          integer,
    max_standard          integer,
    max_rapid             integer,
    max_blitz             integer,
    rank_country_standard bigint,
    rank_world_standard   bigint
)
language sql stable
as $$
    with base as (
        select * from latest_ratings where fideid = p_fideid
    ),
    picked as (
        select fideid, name, country, title, birthday
        from base
        order by case rating_type when 'standard' then 0 when 'rapid' then 1 else 2 end
        limit 1
    ),
    std as (
        select rating from base where rating_type = 'standard'
    )
    select
        p.fideid, p.name, p.country, p.title,
        extract(year from current_date)::int - p.birthday as age,
        (select rating from base where rating_type = 'standard') as rating_standard,
        (select rating from base where rating_type = 'rapid') as rating_rapid,
        (select rating from base where rating_type = 'blitz') as rating_blitz,
        (select max(rating) from ratings where fideid = p_fideid and rating_type = 'standard') as max_standard,
        (select max(rating) from ratings where fideid = p_fideid and rating_type = 'rapid') as max_rapid,
        (select max(rating) from ratings where fideid = p_fideid and rating_type = 'blitz') as max_blitz,
        case when (select rating from std) is not null then
            (select count(*) + 1 from latest_ratings lr
             where lr.rating_type = 'standard' and lr.country = p.country and lr.rating > (select rating from std)
               and coalesce(lr.flag, '') not like '%i%')
        end as rank_country_standard,
        case when (select rating from std) is not null then
            (select count(*) + 1 from latest_ratings lr
             where lr.rating_type = 'standard' and lr.rating > (select rating from std)
               and coalesce(lr.flag, '') not like '%i%')
        end as rank_world_standard
    from picked p;
$$;
