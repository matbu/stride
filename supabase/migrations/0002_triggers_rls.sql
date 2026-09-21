-- Coach — triggers de cohérence, fonctions d'aide et politiques RLS

-- ---------------------------------------------------------------------------
-- Compte : création du profil à l'inscription
-- ---------------------------------------------------------------------------

create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(nullif(btrim(new.raw_user_meta_data ->> 'display_name'), ''),
             split_part(new.email, '@', 1))
  );
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Propage le changement de nom aux adhésions (copie utilisée par la sync).
create function public.profile_name_changed() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.display_name is distinct from old.display_name then
    update public.memberships set display_name = new.display_name where user_id = new.id;
  end if;
  return new;
end $$;

create trigger profile_name_changed after update on public.profiles
  for each row execute function public.profile_name_changed();

-- ---------------------------------------------------------------------------
-- Cohérence des colonnes dénormalisées (le client ne peut pas les forger)
-- ---------------------------------------------------------------------------

-- group_athletes : club_id vient du groupe, user_id de l'athlète, et les deux doivent
-- appartenir au même club.
create function public.group_athletes_fill() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  g_club uuid;
  a_club uuid;
  a_user uuid;
begin
  select club_id into g_club from public.training_groups where id = new.group_id;
  select club_id, user_id into a_club, a_user from public.athletes where id = new.athlete_id;
  if g_club is null or a_club is null or g_club <> a_club then
    raise exception 'group_and_athlete_must_share_club' using errcode = 'P0001';
  end if;
  new.club_id := g_club;
  new.user_id := a_user;
  return new;
end $$;

create trigger group_athletes_fill before insert on public.group_athletes
  for each row execute function public.group_athletes_fill();

-- Quand une fiche athlète est rattachée (ou détachée) d'un compte, on répercute.
create function public.athletes_user_changed() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.user_id is distinct from old.user_id then
    update public.group_athletes set user_id = new.user_id where athlete_id = new.id;
  end if;
  return new;
end $$;

create trigger athletes_user_changed after update of user_id on public.athletes
  for each row execute function public.athletes_user_changed();

-- sessions : type, groupe et modèle d'origine doivent appartenir au même club.
create function public.sessions_validate() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.session_types t
                 where t.id = new.type_id and t.club_id = new.club_id) then
    raise exception 'type_not_in_club' using errcode = 'P0001';
  end if;
  if new.group_id is not null and not exists (
       select 1 from public.training_groups g
       where g.id = new.group_id and g.club_id = new.club_id) then
    raise exception 'group_not_in_club' using errcode = 'P0001';
  end if;
  if new.template_id is not null and not exists (
       select 1 from public.sessions s
       where s.id = new.template_id and s.club_id = new.club_id) then
    raise exception 'template_not_in_club' using errcode = 'P0001';
  end if;
  return new;
end $$;

create trigger sessions_validate before insert or update on public.sessions
  for each row execute function public.sessions_validate();

-- Un déplacement de séance vers un autre groupe met à jour ses blocs.
create function public.sessions_group_changed() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.group_id is distinct from old.group_id then
    update public.session_blocks set group_id = new.group_id where session_id = new.id;
  end if;
  return new;
end $$;

create trigger sessions_group_changed after update of group_id on public.sessions
  for each row execute function public.sessions_group_changed();

create function public.session_blocks_fill() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  s_club uuid;
  s_group uuid;
begin
  select club_id, group_id into s_club, s_group from public.sessions where id = new.session_id;
  if s_club is null then
    raise exception 'session_not_found' using errcode = 'P0001';
  end if;
  new.club_id := s_club;
  new.group_id := s_group;
  return new;
end $$;

create trigger session_blocks_fill before insert or update of session_id on public.session_blocks
  for each row execute function public.session_blocks_fill();

create function public.event_groups_fill() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  e_club uuid;
  g_club uuid;
begin
  select club_id into e_club from public.events where id = new.event_id;
  select club_id into g_club from public.training_groups where id = new.group_id;
  if e_club is null or g_club is null or e_club <> g_club then
    raise exception 'event_and_group_must_share_club' using errcode = 'P0001';
  end if;
  new.club_id := e_club;
  return new;
