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
