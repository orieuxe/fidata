--! Previous: -
--! Hash: sha1:48c94afc437e9b8b05394527e38d1c19a2f1806d

-- Baseline: FIDE rating history schema, indexes, and the most-active-players query.
-- Idempotent (IF NOT EXISTS / OR REPLACE / guarded DO blocks) so it applies cleanly
-- both to a fresh shadow database and to the already-populated main database.

do $$ begin
    create type rating_type as enum ('standard', 'rapid', 'blitz');
exception
    when duplicate_object then null;
end $$;

create table if not exists ratings (
    fideid      integer     not null,
    period      date        not null,
    rating_type rating_type not null,
    name        text        not null,
    country     text,
    sex         text,
    title       text,
    w_title     text,
    o_title     text,
    birthday    integer,
    rating      integer,
    games       integer,
    k           integer,
    flag        text,
    primary key (fideid, period, rating_type)
);

create index if not exists ratings_period_type_idx on ratings (period, rating_type);
create index if not exists ratings_fideid_idx on ratings (fideid);
create index if not exists ratings_birthday_idx on ratings (birthday);
create index if not exists ratings_title_idx on ratings (title) where title is not null and title <> '';
create index if not exists ratings_type_country_period_idx on ratings (rating_type, country, period);

-- Most recent snapshot per player per rating type, for "current" lookups.
create or replace view latest_ratings as
    select distinct on (fideid, rating_type) *
    from ratings
    order by fideid, rating_type, period desc;

-- Distinct country codes, for populating a filter dropdown. A live `distinct` over
-- `ratings` takes ~6s at current volume (full scan), so this is a small table the
-- scraper keeps upserted instead (see scraper/src/db.ts).
create table if not exists countries (
    code text primary key
);
insert into countries
    select distinct country from ratings where country is not null
    on conflict do nothing;

-- Most active players (by games played), filterable by year/country/time-control/
-- title/age. Exposed by PostgREST at /rpc/most_active_players.
-- ponytail: an unfiltered call (p_year null + no other filters) does a full-table
-- GroupAggregate, ~75s and growing with every backfilled month. Filtered calls
-- (year/country/type) are fast (tested ~130-600ms). If an unfiltered "all time"
-- view becomes a real access pattern, upgrade to a rollup table
-- (fideid, year, rating_type -> games_sum) refreshed by the scraper.
--
-- The rating shown is the player's latest rating in the filtered time control,
-- defaulting to "standard" when no time control filter is given (a player's games
-- can be summed across multiple time controls, so a single rating column needs a
-- tiebreak).
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
    select a.fideid, a.name, a.country, a.title, a.total_games, lr.rating
    from active a
    left join latest_ratings lr
        on lr.fideid = a.fideid
       and lr.rating_type = coalesce(p_rating_type, 'standard')
    order by a.total_games desc;
$$;
