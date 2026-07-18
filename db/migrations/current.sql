-- Male/female filter (see TODO.md) -- ratings.sex was already scraped, just
-- not exposed as a p_sex param anywhere. rating_change_snapshots is a frozen
-- copy of ratings columns per (bucket, fideid, rating_type) (see 000009.sql),
-- so it needs its own sex column, backfilled once here since the 'rolling'
-- bucket is the only one the scraper ever rewrites -- frozen year buckets
-- would otherwise carry a null sex forever.
alter table rating_change_snapshots add column if not exists sex text;

update rating_change_snapshots s
set sex = r.sex
from (
    select distinct on (fideid, rating_type) fideid, rating_type, sex
    from ratings
    where sex is not null
    order by fideid, rating_type, period desc
) r
where r.fideid = s.fideid and r.rating_type = s.rating_type and s.sex is null;

-- p_sex is inserted mid-signature (next to p_country) rather than appended,
-- so `create or replace` doesn't overload the old signature -- Postgres
-- resolves overloads by argument list, and the old one would otherwise stay
-- callable and ambiguous with the new one for any named-param PostgREST call.
drop function if exists public.top_players(integer, text, rating_type, text[], integer, integer, integer);
drop function if exists public.rating_change(date, date, text, rating_type, text[], integer, integer, text, integer, integer);
drop function if exists public.most_active_players(date, date, text, rating_type, text[], integer, integer, integer, integer);

--!include functions/top_players.sql
--!include functions/rating_change.sql
--!include functions/most_active_players.sql
