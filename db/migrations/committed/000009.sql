--! Previous: sha1:4f60512d9f8e4c3ddeea23c3cfbde4e442705435
--! Hash: sha1:4a35cb3cfd7f0e8b1394be56e76feeeb929ffb90

-- Top players by rating, filterable the same way as most_active_players /
-- rating_change (year/country/title/age), excluding FIDE-inactive players.
-- rating_type has no "all" state on purpose: ranking players by rating only
-- makes sense within a single time control.
create function top_players(
    p_year        integer     default null,
    p_country     text        default null,
    p_rating_type rating_type default 'standard',
    p_titles      text[]      default null,
    p_min_age     integer     default null,
    p_max_age     integer     default null,
    p_limit       integer     default 25
)
returns table (
    fideid integer,
    name   text,
    country text,
    title  text,
    rating integer,
    age    integer
)
language sql stable
as $$
    with filtered as (
        select distinct on (r.fideid)
            r.fideid, r.name, r.country, r.title, r.birthday, r.rating
        from ratings r
        where r.rating_type = p_rating_type
          and r.period >= coalesce(make_date(p_year, 1, 1), '-infinity'::date)
          and r.period <= least(make_date(p_year, 12, 1), current_date)
          and coalesce(r.flag, '') not like '%i%'
          and (p_country is null or r.country = p_country)
          and (
              p_titles is null or cardinality(p_titles) = 0
              or r.title = any(p_titles)
              or ('UNTITLED' = any(p_titles) and (r.title is null or r.title = ''))
          )
        order by r.fideid, r.period desc
    )
    select fideid, name, country, title, rating,
           coalesce(p_year, extract(year from current_date)::int) - birthday as age
    from filtered
    where rating is not null
      and (p_min_age is null or (coalesce(p_year, extract(year from current_date)::int) - birthday) >= p_min_age)
      and (p_max_age is null or (coalesce(p_year, extract(year from current_date)::int) - birthday) <= p_max_age)
    order by rating desc
    limit p_limit;
$$;
