-- 1) Places numérotées des billets (bus de 50 places) ; 2) rôle « comptable » (finances en lecture seule) ;
-- 3) SMS quotidien des recettes envoyé à l'administrateur.

-- ───────────────────────── 1. Places des billets ─────────────────────────

alter table public.trajets add column if not exists capacite integer not null default 50;
do $$ begin
  alter table public.trajets add constraint trajets_capacite_check check (capacite between 1 and 200);
exception when duplicate_object then null; end $$;

create or replace function public._places_capacite(p_company bigint, p_depart bigint, p_arrivee bigint) returns integer
language sql stable security definer set search_path = public as $$
  select coalesce((select t.capacite from public.trajets t
                    where t.company_id = p_company and t.gare_depart_id = p_depart and t.gare_arrivee_id = p_arrivee), 50)
$$;

-- Places déjà attribuées pour un voyage (même trajet, même date, même heure de départ) et capacité du bus.
create or replace function public.places_prises(p_depart bigint, p_arrivee bigint, p_date date, p_heure text default null)
returns table (capacite integer, prises integer[])
language plpgsql stable security definer set search_path = public as $$
declare cid bigint := public.app_company_id();
begin
  if public.app_role() is null or public.app_role() not in ('admin', 'chef_gare', 'agent', 'guichet', 'convoyeur') then
    raise exception 'Non autorisé';
  end if;
  return query
    select public._places_capacite(cid, p_depart, p_arrivee),
           coalesce((select array_agg(distinct t.siege::integer order by t.siege::integer)
                       from public.tickets t
                      where t.company_id = cid and t.gare_depart_id = p_depart and t.gare_arrivee_id = p_arrivee
                        and t.date_voyage = p_date and coalesce(t.heure_depart, '') = coalesce(nullif(trim(p_heure), ''), '')
                        and t.statut <> 'annule' and t.siege ~ '^[0-9]{1,3}$'), '{}'::integer[]);
end $$;

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

revoke execute on function public._places_capacite(bigint, bigint, bigint) from public, anon, authenticated;
revoke execute on function public.places_prises(bigint, bigint, date, text) from public, anon;
grant execute on function public.places_prises(bigint, bigint, date, text) to authenticated;

-- ───────────────────────── 2. Rôle comptable ─────────────────────────
-- Voit tout ce qui est financier (rapports, recettes, colis et billets en lecture) ; ne crée ni colis ni billet, ne scanne pas.

alter table public.vip_profiles drop constraint if exists vip_profiles_role_check;
alter table public.vip_profiles add constraint vip_profiles_role_check
  check (role in ('superadmin', 'admin', 'chef_gare', 'agent', 'barragiste', 'guichet', 'convoyeur', 'comptable'));

create or replace function public.admin_creer_utilisateur(
  p_username text, p_password text, p_nom text,
  p_role text default 'agent', p_gare_id bigint default null, p_telephone text default null)
returns uuid
language plpgsql security definer set search_path = public, auth, extensions as $$
declare
  cid bigint := app_company_id();
  uid uuid;
  ident text := public.normaliser_identifiant(p_username);
  maxu integer;
begin
  if app_role() is distinct from 'admin' then raise exception 'Réservé aux administrateurs'; end if;
  if p_role not in ('admin', 'chef_gare', 'agent', 'barragiste', 'guichet', 'convoyeur', 'comptable') then raise exception 'Rôle invalide'; end if;
  select max_utilisateurs into maxu from public.companies where id = cid;
  if (select count(*) from public.vip_profiles where company_id = cid and actif) >= maxu then
    raise exception 'Limite de % utilisateurs atteinte pour votre abonnement', maxu;
  end if;
  if p_gare_id is not null and not exists (select 1 from public.gares where id = p_gare_id and company_id = cid) then
    raise exception 'Gare invalide';
  end if;

  uid := public._creer_compte_auth(ident, p_password);
  perform set_config('vipcolis.bypass', 'on', true);
  insert into public.vip_profiles (id, nom, username, role, gare_id, telephone, company_id)
  values (uid, trim(p_nom), ident, p_role, p_gare_id, coalesce(nullif(trim(p_telephone), ''), case when ident ~ '^[0-9]+$' then ident end), cid);
  perform set_config('vipcolis.bypass', 'off', true);
  return uid;
end $$;

