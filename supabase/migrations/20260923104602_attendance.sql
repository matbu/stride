-- Présence à l'entraînement, prise par un coach (contrairement à `session_completions`, qui est
-- l'athlète qui se déclare lui-même). Par jour et par groupe : existence de la ligne = présent.
-- Fonctionne même pour un athlète sans compte (fiche seule) : `user_id` reste alors null.
create table public.attendances (
  id         uuid primary key default gen_random_uuid(),
  club_id    uuid not null references public.clubs (id) on delete cascade,
  group_id   uuid not null references public.training_groups (id) on delete cascade,
  athlete_id uuid not null references public.athletes (id) on delete cascade,
  user_id    uuid references auth.users (id) on delete set null,
  date       date not null,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now(),
  unique (group_id, athlete_id, date)
);
create index attendances_athlete_idx on public.attendances (athlete_id);
create index attendances_club_date_idx on public.attendances (club_id, date);

-- club_id/user_id dénormalisés depuis le groupe et l'athlète (voir group_athletes_fill, le même
-- principe) ; on vérifie au passage que le groupe et l'athlète appartiennent au même club.
create function public.attendances_fill() returns trigger
language plpgsql security definer set search_path = '' as $$
declare g_club uuid; a_club uuid; a_user uuid;
begin
  select club_id into g_club from public.training_groups where id = new.group_id;
  select club_id, user_id into a_club, a_user from public.athletes where id = new.athlete_id;
  if g_club is null or a_club is null or g_club <> a_club then
    raise exception 'group_and_athlete_must_share_club' using errcode = 'P0001';
  end if;
  new.club_id := g_club;
  new.user_id := a_user;
  new.created_by := auth.uid();
  return new;
end $$;

create trigger attendances_fill before insert on public.attendances
  for each row execute function public.attendances_fill();

alter table public.attendances enable row level security;

-- Seul un coach prend ou retire la présence ; un athlète consulte la sienne, un coach voit tout.
create policy attendances_select on public.attendances for select to authenticated
  using (public.is_coach(club_id) or user_id = (select auth.uid()));
create policy attendances_insert on public.attendances for insert to authenticated
  with check (public.is_coach(club_id));
create policy attendances_delete on public.attendances for delete to authenticated
  using (public.is_coach(club_id));

alter publication powersync add table public.attendances;
