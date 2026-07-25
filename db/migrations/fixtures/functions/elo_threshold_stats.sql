-- Fun stats: who crossed an elo threshold youngest/oldest, and in fewest
-- games. Based on `ratings` history (first period where rating >= X), not
-- FIDE title-attribution dates, which are unreliable. Exposed at
-- /rpc/elo_threshold_stats.
create or replace function public.elo_threshold_stats(p_threshold integer, p_rating_type rating_type default 'standard'::rating_type)
 returns table(metric text, fideid integer, name text, country text, title text, period date, rating integer, age integer, games_to_threshold bigint)
 language sql
 stable
as $function$
    with first_cross as (
        select distinct on (r.fideid)
            r.fideid, r.period, r.rating, r.name, r.country, r.title
        from ratings r
        where r.rating_type = p_rating_type
          and r.rating >= p_threshold
        order by r.fideid, r.period
    ),
    -- Age at crossing: use the latest birthday known at the time of
    -- crossing (max of all non-null birthdays recorded for this fideid
    -- up to that period), not latest_ratings.birthday. FIDE occasionally
    -- reuses fideids for completely different players (e.g. 700258 =
    -- Szekely 1955 → Revesz 1989); latest_ratings would pull the new
    -- player's birthday and make the old player look decades younger.
    crossing as (
        select
            fc.fideid, fc.name, fc.country, fc.title, fc.period, fc.rating,
            extract(year from fc.period)::int - g.birthday as age,
            g.games_to_threshold,
            g.has_any_games
        from first_cross fc
        -- single scan of the player's history up to the crossing period,
        -- covering both the games tally and the "did we see them below
        -- the threshold first" check in one index scan instead of two.
        join lateral (
            select
                sum(coalesce(r2.games, 0)) as games_to_threshold,
                max(r2.birthday) filter (where r2.birthday > 1900) as birthday,
                bool_or(r2.games > 0) as has_any_games,
                bool_or(r2.rating < p_threshold and r2.period < fc.period) as has_prior_below
            from ratings r2
            where r2.fideid = fc.fideid
              and r2.rating_type = p_rating_type
              and r2.period <= fc.period
        ) g on true
        -- ponytail: sanity band, not a data audit -- FIDE birth years have
        -- occasional typos that survive corrections (off by a decade etc);
        -- this just keeps the worst of them off a public "fun stat" page.
        where extract(year from fc.period)::int - g.birthday between 5 and 100
          -- require at least one earlier row actually below the threshold
          -- as proof we observed the real climb.
          and g.has_prior_below
    )
    (select 'youngest' as metric, fideid, name, country, title, period, rating, age, games_to_threshold from crossing order by age asc, games_to_threshold asc limit 1)
    union all
    (select 'oldest' as metric, fideid, name, country, title, period, rating, age, games_to_threshold from crossing order by age desc, games_to_threshold asc limit 1)
    union all
    (select 'fewest_games' as metric, fideid, name, country, title, period, rating, age, games_to_threshold from crossing where has_any_games order by games_to_threshold asc, age asc limit 1)
$function$
;
