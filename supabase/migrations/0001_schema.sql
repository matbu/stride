-- Coach — schéma initial
--
-- Conventions
--  * Toutes les clés primaires sont des UUID générés côté client (création hors ligne).
--  * Suppressions physiques : PowerSync propage les DELETE. Les entités qu'on ne veut jamais
--    perdre par accident (groupes, types de séance) sont archivées via `archived`.
--  * `club_id` est dénormalisé sur les tables filles : il sert aux politiques RLS et aux
--    règles de sync PowerSync. Des triggers le renseignent, le client ne peut pas le forger.
--  * Les écritures d'administration du club (rôles, invitations, adhésions) passent par des
--    RPC (voir 0003_functions.sql), jamais par des INSERT/UPDATE directs.

create extension if not exists citext with schema extensions;

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

create type public.club_role as enum ('owner', 'coach', 'athlete');
create type public.membership_status as enum ('pending', 'active');
create type public.block_kind as enum ('warmup', 'main', 'cooldown', 'other');
create type public.event_kind as enum ('competition', 'deadline', 'camp', 'other');
create type public.event_priority as enum ('A', 'B', 'C');
create type public.activity_provider as enum ('strava', 'garmin', 'coros');

-- ---------------------------------------------------------------------------
-- Utilitaires
-- ---------------------------------------------------------------------------

create function public.touch_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

-- ---------------------------------------------------------------------------
-- Comptes et clubs
-- ---------------------------------------------------------------------------

