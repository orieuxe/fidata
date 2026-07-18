create or replace function public.rating_change(p_from date, p_to date, p_country text default null::text, p_rating_type rating_type default null::rating_type, p_titles text[] default null::text[], p_min_age integer default null::integer, p_max_age integer default null::integer, p_direction text default 'gain'::text, p_limit integer default 50, p_offset integer default 0)
 returns table(fideid integer, name text, country text, title text, start_rating integer, end_rating integer, delta integer, age integer)
 language sql
 stable
as $function$
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
          and (p_rating_type is null or r.rating_type = p_rating_type)
          and (
              p_titles is null or cardinality(p_titles) = 0
              or r.title = any(p_titles)
              or ('UNTITLED' = any(p_titles) and (r.title is null or r.title = ''))
          )
          and (p_min_age is null or (extract(year from p_to - interval '1 day')::int - r.birthday) >= p_min_age)
          and (p_max_age is null or (extract(year from p_to - interval '1 day')::int - r.birthday) <= p_max_age)
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
    select fideid, name, country, title, start_rating, end_rating,
           end_rating - start_rating as delta,
           extract(year from p_to - interval '1 day')::int - birthday as age
    from changes
    where start_rating is not null and end_rating is not null
    order by (case when p_direction = 'loss' then end_rating - start_rating
                   else start_rating - end_rating end) asc
    limit p_limit
    offset p_offset;
$function$
;
