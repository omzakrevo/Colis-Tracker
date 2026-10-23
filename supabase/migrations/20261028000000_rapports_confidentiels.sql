-- Rapports : administrateur, comptable (toute l'entreprise) et chef de gare (sa gare) uniquement.
-- Agent / guichet : seulement leurs propres opérations (colis qu'ils ont enregistrés).

create or replace function public.colis_par_jour(p_debut date default null, p_fin date default null)
returns table (date date, total bigint, recette numeric)
language sql stable set search_path = public as $$
  select date_envoi, count(*),
         coalesce(sum(prix) filter (where app_role() in ('admin', 'comptable') or gare_depart_id = app_gare_id()), 0)
  from colis
  where (p_debut is null or date_envoi >= p_debut) and (p_fin is null or date_envoi <= p_fin)
    and (app_role() in ('admin', 'comptable', 'chef_gare') or agent_id = auth.uid())
  group by date_envoi order by date_envoi
$$;

create or replace function public.recettes_par_gare()
returns table (gare_id bigint, gare_nom text, total_colis bigint, recette_totale numeric)
language sql stable set search_path = public as $$
  select g.id, g.nom, count(c.id), coalesce(sum(c.prix), 0)
  from gares g left join colis c on c.gare_depart_id = g.id
    and (app_role() in ('admin', 'comptable', 'chef_gare') or c.agent_id = auth.uid())
  where app_role() in ('admin', 'comptable') or g.id = app_gare_id()
  group by g.id, g.nom order by g.nom
$$;

create or replace function public.recettes_par_agent()
returns table (agent_id uuid, agent_nom text, total_colis bigint, recette_totale numeric)
language sql stable set search_path = public as $$
  select p.id, p.nom, count(c.id), coalesce(sum(c.prix), 0)
  from vip_profiles p left join colis c on c.agent_id = p.id
  where p.role = 'agent'
    and (app_role() in ('admin', 'comptable') or (app_role() = 'chef_gare' and p.gare_id = app_gare_id()) or p.id = auth.uid())
  group by p.id, p.nom order by p.nom
$$;
