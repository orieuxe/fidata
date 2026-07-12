--! Previous: sha1:c7887649d1cc184bd3f0d5608a9205fe3e4e07fe
--! Hash: sha1:437aea6168d9f91c678c5243de6bd3575f065e46

-- Security fix: PostgREST's db-anon-role was set to "postgres" (the
-- superuser), so every unauthenticated request the public API serves --
-- once this is deployed off localhost -- would execute as superuser,
-- capable of arbitrary writes/DDL. This app is read-only from the
-- frontend, so give PostgREST a role that can only SELECT/EXECUTE.
do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'web_anon') then
        create role web_anon nologin;
    end if;
end $$;

grant usage on schema public to web_anon;
grant select on ratings, latest_ratings, countries to web_anon;
grant execute on all functions in schema public to web_anon;
