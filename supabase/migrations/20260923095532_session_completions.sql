-- Un athlète marque une séance placée comme faite (façon Pronote) : par défaut « non fait »,
-- l'existence d'une ligne ici vaut « fait ». Seul l'athlète marque la sienne ; un coach consulte
-- (utile en filtrant le calendrier par athlète), il ne marque pas à sa place.
create table public.session_completions (
  id         uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.sessions (id) on delete cascade,
  athlete_id uuid not null references public.athletes (id) on delete cascade,
  club_id    uuid not null references public.clubs (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (session_id, athlete_id)
);
create index session_completions_athlete_idx on public.session_completions (athlete_id);

create function public.session_completions_fill() returns trigger
language plpgsql security definer set search_path = '' as $$
declare a_club uuid; a_user uuid; s_club uuid;
begin
  select club_id, user_id into a_club, a_user from public.athletes where id = new.athlete_id;
  select club_id into s_club from public.sessions where id = new.session_id;
  if a_club is null then raise exception 'athlete_not_found' using errcode = 'P0001'; end if;
  if a_user is null then raise exception 'athlete_has_no_account' using errcode = 'P0001'; end if;
  if s_club is null or s_club <> a_club then
    raise exception 'session_and_athlete_must_share_club' using errcode = 'P0001';
  end if;
  new.club_id := a_club;
  new.user_id := a_user;
  return new;
end $$;

create trigger session_completions_fill before insert on public.session_completions
  for each row execute function public.session_completions_fill();

alter table public.session_completions enable row level security;

create policy session_completions_select on public.session_completions for select to authenticated
  using (public.is_coach(club_id) or user_id = (select auth.uid()));
create policy session_completions_insert on public.session_completions for insert to authenticated
  with check (public.is_my_athlete(athlete_id));
create policy session_completions_delete on public.session_completions for delete to authenticated
  using (user_id = (select auth.uid()));

alter publication powersync add table public.session_completions;
