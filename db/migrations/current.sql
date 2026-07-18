-- Enter migration here

-- Switch most_active_players/rating_change from a calendar-year p_year to
-- an explicit p_from/p_to date range, so the frontend can default to a
-- rolling last-12-months window instead of the current calendar year.
drop function if exists most_active_players(integer, text, rating_type, text[], integer, integer, integer, integer);
--!include functions/most_active_players.sql

drop function if exists rating_change(integer, text, rating_type, text[], integer, integer, text, integer, integer);
--!include functions/rating_change.sql
