-- Mode de paiement (espèces / Orange Money) sur les colis et les billets, rapport de fin de journée des guichets
-- (montants affichés si l'administrateur l'active) et compteurs « mon activité » du tableau de bord.

alter table public.colis   add column if not exists mode_paiement text not null default 'especes';
alter table public.tickets add column if not exists mode_paiement text not null default 'especes';
alter table public.colis   drop constraint if exists colis_mode_paiement_check;
alter table public.colis   add constraint colis_mode_paiement_check check (mode_paiement in ('especes', 'orange_money'));
alter table public.tickets drop constraint if exists tickets_mode_paiement_check;
alter table public.tickets add constraint tickets_mode_paiement_check check (mode_paiement in ('especes', 'orange_money'));

-- Choix de l'administrateur : le rapport de fin de journée montre-t-il les montants ?
alter table public.company_settings add column if not exists cloture_montants boolean not null default false;

-- Les vues doivent être recréées pour exposer la nouvelle colonne.
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

drop view if exists public.tickets_detail;
create view public.tickets_detail with (security_invoker = true) as
select t.*, gd.nom as gare_depart_nom, ga.nom as gare_arrivee_nom, p.nom as vendeur_nom
from public.tickets t
left join public.gares gd on gd.id = t.gare_depart_id
left join public.gares ga on ga.id = t.gare_arrivee_id
left join public.vip_profiles p on p.id = t.vendeur_id;
grant select on public.tickets_detail to authenticated;

-- Compteurs du tableau de bord : uniquement ce que l'utilisateur a fait lui-même.
create or replace function public.mon_activite(p_debut timestamptz, p_fin timestamptz)
returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'colis_envoyes',  (select count(*) from colis
                        where agent_id = auth.uid() and company_id = app_company_id()
                          and created_at >= p_debut and created_at < p_fin and statut <> 'annule'),
    'colis_recus',    (select count(distinct h.colis_id) from historique_colis h
                        join colis c on c.id = h.colis_id
                        where h.agent_id = auth.uid() and c.company_id = app_company_id()
                          and h.statut = 'arrive' and h.date_changement >= p_debut and h.date_changement < p_fin),
    'billets_vendus', (select count(*) from tickets
                        where vendeur_id = auth.uid() and company_id = app_company_id()
                          and created_at >= p_debut and created_at < p_fin and statut <> 'annule')
  )
$$;
revoke all on function public.mon_activite(timestamptz, timestamptz) from public, anon;
grant execute on function public.mon_activite(timestamptz, timestamptz) to authenticated;

-- Journal chronologique d'une personne (billets vendus, colis enregistrés, colis réceptionnés).
-- Chacun ne voit que le sien ; l'administrateur peut demander celui d'un employé.
create or replace function public.journal_activite(p_agent uuid, p_debut timestamptz, p_fin timestamptz)
returns table (quand timestamptz, type text, numero text, libelle text, mode_paiement text, montant numeric)
language plpgsql stable security definer set search_path = public as $$
declare
  qui uuid := coalesce(p_agent, auth.uid());
begin
  if app_role() is null then raise exception 'Non autorisé'; end if;
  if qui <> auth.uid() and app_role() <> 'admin' then raise exception 'Non autorisé'; end if;
  return query
    select t.created_at, 'billet'::text, t.numero,
           coalesce(gd.nom, '-') || ' > ' || coalesce(ga.nom, '-') || ' - ' || t.client_nom
             || case when coalesce(t.siege, '') <> '' then ' (place ' || t.siege || ')' else '' end,
           t.mode_paiement, t.prix
      from tickets t
      left join gares gd on gd.id = t.gare_depart_id
      left join gares ga on ga.id = t.gare_arrivee_id
     where t.vendeur_id = qui and t.company_id = app_company_id() and t.statut <> 'annule'
       and t.created_at >= p_debut and t.created_at < p_fin
    union all
    select c.created_at, 'colis_envoye'::text, c.numero,
           coalesce(ga.nom, '-') || ' - ' || c.destinataire_nom || ' (' || c.nombre || ' colis)',
           c.mode_paiement, c.prix
      from colis c
      left join gares ga on ga.id = c.gare_arrivee_id
     where c.agent_id = qui and c.company_id = app_company_id() and c.statut <> 'annule'
       and c.created_at >= p_debut and c.created_at < p_fin
    union all
    select h.date_changement, 'colis_recu'::text, c.numero,
           'De ' || coalesce(gd.nom, '-') || ' - ' || c.destinataire_nom,
           null::text, null::numeric
      from historique_colis h
      join colis c on c.id = h.colis_id
      left join gares gd on gd.id = c.gare_depart_id
     where h.agent_id = qui and h.statut = 'arrive' and c.company_id = app_company_id()
       and h.date_changement >= p_debut and h.date_changement < p_fin
    order by 1;
end $$;
revoke all on function public.journal_activite(uuid, timestamptz, timestamptz) from public, anon;
grant execute on function public.journal_activite(uuid, timestamptz, timestamptz) to authenticated;

notify pgrst, 'reload schema';
