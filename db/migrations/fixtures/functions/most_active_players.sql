create or replace function public.most_active_players(p_from date default null::date, p_to date default null::date, p_country text default null::text, p_rating_type rating_type default null::rating_type, p_titles text[] default null::text[], p_min_age integer default null::integer, p_max_age integer default null::integer, p_limit integer default 50, p_offset integer default 0)
 returns table(fideid integer, name text, country text, title text, total_games bigint, rating integer, age integer)
 language sql
 stable
as $function$
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
          and (p_rating_type is null or r.rating_type = p_rating_type)
          and (
              p_titles is null or cardinality(p_titles) = 0
              or r.title = any(p_titles)
              or ('UNTITLED' = any(p_titles) and (r.title is null or r.title = ''))
          )
          and (p_min_age is null or (
                  extract(year from coalesce(p_to - interval '1 day', current_date))::int - r.birthday
              ) >= p_min_age)
          and (p_max_age is null or (
                  extract(year from coalesce(p_to - interval '1 day', current_date))::int - r.birthday
              ) <= p_max_age)
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
        extract(year from coalesce(p_to - interval '1 day', current_date))::int - a.birthday as age
    from active a
    order by a.total_games desc;
$function$
;
