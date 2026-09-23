-- Remplace find_club (nom exact requis) par une recherche « live » par sous-chaîne.
-- Déclenchée à partir de 2 caractères et limitée à 20 résultats côté serveur (défense en
-- profondeur : même si le client oublie la limite, on ne laisse pas taper une lettre courante
-- pour lister tous les clubs de l'appli).
drop function if exists public.find_club(text);

create function public.search_clubs(p_query text) returns table (id uuid, name text)
language sql stable security definer set search_path = '' as $$
  select c.id, c.name::text
  from public.clubs c
  where auth.uid() is not null
    and char_length(btrim(p_query)) >= 2
    and strpos(lower(c.name::text), lower(btrim(p_query))) > 0
  order by strpos(lower(c.name::text), lower(btrim(p_query))), c.name
  limit 20
$$;

revoke all on function public.search_clubs(text) from public, anon;
grant execute on function public.search_clubs(text) to authenticated;
