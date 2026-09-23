-- Profil athlète en libre-service : photo, description, records personnels (d'entraînement —
-- différents des records officiels FFA) et lien vers la fiche athle.fr. Séparé de `athletes`
-- (géré par les coachs, ex. le nom officiel du roster) : ici l'athlète gère seul ses données,
-- un coach peut seulement les consulter — comme pour les groupes (`group_athletes`).
--
-- `athlete_profiles.id` EST l'id de l'athlète (relation 1:1, table d'extension) : pas de colonne
-- `athlete_id` séparée. `club_id`/`user_id` sont dénormalisés et remplis par trigger (PowerSync ne
-- fait pas de jointure dans ses règles de sync, voir powersync/sync-rules.yaml).

create table public.athlete_profiles (
  id          uuid primary key references public.athletes (id) on delete cascade,
  club_id     uuid not null references public.clubs (id) on delete cascade,
  user_id     uuid not null references auth.users (id) on delete cascade,
  bio         text not null default '',
  avatar_path text,   -- chemin dans le bucket de stockage 'avatars' ; l'URL se dérive côté client
  ffa_url     text,   -- lien externe vers la fiche athle.fr ; pas de récupération automatique
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create function public.athlete_profiles_fill() returns trigger
language plpgsql security definer set search_path = '' as $$
declare a_club uuid; a_user uuid;
begin
  select club_id, user_id into a_club, a_user from public.athletes where id = new.id;
  if a_club is null then raise exception 'athlete_not_found' using errcode = 'P0001'; end if;
  if a_user is null then raise exception 'athlete_has_no_account' using errcode = 'P0001'; end if;
  new.club_id := a_club;
  new.user_id := a_user;
  return new;
end $$;

create trigger athlete_profiles_fill before insert on public.athlete_profiles
  for each row execute function public.athlete_profiles_fill();

-- Records personnels : texte libre pour la performance (unités très différentes selon la
-- discipline — secondes, min:s, mètres...), volontairement pas de parsing/tri structuré ici.
create table public.athlete_records (
  id          uuid primary key default gen_random_uuid(),
  athlete_id  uuid not null references public.athletes (id) on delete cascade,
  club_id     uuid not null references public.clubs (id) on delete cascade,
  user_id     uuid not null references auth.users (id) on delete cascade,
  discipline  text not null check (char_length(btrim(discipline)) > 0),
  performance text not null check (char_length(btrim(performance)) > 0),
  achieved_on date,
  competition text not null default '',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index athlete_records_athlete_idx on public.athlete_records (athlete_id);

create function public.athlete_records_fill() returns trigger
language plpgsql security definer set search_path = '' as $$
declare a_club uuid; a_user uuid;
begin
  select club_id, user_id into a_club, a_user from public.athletes where id = new.athlete_id;
  if a_club is null then raise exception 'athlete_not_found' using errcode = 'P0001'; end if;
  if a_user is null then raise exception 'athlete_has_no_account' using errcode = 'P0001'; end if;
  new.club_id := a_club;
  new.user_id := a_user;
  return new;
end $$;

create trigger athlete_records_fill before insert on public.athlete_records
  for each row execute function public.athlete_records_fill();

create trigger touch_updated_at before update on public.athlete_profiles
  for each row execute function public.touch_updated_at();
create trigger touch_updated_at before update on public.athlete_records
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- RLS : un coach du club voit tout, l'athlète gère seulement le sien.
-- ---------------------------------------------------------------------------

alter table public.athlete_profiles enable row level security;
alter table public.athlete_records  enable row level security;

create policy athlete_profiles_select on public.athlete_profiles for select to authenticated
  using (public.is_coach(club_id) or user_id = (select auth.uid()));
create policy athlete_profiles_insert on public.athlete_profiles for insert to authenticated
  with check (public.is_my_athlete(id));
create policy athlete_profiles_update on public.athlete_profiles for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy athlete_profiles_delete on public.athlete_profiles for delete to authenticated
  using (user_id = (select auth.uid()));

create policy athlete_records_select on public.athlete_records for select to authenticated
  using (public.is_coach(club_id) or user_id = (select auth.uid()));
create policy athlete_records_insert on public.athlete_records for insert to authenticated
  with check (public.is_my_athlete(athlete_id));
create policy athlete_records_update on public.athlete_records for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy athlete_records_delete on public.athlete_records for delete to authenticated
  using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- Stockage des photos de profil. Bucket public : une URL publique est bien plus simple à
-- consommer côté app (pas de rafraîchissement d'URL signée) ; ce n'est qu'une photo de profil,
-- pas une donnée d'entraînement. Écriture restreinte au dossier `{user_id}/…` de chacun.
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

create policy avatars_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy avatars_update on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy avatars_delete on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
