--! Previous: sha1:599cf47e25a7b85608f5c3c3b4c1f1f7b24e5efd
--! Hash: sha1:74d845a2991da439ba561d09660a73029188655b

-- Perf fix: latest_ratings was a plain view doing DISTINCT ON over the full
-- ratings table (61M+ rows) on every request -- ~35s (full seq scan + ~2GB
-- disk sort) just to serve the top-25 standard list. Data only changes once
-- a month (the scrape cron), so materialize it and refresh from the scraper
-- after each run instead of recomputing on every page load.
drop view if exists latest_ratings;

create materialized view latest_ratings as
    select distinct on (fideid, rating_type) *
    from ratings
    order by fideid, rating_type, period desc;

-- Unique index required for REFRESH MATERIALIZED VIEW CONCURRENTLY (lets
-- refreshes run without blocking reads). Second index serves the "top N by
-- rating within a type" query the top-players page actually runs.
create unique index if not exists latest_ratings_fideid_type_idx on latest_ratings (fideid, rating_type);
create index if not exists latest_ratings_type_rating_idx on latest_ratings (rating_type, rating desc);