end $$;

create trigger event_groups_fill before insert on public.event_groups
  for each row execute function public.event_groups_fill();

-- ---------------------------------------------------------------------------
-- Fonctions d'aide pour les politiques
-- (security definer : elles lisent `memberships` sans repasser par sa RLS)
-- ---------------------------------------------------------------------------

create function public.my_role(p_club uuid) returns public.club_role
language sql stable security definer set search_path = '' as $$
  select m.role from public.memberships m
  where m.club_id = p_club and m.user_id = (select auth.uid()) and m.status = 'active'
$$;

create function public.is_member(p_club uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.my_role(p_club) is not null
$$;

create function public.is_coach(p_club uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(public.my_role(p_club) in ('owner', 'coach'), false)
$$;

create function public.is_owner(p_club uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(public.my_role(p_club) = 'owner', false)
$$;

create function public.in_group(p_group uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.group_athletes ga
    where ga.group_id = p_group and ga.user_id = (select auth.uid())
  )
$$;

create function public.is_my_athlete(p_athlete uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.athletes a
    where a.id = p_athlete and a.user_id = (select auth.uid())
  )
$$;

-- ---------------------------------------------------------------------------
-- RLS
-- Par défaut tout est refusé. Les tables sans politique d'écriture (clubs à la création,
-- memberships, invitations) ne se modifient que par les RPC de 0003_functions.sql.
-- ---------------------------------------------------------------------------

alter table public.profiles            enable row level security;
alter table public.clubs               enable row level security;
alter table public.memberships         enable row level security;
alter table public.training_groups     enable row level security;
alter table public.athletes            enable row level security;
alter table public.group_athletes      enable row level security;
alter table public.invitations         enable row level security;
alter table public.session_types       enable row level security;
alter table public.sessions            enable row level security;
alter table public.session_blocks      enable row level security;
alter table public.events              enable row level security;
alter table public.event_groups        enable row level security;
alter table public.integrations        enable row level security;
alter table public.integration_secrets enable row level security;
alter table public.activities          enable row level security;

-- profiles : chacun le sien. Les noms des autres membres passent par memberships.display_name.
create policy profiles_select on public.profiles for select to authenticated
  using (id = (select auth.uid()));
create policy profiles_update on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- clubs : visible dès qu'on a une adhésion, même en attente ("demande envoyée à …").
create policy clubs_select on public.clubs for select to authenticated
  using (exists (
    select 1 from public.memberships m
    where m.club_id = clubs.id and m.user_id = (select auth.uid())
  ));
create policy clubs_update on public.clubs for update to authenticated
  using (public.is_owner(id)) with check (public.is_owner(id));

-- memberships : lecture seule. Ses propres lignes, les membres actifs du club, et pour un
-- coach les demandes en attente.
create policy memberships_select on public.memberships for select to authenticated
  using (
    user_id = (select auth.uid())
    or public.is_coach(club_id)
    or (status = 'active' and public.is_member(club_id))
  );

-- invitations : lecture par les coachs. Création et révocation par RPC.
create policy invitations_select on public.invitations for select to authenticated
  using (public.is_coach(club_id));

-- training_groups : tous les membres les voient (un athlète choisit son groupe).
create policy training_groups_select on public.training_groups for select to authenticated
  using (public.is_member(club_id));
create policy training_groups_insert on public.training_groups for insert to authenticated
  with check (public.is_coach(club_id));
create policy training_groups_update on public.training_groups for update to authenticated
  using (public.is_coach(club_id)) with check (public.is_coach(club_id));
create policy training_groups_delete on public.training_groups for delete to authenticated
  using (public.is_coach(club_id));

-- athletes : les coachs voient tout le club, un athlète seulement sa propre fiche.
create policy athletes_select on public.athletes for select to authenticated
  using (public.is_coach(club_id) or user_id = (select auth.uid()));
create policy athletes_insert on public.athletes for insert to authenticated
  with check (public.is_coach(club_id));
create policy athletes_update on public.athletes for update to authenticated
  using (public.is_coach(club_id)) with check (public.is_coach(club_id));
create policy athletes_delete on public.athletes for delete to authenticated
  using (public.is_coach(club_id));

-- group_athletes : un athlète rejoint ou quitte librement un groupe de son club.
-- club_id et user_id sont fixés par trigger ; on contrôle donc l'athlète, pas ces colonnes.
create policy group_athletes_select on public.group_athletes for select to authenticated
  using (public.is_coach(club_id) or user_id = (select auth.uid()));
create policy group_athletes_insert on public.group_athletes for insert to authenticated
  with check (public.is_coach(club_id) or public.is_my_athlete(athlete_id));
create policy group_athletes_delete on public.group_athletes for delete to authenticated
  using (public.is_coach(club_id) or user_id = (select auth.uid()));

-- session_types
create policy session_types_select on public.session_types for select to authenticated
  using (public.is_member(club_id));
create policy session_types_insert on public.session_types for insert to authenticated
  with check (public.is_coach(club_id));
create policy session_types_update on public.session_types for update to authenticated
  using (public.is_coach(club_id)) with check (public.is_coach(club_id));

-- sessions : les coachs voient tout ; un athlète voit les séances placées de ses groupes,
-- jamais la bibliothèque de modèles.
create policy sessions_select on public.sessions for select to authenticated
  using (
    public.is_coach(club_id)
    or (not is_template and group_id is not null and public.in_group(group_id))
  );
create policy sessions_insert on public.sessions for insert to authenticated
  with check (public.is_coach(club_id));
create policy sessions_update on public.sessions for update to authenticated
  using (public.is_coach(club_id)) with check (public.is_coach(club_id));
create policy sessions_delete on public.sessions for delete to authenticated
  using (public.is_coach(club_id));

create policy session_blocks_select on public.session_blocks for select to authenticated
  using (
    public.is_coach(club_id)
    or (group_id is not null and public.in_group(group_id))
  );
create policy session_blocks_insert on public.session_blocks for insert to authenticated
  with check (public.is_coach(club_id));
create policy session_blocks_update on public.session_blocks for update to authenticated
  using (public.is_coach(club_id)) with check (public.is_coach(club_id));
create policy session_blocks_delete on public.session_blocks for delete to authenticated
  using (public.is_coach(club_id));

-- events : visibles par tout le club, gérés par les coachs.
create policy events_select on public.events for select to authenticated
  using (public.is_member(club_id));
create policy events_insert on public.events for insert to authenticated
  with check (public.is_coach(club_id));
create policy events_update on public.events for update to authenticated
  using (public.is_coach(club_id)) with check (public.is_coach(club_id));
create policy events_delete on public.events for delete to authenticated
  using (public.is_coach(club_id));

create policy event_groups_select on public.event_groups for select to authenticated
  using (public.is_member(club_id));
create policy event_groups_insert on public.event_groups for insert to authenticated
  with check (public.is_coach(club_id));
create policy event_groups_delete on public.event_groups for delete to authenticated
  using (public.is_coach(club_id));

-- integrations / activities : strictement personnelles pour l'instant.
-- Les conditions de l'API Strava limitent l'affichage des données d'un athlète à d'autres
-- personnes : à vérifier avant d'ouvrir ces lectures aux coachs.
create policy integrations_select on public.integrations for select to authenticated
  using (public.is_my_athlete(athlete_id));
create policy integrations_delete on public.integrations for delete to authenticated
  using (public.is_my_athlete(athlete_id));

create policy activities_select on public.activities for select to authenticated
  using (public.is_my_athlete(athlete_id));

-- integration_secrets : aucune politique = inaccessible aux clients.

-- ---------------------------------------------------------------------------
-- Droits d'exécution des fonctions d'aide
-- ---------------------------------------------------------------------------

revoke all on function public.my_role(uuid), public.is_member(uuid), public.is_coach(uuid),
  public.is_owner(uuid), public.in_group(uuid), public.is_my_athlete(uuid) from public, anon;
grant execute on function public.my_role(uuid), public.is_member(uuid), public.is_coach(uuid),
  public.is_owner(uuid), public.in_group(uuid), public.is_my_athlete(uuid) to authenticated;
