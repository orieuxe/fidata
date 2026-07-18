--! Previous: sha1:fd5e7337923988dbfc9a38ec9420af6aed9db2a4
--! Hash: sha1:4307ce1e3fcd7b7b06a5b32f2e57faa127ec4985

-- Matches the coalesce(flag, '') not like '%i%' filter top_players/player_profile
-- apply on top of latest_ratings_type_rating_idx, so the planner can use an
-- Index Scan instead of a Bitmap Heap Scan that revisits every flagged-out row.
create index if not exists latest_ratings_active_type_rating_idx on latest_ratings (rating_type, rating desc) where coalesce(flag, '') not like '%i%';

--! Included functions/top_players.sql
-- Top N players by rating, filterable by year/country/time-control/title/age.
-- Exposed at /rpc/top_players.
--
-- p_year null or the current year -> reads latest_ratings (small, indexed
-- materialized view, see 000001.sql) instead of a live DISTINCT ON over the
-- full ratings table, which was the same ~35s-class scan latest_ratings was
-- introduced to avoid. Only a genuinely historical p_year (a past year's
-- leaderboard) falls back to scanning ratings directly.
-- Both branches' WHERE conditions are constant (don't reference table
-- columns), so Postgres proves one side always-false and skips scanning it
-- entirely instead of paying for both.
create or replace function public.top_players(p_year integer default null::integer, p_country text default null::text, p_rating_type rating_type default 'standard'::rating_type, p_titles text[] default null::text[], p_min_age integer default null::integer, p_max_age integer default null::integer, p_limit integer default 25)
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
          and (
              p_titles is null or cardinality(p_titles) = 0
              or title = any(p_titles)
              or ('UNTITLED' = any(p_titles) and (title is null or title = ''))
          )
        union all
        select r.fideid, r.name, r.country, r.title, r.birthday, r.rating
        from (
            select distinct on (r.fideid)
                r.fideid, r.name, r.country, r.title, r.birthday, r.rating
            from ratings r
            where p_year is not null and p_year < extract(year from current_date)::int
              and r.rating_type = p_rating_type
              and r.period <= make_date(p_year, 12, 1)
              and coalesce(r.flag, '') not like '%i%'
              and (p_country is null or r.country = p_country)
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

-- Rolling 12-month games-played aggregate per (fideid, rating_type), same
-- reasoning as latest_ratings (000001.sql): player_profile does 10 lookups
-- against this per call, and a live GROUP BY over ~1.7M `ratings` rows every
-- time was the bottleneck (see player_profile.sql). Refreshed monthly by the
-- scraper alongside latest_ratings, not live -- 12-month activity doesn't
-- need day-level freshness.
create materialized view if not exists player_activity_12m as
    select r.fideid, r.rating_type, max(r.country) as country, sum(coalesce(r.games, 0)) as games_12m
    from ratings r
    where r.period >= current_date - interval '12 months'
    group by r.fideid, r.rating_type
with data;

create unique index if not exists player_activity_12m_fideid_type_idx on player_activity_12m (fideid, rating_type);
create index if not exists player_activity_12m_type_country_games_idx on player_activity_12m (rating_type, country, games_12m desc);
create index if not exists player_activity_12m_type_games_idx on player_activity_12m (rating_type, games_12m desc);

grant select on player_activity_12m to web_anon;

-- Precomputed elo/activity ranks (country + world scope) per (fideid,
-- rating_type). player_profile previously computed these live via
-- count(*) filter (where rating > mine) + 1 over the whole active
-- population, 6 times per call (~3.3s even once latest_ratings/
-- player_activity_12m were indexed -- see player_profile.sql) -- a rank is
-- inherently O(population), not fixable with an index, only by moving the
-- O(population) work here, done once a month instead of once per request.
-- rank() matches the count(*)+1 formula exactly: ties share a rank, and
-- rank() = 1 + count of strictly-greater rows.
create materialized view if not exists player_ranks as
    with active as (
        select lr.fideid, lr.rating_type, lr.country, lr.rating, pa.games_12m
        from latest_ratings lr
        join player_activity_12m pa on pa.fideid = lr.fideid and pa.rating_type = lr.rating_type
        where coalesce(lr.flag, '') not like '%i%'
    )
    select
        fideid, rating_type,
        rank() over (partition by rating_type, country order by rating desc) as rank_country,
        rank() over (partition by rating_type order by rating desc) as rank_world,
        rank() over (partition by rating_type, country order by games_12m desc) as rank_activity_country,
        rank() over (partition by rating_type order by games_12m desc) as rank_activity_world,
        count(*) over (partition by rating_type, country) as total_activity_country,
        count(*) over (partition by rating_type) as total_activity_world
    from active
with data;

create unique index if not exists player_ranks_fideid_type_idx on player_ranks (fideid, rating_type);

grant select on player_ranks to web_anon;

--! Included functions/player_profile.sql
-- Player detail page header: profile, current/peak ratings, per-cadence Elo
-- rank and per-cadence (standard/rapid/blitz) rolling-12-month activity
-- rank, each with a total for the frontend to derive a percentile from
-- (rank / total * 100) -- no percentage math in SQL.
-- Exposed at /rpc/player_profile.
--
-- Elo rank is computed among active players only (players with games_12m >
-- 0 for that cadence), so it shares its total with the activity rank
-- (total_activity_*_standard) -- no separate total column.
--
-- Ranks are read from player_ranks (materialized, see 000009.sql), not
-- computed here: a rank is O(population) by nature (count of players rated
-- above you), and this function used to do that 6 times per call live --
-- ~3.3s even with every index in place. Moving the O(population) work to a
-- monthly refresh (~6s total for the whole table, see scraper) turns each
-- call here into O(1) index lookups instead.
create or replace function public.player_profile(p_fideid integer)
 returns table(
    fideid                          integer,
    name                            text,
    country                         text,
    title                           text,
    age                             integer,
    rating_standard                 integer,
    rating_rapid                    integer,
    rating_blitz                    integer,
    max_standard                    integer,
    max_rapid                       integer,
    max_blitz                       integer,
    rank_country_standard           bigint,
    rank_world_standard             bigint,
    rank_country_rapid              bigint,
    rank_world_rapid                bigint,
    rank_country_blitz              bigint,
    rank_world_blitz                bigint,
    games_12m_standard              bigint,
    games_12m_rapid                 bigint,
    games_12m_blitz                 bigint,
    rank_activity_country_standard  bigint,
    rank_activity_world_standard    bigint,
    total_activity_country_standard bigint,
    total_activity_world_standard   bigint,
    rank_activity_country_rapid     bigint,
    rank_activity_world_rapid       bigint,
    total_activity_country_rapid    bigint,
    total_activity_world_rapid      bigint,
    rank_activity_country_blitz     bigint,
    rank_activity_world_blitz       bigint,
    total_activity_country_blitz    bigint,
    total_activity_world_blitz      bigint
 )
 language sql
 stable
as $function$
    with base as (
        select * from latest_ratings where fideid = p_fideid
    ),
    picked as (
        select fideid, name, country, title, birthday
        from base
        order by case rating_type when 'standard' then 0 when 'rapid' then 1 else 2 end
        limit 1
    ),
    my_games as (
        select rating_type, games_12m from player_activity_12m where fideid = p_fideid
    ),
    my_ranks as (
        select * from player_ranks where fideid = p_fideid
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
        (select rank_country from my_ranks where rating_type = 'standard') as rank_country_standard,
        (select rank_world from my_ranks where rating_type = 'standard') as rank_world_standard,
        (select rank_country from my_ranks where rating_type = 'rapid') as rank_country_rapid,
        (select rank_world from my_ranks where rating_type = 'rapid') as rank_world_rapid,
        (select rank_country from my_ranks where rating_type = 'blitz') as rank_country_blitz,
        (select rank_world from my_ranks where rating_type = 'blitz') as rank_world_blitz,
        (select games_12m from my_games where rating_type = 'standard') as games_12m_standard,
        (select games_12m from my_games where rating_type = 'rapid') as games_12m_rapid,
        (select games_12m from my_games where rating_type = 'blitz') as games_12m_blitz,
        (select rank_activity_country from my_ranks where rating_type = 'standard') as rank_activity_country_standard,
        (select rank_activity_world from my_ranks where rating_type = 'standard') as rank_activity_world_standard,
        (select total_activity_country from my_ranks where rating_type = 'standard') as total_activity_country_standard,
        (select total_activity_world from my_ranks where rating_type = 'standard') as total_activity_world_standard,
        (select rank_activity_country from my_ranks where rating_type = 'rapid') as rank_activity_country_rapid,
        (select rank_activity_world from my_ranks where rating_type = 'rapid') as rank_activity_world_rapid,
        (select total_activity_country from my_ranks where rating_type = 'rapid') as total_activity_country_rapid,
        (select total_activity_world from my_ranks where rating_type = 'rapid') as total_activity_world_rapid,
        (select rank_activity_country from my_ranks where rating_type = 'blitz') as rank_activity_country_blitz,
        (select rank_activity_world from my_ranks where rating_type = 'blitz') as rank_activity_world_blitz,
        (select total_activity_country from my_ranks where rating_type = 'blitz') as total_activity_country_blitz,
        (select total_activity_world from my_ranks where rating_type = 'blitz') as total_activity_world_blitz
    from picked p;
$function$
;
--! EndIncluded functions/player_profile.sql

-- Rating gainers/losers ("movers" page) precomputed snapshots. rating_change
-- was a live GROUP BY across the whole requested period (up to ~800k rows
-- for the default rolling-12-months view) plus 2 correlated subqueries per
-- candidate row -- ~4.4s. The frontend only ever asks for one of two shapes
-- (rolling 12 months, or a full calendar year -- see yearFilterRange in
-- web/app/utils/filterOptions.ts), so both get precomputed here instead:
--   - bucket = 'rolling': rewritten every scrape (scraper/src/db.ts).
--   - bucket = '<year>': frozen once, never rewritten again. The scraper
--     runs on the 3rd of the month (deploy/fidata-scraper.timer), after
--     the 1st, so in December the rolling 12-month window already lands
--     exactly on Jan-Dec of the current year (excludes last December's
--     row, includes this one) -- no separate calendar-year query needed,
--     that December's rolling snapshot IS the year, just copied under its
--     own bucket key.
-- Anything else (a custom p_from/p_to via direct API use, or a bucket not
-- frozen yet) falls back to the original live query in rating_change().
create table if not exists rating_change_snapshots (
    bucket       text not null,
    fideid       integer not null,
    rating_type  rating_type not null,
    name         text not null,
    country      text,
    title        text,
    birthday     integer,
    start_rating integer,
    end_rating   integer,
    primary key (bucket, fideid, rating_type)
);

create index if not exists rating_change_snapshots_type_delta_idx
    on rating_change_snapshots (bucket, rating_type, ((end_rating - start_rating)));
create index if not exists rating_change_snapshots_type_country_delta_idx
    on rating_change_snapshots (bucket, rating_type, country, ((end_rating - start_rating)));

grant select on rating_change_snapshots to web_anon;

--! Included functions/rating_change.sql
-- Biggest rating gainers/losers over a period ("movers" page). Exposed at
-- /rpc/rating_change.
--
-- Reads rating_change_snapshots (see 000009.sql) when p_from/p_to match one
-- of the two shapes the frontend actually sends (rolling 12 months, or a
-- full calendar year) and that bucket has been precomputed. Falls back to
-- the original live scan otherwise -- a custom range via direct API use, or
-- a year that hasn't been frozen yet (the current in-progress year before
-- December, or a year older than this feature).
create or replace function public.rating_change(p_from date, p_to date, p_country text default null::text, p_rating_type rating_type default null::rating_type, p_titles text[] default null::text[], p_min_age integer default null::integer, p_max_age integer default null::integer, p_direction text default 'gain'::text, p_limit integer default 50, p_offset integer default 0)
 returns table(fideid integer, name text, country text, title text, start_rating integer, end_rating integer, delta integer, age integer)
 language plpgsql
 stable
as $function$
declare
    v_bucket text;
    v_today_to date := (date_trunc('month', current_date) + interval '1 month')::date;
    v_today_from date := (date_trunc('month', current_date) + interval '1 month' - interval '12 months')::date;
    v_age_year int := extract(year from p_to - interval '1 day')::int;
begin
    if p_rating_type is not null and p_from = v_today_from and p_to = v_today_to then
        v_bucket := 'rolling';
    elsif p_rating_type is not null
          and extract(month from p_from) = 1 and extract(day from p_from) = 1
          and p_to = p_from + interval '1 year' then
        v_bucket := extract(year from p_from)::text;
    end if;

    if v_bucket is not null and exists (
        select 1 from rating_change_snapshots where bucket = v_bucket and rating_type = p_rating_type limit 1
    ) then
        return query
            select
                s.fideid, s.name, s.country, s.title, s.start_rating, s.end_rating,
                s.end_rating - s.start_rating as delta,
                v_age_year - s.birthday as age
            from rating_change_snapshots s
            where s.bucket = v_bucket
              and s.rating_type = p_rating_type
              and (p_country is null or s.country = p_country)
              and (
                  p_titles is null or cardinality(p_titles) = 0
                  or s.title = any(p_titles)
                  or ('UNTITLED' = any(p_titles) and (s.title is null or s.title = ''))
              )
              and (p_min_age is null or (v_age_year - s.birthday) >= p_min_age)
              and (p_max_age is null or (v_age_year - s.birthday) <= p_max_age)
            order by (case when p_direction = 'loss' then s.end_rating - s.start_rating
                           else s.start_rating - s.end_rating end) asc
            limit p_limit
            offset p_offset;
        return;
    end if;

    return query
        with candidates as (
            select
                r.fideid,
                max(r.name)     as name,
                max(r.country)  as country,
                max(r.title)    as title,
                max(r.birthday) as birthday
            from ratings r
            where r.period >= p_from
              and r.period < p_to
              and r.games > 0
              and (p_country is null or r.country = p_country)
              and (p_rating_type is null or r.rating_type = p_rating_type)
              and (
                  p_titles is null or cardinality(p_titles) = 0
                  or r.title = any(p_titles)
                  or ('UNTITLED' = any(p_titles) and (r.title is null or r.title = ''))
              )
              and (p_min_age is null or (v_age_year - r.birthday) >= p_min_age)
              and (p_max_age is null or (v_age_year - r.birthday) <= p_max_age)
            group by r.fideid
        ),
        changes as materialized (
            select
                c.fideid, c.name, c.country, c.title, c.birthday,
                (
                    select r2.rating from ratings r2
                    where r2.fideid = c.fideid
                      and r2.rating_type = coalesce(p_rating_type, 'standard')
                      and r2.period >= p_from
                      and r2.period < p_to
                    order by r2.period asc
                    limit 1
                ) as start_rating,
                (
                    select r2.rating from ratings r2
                    where r2.fideid = c.fideid
                      and r2.rating_type = coalesce(p_rating_type, 'standard')
                      and r2.period < p_to
                      and r2.period <= current_date
                    order by r2.period desc
                    limit 1
                ) as end_rating
            from candidates c
        )
        select changes.fideid, changes.name, changes.country, changes.title, changes.start_rating, changes.end_rating,
               changes.end_rating - changes.start_rating as delta,
               v_age_year - changes.birthday as age
        from changes
        where changes.start_rating is not null and changes.end_rating is not null
        order by (case when p_direction = 'loss' then changes.end_rating - changes.start_rating
                       else changes.start_rating - changes.end_rating end) asc
        limit p_limit
        offset p_offset;
end;
$function$
;
--! EndIncluded functions/rating_change.sql
