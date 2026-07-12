-- FIDE rating history, one row per player per month per rating type.
create type rating_type as enum ('standard', 'rapid', 'blitz');

create table ratings (
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
    flag        text,
    primary key (fideid, period, rating_type)
);

create index ratings_period_type_idx on ratings (period, rating_type);
create index ratings_fideid_idx on ratings (fideid);

-- Most recent snapshot per player per rating type, for "current" lookups.
create view latest_ratings as
    select distinct on (fideid, rating_type) *
    from ratings
    order by fideid, rating_type, period desc;
