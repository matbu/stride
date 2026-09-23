-- Émule le strict minimum de Supabase pour exécuter les migrations sur un Postgres nu.
-- (Sur un vrai projet Supabase, tout ceci existe déjà : ne pas exécuter.)

-- Les rôles sont globaux au cluster : on tolère qu'ils existent déjà.
do $$
begin
  create role anon nologin;
exception when duplicate_object then null;
end $$;
do $$
begin
  create role authenticated nologin;
exception when duplicate_object then null;
end $$;
do $$
begin
  create role service_role nologin bypassrls;
exception when duplicate_object then null;
end $$;

create schema auth;
create schema extensions;

create table auth.users (
  id                 uuid primary key default gen_random_uuid(),
  email              text,
  raw_user_meta_data jsonb not null default '{}'
);

create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

-- Stockage (minimal : juste ce dont les migrations ont besoin pour créer un bucket et ses
-- politiques — pas d'API réelle de fichiers, on ne teste que le SQL).
create schema storage;

create table storage.buckets (
  id     text primary key,
  name   text not null,
  public boolean not null default false
);

create table storage.objects (
  id        uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets (id),
  name      text,
  owner     uuid
);
alter table storage.objects enable row level security;

create function storage.foldername(name text) returns text[]
language sql immutable as $$
  select (string_to_array(name, '/'))[1 : array_length(string_to_array(name, '/'), 1) - 1]
$$;

-- Sur un vrai projet Supabase, ces tables ont déjà les GRANTs table par table (indépendants du
-- schéma `public`, donc pas couverts par le `alter default privileges` plus bas) : la RLS est ce
-- qui protège, pas l'absence de droit.
grant select, insert, update, delete on storage.objects, storage.buckets to anon, authenticated, service_role;

grant usage on schema public, auth, extensions, storage to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;

-- Privilèges par défaut de Supabase : tout est ouvert, c'est la RLS qui protège.
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;