-- Lecture seule des colis, billets et trajets de l'entreprise.
drop policy if exists colis_select_comptable on public.colis;
create policy colis_select_comptable on public.colis for select to authenticated
  using (public.app_role() = 'comptable' and company_id = public.app_company_id());
drop policy if exists tickets_select_comptable on public.tickets;
create policy tickets_select_comptable on public.tickets for select to authenticated
  using (public.app_role() = 'comptable' and company_id = public.app_company_id());
drop policy if exists trajets_select_comptable on public.trajets;
create policy trajets_select_comptable on public.trajets for select to authenticated
  using (public.app_role() = 'comptable' and company_id = public.app_company_id());

-- Statistiques : le comptable voit toute l'entreprise comme l'administrateur.
create or replace function public.dashboard_stats() returns json
language sql stable set search_path = public as $$
  select json_build_object(
    'total_colis',         (select count(*) from colis),
    'colis_aujourd_hui',   (select count(*) from colis where date_envoi = current_date),
    'colis_en_route',      (select count(*) from colis where statut = 'en_route'),
    'colis_arrives',       (select count(*) from colis where statut = 'arrive'),
    'colis_non_retires',   (select count(*) from colis where statut = 'arrive'),
    'recette_totale',      coalesce((select sum(prix) from colis
                             where statut <> 'annule' and (app_role() in ('admin', 'comptable') or gare_depart_id = app_gare_id())), 0),
    'recette_aujourd_hui', coalesce((select sum(prix) from colis
                             where statut <> 'annule' and date_envoi = current_date
                               and (app_role() in ('admin', 'comptable') or gare_depart_id = app_gare_id())), 0),
    'total_gares',         (select count(*) from gares where app_role() in ('admin', 'comptable') or id = app_gare_id()),
    'total_agents',        (select count(*) from vip_profiles
                             where actif and role <> 'superadmin'
                               and (app_role() in ('admin', 'comptable') or gare_id = app_gare_id()))
  )
$$;

create or replace function public.colis_par_jour(p_debut date default null, p_fin date default null)
returns table (date date, total bigint, recette numeric)
language sql stable set search_path = public as $$
  select date_envoi, count(*),
         coalesce(sum(prix) filter (where app_role() in ('admin', 'comptable') or gare_depart_id = app_gare_id()), 0)
  from colis
  where (p_debut is null or date_envoi >= p_debut) and (p_fin is null or date_envoi <= p_fin)
  group by date_envoi order by date_envoi
$$;

create or replace function public.recettes_par_gare()
returns table (gare_id bigint, gare_nom text, total_colis bigint, recette_totale numeric)
language sql stable set search_path = public as $$
  select g.id, g.nom, count(c.id), coalesce(sum(c.prix), 0)
  from gares g left join colis c on c.gare_depart_id = g.id
  where app_role() in ('admin', 'comptable') or g.id = app_gare_id()
  group by g.id, g.nom order by g.nom
$$;

create or replace function public.recettes_par_agent()
returns table (agent_id uuid, agent_nom text, total_colis bigint, recette_totale numeric)
language sql stable set search_path = public as $$
  select p.id, p.nom, count(c.id), coalesce(sum(c.prix), 0)
  from vip_profiles p left join colis c on c.agent_id = p.id
  where p.role = 'agent' and (app_role() in ('admin', 'comptable') or p.gare_id = app_gare_id())
  group by p.id, p.nom order by p.nom
$$;

-- ───────────────────────── 3. SMS quotidien des recettes ─────────────────────────

alter table public.sms_settings add column if not exists rapport_actif boolean not null default false;
alter table public.sms_settings add column if not exists rapport_heure text not null default '22:00';
alter table public.sms_settings add column if not exists rapport_numeros text not null default '';
alter table public.sms_settings add column if not exists rapport_dernier date;
grant select (rapport_actif, rapport_heure, rapport_numeros, rapport_dernier) on public.sms_settings to authenticated;

alter table public.sms_outbox drop constraint if exists sms_outbox_type_check;
alter table public.sms_outbox add constraint sms_outbox_type_check
  check (type in ('envoi_exp', 'envoi_dest', 'arrive', 'retire', 'billet', 'test', 'rapport'));

