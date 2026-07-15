create or replace function public.search_players(p_name text, p_limit integer default 25, p_offset integer default 0)
 returns table(fideid integer, name text, country text, title text, rating_standard integer, rating_rapid integer, rating_blitz integer, age integer)
 language sql
 stable
as $function$
    with matches as (
        select distinct on (r.fideid)
            r.fideid, r.name, r.country, r.title, r.birthday
        from ratings r
        where char_length(btrim(p_name)) >= 2
          and r.name ilike '%' || p_name || '%'
          and coalesce(r.flag, '') not like '%i%'
        order by r.fideid, r.period desc
    ),
    pivoted as (
        select m.fideid, m.name, m.country, m.title, m.birthday,
            (select r2.rating from ratings r2
             where r2.fideid = m.fideid and r2.rating_type = 'standard'
             order by r2.period desc limit 1) as rating_standard,
            (select r2.rating from ratings r2
             where r2.fideid = m.fideid and r2.rating_type = 'rapid'
             order by r2.period desc limit 1) as rating_rapid,
            (select r2.rating from ratings r2
             where r2.fideid = m.fideid and r2.rating_type = 'blitz'
             order by r2.period desc limit 1) as rating_blitz
        from matches m
    )
    select fideid, name, country, title, rating_standard, rating_rapid, rating_blitz,
           extract(year from current_date)::int - birthday as age
    from pivoted
    order by coalesce(rating_standard, rating_rapid, rating_blitz, 0) desc, name
    limit p_limit offset p_offset;
$function$
;
