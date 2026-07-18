-- Most active players by games played ("active" page). Exposed at
-- /rpc/most_active_players.
--
-- Reads rating_change_snapshots (see 000009.sql, 000010.sql) when
-- p_from/p_to match one of the two shapes the frontend actually sends
-- (rolling 12 months, or a full calendar year) and that bucket has been
-- precomputed -- same table rating_change already uses, total_games is
-- just another column off the same GROUP BY fideid, rating_type. Falls
-- back to the original live scan otherwise: a custom range via direct API
-- use, an unfrozen year, or the "all time" (p_from/p_to both null) case,
-- which stays a genuinely live O(whole table) aggregate -- see the
-- ponytail note this function used to carry (~75s, upgrade to a rollup
-- table if that becomes a real access pattern -- it isn't the default and
-- isn't covered here).
create or replace function public.most_active_players(p_from date default null::date, p_to date default null::date, p_country text default null::text, p_sex text default null::text, p_rating_type rating_type default null::rating_type, p_titles text[] default null::text[], p_min_age integer default null::integer, p_max_age integer default null::integer, p_limit integer default 50, p_offset integer default 0)
 returns table(fideid integer, name text, country text, title text, total_games bigint, rating integer, age integer)
 language plpgsql
 stable
as $function$
declare
    v_bucket text;
    v_today_to date := (date_trunc('month', current_date) + interval '1 month')::date;
    v_today_from date := (date_trunc('month', current_date) + interval '1 month' - interval '12 months')::date;
    v_age_year int := extract(year from coalesce(p_to - interval '1 day', current_date))::int;
begin
    if p_rating_type is not null and p_from = v_today_from and p_to = v_today_to then
        v_bucket := 'rolling';
    elsif p_rating_type is not null and p_from is not null and p_to is not null
          and extract(month from p_from) = 1 and extract(day from p_from) = 1
          and p_to = p_from + interval '1 year' then
        v_bucket := extract(year from p_from)::text;
    end if;

    if v_bucket is not null and exists (
        select 1 from rating_change_snapshots where bucket = v_bucket and rating_type = p_rating_type limit 1
    ) then
        return query
            select
                s.fideid, s.name, s.country, s.title, s.total_games, s.end_rating,
                v_age_year - s.birthday as age
            from rating_change_snapshots s
            where s.bucket = v_bucket
              and s.rating_type = p_rating_type
              and (p_country is null or s.country = p_country)
              and (p_sex is null or s.sex = p_sex)
              and (
                  p_titles is null or cardinality(p_titles) = 0
                  or s.title = any(p_titles)
                  or ('UNTITLED' = any(p_titles) and (s.title is null or s.title = ''))
              )
              and (p_min_age is null or (v_age_year - s.birthday) >= p_min_age)
              and (p_max_age is null or (v_age_year - s.birthday) <= p_max_age)
            order by s.total_games desc
            limit p_limit
            offset p_offset;
        return;
    end if;

    return query
        with active as (
            select
                r.fideid,
                max(r.name)     as name,
                max(r.country)  as country,
                max(r.title)    as title,
                max(r.birthday) as birthday,
                sum(coalesce(r.games, 0)) as total_games
            from ratings r
            where r.period >= coalesce(p_from, '-infinity'::date)
              and r.period <  coalesce(p_to, 'infinity'::date)
              and (p_country is null or r.country = p_country)
              and (p_sex is null or r.sex = p_sex)
              and (p_rating_type is null or r.rating_type = p_rating_type)
              and (
                  p_titles is null or cardinality(p_titles) = 0
                  or r.title = any(p_titles)
                  or ('UNTITLED' = any(p_titles) and (r.title is null or r.title = ''))
              )
              and (p_min_age is null or (v_age_year - r.birthday) >= p_min_age)
              and (p_max_age is null or (v_age_year - r.birthday) <= p_max_age)
            group by r.fideid
            order by total_games desc
            limit p_limit
            offset p_offset
        )
        select
            a.fideid, a.name, a.country, a.title, a.total_games,
            (
                select r2.rating
                from ratings r2
                where r2.fideid = a.fideid
                  and r2.rating_type = coalesce(p_rating_type, 'standard')
                  and r2.period < coalesce(p_to, 'infinity'::date)
                  and r2.period <= current_date
                order by r2.period desc
                limit 1
            ) as rating,
            v_age_year - a.birthday as age
        from active a
        order by a.total_games desc;
end;
$function$
;
