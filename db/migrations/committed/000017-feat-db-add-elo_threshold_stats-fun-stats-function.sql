--! Previous: sha1:99f7989a02ce7bcaa8c4cd832c331800a89201d4
--! Hash: sha1:a711b02f83d35ad1d5cf0c000e81723a01ee181d
--! Message: feat(db): add elo_threshold_stats fun-stats function

--! Included functions/elo_threshold_stats.sql
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
    -- birthday sourced from latest_ratings (FIDE's most recently corrected
    -- value), not the crossing row: FIDE occasionally fixes a player's
    -- birth year later on, and the row at the actual crossing period can
    -- still carry the old, wrong value.
    crossing as (
        select
            fc.fideid, fc.name, fc.country, fc.title, fc.period, fc.rating,
            extract(year from fc.period)::int - lr.birthday as age,
            g.games_to_threshold
        from first_cross fc
        join latest_ratings lr on lr.fideid = fc.fideid and lr.rating_type = p_rating_type
        -- single scan of the player's history up to the crossing period,
        -- covering both the games tally and the "did we see them below
        -- the threshold first" check below in one index scan instead of two.
        join lateral (
            select
                sum(coalesce(r2.games, 0)) as games_to_threshold,
                bool_or(r2.rating < p_threshold and r2.period < fc.period) as has_prior_below
            from ratings r2
            where r2.fideid = fc.fideid
              and r2.rating_type = p_rating_type
              and r2.period <= fc.period
        ) g on true
        -- ponytail: sanity band, not a data audit -- FIDE birth years have
        -- occasional typos that survive corrections (off by a decade etc);
        -- this just keeps the worst of them off a public "fun stat" page.
        where extract(year from fc.period)::int - lr.birthday between 5 and 100
          -- `ratings` only goes back to 2001 (pre-2015 rows are a
          -- third-party backfill, see backfill-historical.ts) -- a player
          -- already rated >= threshold on their *first* row in our data
          -- (e.g. an old GM re-registering after decades away) isn't a
          -- real "crossing", just missing pre-2001 history. Require at
          -- least one earlier row actually below the threshold as proof
          -- we observed the real climb.
          and g.has_prior_below
    )
    (select 'youngest' as metric, * from crossing order by age asc, games_to_threshold asc limit 1)
    union all
    (select 'oldest' as metric, * from crossing order by age desc, games_to_threshold asc limit 1)
    union all
    (select 'fewest_games' as metric, * from crossing order by games_to_threshold asc, age asc limit 1)
$function$
;
--! EndIncluded functions/elo_threshold_stats.sql
