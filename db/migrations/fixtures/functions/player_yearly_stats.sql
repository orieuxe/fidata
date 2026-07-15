create or replace function public.player_yearly_stats(p_fideid integer)
 returns table(year integer, games_standard bigint, delta_standard integer, games_rapid bigint, delta_rapid integer, games_blitz bigint, delta_blitz integer, games_total bigint)
 language sql
 stable
as $function$
    with player_ratings as (
        select rating_type, period, rating, games
        from ratings
        where fideid = p_fideid
    ),
    games_pivot as (
        select
            extract(year from period)::int as year,
            sum(coalesce(games, 0)) filter (where rating_type = 'standard') as games_standard,
            sum(coalesce(games, 0)) filter (where rating_type = 'rapid')    as games_rapid,
            sum(coalesce(games, 0)) filter (where rating_type = 'blitz')    as games_blitz,
            sum(coalesce(games, 0))                                        as games_total
        from player_ratings
        group by 1
    ),
    year_end_ratings as (
        select distinct on (rating_type, extract(year from period)::int)
            rating_type, extract(year from period)::int as year, rating
        from player_ratings
        order by rating_type, extract(year from period)::int, period desc
    ),
    type_deltas as (
        select year, rating_type, rating - lag(rating) over (partition by rating_type order by year) as delta
        from year_end_ratings
    ),
    delta_pivot as (
        select
            year,
            max(delta) filter (where rating_type = 'standard') as delta_standard,
            max(delta) filter (where rating_type = 'rapid')    as delta_rapid,
            max(delta) filter (where rating_type = 'blitz')    as delta_blitz
        from type_deltas
        group by year
    )
    select
        g.year,
        g.games_standard, dp.delta_standard,
        g.games_rapid, dp.delta_rapid,
        g.games_blitz, dp.delta_blitz,
        g.games_total
    from games_pivot g
    left join delta_pivot dp using (year)
    order by g.year desc;
$function$
;
