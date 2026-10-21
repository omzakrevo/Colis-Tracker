-- Colis rattaché à un billet de voyage (numéro du billet scanné ou saisi à l'enregistrement du colis).

alter table public.colis add column if not exists billet_numero text;
create index if not exists colis_billet_numero_idx on public.colis (company_id, billet_numero) where billet_numero is not null;

-- La vue doit être recréée pour exposer la nouvelle colonne.
drop view if exists public.colis_detail;
create view public.colis_detail with (security_invoker = true) as
select c.*,
       gd.nom as gare_depart_nom,
       ga.nom as gare_arrivee_nom,
       p.nom  as agent_nom
from public.colis c
left join public.gares gd on gd.id = c.gare_depart_id
left join public.gares ga on ga.id = c.gare_arrivee_id
left join public.vip_profiles p on p.id = c.agent_id;
grant select on public.colis_detail to authenticated;

notify pgrst, 'reload schema';
