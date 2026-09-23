-- Un upload (`INSERT ... ON CONFLICT DO UPDATE`) se termine par un `RETURNING *` côté service
-- Storage : Postgres doit donc pouvoir SELECT la ligne tout juste écrite, en plus du droit
-- d'écriture — sans politique SELECT, ça échoue avec la même erreur générique
-- (« new row violates row-level security policy ») que s'il manquait le droit d'écrire, ce qui a
-- fait perdre du temps à la diagnostiquer. Le flag "public" du bucket ne couvre que l'URL
-- publique (`getPublicUrl`), pas les requêtes authentifiées sur `storage.objects` — cette
-- politique était donc manquante depuis le début pour `avatars` et `club_logos`.
create policy avatars_select on storage.objects for select to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy club_logos_select on storage.objects for select to authenticated
  using (bucket_id = 'club_logos' and public.is_coach((storage.foldername(name))[1]::uuid));
