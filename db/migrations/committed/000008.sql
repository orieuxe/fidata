--! Previous: sha1:3682c0d5f7bc687a8bf76a14b6f04b9063274043
--! Hash: sha1:fd5e7337923988dbfc9a38ec9420af6aed9db2a4

-- Enter migration here

drop function if exists player_profile(integer);
--! Included functions/player_profile.sql
-- Player detail page header: profile, current/peak ratings, per-cadence Elo
-- rank and per-cadence (standard/rapid/blitz) rolling-12-month activity
-- rank, each with a total for the frontend to derive a percentile from
-- (rank / total * 100) -- no percentage math in SQL.
-- Exposed at /rpc/player_profile.
--
-- Elo rank is computed among active players only (players with games_12m >
-- 0 for that cadence, see window_games), so it shares its total with the
-- activity rank (total_activity_*_standard) -- no separate total column.
--
-- Activity is a rolling 12-month window (current_date - 12 months), not
-- calendar year, and is scoped per rating_type: "active" for a cadence
-- means having games > 0 in that cadence within the window. `ratings` only
-- keeps rows where games > 0 (see baseline migration), so summing games is
-- enough -- no extra "did they actually play" filter needed.
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
    std as (
        select rating from base where rating_type = 'standard'
    ),
    rpd as (
        select rating from base where rating_type = 'rapid'
    ),
    blz as (
        select rating from base where rating_type = 'blitz'
    ),
    window_games as (
        select r.fideid, r.rating_type, max(r.country) as country, sum(coalesce(r.games, 0)) as games_12m
        from ratings r
        where r.period >= current_date - interval '12 months'
        group by r.fideid, r.rating_type
    ),
    my_games as (
        select rating_type, games_12m from window_games where fideid = p_fideid
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
        case when (select rating from std) is not null then rc.rnk end as rank_country_standard,
        case when (select rating from std) is not null then rw.rnk end as rank_world_standard,
        case when (select rating from rpd) is not null then rcr.rnk end as rank_country_rapid,
        case when (select rating from rpd) is not null then rwr.rnk end as rank_world_rapid,
        case when (select rating from blz) is not null then rcb.rnk end as rank_country_blitz,
        case when (select rating from blz) is not null then rwb.rnk end as rank_world_blitz,
        (select games_12m from my_games where rating_type = 'standard') as games_12m_standard,
        (select games_12m from my_games where rating_type = 'rapid') as games_12m_rapid,
        (select games_12m from my_games where rating_type = 'blitz') as games_12m_blitz,
        case when (select games_12m from my_games where rating_type = 'standard') is not null then acs.rnk end as rank_activity_country_standard,
        case when (select games_12m from my_games where rating_type = 'standard') is not null then aws.rnk end as rank_activity_world_standard,
        case when (select games_12m from my_games where rating_type = 'standard') is not null then acs.total end as total_activity_country_standard,
        case when (select games_12m from my_games where rating_type = 'standard') is not null then aws.total end as total_activity_world_standard,
        case when (select games_12m from my_games where rating_type = 'rapid') is not null then acr.rnk end as rank_activity_country_rapid,
        case when (select games_12m from my_games where rating_type = 'rapid') is not null then awr.rnk end as rank_activity_world_rapid,
        case when (select games_12m from my_games where rating_type = 'rapid') is not null then acr.total end as total_activity_country_rapid,
        case when (select games_12m from my_games where rating_type = 'rapid') is not null then awr.total end as total_activity_world_rapid,
        case when (select games_12m from my_games where rating_type = 'blitz') is not null then acb.rnk end as rank_activity_country_blitz,
        case when (select games_12m from my_games where rating_type = 'blitz') is not null then awb.rnk end as rank_activity_world_blitz,
        case when (select games_12m from my_games where rating_type = 'blitz') is not null then acb.total end as total_activity_country_blitz,
        case when (select games_12m from my_games where rating_type = 'blitz') is not null then awb.total end as total_activity_world_blitz
    from picked p
    left join lateral (
        select count(*) filter (where lr.rating > (select rating from std)) + 1 as rnk
        from latest_ratings lr
        join window_games wg on wg.fideid = lr.fideid and wg.rating_type = lr.rating_type
        where lr.rating_type = 'standard' and lr.country = p.country
          and coalesce(lr.flag, '') not like '%i%'
    ) rc on true
    left join lateral (
        select count(*) filter (where lr.rating > (select rating from std)) + 1 as rnk
        from latest_ratings lr
        join window_games wg on wg.fideid = lr.fideid and wg.rating_type = lr.rating_type
        where lr.rating_type = 'standard'
          and coalesce(lr.flag, '') not like '%i%'
    ) rw on true
    left join lateral (
        select count(*) filter (where lr.rating > (select rating from rpd)) + 1 as rnk
        from latest_ratings lr
        join window_games wg on wg.fideid = lr.fideid and wg.rating_type = lr.rating_type
        where lr.rating_type = 'rapid' and lr.country = p.country
          and coalesce(lr.flag, '') not like '%i%'
    ) rcr on true
    left join lateral (
        select count(*) filter (where lr.rating > (select rating from rpd)) + 1 as rnk
        from latest_ratings lr
        join window_games wg on wg.fideid = lr.fideid and wg.rating_type = lr.rating_type
        where lr.rating_type = 'rapid'
          and coalesce(lr.flag, '') not like '%i%'
    ) rwr on true
    left join lateral (
        select count(*) filter (where lr.rating > (select rating from blz)) + 1 as rnk
        from latest_ratings lr
        join window_games wg on wg.fideid = lr.fideid and wg.rating_type = lr.rating_type
        where lr.rating_type = 'blitz' and lr.country = p.country
          and coalesce(lr.flag, '') not like '%i%'
    ) rcb on true
    left join lateral (
        select count(*) filter (where lr.rating > (select rating from blz)) + 1 as rnk
        from latest_ratings lr
        join window_games wg on wg.fideid = lr.fideid and wg.rating_type = lr.rating_type
        where lr.rating_type = 'blitz'
          and coalesce(lr.flag, '') not like '%i%'
    ) rwb on true
    left join lateral (
        select
            count(*) filter (where wg.games_12m > (select games_12m from my_games where rating_type = 'standard')) + 1 as rnk,
            count(*) as total
        from window_games wg
        where wg.rating_type = 'standard' and wg.country = p.country
    ) acs on true
    left join lateral (
        select
            count(*) filter (where wg.games_12m > (select games_12m from my_games where rating_type = 'standard')) + 1 as rnk,
            count(*) as total
        from window_games wg
        where wg.rating_type = 'standard'
    ) aws on true
    left join lateral (
        select
            count(*) filter (where wg.games_12m > (select games_12m from my_games where rating_type = 'rapid')) + 1 as rnk,
            count(*) as total
        from window_games wg
        where wg.rating_type = 'rapid' and wg.country = p.country
    ) acr on true
    left join lateral (
        select
            count(*) filter (where wg.games_12m > (select games_12m from my_games where rating_type = 'rapid')) + 1 as rnk,
            count(*) as total
        from window_games wg
        where wg.rating_type = 'rapid'
    ) awr on true
    left join lateral (
        select
            count(*) filter (where wg.games_12m > (select games_12m from my_games where rating_type = 'blitz')) + 1 as rnk,
            count(*) as total
        from window_games wg
        where wg.rating_type = 'blitz' and wg.country = p.country
    ) acb on true
    left join lateral (
        select
            count(*) filter (where wg.games_12m > (select games_12m from my_games where rating_type = 'blitz')) + 1 as rnk,
            count(*) as total
        from window_games wg
        where wg.rating_type = 'blitz'
    ) awb on true;
$function$
;
--! EndIncluded functions/player_profile.sql
