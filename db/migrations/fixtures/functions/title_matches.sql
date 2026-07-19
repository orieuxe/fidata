-- Shared title-filter predicate for most_active_players/rating_change/top_players
-- (each repeats this OR-chain 2-3x per query, once per source table). Plain SQL
-- + immutable so Postgres inlines it -- verified via EXPLAIN that it produces
-- the exact same index scan on ratings_title_idx as the literal expression.
create or replace function public.title_matches(p_title text, p_titles text[])
 returns boolean
 language sql
 immutable
as $function$
    select p_titles is null or cardinality(p_titles) = 0
        or p_title = any(p_titles)
        or ('UNTITLED' = any(p_titles) and (p_title is null or p_title = ''))
$function$
;
