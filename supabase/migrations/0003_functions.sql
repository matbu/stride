-- Coach — RPC d'administration du club
--
-- Tout ce qui touche aux rôles, aux adhésions et aux invitations passe ici : ces opérations
-- nécessitent d'être en ligne et sont validées côté serveur. Les erreurs métier sont des
-- exceptions dont le message est un code stable (ex. 'club_name_taken') que l'app traduit.

create function public.display_name_of(p_user uuid) returns text
language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select nullif(btrim(p.display_name), '') from public.profiles p where p.id = p_user),
    'Sans nom')
$$;

-- Crée la fiche athlète d'un compte s'il n'en a pas encore dans ce club.
create function public._ensure_athlete(p_club uuid, p_user uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  select id into v_id from public.athletes where club_id = p_club and user_id = p_user;
  if v_id is null then
    insert into public.athletes (club_id, user_id, full_name)
    values (p_club, p_user, public.display_name_of(p_user))
    returning id into v_id;
  end if;
  return v_id;
end $$;

-- Détache un compte du club : la fiche athlète reste (historique) mais n'est plus liée.
create function public._detach_user(p_club uuid, p_user uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.athletes set user_id = null where club_id = p_club and user_id = p_user;
  delete from public.memberships where club_id = p_club and user_id = p_user;
end $$;

-- ---------------------------------------------------------------------------
-- Créer un club
-- ---------------------------------------------------------------------------

create function public.create_club(p_name text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_uid  uuid := auth.uid();
  v_name text := btrim(p_name);
  v_club uuid;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if char_length(v_name) not between 2 and 80 then raise exception 'invalid_club_name'; end if;

  begin
    insert into public.clubs (name, created_by) values (v_name, v_uid) returning id into v_club;
  exception when unique_violation then
    raise exception 'club_name_taken';
  end;

  insert into public.memberships (club_id, user_id, role, status, display_name)
  values (v_club, v_uid, 'owner', 'active', public.display_name_of(v_uid));

  -- Types de séance par défaut, modifiables ensuite par les coachs.
  insert into public.session_types (club_id, name, color, icon, sort_order) values
    (v_club, 'Endurance',       '#2E9E5B', 'run',        0),
    (v_club, 'Fractionné',      '#E5484D', 'bolt',       1),
    (v_club, 'Seuil / Tempo',   '#F5A524', 'speed',      2),
    (v_club, 'Vitesse',         '#8E4EC6', 'sprint',     3),
    (v_club, 'Côtes',           '#B5651D', 'hill',       4),
    (v_club, 'Musculation',     '#3E63DD', 'dumbbell',   5),
    (v_club, 'Technique',       '#12A594', 'technique',  6),
    (v_club, 'Récupération',    '#7D8590', 'recovery',   7);

  return v_club;
end $$;

-- ---------------------------------------------------------------------------
-- Rejoindre un club : recherche, demande, validation
-- ---------------------------------------------------------------------------

-- Recherche par nom exact (insensible à la casse) : on n'expose pas la liste des clubs.
-- lower() plutôt que l'opérateur citext, invisible avec search_path = ''.
create function public.find_club(p_name text) returns table (id uuid, name text)
language sql stable security definer set search_path = '' as $$
  select c.id, c.name::text from public.clubs c
  where auth.uid() is not null and lower(c.name::text) = lower(btrim(p_name))
$$;

create function public.request_join(p_club uuid, p_role public.club_role) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_existing public.memberships;
  v_id uuid;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if p_role not in ('coach', 'athlete') then raise exception 'invalid_role'; end if;
  if not exists (select 1 from public.clubs where id = p_club) then
    raise exception 'club_not_found';
  end if;

  select * into v_existing from public.memberships where club_id = p_club and user_id = v_uid;
  if found then
    raise exception '%', case v_existing.status when 'active' then 'already_member'
                                                else 'already_requested' end;
  end if;

  insert into public.memberships (club_id, user_id, role, status, display_name)
  values (p_club, v_uid, p_role, 'pending', public.display_name_of(v_uid))
  returning id into v_id;
  return v_id;
end $$;

-- Un coach valide les athlètes ; seul le propriétaire valide les coachs.
create function public._can_decide(p_membership public.memberships) returns boolean
language sql stable security definer set search_path = '' as $$
  select case p_membership.role
    when 'coach' then public.is_owner(p_membership.club_id)
    else public.is_coach(p_membership.club_id)
  end
$$;

create function public.approve_membership(p_membership uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare m public.memberships;
begin
  select * into m from public.memberships where id = p_membership and status = 'pending' for update;
  if not found then raise exception 'request_not_found'; end if;
  if not public._can_decide(m) then raise exception 'forbidden'; end if;

  update public.memberships set status = 'active' where id = m.id;
  if m.role = 'athlete' then perform public._ensure_athlete(m.club_id, m.user_id); end if;
end $$;

create function public.reject_membership(p_membership uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare m public.memberships;
begin
  select * into m from public.memberships where id = p_membership and status = 'pending' for update;
  if not found then raise exception 'request_not_found'; end if;
  if not public._can_decide(m) then raise exception 'forbidden'; end if;
  delete from public.memberships where id = m.id;
end $$;

-- ---------------------------------------------------------------------------
-- Invitations
-- ---------------------------------------------------------------------------

-- Code de 12 caractères hexadécimaux (48 bits, tirés d'un UUID v4 cryptographique).
create function public._new_invitation_code() returns text
language sql volatile set search_path = '' as $$
  select upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12))
$$;

create function public._normalize_code(p_code text) returns text
language sql immutable set search_path = '' as $$
  select upper(regexp_replace(coalesce(p_code, ''), '[^0-9A-Za-z]', '', 'g'))
$$;

-- Un coach invite des athlètes ; seul le propriétaire invite des coachs.
-- p_max_uses NULL = code réutilisable (ex. à poster dans un groupe WhatsApp).
create function public.create_invitation(
  p_club uuid,
  p_role public.club_role,
  p_athlete uuid default null,
  p_max_uses int default 1,
  p_expires_days int default 14
) returns text
language plpgsql security definer set search_path = '' as $$
declare v_code text;
begin
  if p_role = 'coach' then
    if not public.is_owner(p_club) then raise exception 'forbidden'; end if;
  elsif p_role = 'athlete' then
    if not public.is_coach(p_club) then raise exception 'forbidden'; end if;
  else
    raise exception 'invalid_role';
  end if;

  if p_athlete is not null and not exists (
       select 1 from public.athletes where id = p_athlete and club_id = p_club) then
    raise exception 'athlete_not_in_club';
  end if;

  v_code := public._new_invitation_code();
  insert into public.invitations (club_id, code, role, athlete_id, max_uses, expires_at, created_by)
  values (p_club, v_code, p_role, p_athlete, p_max_uses,
          case when p_expires_days is null then null
               else now() + make_interval(days => p_expires_days) end,
          auth.uid());
  return v_code;
end $$;

create function public.revoke_invitation(p_invitation uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare i public.invitations;
begin
  select * into i from public.invitations where id = p_invitation;
  if not found or not public.is_coach(i.club_id) then raise exception 'forbidden'; end if;
  update public.invitations set revoked_at = coalesce(revoked_at, now()) where id = i.id;
end $$;

-- Aperçu avant d'accepter : "Rejoindre <club> en tant que <rôle>".
create function public.preview_invitation(p_code text)
returns table (club_id uuid, club_name text, role public.club_role, valid boolean)
language sql stable security definer set search_path = '' as $$
  select i.club_id, c.name::text, i.role,
         (i.revoked_at is null
          and (i.expires_at is null or i.expires_at > now())
          and (i.max_uses is null or i.uses < i.max_uses))
  from public.invitations i
  join public.clubs c on c.id = i.club_id
  where auth.uid() is not null and i.code = public._normalize_code(p_code)
$$;

create function public.accept_invitation(p_code text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  i public.invitations;
  v_existing public.memberships;
  v_athlete uuid;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  select * into i from public.invitations
  where code = public._normalize_code(p_code) for update;
  if not found then raise exception 'invitation_not_found'; end if;
  if i.revoked_at is not null
     or (i.expires_at is not null and i.expires_at <= now())
     or (i.max_uses is not null and i.uses >= i.max_uses) then
    raise exception 'invitation_invalid';
  end if;

  select * into v_existing from public.memberships where club_id = i.club_id and user_id = v_uid;
  if found and v_existing.status = 'active' then raise exception 'already_member'; end if;

  -- Une invitation vaut approbation : elle remplace une éventuelle demande en attente.
  insert into public.memberships (club_id, user_id, role, status, display_name)
  values (i.club_id, v_uid, i.role, 'active', public.display_name_of(v_uid))
  on conflict (club_id, user_id)
  do update set role = excluded.role, status = 'active';

  if i.role = 'athlete' then
    -- Fiche créée à l'avance par le coach : on la rattache si elle est libre.
    if i.athlete_id is not null then
      update public.athletes set user_id = v_uid
      where id = i.athlete_id and user_id is null
        and not exists (select 1 from public.athletes
                        where club_id = i.club_id and user_id = v_uid)
      returning id into v_athlete;
    end if;
    if v_athlete is null then perform public._ensure_athlete(i.club_id, v_uid); end if;
  end if;

  update public.invitations set uses = uses + 1 where id = i.id;
  return i.club_id;
end $$;

-- ---------------------------------------------------------------------------
-- Gestion des membres
-- ---------------------------------------------------------------------------

-- Passer la main : le propriétaire actuel devient coach, le coach désigné devient propriétaire.
create function public.transfer_ownership(p_club uuid, p_new_owner uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid();
begin
  if not public.is_owner(p_club) then raise exception 'forbidden'; end if;
  if p_new_owner = v_uid then raise exception 'already_owner'; end if;
  if not exists (select 1 from public.memberships
                 where club_id = p_club and user_id = p_new_owner
                   and role = 'coach' and status = 'active') then
    raise exception 'new_owner_must_be_active_coach';
  end if;

  -- Ordre important : l'index d'unicité n'autorise qu'un propriétaire à la fois.
  update public.memberships set role = 'coach' where club_id = p_club and user_id = v_uid;
  update public.memberships set role = 'owner' where club_id = p_club and user_id = p_new_owner;
end $$;

create function public.leave_club(p_club uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid();
begin
  if public.my_role(p_club) = 'owner' then raise exception 'owner_must_transfer'; end if;
  perform public._detach_user(p_club, v_uid);
end $$;

-- Un coach retire un athlète ; le propriétaire retire un coach ; on ne retire pas le propriétaire.
create function public.remove_member(p_club uuid, p_user uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_target public.club_role;
begin
  select role into v_target from public.memberships
  where club_id = p_club and user_id = p_user and status = 'active';
  if v_target is null then raise exception 'member_not_found'; end if;
  if v_target = 'owner' then raise exception 'owner_must_transfer'; end if;
  if v_target = 'coach' and not public.is_owner(p_club) then raise exception 'forbidden'; end if;
  if v_target = 'athlete' and not public.is_coach(p_club) then raise exception 'forbidden'; end if;
  perform public._detach_user(p_club, p_user);
end $$;

-- ---------------------------------------------------------------------------
-- Droits d'exécution : uniquement les utilisateurs connectés, et seulement les RPC publiques
-- ---------------------------------------------------------------------------

revoke all on function
  public.display_name_of(uuid), public._ensure_athlete(uuid, uuid), public._detach_user(uuid, uuid),
  public._can_decide(public.memberships), public._new_invitation_code(), public._normalize_code(text)
  from public, anon, authenticated;

revoke all on function
  public.create_club(text), public.find_club(text), public.request_join(uuid, public.club_role),
  public.approve_membership(uuid), public.reject_membership(uuid),
  public.create_invitation(uuid, public.club_role, uuid, int, int),
  public.revoke_invitation(uuid), public.preview_invitation(text), public.accept_invitation(text),
  public.transfer_ownership(uuid, uuid), public.leave_club(uuid), public.remove_member(uuid, uuid)
  from public, anon;

grant execute on function
  public.create_club(text), public.find_club(text), public.request_join(uuid, public.club_role),
  public.approve_membership(uuid), public.reject_membership(uuid),
  public.create_invitation(uuid, public.club_role, uuid, int, int),
  public.revoke_invitation(uuid), public.preview_invitation(text), public.accept_invitation(text),
  public.transfer_ownership(uuid, uuid), public.leave_club(uuid), public.remove_member(uuid, uuid)
  to authenticated;
