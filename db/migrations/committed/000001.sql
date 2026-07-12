--! Previous: -
--! Hash: sha1:c7887649d1cc184bd3f0d5608a9205fe3e4e07fe

-- Baseline: FIDE rating history schema, functions, and indexes.
-- Squashed from the original 000001-000011 history (local-only DB, no need
-- to preserve migration-by-migration history) -- generated from a
-- pg_dump of the live schema so it's guaranteed to match the actual current
-- state rather than hand-replaying old intermediate steps.

do $$ begin
    create type rating_type as enum ('standard', 'rapid', 'blitz');
exception when duplicate_object then null;
end $$;

create table if not exists ratings (
    fideid      integer     not null,
    period      date        not null,
    rating_type rating_type not null,
    name        text        not null,
    country     text,
    sex         text,
    title       text,
    w_title     text,
    o_title     text,
    birthday    integer,
    rating      integer,
    games       integer,
    k           integer,
    flag        text
);

do $$ begin
    if not exists (select 1 from pg_constraint where conname = 'ratings_pkey') then
        alter table ratings add constraint ratings_pkey primary key (fideid, period, rating_type);
    end if;
end $$;

create index if not exists ratings_period_type_idx on ratings (period, rating_type);
create index if not exists ratings_fideid_idx on ratings (fideid);
create index if not exists ratings_fideid_type_period_idx on ratings (fideid, rating_type, period desc);
create index if not exists ratings_birthday_idx on ratings (birthday);
create index if not exists ratings_title_idx on ratings (title) where title is not null and title <> '';
create index if not exists ratings_country_idx on ratings (country);
create index if not exists ratings_type_country_period_idx on ratings (rating_type, country, period);

-- Distinct country codes, for populating a filter dropdown, with a readable
-- name and ISO alpha-2 (for flag-icons) per FIDE federation code. A live
-- `distinct` over `ratings` takes ~6s at current volume (full scan), so this
-- is a small table the scraper keeps upserted instead (see scraper/src/db.ts).
create table if not exists countries (
    code text primary key,
    name text,
    iso2 text
);

-- Most recent snapshot per player per rating type. Materialized (not a plain
-- view) because a live DISTINCT ON over the full ratings table (61M+ rows)
-- took ~35s per request; data only changes once a month (the scrape cron),
-- so this is refreshed from the scraper after each run instead
-- (REFRESH MATERIALIZED VIEW CONCURRENTLY, see scraper/src/db.ts).
create materialized view if not exists latest_ratings as
    select distinct on (fideid, rating_type) *
    from ratings
    order by fideid, rating_type, period desc
with data;

-- Unique index required for REFRESH MATERIALIZED VIEW CONCURRENTLY (lets
-- refreshes run without blocking reads). Second index serves the "top N by
-- rating within a type" query the top-players page actually runs.
create unique index if not exists latest_ratings_fideid_type_idx on latest_ratings (fideid, rating_type);
create index if not exists latest_ratings_type_rating_idx on latest_ratings (rating_type, rating desc);

