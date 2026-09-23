-- Ajoute le type de séance "Compétition".
--  1. Les clubs déjà créés reçoivent le type s'ils ne l'ont pas déjà.
--  2. create_club() est redéfinie pour que les prochains clubs le reçoivent aussi.

insert into public.session_types (club_id, name, color, icon, sort_order)
select c.id, 'Compétition', '#D6409F', 'competition', 8
from public.clubs c
where not exists (
  select 1 from public.session_types t where t.club_id = c.id and t.name = 'Compétition'
);

create or replace function public.create_club(p_name text) returns uuid
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
    (v_club, 'Récupération',    '#7D8590', 'recovery',   7),
    (v_club, 'Compétition',     '#D6409F', 'competition',8);

  return v_club;
end $$;
