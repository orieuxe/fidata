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
