-- Indexes to support filtering the most_active_players query below.
create index if not exists ratings_country_idx on ratings (country);
create index if not exists ratings_birthday_idx on ratings (birthday);
create index if not exists ratings_title_idx on ratings (title) where title is not null and title <> '';

-- Most active players (by games played) within a period/country/time-control/title/age filter.
-- Exposed by PostgREST at /rpc/most_active_players.
-- ponytail: no-filter call (p_year null + no other filters) does a full-table GroupAggregate,
-- ~75s at current data volume and growing with every backfilled month. Fine for a filtered
-- query (tested ~130-600ms); if an unfiltered "all time" view becomes a real access pattern,
-- upgrade to a rollup table (fideid, year, rating_type -> games_sum) refreshed by the scraper.
create or replace function most_active_players(
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
    total_games bigint
)
language sql stable
as $$
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
    limit p_limit;
$$;

-- Distinct country codes, for populating a filter dropdown. A live `distinct` over
-- `ratings` takes ~6s at current volume (full scan), so this is a small table the
-- scraper keeps upserted instead (see scraper/src/db.ts).
create table if not exists countries (
    code text primary key
);
insert into countries
    select distinct country from ratings where country is not null
    on conflict do nothing;
