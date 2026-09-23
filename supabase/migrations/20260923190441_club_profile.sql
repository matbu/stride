-- Profil libre-service du club : description et logo, gérés par un coach, visibles de tout
-- membre (affichés en haut de l'écran Accueil). Même principe que `athlete_profiles`, mais
-- plus simple : `id` EST déjà l'id du club (pas de club_id séparé à dénormaliser).

create table public.club_profiles (
  id          uuid primary key references public.clubs (id) on delete cascade,
  description text not null default '',
  logo_path   text,   -- chemin dans le bucket de stockage 'club_logos' ; l'URL se dérive côté client
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create trigger touch_updated_at before update on public.club_profiles
  for each row execute function public.touch_updated_at();

alter table public.club_profiles enable row level security;

create policy club_profiles_select on public.club_profiles for select to authenticated
  using (public.is_member(id));
create policy club_profiles_insert on public.club_profiles for insert to authenticated
  with check (public.is_coach(id));
create policy club_profiles_update on public.club_profiles for update to authenticated
  using (public.is_coach(id)) with check (public.is_coach(id));
create policy club_profiles_delete on public.club_profiles for delete to authenticated
  using (public.is_coach(id));

alter publication powersync add table public.club_profiles;

-- ---------------------------------------------------------------------------
-- Stockage du logo. Bucket public, comme 'avatars' : une URL publique est plus simple à
-- consommer côté app, et un logo de club n'est pas une donnée sensible. Écriture restreinte
-- aux coachs du club concerné (dossier `{club_id}/…`).
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public)
values ('club_logos', 'club_logos', true)
on conflict (id) do nothing;

create policy club_logos_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'club_logos' and public.is_coach((storage.foldername(name))[1]::uuid));
create policy club_logos_update on storage.objects for update to authenticated
  using (bucket_id = 'club_logos' and public.is_coach((storage.foldername(name))[1]::uuid));
create policy club_logos_delete on storage.objects for delete to authenticated
  using (bucket_id = 'club_logos' and public.is_coach((storage.foldername(name))[1]::uuid));
