-- Une séance créée (ou éditée) pour plusieurs groupes à la fois reste une ligne par groupe
-- (chaque groupe garde sa propre copie, modifiable indépendamment ensuite), mais toutes
-- partagent ce même `linked_id` tant qu'elles n'ont pas divergé côté client (l'app les affiche
-- alors comme une seule séance, avec tous ses groupes). Null pour une séance à un seul groupe.
alter table public.sessions add column linked_id uuid;
create index sessions_linked_id_idx on public.sessions (linked_id) where linked_id is not null;
