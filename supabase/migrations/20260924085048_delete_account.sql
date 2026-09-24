-- Suppression de compte en libre-service (exigée par l'App Store, et un droit RGPD de toute
-- façon). Techniquement : `delete from auth.users` — tout ce qui référence l'utilisateur avec
-- `on delete cascade`/`set null` suit déjà (profil, adhésions, profil/records athlète, fait/non
-- fait, présences...). Sauf ces cinq colonnes `created_by`, jamais pensées pour ce cas (une
-- simple valeur historique, pas une vraie dépendance) et donc sans action à la suppression —
-- elles bloqueraient la suppression du compte avec une violation de contrainte. On les bascule
-- en `on delete set null` (et on retire le `not null` là où il y en avait un).

alter table public.clubs alter column created_by drop not null;
alter table public.clubs drop constraint clubs_created_by_fkey;
alter table public.clubs add constraint clubs_created_by_fkey
  foreign key (created_by) references auth.users (id) on delete set null;

alter table public.invitations alter column created_by drop not null;
alter table public.invitations drop constraint invitations_created_by_fkey;
alter table public.invitations add constraint invitations_created_by_fkey
  foreign key (created_by) references auth.users (id) on delete set null;

alter table public.sessions drop constraint sessions_created_by_fkey;
alter table public.sessions add constraint sessions_created_by_fkey
  foreign key (created_by) references auth.users (id) on delete set null;

alter table public.events drop constraint events_created_by_fkey;
alter table public.events add constraint events_created_by_fkey
  foreign key (created_by) references auth.users (id) on delete set null;

alter table public.attendances drop constraint attendances_created_by_fkey;
alter table public.attendances add constraint attendances_created_by_fkey
  foreign key (created_by) references auth.users (id) on delete set null;

-- Un propriétaire de club doit d'abord passer la main (même règle que pour quitter un club,
-- `owner_must_transfer`) : supprimer son compte sans ça laisserait le club sans personne pour
-- le gérer.
create function public.delete_own_account() returns void
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid();
begin
  if exists (
    select 1 from public.memberships
    where user_id = v_uid and role = 'owner' and status = 'active'
  ) then
    raise exception 'owner_must_transfer';
  end if;
  delete from auth.users where id = v_uid;
end $$;

revoke execute on function public.delete_own_account() from public, anon;
grant execute on function public.delete_own_account() to authenticated;
