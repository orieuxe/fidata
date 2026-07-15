create or replace function public.player_profile(p_fideid integer)
 returns table(fideid integer, name text, country text, title text, age integer, rating_standard integer, rating_rapid integer, rating_blitz integer, max_standard integer, max_rapid integer, max_blitz integer, rank_country_standard bigint, rank_world_standard bigint)
 language sql
 stable
as $function$
    with base as (
        select * from latest_ratings where fideid = p_fideid
    ),
    picked as (
        select fideid, name, country, title, birthday
        from base
        order by case rating_type when 'standard' then 0 when 'rapid' then 1 else 2 end
        limit 1
    ),
    std as (
        select rating from base where rating_type = 'standard'
    )
    select
        p.fideid, p.name, p.country, p.title,
        extract(year from current_date)::int - p.birthday as age,
        (select rating from base where rating_type = 'standard') as rating_standard,
        (select rating from base where rating_type = 'rapid') as rating_rapid,
        (select rating from base where rating_type = 'blitz') as rating_blitz,
        (select max(rating) from ratings where fideid = p_fideid and rating_type = 'standard') as max_standard,
        (select max(rating) from ratings where fideid = p_fideid and rating_type = 'rapid') as max_rapid,
        (select max(rating) from ratings where fideid = p_fideid and rating_type = 'blitz') as max_blitz,
        case when (select rating from std) is not null then
            (select count(*) + 1 from latest_ratings lr
             where lr.rating_type = 'standard' and lr.country = p.country and lr.rating > (select rating from std)
               and coalesce(lr.flag, '') not like '%i%')
        end as rank_country_standard,
        case when (select rating from std) is not null then
            (select count(*) + 1 from latest_ratings lr
             where lr.rating_type = 'standard' and lr.rating > (select rating from std)
               and coalesce(lr.flag, '') not like '%i%')
        end as rank_world_standard
    from picked p;
$function$
;