-- Most active players (by games played), filterable by year/country/time-control/
-- title/age. Exposed by PostgREST at /rpc/most_active_players.
-- ponytail: an unfiltered call (p_year null + no other filters) does a full-table
-- GroupAggregate, ~75s and growing with every backfilled month. Filtered calls
-- (year/country/type) are fast (tested ~130-600ms). If an unfiltered "all time"
-- view becomes a real access pattern, upgrade to a rollup table
-- (fideid, year, rating_type -> games_sum) refreshed by the scraper.
--
-- The rating shown is the player's latest rating in the filtered time control,
-- defaulting to "standard" when no time control filter is given (a player's games
-- can be summed across multiple time controls, so a single rating column needs a
-- tiebreak).
--
-- The p_year filter is written as a single always-applicable range (coalescing
-- to -infinity/infinity when p_year is null) rather than "p_year is null or
-- (period >= .. and period < ..)". PostgREST calls RPC functions through a
-- LATERAL + json_to_record wrapper that turns parameters into correlated
-- lateral references, which defeats the planner's ability to prove an
-- OR-branched range is sargable -- confirmed via EXPLAIN on the exact query
-- PostgREST sends (full 64M-row Seq Scan with the OR form, index range scan
-- with the coalesce form).
create or replace function most_active_players(
    p_year        integer     default null,
    p_country     text        default null,
    p_rating_type rating_type default null,
    p_titles      text[]      default null,
    p_min_age     integer     default null,
    p_max_age     integer     default null,
    p_limit       integer     default 50,
    p_offset      integer     default 0
)
returns table (
    fideid      integer,
    name        text,
    country     text,
    title       text,
    total_games bigint,
    rating      integer,
    age         integer
)
language sql stable
as $$
    with active as (
        select
            r.fideid,
            max(r.name)     as name,
            max(r.country)  as country,
            max(r.title)    as title,
            max(r.birthday) as birthday,
            sum(coalesce(r.games, 0)) as total_games
        from ratings r
        where r.period >= coalesce(make_date(p_year, 1, 1), '-infinity'::date)
          and r.period <  coalesce(make_date(p_year + 1, 1, 1), 'infinity'::date)
          and (p_country is null or r.country = p_country)
          and (p_rating_type is null or r.rating_type = p_rating_type)
          and (
              p_titles is null or cardinality(p_titles) = 0
              or r.title = any(p_titles)
              or ('UNTITLED' = any(p_titles) and (r.title is null or r.title = ''))
          )
          and (p_min_age is null or (
                  extract(year from r.period)::int - r.birthday
              ) >= p_min_age)
          and (p_max_age is null or (
                  extract(year from r.period)::int - r.birthday
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
              and r2.period <= least(make_date(p_year, 12, 1), current_date)
            order by r2.period desc
            limit 1
        ) as rating,
        coalesce(p_year, extract(year from current_date)::int) - a.birthday as age
    from active a
    order by a.total_games desc;
$$;

-- Rating gainers/losers over a year, filterable the same way. Exposed at
-- /rpc/rating_change.
create or replace function rating_change(
    p_year        integer,
    p_country     text        default null,
    p_rating_type rating_type default null,
    p_titles      text[]      default null,
    p_min_age     integer     default null,
    p_max_age     integer     default null,
    p_direction   text        default 'gain',
    p_limit       integer     default 50,
    p_offset      integer     default 0
)
returns table (
    fideid       integer,
    name         text,
    country      text,
    title        text,
    start_rating integer,
    end_rating   integer,
    delta        integer,
    age          integer
)
language sql stable
as $$
    with candidates as (
        select
            r.fideid,
            max(r.name)     as name,
            max(r.country)  as country,
            max(r.title)    as title,
            max(r.birthday) as birthday
        from ratings r
        where r.period >= make_date(p_year, 1, 1)
          and r.period < make_date(p_year + 1, 1, 1)
          and r.games > 0
          and (p_country is null or r.country = p_country)
          and (p_rating_type is null or r.rating_type = p_rating_type)
          and (
              p_titles is null or cardinality(p_titles) = 0
              or r.title = any(p_titles)
              or ('UNTITLED' = any(p_titles) and (r.title is null or r.title = ''))
          )
          and (p_min_age is null or (p_year - r.birthday) >= p_min_age)
          and (p_max_age is null or (p_year - r.birthday) <= p_max_age)
        group by r.fideid
    ),
    changes as materialized (
        select
            c.fideid, c.name, c.country, c.title, c.birthday,
            (
                select r2.rating from ratings r2
                where r2.fideid = c.fideid
                  and r2.rating_type = coalesce(p_rating_type, 'standard')
                  and r2.period >= make_date(p_year, 1, 1)
                  and r2.period < make_date(p_year + 1, 1, 1)
                order by r2.period asc
                limit 1
            ) as start_rating,
            (
                select r2.rating from ratings r2
                where r2.fideid = c.fideid
                  and r2.rating_type = coalesce(p_rating_type, 'standard')
                  and r2.period >= make_date(p_year, 1, 1)
                  and r2.period <= least(make_date(p_year, 12, 1), current_date)
                order by r2.period desc
                limit 1
            ) as end_rating
        from candidates c
    )
    select fideid, name, country, title, start_rating, end_rating,
           end_rating - start_rating as delta,
           p_year - birthday as age
    from changes
    where start_rating is not null and end_rating is not null
    order by (case when p_direction = 'loss' then end_rating - start_rating
                   else start_rating - end_rating end) asc
    limit p_limit
    offset p_offset;
$$;

-- Top players by rating, filterable the same way (rating_type required,
-- defaults to standard -- "all time controls" doesn't make sense for a
-- single rating ranking). Excludes FIDE-inactive players (flag i/wi).
-- Exposed at /rpc/top_players.
create or replace function top_players(
    p_year        integer     default null,
    p_country     text        default null,
    p_rating_type rating_type default 'standard',
    p_titles      text[]      default null,
    p_min_age     integer     default null,
    p_max_age     integer     default null,
    p_limit       integer     default 25
)
returns table (
    fideid  integer,
    name    text,
    country text,
    title   text,
    rating  integer,
    age     integer
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

insert into countries (code, name, iso2) values
    ('AFG', 'Afghanistan', 'AF'),
    ('AHO', 'Netherlands Antilles (former)', NULL),
    ('ALB', 'Albania', 'AL'),
    ('ALG', 'Algeria', 'DZ'),
    ('AND', 'Andorra', 'AD'),
    ('ANG', 'Angola', 'AO'),
    ('ANT', 'Antigua and Barbuda', 'AG'),
    ('ARG', 'Argentina', 'AR'),
    ('ARM', 'Armenia', 'AM'),
    ('ARU', 'Aruba', 'AW'),
    ('AUS', 'Australia', 'AU'),
    ('AUT', 'Austria', 'AT'),
    ('AZE', 'Azerbaijan', 'AZ'),
    ('BAH', 'Bahamas', 'BS'),
    ('BAN', 'Bangladesh', 'BD'),
    ('BAR', 'Barbados', 'BB'),
    ('BDI', 'Burundi', 'BI'),
    ('BEL', 'Belgium', 'BE'),
    ('BER', 'Bermuda', 'BM'),
    ('BHU', 'Bhutan', 'BT'),
    ('BIH', 'Bosnia and Herzegovina', 'BA'),
    ('BIZ', 'Belize', 'BZ'),
    ('BOL', 'Bolivia', 'BO'),
    ('BOT', 'Botswana', 'BW'),
    ('BRA', 'Brazil', 'BR'),
    ('BRN', 'Bahrain', 'BH'),
    ('BRU', 'Brunei Darussalam', 'BN'),
    ('BUL', 'Bulgaria', 'BG'),
    ('BUR', 'Burkina Faso', 'BF'),
    ('CAF', 'Central African Republic', 'CF'),
    ('CAM', 'Cambodia', 'KH'),
    ('CAN', 'Canada', 'CA'),
    ('CGO', 'Congo', 'CG'),
    ('CHA', 'Chad', 'TD'),
    ('CHI', 'Chile', 'CL'),
    ('CHN', 'China', 'CN'),
    ('CIV', 'Cote d''Ivoire', 'CI'),
    ('CMR', 'Cameroon', 'CM'),
    ('COD', 'Congo, Democratic Republic of the', 'CD'),
    ('COK', 'Cook Islands', 'CK'),
    ('COL', 'Colombia', 'CO'),
    ('COM', 'Comoros', 'KM'),
    ('CPV', 'Cape Verde', 'CV'),
    ('CRC', 'Costa Rica', 'CR'),
    ('CRO', 'Croatia', 'HR'),
    ('CUB', 'Cuba', 'CU'),
    ('CYP', 'Cyprus', 'CY'),
    ('CZE', 'Czech Republic', 'CZ'),
    ('DEN', 'Denmark', 'DK'),
    ('DJI', 'Djibouti', 'DJ'),
    ('DMA', 'Dominica', 'DM'),
    ('DOM', 'Dominican Republic', 'DO'),
    ('ECU', 'Ecuador', 'EC'),
    ('EGY', 'Egypt', 'EG'),
    ('ENG', 'England', NULL),
    ('ERI', 'Eritrea', 'ER'),
    ('ESA', 'El Salvador', 'SV'),
    ('ESP', 'Spain', 'ES'),
    ('EST', 'Estonia', 'EE'),
    ('ETH', 'Ethiopia', 'ET'),
    ('FID', 'FIDE (no federation)', NULL),
    ('FIJ', 'Fiji', 'FJ'),
    ('FRA', 'France', 'FR'),
    ('FSM', 'Micronesia', 'FM'),
    ('GAB', 'Gabon', 'GA'),
    ('GAM', 'Gambia', 'GM'),
    ('GCI', 'Guernsey', 'GG'),
    ('GEO', 'Georgia', 'GE'),
    ('GER', 'Germany', 'DE'),
    ('GHA', 'Ghana', 'GH'),
    ('GRE', 'Greece', 'GR'),
    ('GRN', 'Grenada', 'GD'),
    ('GUA', 'Guatemala', 'GT'),
    ('GUM', 'Guam', 'GU'),
    ('GUY', 'Guyana', 'GY'),
    ('HAI', 'Haiti', 'HT'),
    ('HKG', 'Hong Kong, China', 'HK'),
    ('HON', 'Honduras', 'HN'),
    ('HUN', 'Hungary', 'HU'),
    ('INA', 'Indonesia', 'ID'),
    ('IND', 'India', 'IN'),
    ('Ind', 'Independent', NULL),
    ('IRI', 'Iran', 'IR'),
    ('IRL', 'Ireland', 'IE'),
    ('IRQ', 'Iraq', 'IQ'),
    ('ISL', 'Iceland', 'IS'),
    ('ISR', 'Israel', 'IL'),
    ('ISV', 'US Virgin Islands', 'VI'),
    ('ITA', 'Italy', 'IT'),
    ('IVB', 'British Virgin Islands', 'VG'),
    ('JAM', 'Jamaica', 'JM'),
    ('JCI', 'Jersey', 'JE'),
    ('JOR', 'Jordan', 'JO'),
    ('JPN', 'Japan', 'JP'),
    ('KAZ', 'Kazakhstan', 'KZ'),
    ('KEN', 'Kenya', 'KE'),
    ('KGZ', 'Kyrgyzstan', 'KG'),
    ('KOR', 'Korea', 'KR'),
    ('KOS', 'Kosovo', 'XK'),
    ('KSA', 'Saudi Arabia', 'SA'),
    ('KUW', 'Kuwait', 'KW'),
    ('LAO', 'Laos', 'LA'),
    ('LAT', 'Latvia', 'LV'),
    ('LBA', 'Libya', 'LY'),
    ('LBR', 'Liberia', 'LR'),
    ('LCA', 'Saint Lucia', 'LC'),
    ('LES', 'Lesotho', 'LS'),
    ('LIB', 'Lebanon', 'LB'),
    ('LIE', 'Liechtenstein', 'LI'),
    ('LTU', 'Lithuania', 'LT'),
    ('LUX', 'Luxembourg', 'LU'),
    ('MAC', 'Macau, China', 'MO'),
    ('MAD', 'Madagascar', 'MG'),
    ('MAR', 'Morocco', 'MA'),
    ('MAS', 'Malaysia', 'MY'),
    ('MAW', 'Malawi', 'MW'),
    ('MDA', 'Moldova', 'MD'),
    ('MDV', 'Maldives', 'MV'),
    ('MEX', 'Mexico', 'MX'),
    ('MGL', 'Mongolia', 'MN'),
    ('MKD', 'North Macedonia', 'MK'),
    ('MLI', 'Mali', 'ML'),
    ('MLT', 'Malta', 'MT'),
    ('MNC', 'Monaco', 'MC'),
    ('MNE', 'Montenegro', 'ME'),
    ('MOZ', 'Mozambique', 'MZ'),
    ('MRI', 'Mauritius', 'MU'),
    ('MTN', 'Mauritania', 'MR'),
    ('MYA', 'Myanmar', 'MM'),
    ('NAM', 'Namibia', 'NA'),
    ('NCA', 'Nicaragua', 'NI'),
    ('NED', 'Netherlands', 'NL'),
    ('NEP', 'Nepal', 'NP'),
    ('NGR', 'Nigeria', 'NG'),
    ('NON', 'Non-affiliated', NULL),
    ('NOR', 'Norway', 'NO'),
    ('NRU', 'Nauru', 'NR'),
    ('NZL', 'New Zealand', 'NZ'),
    ('OMA', 'Oman', 'OM'),
    ('PAK', 'Pakistan', 'PK'),
    ('PAN', 'Panama', 'PA'),
    ('PAR', 'Paraguay', 'PY'),
    ('PER', 'Peru', 'PE'),
    ('PHI', 'Philippines', 'PH'),
    ('PLE', 'Palestine', 'PS'),
    ('PLW', 'Palau', 'PW'),
    ('PNG', 'Papua New Guinea', 'PG'),
    ('POL', 'Poland', 'PL'),
    ('POR', 'Portugal', 'PT'),
    ('PUR', 'Puerto Rico', 'PR'),
    ('QAT', 'Qatar', 'QA'),
    ('ROU', 'Romania', 'RO'),
    ('RSA', 'South Africa', 'ZA'),
    ('RUS', 'Russia', 'RU'),
    ('RWA', 'Rwanda', 'RW'),
    ('SAM', 'Samoa', 'WS'),
    ('SCO', 'Scotland', NULL),
    ('SEN', 'Senegal', 'SN'),
    ('SEY', 'Seychelles', 'SC'),
    ('SIN', 'Singapore', 'SG'),
    ('SKN', 'Saint Kitts and Nevis', 'KN'),
    ('SLE', 'Sierra Leone', 'SL'),
    ('SLO', 'Slovenia', 'SI'),
    ('SMR', 'San Marino', 'SM'),
    ('SOL', 'Solomon Islands', 'SB'),
    ('SOM', 'Somalia', 'SO'),
    ('SRB', 'Serbia', 'RS'),
    ('SRI', 'Sri Lanka', 'LK'),
    ('SSD', 'South Sudan', 'SS'),
    ('STP', 'Sao Tome and Principe', 'ST'),
    ('SUD', 'Sudan', 'SD'),
    ('SUI', 'Switzerland', 'CH'),
    ('SUR', 'Suriname', 'SR'),
    ('SVK', 'Slovakia', 'SK'),
    ('SWE', 'Sweden', 'SE'),
    ('SWZ', 'Eswatini', 'SZ'),
    ('SYR', 'Syria', 'SY'),
    ('TAN', 'Tanzania', 'TZ'),
    ('TGA', 'Tonga', 'TO'),
    ('THA', 'Thailand', 'TH'),
    ('TJK', 'Tajikistan', 'TJ'),
    ('TKM', 'Turkmenistan', 'TM'),
    ('TLS', 'Timor-Leste', 'TL'),
    ('TOG', 'Togo', 'TG'),
    ('TPE', 'Chinese Taipei', 'TW'),
    ('TTO', 'Trinidad and Tobago', 'TT'),
    ('TUN', 'Tunisia', 'TN'),
    ('TUR', 'Turkiye', 'TR'),
    ('UAE', 'United Arab Emirates', 'AE'),
    ('UGA', 'Uganda', 'UG'),
    ('UKR', 'Ukraine', 'UA'),
    ('URU', 'Uruguay', 'UY'),
    ('USA', 'United States of America', 'US'),
    ('UZB', 'Uzbekistan', 'UZ'),
    ('VAN', 'Vanuatu', 'VU'),
    ('VEN', 'Venezuela', 'VE'),
    ('VIE', 'Vietnam', 'VN'),
    ('VIN', 'Saint Vincent and the Grenadines', 'VC'),
    ('WLS', 'Wales', NULL),
    ('YEM', 'Yemen', 'YE'),
    ('ZAM', 'Zambia', 'ZM'),
    ('ZIM', 'Zimbabwe', 'ZW')
on conflict (code) do update set name = excluded.name, iso2 = excluded.iso2;
