-- unaccent : recherche insensible aux accents (« leo » trouve « Léo »). Utilisée par l'outil
-- d'admin local (scripts/admin/server.py). Même schéma que citext, cf. 0001_schema.sql.
create extension if not exists unaccent with schema extensions;