create or replace function public.sms_enregistrer(p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare cid bigint := public.app_company_id();
begin
  if public.app_role() is distinct from 'admin' or cid is null then raise exception 'Non autorisé'; end if;
  if p ? 'rapport_heure' and (p ->> 'rapport_heure') !~ '^([01]?[0-9]|2[0-3]):[0-5][0-9]$' then
    raise exception 'Heure invalide (format HH:MM)';
  end if;
  insert into public.sms_settings (company_id) values (cid) on conflict do nothing;
  update public.sms_settings set
    actif = coalesce((p ->> 'actif')::boolean, actif),
    source = case when p ->> 'source' in ('global', 'propre') then p ->> 'source' else source end,
    username = coalesce(p ->> 'username', username),
    password = coalesce(nullif(p ->> 'password', ''), password),
    terminal_id = coalesce(p ->> 'terminal_id', terminal_id),
    sender = coalesce(left(p ->> 'sender', 18), sender),
    port = coalesce((p ->> 'port')::integer, port),
    indicatif = coalesce(p ->> 'indicatif', indicatif),
    sms_colis_envoi = coalesce((p ->> 'sms_colis_envoi')::boolean, sms_colis_envoi),
    sms_colis_arrive = coalesce((p ->> 'sms_colis_arrive')::boolean, sms_colis_arrive),
    sms_colis_retire = coalesce((p ->> 'sms_colis_retire')::boolean, sms_colis_retire),
    sms_billet = coalesce((p ->> 'sms_billet')::boolean, sms_billet),
    tpl_envoi_exp = coalesce(nullif(p ->> 'tpl_envoi_exp', ''), tpl_envoi_exp),
    tpl_envoi_dest = coalesce(nullif(p ->> 'tpl_envoi_dest', ''), tpl_envoi_dest),
    tpl_arrive = coalesce(nullif(p ->> 'tpl_arrive', ''), tpl_arrive),
    tpl_retire = coalesce(nullif(p ->> 'tpl_retire', ''), tpl_retire),
    tpl_billet = coalesce(nullif(p ->> 'tpl_billet', ''), tpl_billet),
    rapport_actif = coalesce((p ->> 'rapport_actif')::boolean, rapport_actif),
    rapport_heure = coalesce(lpad(nullif(p ->> 'rapport_heure', ''), 5, '0'), rapport_heure),
    rapport_numeros = coalesce(p ->> 'rapport_numeros', rapport_numeros),
    updated_at = now()
  where company_id = cid and not (bloque and (p ->> 'actif')::boolean is true);
end $$;

-- Texte du SMS : recettes du jour par gare de départ (colis + billets), total, comparaison avec la veille.
create or replace function public._sms_rapport_texte(p_company bigint, p_jour date) returns text
language plpgsql stable security definer set search_path = public as $$
declare
  tz constant text := 'Africa/Ouagadougou';
  l record; total numeric := 0; hier numeric := 0; nb integer := 0; txt text; ev text;
  entreprise text := coalesce((select nom from public.companies where id = p_company), 'Recettes');
begin
  txt := 'Recettes du ' || to_char(p_jour, 'DD/MM') || ' - ' ||
         translate(entreprise, 'àâäéèêëîïôöùûüçÀÂÄÉÈÊËÎÏÔÖÙÛÜÇ', 'aaaeeeeiioouuucAAAEEEEIIOOUUUC');
  for l in
    select g.nom as nom, coalesce(c.s, 0) + coalesce(b.s, 0) as montant
      from public.gares g
      left join (select gare_depart_id gid, sum(prix) s from public.colis
                  where company_id = p_company and statut <> 'annule' and date_envoi = p_jour group by 1) c on c.gid = g.id
      left join (select gare_depart_id gid, sum(prix) s from public.tickets
                  where company_id = p_company and statut <> 'annule' and (created_at at time zone tz)::date = p_jour group by 1) b on b.gid = g.id
     where g.company_id = p_company and coalesce(c.s, 0) + coalesce(b.s, 0) > 0
     order by montant desc, g.nom
  loop
    total := total + l.montant;
    nb := nb + 1;
    if nb <= 12 then
      txt := txt || E'\n' || translate(l.nom, 'àâäéèêëîïôöùûüçÀÂÄÉÈÊËÎÏÔÖÙÛÜÇ', 'aaaeeeeiioouuucAAAEEEEIIOOUUUC')
             || ': ' || replace(to_char(l.montant, 'FM999,999,999,999'), ',', ' ');
    end if;
  end loop;
  if nb = 0 then txt := txt || E'\nAucune recette.'; end if;
  if nb > 12 then txt := txt || E'\n(+' || (nb - 12) || ' autres gares)'; end if;
  txt := txt || E'\nTOTAL: ' || replace(to_char(total, 'FM999,999,999,999'), ',', ' ') || ' F';

  select coalesce((select sum(prix) from public.colis where company_id = p_company and statut <> 'annule' and date_envoi = p_jour - 1), 0)
       + coalesce((select sum(prix) from public.tickets where company_id = p_company and statut <> 'annule'
                    and (created_at at time zone tz)::date = p_jour - 1), 0)
    into hier;
  ev := case when hier = 0 then 'n/a'
             else (case when total >= hier then '+' else '' end) || round((total - hier) * 100 / hier)::text || '%' end;
  return txt || E'\nHier: ' || replace(to_char(hier, 'FM999,999,999,999'), ',', ' ') || ' F (' || ev || ')';
end $$;

-- Envoie le rapport aux numéros choisis. Avant 12h, le rapport porte sur la veille (envoi le matin).
create or replace function public._sms_rapport_envoyer(p_company bigint, p_jour date) returns integer
language plpgsql security definer set search_path = public as $$
declare s public.sms_settings; msg text; num text; n integer := 0; oid bigint;
begin
  select * into s from public.sms_settings where company_id = p_company;
  if not found or coalesce(trim(s.rapport_numeros), '') = '' then return 0; end if;
  msg := public._sms_rapport_texte(p_company, p_jour);
  for num in select trim(x) from unnest(regexp_split_to_array(s.rapport_numeros, '[,;\s]+')) x where trim(x) <> '' loop
    insert into public.sms_outbox (company_id, type, telephone, message) values (p_company, 'rapport', num, msg)
    returning sms_outbox.id into oid;
    perform public._sms_envoyer(oid);
    n := n + 1;
  end loop;
  return n;
end $$;

-- Appelée régulièrement (pg_cron ou tâche planifiée) : envoie le rapport une fois par jour à l'heure choisie.
create or replace function public.sms_rapport_tick() returns integer
language plpgsql security definer set search_path = public as $$
declare
  tz constant text := 'Africa/Ouagadougou';
  s record; local_now timestamp := now() at time zone tz; auj date := (now() at time zone tz)::date; total integer := 0;
  jour date;
begin
  for s in select * from public.sms_settings where rapport_actif and not bloque and coalesce(trim(rapport_numeros), '') <> '' loop
    if (s.rapport_dernier is null or s.rapport_dernier < auj) and local_now::time >= s.rapport_heure::time then
      jour := case when s.rapport_heure::time < time '12:00' then auj - 1 else auj end;
      update public.sms_settings set rapport_dernier = auj where company_id = s.company_id;
      total := total + public._sms_rapport_envoyer(s.company_id, jour);
    end if;
  end loop;
  return total;
end $$;

-- Envoi d'essai à la demande de l'administrateur (rapport du jour en cours, sans toucher à la planification).
create or replace function public.sms_rapport_tester() returns integer
language plpgsql security definer set search_path = public as $$
declare cid bigint := public.app_company_id(); n integer;
begin
  if public.app_role() is distinct from 'admin' or cid is null then raise exception 'Non autorisé'; end if;
  perform public._sms_reglages(cid);
  n := public._sms_rapport_envoyer(cid, (now() at time zone 'Africa/Ouagadougou')::date);
  if n = 0 then raise exception 'Aucun numéro renseigné pour le rapport quotidien'; end if;
  return n;
end $$;

revoke execute on function public._sms_rapport_texte(bigint, date), public._sms_rapport_envoyer(bigint, date),
  public.sms_rapport_tick() from public, anon, authenticated;
grant execute on function public.sms_rapport_tick() to service_role;
revoke execute on function public.sms_enregistrer(jsonb), public.sms_rapport_tester() from public, anon;
grant execute on function public.sms_enregistrer(jsonb), public.sms_rapport_tester() to authenticated;

-- Planification : toutes les 10 minutes via pg_cron s'il est disponible sur votre serveur.
do $$
begin
  begin
    create extension if not exists pg_cron;
  exception when others then
    raise notice 'pg_cron indisponible : lancez public.sms_rapport_tick() depuis une autre planification';
  end;
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    begin
      perform cron.unschedule('tchi-sms-rapport');
    exception when others then null;
    end;
    perform cron.schedule('tchi-sms-rapport', '*/10 * * * *', 'select public.sms_rapport_tick()');
  end if;
exception when others then
  raise notice 'planification du rapport SMS non créée : %', sqlerrm;
end $$;

notify pgrst, 'reload schema';
