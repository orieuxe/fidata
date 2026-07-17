--! Previous: sha1:8230358304133d7c9753772972b6020af936be47
--! Hash: sha1:1c39bde71f8572378a6b7c797d8aa3c4389b0eea
--! Message: add elo/activity rank percentile to player_profile

-- Enter migration here

-- Player detail page header: profile, current/peak ratings, Elo rank (with
-- percentile) and this-year activity rank (with percentile). Exposed at
-- /rpc/player_profile.
--
-- Elo rank/percentile reuse the same latest_ratings scan pattern as the
-- original rank columns (see rank_country_standard below) -- bundled into
-- one LATERAL per scope (country/world) so rank and total are computed in
-- a single pass instead of two.
--
-- Activity rank is scoped to the current calendar year, same convention as
-- player_yearly_stats. `ratings` only keeps rows where games > 0 (see
-- baseline migration), so year_games needs no extra "did they actually
-- play" filter. Filtered to the current year like most_active_players'
-- p_year branch, which is fast (~130-600ms) -- an all-time version would
-- hit the ~75s unfiltered full-table cost noted there.
--
-- Dropped first: postgres refuses `create or replace` when the return type
-- (OUT parameter row) changes, only when it's identical.
drop function if exists player_profile(integer);
create or replace function player_profile(p_fideid integer)
returns table (
    fideid                       integer,
    name                         text,
    country                      text,
    title                        text,
    age                          integer,
    rating_standard              integer,
    rating_rapid                 integer,
    rating_blitz                 integer,
    max_standard                 integer,
    max_rapid                    integer,
    max_blitz                    integer,
    rank_country_standard        bigint,
    rank_world_standard          bigint,
    percentile_country_standard  numeric,
    percentile_world_standard    numeric,
    games_this_year              bigint,
    rank_activity_country        bigint,
    rank_activity_world          bigint,
    percentile_activity_country  numeric,
    percentile_activity_world    numeric
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
    ),
    year_games as (
        select r.fideid, max(r.country) as country, sum(r.games) as games_year
        from ratings r
        where r.period >= date_trunc('year', current_date)
          and r.period < date_trunc('year', current_date) + interval '1 year'
        group by r.fideid
    ),
    my_games as (
        select games_year from year_games where fideid = p_fideid
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
        case when (select rating from std) is not null then round(100.0 * rc.rnk / nullif(rc.total, 0), 1) end as percentile_country_standard,
        case when (select rating from std) is not null then round(100.0 * rw.rnk / nullif(rw.total, 0), 1) end as percentile_world_standard,
        (select games_year from my_games) as games_this_year,
        case when (select games_year from my_games) is not null then ac.rnk end as rank_activity_country,
        case when (select games_year from my_games) is not null then aw.rnk end as rank_activity_world,
        case when (select games_year from my_games) is not null then round(100.0 * ac.rnk / nullif(ac.total, 0), 1) end as percentile_activity_country,
        case when (select games_year from my_games) is not null then round(100.0 * aw.rnk / nullif(aw.total, 0), 1) end as percentile_activity_world
    from picked p
    left join lateral (
        select
            count(*) filter (where lr.rating > (select rating from std)) + 1 as rnk,
            count(*) as total
        from latest_ratings lr
        where lr.rating_type = 'standard' and lr.country = p.country
          and coalesce(lr.flag, '') not like '%i%'
    ) rc on true
    left join lateral (
        select
            count(*) filter (where lr.rating > (select rating from std)) + 1 as rnk,
            count(*) as total
        from latest_ratings lr
        where lr.rating_type = 'standard'
          and coalesce(lr.flag, '') not like '%i%'
    ) rw on true
    left join lateral (
        select
            count(*) filter (where yg.games_year > (select games_year from my_games)) + 1 as rnk,
            count(*) as total
        from year_games yg
        where yg.country = p.country
    ) ac on true
    left join lateral (
        select
            count(*) filter (where yg.games_year > (select games_year from my_games)) + 1 as rnk,
            count(*) as total
        from year_games yg
    ) aw on true;
$$;