create table public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create table public.clubs (
  id         uuid primary key default gen_random_uuid(),
  name       extensions.citext not null unique
             check (name::text = btrim(name::text) and char_length(name::text) between 2 and 80),
  created_by uuid not null references auth.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.memberships (
  id           uuid primary key default gen_random_uuid(),
  club_id      uuid not null references public.clubs (id) on delete cascade,
  user_id      uuid not null references auth.users (id) on delete cascade,
  role         public.club_role not null,
  status       public.membership_status not null default 'pending',
  -- Copie de profiles.display_name (maintenue par trigger) : évite de synchroniser `profiles`.
  display_name text not null default '',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (club_id, user_id),
  -- Le propriétaire est forcément actif : on ne peut pas "demander" à être owner.
  check (status = 'active' or role <> 'owner')
);
create index memberships_user_idx on public.memberships (user_id);
-- Un seul propriétaire ("super coach") par club.
create unique index memberships_one_owner on public.memberships (club_id) where role = 'owner';

create table public.training_groups (
  id         uuid primary key default gen_random_uuid(),
  club_id    uuid not null references public.clubs (id) on delete cascade,
  name       text not null check (char_length(btrim(name)) > 0),
  sort_order int not null default 0,
  archived   boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index training_groups_club_idx on public.training_groups (club_id);

-- Fiche athlète : peut exister sans compte (user_id NULL) puis être rattachée à l'invitation.
create table public.athletes (
  id         uuid primary key default gen_random_uuid(),
  club_id    uuid not null references public.clubs (id) on delete cascade,
  user_id    uuid references auth.users (id) on delete set null,
  full_name  text not null check (char_length(btrim(full_name)) > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index athletes_club_idx on public.athletes (club_id);
create unique index athletes_club_user_idx on public.athletes (club_id, user_id) where user_id is not null;

-- Un groupe peut être vide : aucune contrainte n'impose la présence d'athlètes.
create table public.group_athletes (
  id         uuid primary key default gen_random_uuid(),
  club_id    uuid not null references public.clubs (id) on delete cascade,
  group_id   uuid not null references public.training_groups (id) on delete cascade,
  athlete_id uuid not null references public.athletes (id) on delete cascade,
  -- Copie de athletes.user_id (maintenue par trigger), utilisée par les règles de sync.
  user_id    uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  unique (group_id, athlete_id)
);
create index group_athletes_user_idx on public.group_athletes (user_id);
create index group_athletes_athlete_idx on public.group_athletes (athlete_id);

create table public.invitations (
  id         uuid primary key default gen_random_uuid(),
  club_id    uuid not null references public.clubs (id) on delete cascade,
  code       text not null unique,
  role       public.club_role not null check (role in ('coach', 'athlete')),
  athlete_id uuid references public.athletes (id) on delete set null,
  max_uses   int check (max_uses is null or max_uses > 0) default 1,
  uses       int not null default 0,
  expires_at timestamptz,
  revoked_at timestamptz,
  created_by uuid not null references auth.users (id),
  created_at timestamptz not null default now()
);
create index invitations_club_idx on public.invitations (club_id);

-- ---------------------------------------------------------------------------
-- Séances
-- ---------------------------------------------------------------------------

create table public.session_types (
  id         uuid primary key default gen_random_uuid(),
  club_id    uuid not null references public.clubs (id) on delete cascade,
  name       text not null check (char_length(btrim(name)) > 0),
  color      text not null check (color ~ '^#[0-9A-Fa-f]{6}$'),
  icon       text not null default 'run',
  sort_order int not null default 0,
  archived   boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index session_types_club_idx on public.session_types (club_id);

-- Une ligne = soit un modèle de la bibliothèque (is_template), soit une séance placée
-- (groupe + date). Placer un modèle copie la séance et ses blocs : le modèle peut ensuite
-- évoluer sans réécrire l'historique.
create table public.sessions (
  id             uuid primary key default gen_random_uuid(),
  club_id        uuid not null references public.clubs (id) on delete cascade,
  type_id        uuid not null references public.session_types (id),
  title          text not null check (char_length(btrim(title)) > 0),
  description    text not null default '',
  is_template    boolean not null default false,
  group_id       uuid references public.training_groups (id),
  scheduled_date date,
  start_time     time,
  duration_min   int check (duration_min is null or duration_min > 0),
  location       text not null default '',
  template_id    uuid references public.sessions (id) on delete set null,
  created_by     uuid references auth.users (id),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  check (
    (is_template and group_id is null and scheduled_date is null)
    or (not is_template and group_id is not null and scheduled_date is not null)
  )
);
create index sessions_club_date_idx on public.sessions (club_id, scheduled_date);
create index sessions_group_date_idx on public.sessions (group_id, scheduled_date);

-- Un bloc = une ligne : deux coachs qui modifient deux blocs différents ne se marchent
-- pas dessus. Le détail des exercices est un tableau JSON dans `items`, par exemple
-- [{"reps":6,"distance_m":400,"recovery_s":90,"intensity":"5k","note":""}].
create table public.session_blocks (
  id         uuid primary key default gen_random_uuid(),
  club_id    uuid not null references public.clubs (id) on delete cascade,
  session_id uuid not null references public.sessions (id) on delete cascade,
  group_id   uuid,  -- copie de sessions.group_id (NULL pour un modèle), pour la sync
  kind       public.block_kind not null default 'main',
  position   int not null default 0,
  title      text not null default '',
  notes      text not null default '',
  items      jsonb not null default '[]'::jsonb check (jsonb_typeof(items) = 'array'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index session_blocks_session_idx on public.session_blocks (session_id, position);
create index session_blocks_group_idx on public.session_blocks (group_id);

-- ---------------------------------------------------------------------------
-- Calendrier de saison
-- ---------------------------------------------------------------------------

create table public.events (
  id         uuid primary key default gen_random_uuid(),
  club_id    uuid not null references public.clubs (id) on delete cascade,
  kind       public.event_kind not null,
  title      text not null check (char_length(btrim(title)) > 0),
  start_date date not null,
  end_date   date not null,
  location   text not null default '',
  priority   public.event_priority,
  notes      text not null default '',
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (end_date >= start_date)
);
create index events_club_date_idx on public.events (club_id, start_date);

-- Groupes concernés. Aucune ligne = tout le club.
create table public.event_groups (
  id       uuid primary key default gen_random_uuid(),
  club_id  uuid not null references public.clubs (id) on delete cascade,
  event_id uuid not null references public.events (id) on delete cascade,
  group_id uuid not null references public.training_groups (id) on delete cascade,
  unique (event_id, group_id)
);

-- ---------------------------------------------------------------------------
-- Intégrations (Strava, Garmin, Coros) — schéma prêt, non branché à l'app pour l'instant
-- ---------------------------------------------------------------------------

create table public.integrations (
  id               uuid primary key default gen_random_uuid(),
  club_id          uuid not null references public.clubs (id) on delete cascade,
  athlete_id       uuid not null references public.athletes (id) on delete cascade,
  provider         public.activity_provider not null,
  external_user_id text not null,
  status           text not null default 'active',
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (athlete_id, provider)
);

-- Tokens OAuth : aucune politique RLS, donc lisibles uniquement avec la clé service
-- (Edge Functions). À chiffrer avec Supabase Vault avant la mise en production.
create table public.integration_secrets (
  integration_id uuid primary key references public.integrations (id) on delete cascade,
  access_token   text not null,
  refresh_token  text,
  expires_at     timestamptz
);

create table public.activities (
  id          uuid primary key default gen_random_uuid(),
  club_id     uuid not null references public.clubs (id) on delete cascade,
  athlete_id  uuid not null references public.athletes (id) on delete cascade,
  provider    public.activity_provider not null,
  external_id text not null,
  started_at  timestamptz not null,
  sport       text not null default '',
  name        text not null default '',
  duration_s  int,
  distance_m  numeric,
  avg_hr      int,
  raw         jsonb,
  created_at  timestamptz not null default now(),
  unique (provider, external_id)
);
create index activities_athlete_idx on public.activities (athlete_id, started_at desc);

-- ---------------------------------------------------------------------------
-- Triggers updated_at
-- ---------------------------------------------------------------------------

do $$
declare t text;
begin
  foreach t in array array[
    'profiles', 'clubs', 'memberships', 'training_groups', 'athletes', 'session_types',
    'sessions', 'session_blocks', 'events', 'integrations'
  ] loop
    execute format(
      'create trigger touch_updated_at before update on public.%I
       for each row execute function public.touch_updated_at()', t);
  end loop;
end $$;
