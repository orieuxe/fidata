--! Previous: sha1:1f8056857844036f807ee6da6ef999f1b9549981
--! Hash: sha1:0e57ddea8b184f61c45887456d474ba3385199f9

-- Enter migration here

--! Included functions/search_players.sql
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
    -- latest_ratings already holds each fideid's latest rating per type
    -- (refreshed after every scrape), so no need to re-scan `ratings` here.
    pivoted as (
        select
            fideid,
            max(rating) filter (where rating_type = 'standard') as rating_standard,
            max(rating) filter (where rating_type = 'rapid')    as rating_rapid,
            max(rating) filter (where rating_type = 'blitz')    as rating_blitz
        from latest_ratings
        where fideid in (select fideid from matches)
        group by fideid
    )
    select m.fideid, m.name, m.country, m.title,
           p.rating_standard, p.rating_rapid, p.rating_blitz,
           extract(year from current_date)::int - m.birthday as age
    from matches m
    join pivoted p using (fideid)
    order by coalesce(p.rating_standard, p.rating_rapid, p.rating_blitz, 0) desc, m.name
    limit p_limit offset p_offset;
$function$
;
--! EndIncluded functions/search_players.sql
