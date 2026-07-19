-- Biggest rating gainers/losers over a period ("movers" page). Exposed at
-- /rpc/rating_change.
--
-- Reads rating_change_snapshots (see 000009.sql) when p_from/p_to match one
-- of the two shapes the frontend actually sends (rolling 12 months, or a
-- full calendar year) and that bucket has been precomputed. Falls back to
-- the original live scan otherwise -- a custom range via direct API use, or
-- a year that hasn't been frozen yet (the current in-progress year before
-- December, or a year older than this feature).
create or replace function public.rating_change(p_from date, p_to date, p_country text default null::text, p_sex text default null::text, p_rating_type rating_type default null::rating_type, p_titles text[] default null::text[], p_min_age integer default null::integer, p_max_age integer default null::integer, p_direction text default 'gain'::text, p_limit integer default 50, p_offset integer default 0)
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
              and (p_sex is null or s.sex = p_sex)
              and title_matches(s.title, p_titles)
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
              and (p_sex is null or r.sex = p_sex)
              and (p_rating_type is null or r.rating_type = p_rating_type)
              and title_matches(r.title, p_titles)
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
