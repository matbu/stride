-- Oubli de la migration athlete_profile : la publication `powersync` liste ses tables
-- explicitement (voir 0004_powersync.sql), les deux nouvelles n'y étaient pas.
alter publication powersync add table public.athlete_profiles, public.athlete_records;
