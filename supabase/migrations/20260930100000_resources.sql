-- Ressources pédagogiques du club : liens (YouTube, Instagram, web) et courts médias (photo,
-- vidéo) rangés dans la bibliothèque, consultables par tout membre, gérés par les coachs.
--
-- Confidentialité :
--  * `club` : visible des seuls membres du club ;
--  * `public` : visible de tout utilisateur connecté, qui peut l'ajouter à son propre club.
--
-- Ajouter une ressource publique d'un autre club crée une ligne « référence » dans son club
-- (`source_id` renseigné) plutôt qu'une table de liaison : les règles de sync PowerSync ne font
-- pas de jointure, une ligne portant le `club_id` du club qui l'utilise se synchronise comme
-- tout le reste (voir powersync/sync-rules.yaml). Le contenu d'une référence est recopié de
-- l'originale par trigger et la suit : modifiée → recopiée, supprimée ou repassée en `club` →
-- la référence disparaît. Le fichier n'est jamais dupliqué : `storage_path` pointe sur celui de
-- l'originale.

create table public.resources (
  id           uuid primary key default gen_random_uuid(),
  club_id      uuid not null references public.clubs (id) on delete cascade,
  source_id    uuid references public.resources (id) on delete cascade,
  kind         text not null check (kind in ('youtube', 'instagram', 'link', 'image', 'video')),
  title        text not null check (char_length(btrim(title)) > 0),
  description  text not null default '',
  url          text check (url ~* '^https?://'),   -- liens uniquement
  storage_path text,   -- médias uniquement : chemin dans le bucket 'resources' ({club_id}/…)
  visibility   text not null default 'club' check (visibility in ('club', 'public')),
  created_by   uuid references auth.users (id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  check ((kind in ('image', 'video')) = (storage_path is not null)),
  check ((kind in ('youtube', 'instagram', 'link')) = (url is not null)),
  -- Une référence n'est jamais republiée : seule l'originale est « la » ressource publique.
  check (source_id is null or visibility = 'club'),
  unique (club_id, source_id)
);
create index resources_club_idx on public.resources (club_id);
create index resources_public_idx on public.resources (created_at desc)
  where visibility = 'public' and source_id is null;

create trigger touch_updated_at before update on public.resources
  for each row execute function public.touch_updated_at();

-- Avant écriture : une référence recopie son originale (qui doit être publique, d'un autre
-- club) ; club, origine, nature et fichier d'une ressource ne changent plus après création.
create function public.resources_fill() returns trigger
language plpgsql security definer set search_path = '' as $$
declare src public.resources;
begin
  if tg_op = 'UPDATE' then
    new.club_id := old.club_id;
    new.source_id := old.source_id;
    new.kind := old.kind;
    new.storage_path := old.storage_path;
  end if;
  if new.source_id is not null then
    select * into src from public.resources where id = new.source_id;
    if src.id is null or src.visibility <> 'public' or src.source_id is not null then
      raise exception 'resource_not_public' using errcode = 'P0001';
    end if;
    if src.club_id = new.club_id then
      raise exception 'resource_own_club' using errcode = 'P0001';
    end if;
    new.kind := src.kind;
    new.title := src.title;
    new.description := src.description;
    new.url := src.url;
    new.storage_path := src.storage_path;
    new.visibility := 'club';
  elsif new.storage_path is not null and split_part(new.storage_path, '/', 1) <> new.club_id::text then
    -- Sinon un coach pourrait « adopter » le fichier privé d'un autre club en y pointant, et
    -- gagner le droit de le lire (voir `can_read_resource_file`).
    raise exception 'resource_foreign_file' using errcode = 'P0001';
  end if;
  return new;
end $$;

create trigger resources_fill before insert or update on public.resources
  for each row execute function public.resources_fill();

-- Après modification d'une originale : ses références la suivent, ou disparaissent si elle
-- n'est plus publique.
create function public.resources_propagate() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.visibility <> 'public' then
    delete from public.resources where source_id = new.id;
  else
    update public.resources
       set title = new.title, description = new.description, url = new.url
     where source_id = new.id;
  end if;
  return null;
end $$;

create trigger resources_propagate after update on public.resources
  for each row when (old.source_id is null
                     and (old.visibility, old.title, old.description, old.url)
                         is distinct from (new.visibility, new.title, new.description, new.url))
  execute function public.resources_propagate();

-- ---------------------------------------------------------------------------
-- RLS : tout membre lit les ressources de son club, tout connecté lit les originales
-- publiques (pour les parcourir) ; seuls les coachs écrivent.
-- ---------------------------------------------------------------------------

alter table public.resources enable row level security;

create policy resources_select on public.resources for select to authenticated
  using (public.is_member(club_id) or (visibility = 'public' and source_id is null));
create policy resources_insert on public.resources for insert to authenticated
  with check (public.is_coach(club_id) and (created_by is null or created_by = (select auth.uid())));
create policy resources_update on public.resources for update to authenticated
  using (public.is_coach(club_id)) with check (public.is_coach(club_id));
create policy resources_delete on public.resources for delete to authenticated
  using (public.is_coach(club_id));

alter publication powersync add table public.resources;

-- ---------------------------------------------------------------------------
-- Ressources attachées à une séance (ou à un modèle) : ids de `resources`, dans l'ordre.
-- Une colonne plutôt qu'une table : elle voyage avec la séance (copie d'un modèle placé,
-- synchronisation vers les athlètes du groupe) sans règle de sync ni trigger de plus. Un id
-- dont la ressource a été supprimée est simplement ignoré à l'affichage.
-- ---------------------------------------------------------------------------

alter table public.sessions add column resource_ids jsonb not null default '[]'::jsonb
  check (jsonb_typeof(resource_ids) = 'array');

-- ---------------------------------------------------------------------------
-- Stockage des médias. Bucket privé, contrairement à 'avatars' / 'club_logos' : une vidéo
-- réservée au club ne doit pas être lisible par qui devine l'URL. L'app passe par des URL
-- signées. Taille et formats bornés côté serveur (20 Mo, photos et vidéos courantes).
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'resources', 'resources', false, 20971520,
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'video/mp4', 'video/quicktime']
)
on conflict (id) do nothing;

-- Lecture d'un fichier : via une ressource que l'on a le droit de voir (celle de son club, une
-- référence dans son club, ou une originale publique).
create function public.can_read_resource_file(p_name text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.resources r
    where r.storage_path = p_name
      and (r.visibility = 'public' or public.is_member(r.club_id))
  )
$$;

-- `is_coach(dossier)` dans la politique SELECT : l'upload se termine par un `RETURNING *`
-- (voir la migration `storage_select_policy`), avant que la ligne `resources` n'existe.
create policy resources_files_select on storage.objects for select to authenticated
  using (bucket_id = 'resources'
         and (public.is_coach((storage.foldername(name))[1]::uuid) or public.can_read_resource_file(name)));
create policy resources_files_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'resources' and public.is_coach((storage.foldername(name))[1]::uuid));
create policy resources_files_update on storage.objects for update to authenticated
  using (bucket_id = 'resources' and public.is_coach((storage.foldername(name))[1]::uuid));
create policy resources_files_delete on storage.objects for delete to authenticated
  using (bucket_id = 'resources' and public.is_coach((storage.foldername(name))[1]::uuid));
