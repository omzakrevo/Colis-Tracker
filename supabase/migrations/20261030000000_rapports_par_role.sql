-- Rapports filtrés par rôle, côté serveur :
--   administrateur et comptable : toute l'entreprise ;
--   chef de gare : les colis et billets partis de sa gare ;
--   agent, guichet, convoyeur : uniquement ce qu'ils ont eux-mêmes enregistré ou vendu
--   (et, pour les colis, ce qu'ils ont fait avancer : arrivée, retrait…).

drop function if exists public.rapport_colis(date, date, uuid, bigint, text, boolean);
drop function if exists public.rapport_billets(timestamptz, timestamptz, uuid, bigint);

create or replace function public.rapport_colis(
  p_debut date default null, p_fin date default null, p_agent uuid default null,
  p_gare_depart bigint default null, p_statut text default null, p_traites boolean default false)
returns setof public.colis_detail
language sql stable set search_path = public as $$
  select d.*
  from public.colis_detail d
  where (p_debut is null or d.date_envoi >= p_debut)
    and (p_fin is null or d.date_envoi <= p_fin)
    and (p_gare_depart is null or d.gare_depart_id = p_gare_depart)
    and (p_statut is null or d.statut = p_statut)
    and case app_role()
      when 'admin' then p_agent is null or d.agent_id = p_agent
      when 'comptable' then p_agent is null or d.agent_id = p_agent
      when 'chef_gare' then d.gare_depart_id = app_gare_id() and (p_agent is null or d.agent_id = p_agent)
      when 'agent' then d.agent_id = auth.uid() or (p_traites and exists (
          select 1 from public.historique_colis h
          where h.colis_id = d.id and h.agent_id = auth.uid()
            and (p_debut is null or h.date_changement >= p_debut)
            and (p_fin is null or h.date_changement < p_fin + 1)))
      when 'guichet' then d.agent_id = auth.uid() or (p_traites and exists (
          select 1 from public.historique_colis h
          where h.colis_id = d.id and h.agent_id = auth.uid()
            and (p_debut is null or h.date_changement >= p_debut)
            and (p_fin is null or h.date_changement < p_fin + 1)))
      else false end
$$;

create or replace function public.rapport_billets(
  p_debut timestamptz default null, p_fin timestamptz default null, p_vendeur uuid default null,
  p_gare_depart bigint default null)
returns setof public.tickets_detail
language sql stable set search_path = public as $$
  select t.*
  from public.tickets_detail t
  where (p_debut is null or t.created_at >= p_debut)
    and (p_fin is null or t.created_at < p_fin)
    and (p_gare_depart is null or t.gare_depart_id = p_gare_depart)
    and case app_role()
      when 'admin' then p_vendeur is null or t.vendeur_id = p_vendeur
      when 'comptable' then p_vendeur is null or t.vendeur_id = p_vendeur
      when 'chef_gare' then t.gare_depart_id = app_gare_id() and (p_vendeur is null or t.vendeur_id = p_vendeur)
      when 'guichet' then t.vendeur_id = auth.uid()
      when 'convoyeur' then t.vendeur_id = auth.uid()
      else false end
$$;

revoke all on function public.rapport_colis(date, date, uuid, bigint, text, boolean) from public, anon;
revoke all on function public.rapport_billets(timestamptz, timestamptz, uuid, bigint) from public, anon;
grant execute on function public.rapport_colis(date, date, uuid, bigint, text, boolean) to authenticated;
grant execute on function public.rapport_billets(timestamptz, timestamptz, uuid, bigint) to authenticated;

notify pgrst, 'reload schema';
