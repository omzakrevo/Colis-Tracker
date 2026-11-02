-- Fidélité : à partir de N voyages payés par la même personne (même numéro de téléphone), le voyage suivant est gratuit.
-- N est choisi par l'administrateur (10 par défaut). Le serveur vérifie le droit au voyage gratuit.

alter table public.company_settings add column if not exists fidelite_actif boolean not null default true;
alter table public.company_settings add column if not exists fidelite_seuil integer not null default 10;
alter table public.company_settings drop constraint if exists company_settings_fidelite_seuil_check;
alter table public.company_settings add constraint company_settings_fidelite_seuil_check check (fidelite_seuil between 2 and 500);

alter table public.tickets add column if not exists gratuit boolean not null default false;

-- La vue doit être recréée pour exposer la colonne ; la fonction de rapport (migration 30) en dépend.
drop view if exists public.tickets_detail cascade;
create view public.tickets_detail with (security_invoker = true) as
select t.*, gd.nom as gare_depart_nom, ga.nom as gare_arrivee_nom, p.nom as vendeur_nom
from public.tickets t
left join public.gares gd on gd.id = t.gare_depart_id
left join public.gares ga on ga.id = t.gare_arrivee_id
left join public.vip_profiles p on p.id = t.vendeur_id;
grant select on public.tickets_detail to authenticated;

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
revoke all on function public.rapport_billets(timestamptz, timestamptz, uuid, bigint) from public, anon;
grant execute on function public.rapport_billets(timestamptz, timestamptz, uuid, bigint) to authenticated;

-- Une même personne = les 8 derniers chiffres du téléphone (avec ou sans +226).
create or replace function public._tel_cle(t text) returns text
language sql immutable as $$
  select case when length(d) >= 8 then right(d, 8) else d end
  from (select regexp_replace(coalesce(t, ''), '[^0-9]', '', 'g') as d) x
$$;

-- Voyages payés depuis le dernier voyage gratuit.
create or replace function public._fidelite_compte(p_cid bigint, p_tel text) returns integer
language sql stable security definer set search_path = public as $$
  select count(*)::integer from public.tickets t
   where t.company_id = p_cid and public._tel_cle(t.client_telephone) = public._tel_cle(p_tel)
     and t.statut <> 'annule' and not t.gratuit
     and t.created_at > coalesce((
       select max(g.created_at) from public.tickets g
        where g.company_id = p_cid and public._tel_cle(g.client_telephone) = public._tel_cle(p_tel)
          and g.gratuit and g.statut <> 'annule'), '-infinity'::timestamptz)
$$;

create or replace function public._fidelite_ok(p_cid bigint, p_tel text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select s.fidelite_actif and length(public._tel_cle(p_tel)) >= 8
           and public._fidelite_compte(p_cid, p_tel) >= s.fidelite_seuil
      from public.company_settings s where s.company_id = p_cid limit 1), false)
$$;

-- Situation d'un client : voyages payés, seuil, voyage gratuit disponible ou non.
create or replace function public.fidelite_statut(p_telephone text) returns json
language plpgsql stable security definer set search_path = public as $$
declare
  cid bigint := app_company_id();
  actif boolean; seuil integer; n integer;
begin
  if app_role() is null or app_role() not in ('admin', 'guichet', 'convoyeur') then raise exception 'Non autorisé'; end if;
  select s.fidelite_actif, s.fidelite_seuil into actif, seuil from public.company_settings s where s.company_id = cid limit 1;
  actif := coalesce(actif, true); seuil := coalesce(seuil, 10);
  if length(public._tel_cle(p_telephone)) < 8 then
    return json_build_object('actif', actif, 'seuil', seuil, 'voyages', 0, 'restant', seuil, 'gratuit', false);
  end if;
  n := public._fidelite_compte(cid, p_telephone);
  return json_build_object('actif', actif, 'seuil', seuil, 'voyages', n,
                           'restant', greatest(seuil - n, 0), 'gratuit', actif and n >= seuil);
end $$;
revoke all on function public.fidelite_statut(text) from public, anon;
grant execute on function public.fidelite_statut(text) to authenticated;

-- Le billet gratuit n'est accepté que si le client y a droit ; son prix est alors forcé à 0.
create or replace function public.tickets_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  cap integer; prises integer[]; n integer;
  s text := nullif(trim(coalesce(new.siege, '')), '');
  h text := coalesce(nullif(trim(coalesce(new.heure_depart, '')), ''), '');
begin
  new.numero := 'BIL-' || extract(year from now())::int || '-' || nextval('public.ticket_numero_seq');
  new.statut := 'emis';
  new.vendeur_id := coalesce(auth.uid(), new.vendeur_id);
  if public.app_company_id() is not null then new.company_id := public.app_company_id(); end if;

  -- Nouvel envoi d'un billet déjà créé (réponse perdue) : on laisse la contrainte d'unicité le reconnaître.
  if new.client_ref is not null and exists (select 1 from public.tickets x where x.client_ref = new.client_ref) then
    return new;
  end if;

  if new.gratuit then
    perform pg_advisory_xact_lock(hashtextextended('fidelite|' || new.company_id || '|' || public._tel_cle(new.client_telephone), 0));
    if not public._fidelite_ok(new.company_id, new.client_telephone) then
      raise exception 'Voyage gratuit non disponible pour ce client';
    end if;
    new.prix := 0;
  end if;

  -- Un seul vendeur à la fois par voyage : évite deux billets avec la même place.
  perform pg_advisory_xact_lock(hashtextextended(
    new.company_id || '|' || new.gare_depart_id || '|' || new.gare_arrivee_id || '|' || new.date_voyage || '|' || h, 0));
  cap := public._places_capacite(new.company_id, new.gare_depart_id, new.gare_arrivee_id);
  select coalesce(array_agg(t.siege::integer), '{}'::integer[]) into prises
    from public.tickets t
   where t.company_id = new.company_id and t.gare_depart_id = new.gare_depart_id and t.gare_arrivee_id = new.gare_arrivee_id
     and t.date_voyage = new.date_voyage and coalesce(t.heure_depart, '') = h
     and t.statut <> 'annule' and t.siege ~ '^[0-9]{1,3}$';

  if s is not null then
    if s !~ '^[0-9]{1,3}$' then raise exception 'Numéro de place invalide'; end if;
    n := s::integer;
    if n < 1 or n > cap then raise exception 'La place doit être comprise entre 1 et %', cap; end if;
    if n = any (prises) then raise exception 'La place % est déjà attribuée', n; end if;
  else
    select min(g) into n from generate_series(1, cap) g where g <> all (prises);
    if n is null then raise exception 'Trajet plein : les % places sont attribuées', cap; end if;
  end if;
  new.siege := n::text;
  return new;
end $$;

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
             || case when coalesce(t.siege, '') <> '' then ' (place ' || t.siege || ')' else '' end
             || case when t.gratuit then ' [VOYAGE GRATUIT]' else '' end,
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

notify pgrst, 'reload schema';
