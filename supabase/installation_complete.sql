-- INSTALLATION COMPLÈTE (migrations 12 à 25) : à coller en une seule fois dans Supabase Studio > SQL Editor puis « Run ». Peut être relancée sans risque.

-- ═══ 20261012000000_vip_colis ═══
-- VIP Colis — schéma complet pour Supabase (self-hosted ou cloud)
-- À exécuter une fois dans le SQL Editor de Supabase Studio (ou via `supabase db push`).

create extension if not exists pgcrypto;

-- ───────────────────────── Tables ─────────────────────────

create table if not exists public.gares (
  id          bigint generated always as identity primary key,
  nom         text not null,
  ville       text not null,
  adresse     text not null,
  responsable text,
  telephone   text,
  created_at  timestamptz not null default now()
);

-- Table dédiée à VIP Colis (nommée vip_profiles pour ne pas entrer en conflit avec une table « profiles » existante).
-- Un profil par compte Supabase Auth. Connexion par « username » :
-- l'e-mail technique est <username>@vipcolis.app (jamais affiché).
create table if not exists public.vip_profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  nom         text not null,
  username    text not null unique,
  role        text not null default 'agent' check (role in ('admin', 'chef_gare', 'agent')),
  gare_id     bigint references public.gares(id) on delete set null,
  telephone   text,
  actif       boolean not null default true,
  created_at  timestamptz not null default now()
);

create sequence if not exists public.colis_numero_seq start 100000;

create table if not exists public.colis (
  id                      bigint generated always as identity primary key,
  numero                  text not null unique,
  expediteur_nom          text not null,
  expediteur_telephone    text not null,
  destinataire_nom        text not null,
  destinataire_telephone  text not null,
  gare_depart_id          bigint not null references public.gares(id),
  gare_arrivee_id         bigint not null references public.gares(id),
  description             text not null,
  nombre                  integer not null default 1 check (nombre > 0),
  poids                   numeric(10,2),
  prix                    numeric(10,2) not null check (prix >= 0),
  statut                  text not null default 'enregistre'
                          check (statut in ('enregistre','charge','en_route','arrive','retire','annule')),
  date_envoi              date not null default current_date,
  agent_id                uuid references public.vip_profiles(id) on delete set null,
  retrait_nom             text,
  retrait_telephone       text,
  retrait_piece_identite  text,
  retrait_signature       text,
  retrait_date            timestamptz,
  photo                   text,
  notes                   text,
  created_at              timestamptz not null default now()
);
create index if not exists colis_statut_idx on public.colis(statut);
create index if not exists colis_depart_idx on public.colis(gare_depart_id);
create index if not exists colis_arrivee_idx on public.colis(gare_arrivee_id);
create index if not exists colis_date_idx on public.colis(date_envoi);

create table if not exists public.historique_colis (
  id               bigint generated always as identity primary key,
  colis_id         bigint not null references public.colis(id) on delete cascade,
  statut           text not null,
  notes            text,
  agent_id         uuid references public.vip_profiles(id) on delete set null,
  date_changement  timestamptz not null default now()
);
create index if not exists historique_colis_idx on public.historique_colis(colis_id);

create table if not exists public.company_settings (
  id         integer primary key default 1 check (id = 1),
  nom        text not null default 'VIP Colis',
  slogan     text not null default 'Réseau de transport express — Burkina Faso',
  telephone  text not null default '',
  email      text not null default '',
  adresse    text not null default '',
  ville      text not null default '',
  pays       text not null default 'Burkina Faso',
  logo       text
);
do $$ begin
  insert into public.company_settings (id) values (1) on conflict do nothing;
exception when undefined_column then null; end $$;

-- ───────────────────────── Fonctions utilitaires ─────────────────────────

create or replace function public.app_role() returns text
language sql stable security definer set search_path = public as $$
  select role from public.vip_profiles where id = auth.uid() and actif
$$;

create or replace function public.app_gare_id() returns bigint
language sql stable security definer set search_path = public as $$
  select gare_id from public.vip_profiles where id = auth.uid() and actif
$$;

-- Numéro de suivi COL-YYYY-XXXXXX + agent courant
create or replace function public.colis_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.numero := 'COL-' || extract(year from now())::int || '-' || nextval('public.colis_numero_seq');
  new.statut := 'enregistre';
  new.agent_id := coalesce(auth.uid(), new.agent_id);
  return new;
end $$;

drop trigger if exists colis_before_insert on public.colis;
create trigger colis_before_insert before insert on public.colis
  for each row execute function public.colis_before_insert();

create or replace function public.colis_after_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.historique_colis (colis_id, statut, notes, agent_id)
  values (new.id, 'enregistre', 'Colis enregistré', new.agent_id);
  return new;
end $$;

drop trigger if exists colis_after_insert on public.colis;
create trigger colis_after_insert after insert on public.colis
  for each row execute function public.colis_after_insert();

-- Empêche de modifier le statut / le retrait / le numéro par UPDATE direct :
-- il faut passer par changer_statut() et retirer_colis().
create or replace function public.colis_guard_update() returns trigger
language plpgsql as $$
begin
  if current_setting('vipcolis.bypass', true) is distinct from 'on' then
    new.numero := old.numero;
    new.statut := old.statut;
    new.agent_id := old.agent_id;
    new.retrait_nom := old.retrait_nom;
    new.retrait_telephone := old.retrait_telephone;
    new.retrait_piece_identite := old.retrait_piece_identite;
    new.retrait_signature := old.retrait_signature;
    new.retrait_date := old.retrait_date;
  end if;
  return new;
end $$;

drop trigger if exists colis_guard_update on public.colis;
create trigger colis_guard_update before update on public.colis
  for each row execute function public.colis_guard_update();

-- Un utilisateur non-admin ne peut pas modifier son propre rôle / sa gare / son état.
create or replace function public.vip_profiles_guard_update() returns trigger
language plpgsql as $$
begin
  if public.app_role() is distinct from 'admin' and current_setting('vipcolis.bypass', true) is distinct from 'on' then
    new.role := old.role;
    new.gare_id := old.gare_id;
    new.actif := old.actif;
    new.username := old.username;
  end if;
  return new;
end $$;

drop trigger if exists vip_profiles_guard_update on public.vip_profiles;
create trigger vip_profiles_guard_update before update on public.vip_profiles
  for each row execute function public.vip_profiles_guard_update();

-- ───────────────────────── Actions métier (RPC) ─────────────────────────

create or replace function public.changer_statut(p_id bigint, p_statut text, p_notes text default null)
returns public.colis
language plpgsql security definer set search_path = public as $$
declare
  c public.colis;
  ok boolean;
begin
  select * into c from public.colis where id = p_id;
  if not found then raise exception 'Colis non trouvé'; end if;
  if app_role() is null then raise exception 'Non autorisé'; end if;
  if app_role() <> 'admin' and app_gare_id() not in (c.gare_depart_id, c.gare_arrivee_id) then
    raise exception 'Non autorisé';
  end if;

  ok := (c.statut = 'enregistre' and p_statut in ('charge','annule'))
     or (c.statut = 'charge'     and p_statut in ('en_route','annule'))
     or (c.statut = 'en_route'   and p_statut in ('arrive','annule'))
     or (c.statut = 'arrive'     and p_statut = 'annule');
  if not ok then raise exception 'Transition % → % impossible', c.statut, p_statut; end if;

  perform set_config('vipcolis.bypass', 'on', true);
  update public.colis set statut = p_statut where id = p_id returning * into c;
  perform set_config('vipcolis.bypass', 'off', true);

  insert into public.historique_colis (colis_id, statut, notes, agent_id)
  values (p_id, p_statut, p_notes, auth.uid());
  return c;
end $$;

create or replace function public.retirer_colis(
  p_id bigint, p_nom text, p_telephone text,
  p_piece text default null, p_signature text default null)
returns public.colis
language plpgsql security definer set search_path = public as $$
declare c public.colis;
begin
  select * into c from public.colis where id = p_id;
  if not found then raise exception 'Colis non trouvé'; end if;
  if app_role() is null then raise exception 'Non autorisé'; end if;
  if app_role() <> 'admin' and app_gare_id() is distinct from c.gare_arrivee_id then
    raise exception 'Le retrait se fait à la gare d''arrivée';
  end if;
  if c.statut <> 'arrive' then raise exception 'Le colis doit être à l''état « Arrivé »'; end if;

  perform set_config('vipcolis.bypass', 'on', true);
  update public.colis set
    statut = 'retire', retrait_nom = p_nom, retrait_telephone = p_telephone,
    retrait_piece_identite = p_piece, retrait_signature = p_signature, retrait_date = now()
  where id = p_id returning * into c;
  perform set_config('vipcolis.bypass', 'off', true);

  insert into public.historique_colis (colis_id, statut, notes, agent_id)
  values (p_id, 'retire', 'Retiré par ' || p_nom, auth.uid());
  return c;
end $$;

-- Création d'un compte (admin uniquement) : crée l'utilisateur Auth + son profil.
create or replace function public.admin_creer_utilisateur(
  p_username text, p_password text, p_nom text,
  p_role text default 'agent', p_gare_id bigint default null, p_telephone text default null)
returns uuid
language plpgsql security definer set search_path = public, auth, extensions as $$
declare
  uid uuid := gen_random_uuid();
  mail text := lower(trim(p_username)) || '@vipcolis.app';
begin
  if app_role() is distinct from 'admin' then raise exception 'Réservé aux administrateurs'; end if;
  if length(p_password) < 6 then raise exception 'Mot de passe trop court (6 caractères minimum)'; end if;

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change, email_change_token_new)
  values (
    '00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', mail,
    crypt(p_password, gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '');

  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), uid, uid::text,
          jsonb_build_object('sub', uid::text, 'email', mail, 'email_verified', true),
          'email', now(), now(), now());

  perform set_config('vipcolis.bypass', 'on', true);
  insert into public.vip_profiles (id, nom, username, role, gare_id, telephone)
  values (uid, p_nom, lower(trim(p_username)), p_role, p_gare_id, p_telephone)
  on conflict (id) do update set nom = excluded.nom, username = excluded.username,
    role = excluded.role, gare_id = excluded.gare_id, telephone = excluded.telephone;
  perform set_config('vipcolis.bypass', 'off', true);
  return uid;
end $$;

create or replace function public.admin_changer_mot_de_passe(p_user uuid, p_password text)
returns void
language plpgsql security definer set search_path = public, auth, extensions as $$
begin
  if app_role() is distinct from 'admin' then raise exception 'Réservé aux administrateurs'; end if;
  if length(p_password) < 6 then raise exception 'Mot de passe trop court (6 caractères minimum)'; end if;
  update auth.users set encrypted_password = crypt(p_password, gen_salt('bf')), updated_at = now() where id = p_user;
end $$;

-- ───────────────────────── Vue enrichie + rapports ─────────────────────────

create or replace view public.colis_detail with (security_invoker = true) as
select c.*,
       gd.nom as gare_depart_nom,
       ga.nom as gare_arrivee_nom,
       p.nom  as agent_nom
from public.colis c
left join public.gares gd on gd.id = c.gare_depart_id
left join public.gares ga on ga.id = c.gare_arrivee_id
left join public.vip_profiles p on p.id = c.agent_id;

create or replace view public.historique_detail with (security_invoker = true) as
select h.*, p.nom as agent_nom
from public.historique_colis h
left join public.vip_profiles p on p.id = h.agent_id;

create or replace function public.dashboard_stats() returns json
language sql stable set search_path = public as $$
  select json_build_object(
    'total_colis',         (select count(*) from colis),
    'colis_aujourd_hui',   (select count(*) from colis where date_envoi = current_date),
    'colis_en_route',      (select count(*) from colis where statut = 'en_route'),
    'colis_arrives',       (select count(*) from colis where statut = 'arrive'),
    'colis_non_retires',   (select count(*) from colis where statut = 'arrive'),
    'recette_totale',      coalesce((select sum(prix) from colis where statut <> 'annule'), 0),
    'recette_aujourd_hui', coalesce((select sum(prix) from colis where statut <> 'annule' and date_envoi = current_date), 0),
    'total_gares',         (select count(*) from gares),
    'total_agents',        (select count(*) from vip_profiles where actif)
  )
$$;

create or replace function public.colis_par_jour(p_debut date default null, p_fin date default null)
returns table (date date, total bigint, recette numeric)
language sql stable set search_path = public as $$
  select date_envoi, count(*), coalesce(sum(prix), 0)
  from colis
  where (p_debut is null or date_envoi >= p_debut) and (p_fin is null or date_envoi <= p_fin)
  group by date_envoi order by date_envoi
$$;

create or replace function public.recettes_par_gare()
returns table (gare_id bigint, gare_nom text, total_colis bigint, recette_totale numeric)
language sql stable set search_path = public as $$
  select g.id, g.nom, count(c.id), coalesce(sum(c.prix), 0)
  from gares g left join colis c on c.gare_depart_id = g.id
  group by g.id, g.nom order by g.nom
$$;

create or replace function public.recettes_par_agent()
returns table (agent_id uuid, agent_nom text, total_colis bigint, recette_totale numeric)
language sql stable set search_path = public as $$
  select p.id, p.nom, count(c.id), coalesce(sum(c.prix), 0)
  from vip_profiles p left join colis c on c.agent_id = p.id
  where p.role = 'agent'
  group by p.id, p.nom order by p.nom
$$;

create or replace function public.statuts_summary()
returns table (statut text, total bigint)
language sql stable set search_path = public as $$
  select statut, count(*) from colis group by statut
$$;

-- ───────────────────────── Sécurité (RLS) ─────────────────────────

alter table public.gares enable row level security;
alter table public.vip_profiles enable row level security;
alter table public.colis enable row level security;
alter table public.historique_colis enable row level security;
alter table public.company_settings enable row level security;

drop policy if exists gares_select on public.gares;
drop policy if exists gares_write on public.gares;
create policy gares_select on public.gares for select to authenticated using (true);
create policy gares_write on public.gares for all to authenticated
  using (app_role() = 'admin') with check (app_role() = 'admin');

drop policy if exists vip_profiles_select on public.vip_profiles;
drop policy if exists vip_profiles_update on public.vip_profiles;
drop policy if exists vip_profiles_delete on public.vip_profiles;
create policy vip_profiles_select on public.vip_profiles for select to authenticated using (true);
create policy vip_profiles_update on public.vip_profiles for update to authenticated
  using (app_role() = 'admin' or id = auth.uid())
  with check (app_role() = 'admin' or id = auth.uid());

-- Les colis : l'admin voit tout, les autres voient les colis de leur gare (départ ou arrivée).
drop policy if exists colis_select on public.colis;
drop policy if exists colis_insert on public.colis;
drop policy if exists colis_update on public.colis;
create policy colis_select on public.colis for select to authenticated using (
  app_role() = 'admin' or (app_role() is not null and app_gare_id() in (gare_depart_id, gare_arrivee_id)));
create policy colis_insert on public.colis for insert to authenticated with check (
  app_role() = 'admin' or (app_role() is not null and app_gare_id() = gare_depart_id));
create policy colis_update on public.colis for update to authenticated using (
  app_role() = 'admin' or (app_role() is not null and app_gare_id() in (gare_depart_id, gare_arrivee_id)));

drop policy if exists histo_select on public.historique_colis;
create policy histo_select on public.historique_colis for select to authenticated using (
  exists (select 1 from public.colis c where c.id = colis_id));

drop policy if exists settings_select on public.company_settings;
drop policy if exists settings_update on public.company_settings;
create policy settings_select on public.company_settings for select to authenticated using (true);
create policy settings_update on public.company_settings for update to authenticated
  using (app_role() = 'admin') with check (app_role() = 'admin');

grant usage on schema public to authenticated;
grant select, insert, update, delete on public.gares, public.vip_profiles, public.colis, public.company_settings to authenticated;
grant select on public.historique_colis, public.colis_detail, public.historique_detail to authenticated;
grant usage, select on all sequences in schema public to authenticated;
grant execute on all functions in schema public to authenticated;
revoke execute on function public.admin_creer_utilisateur(text,text,text,text,bigint,text) from public, anon;
revoke execute on function public.admin_changer_mot_de_passe(uuid,text) from public, anon;
revoke execute on function public.changer_statut(bigint,text,text) from public, anon;
revoke execute on function public.retirer_colis(bigint,text,text,text,text) from public, anon;

-- Temps réel : les écrans se mettent à jour tout seuls.
do $$ begin
  alter publication supabase_realtime add table public.colis;
exception when others then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.historique_colis;
exception when others then null; end $$;

-- ═══ 20261013000000_scan_rapide ═══
-- Scan rapide par lot : embarquement et déchargement de plusieurs colis d'un coup.
--   embarquement  : Enregistré            -> Chargé
--   déchargement  : Chargé / En route     -> Arrivé   (si le colis est encore « Chargé »,
--                                                      l'étape « En route » est ajoutée à l'historique)
-- Les droits sont les mêmes que pour changer_statut : admin partout, sinon colis de sa gare.

create or replace function public.scan_lot(p_mode text, p_numeros text[], p_notes text default null)
returns table (r_numero text, r_ok boolean, r_message text, r_statut text)
language plpgsql security definer set search_path = public as $$
declare
  nums text[];
  n text;
  c public.colis;
begin
  if app_role() is null then raise exception 'Non autorisé'; end if;
  if p_mode not in ('embarquement', 'dechargement') then raise exception 'Mode inconnu : %', p_mode; end if;

  select coalesce(array_agg(distinct upper(trim(x))), '{}') into nums
  from unnest(coalesce(p_numeros, '{}')) as x where trim(x) <> '';

  foreach n in array nums loop
    select * into c from public.colis where colis.numero = n;
    if not found then
      return query select n, false, 'Colis introuvable'::text, null::text;
      continue;
    end if;
    if app_role() <> 'admin' and app_gare_id() not in (c.gare_depart_id, c.gare_arrivee_id) then
      return query select n, false, 'Colis d''une autre gare'::text, c.statut;
      continue;
    end if;

    if p_mode = 'embarquement' then
      if c.statut <> 'enregistre' then
        return query select n, false, ('Statut actuel : ' || c.statut)::text, c.statut;
        continue;
      end if;
      perform set_config('vipcolis.bypass', 'on', true);
      update public.colis set statut = 'charge' where id = c.id;
      perform set_config('vipcolis.bypass', 'off', true);
      insert into public.historique_colis (colis_id, statut, notes, agent_id)
      values (c.id, 'charge', coalesce(p_notes, 'Embarquement (scan rapide)'), auth.uid());
      return query select n, true, 'Embarqué'::text, 'charge'::text;
    else
      if c.statut not in ('charge', 'en_route') then
        return query select n, false, ('Statut actuel : ' || c.statut)::text, c.statut;
        continue;
      end if;
      if c.statut = 'charge' then
        insert into public.historique_colis (colis_id, statut, notes, agent_id)
        values (c.id, 'en_route', 'Départ (ajouté automatiquement au déchargement)', auth.uid());
      end if;
      perform set_config('vipcolis.bypass', 'on', true);
      update public.colis set statut = 'arrive' where id = c.id;
      perform set_config('vipcolis.bypass', 'off', true);
      insert into public.historique_colis (colis_id, statut, notes, agent_id)
      values (c.id, 'arrive', coalesce(p_notes, 'Déchargement (scan rapide)'), auth.uid());
      return query select n, true, 'Déchargé'::text, 'arrive'::text;
    end if;
  end loop;
end $$;

revoke execute on function public.scan_lot(text, text[], text) from public, anon;
grant execute on function public.scan_lot(text, text[], text) to authenticated;

-- ═══ 20261014000000_saas_multi_entreprises ═══
-- VIP Colis en SaaS : plusieurs entreprises, abonnements contrôlés par un super administrateur.
--
-- Rôles : superadmin (vous), admin (administrateur d'une entreprise), chef_gare, agent.
-- Chaque ligne métier (gares, colis, paramètres, comptes) appartient à une entreprise (company_id)
-- et la sécurité par ligne (RLS) isole les entreprises les unes des autres.
-- Une entreprise qui s'inscrit est « en_attente » : rien ne fonctionne tant que le superadmin
-- ne l'a pas validée (statut « actif ») avec une date de fin d'abonnement.
-- Identifiant de connexion : numéro de téléphone (chiffres uniquement) ou nom d'utilisateur.

-- ───────────────────────── Entreprises ─────────────────────────

create table if not exists public.companies (
  id               bigint generated always as identity primary key,
  nom              text not null,
  telephone        text,
  ville            text,
  pays             text not null default 'Burkina Faso',
  statut           text not null default 'en_attente' check (statut in ('en_attente', 'actif', 'suspendu')),
  plan             text not null default 'standard',
  abonnement_fin   date,                       -- null = sans limite de date
  max_utilisateurs integer not null default 5 check (max_utilisateurs > 0),
  notes            text,
  created_at       timestamptz not null default now()
);

-- Les données existantes (avant le SaaS) sont rattachées à une première entreprise, active.
insert into public.companies (nom, statut, plan, max_utilisateurs)
select coalesce((select nom from public.company_settings limit 1), 'VIP Colis'), 'actif', 'illimité', 1000
where not exists (select 1 from public.companies);

-- ───────────────────────── Colonnes company_id ─────────────────────────

alter table public.vip_profiles add column if not exists company_id bigint references public.companies(id) on delete cascade;
alter table public.gares        add column if not exists company_id bigint references public.companies(id) on delete cascade;
alter table public.colis        add column if not exists company_id bigint references public.companies(id) on delete cascade;
alter table public.company_settings add column if not exists company_id bigint references public.companies(id) on delete cascade;

update public.gares set company_id = (select min(id) from public.companies) where company_id is null;
update public.colis set company_id = (select min(id) from public.companies) where company_id is null;
update public.vip_profiles set company_id = (select min(id) from public.companies)
  where company_id is null and role <> 'superadmin';
update public.company_settings set company_id = (select min(id) from public.companies) where company_id is null;

alter table public.gares alter column company_id set not null;
alter table public.colis alter column company_id set not null;
create index if not exists gares_company_idx on public.gares(company_id);
create index if not exists colis_company_idx on public.colis(company_id);
create index if not exists vip_profiles_company_idx on public.vip_profiles(company_id);

-- Paramètres : une ligne par entreprise (au lieu d'une ligne unique).
alter table public.company_settings drop constraint if exists company_settings_id_check;
alter table public.company_settings drop constraint if exists company_settings_pkey;
alter table public.company_settings drop column if exists id;
alter table public.company_settings alter column company_id set not null;
alter table public.company_settings add primary key (company_id);

-- Rôle « superadmin » autorisé.
alter table public.vip_profiles drop constraint if exists vip_profiles_role_check;
alter table public.vip_profiles add constraint vip_profiles_role_check
  check (role in ('superadmin', 'admin', 'chef_gare', 'agent', 'barragiste', 'guichet', 'convoyeur', 'comptable'));
alter table public.vip_profiles drop constraint if exists vip_profiles_company_role_check;
alter table public.vip_profiles add constraint vip_profiles_company_role_check
  check (role = 'superadmin' or company_id is not null);

-- ───────────────────────── Fonctions utilitaires ─────────────────────────

-- Numéro de téléphone -> chiffres seuls ; sinon nom d'utilisateur en minuscules.
create or replace function public.normaliser_identifiant(p text) returns text
language sql immutable as $$
  select case when trim(p) ~ '^[+0-9 .()-]+$'
              then regexp_replace(trim(p), '[^0-9]', '', 'g')
              else lower(trim(p)) end
$$;

create or replace function public.app_company_id() returns bigint
language sql stable security definer set search_path = public as $$
  select company_id from public.vip_profiles where id = auth.uid() and actif
$$;

-- L'entreprise peut-elle utiliser l'application (validée, non suspendue, abonnement à jour) ?
create or replace function public.company_ok(cid bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.companies c
    where c.id = cid and c.statut = 'actif'
      and (c.abonnement_fin is null or c.abonnement_fin >= current_date))
$$;

-- Rôle effectif : null si le compte est désactivé ou si l'entreprise n'a pas d'abonnement valide.
create or replace function public.app_role() returns text
language sql stable security definer set search_path = public as $$
  select p.role from public.vip_profiles p
  where p.id = auth.uid() and p.actif and (p.role = 'superadmin' or public.company_ok(p.company_id))
$$;

create or replace function public.app_gare_id() returns bigint
language sql stable security definer set search_path = public as $$
  select gare_id from public.vip_profiles where id = auth.uid() and actif
$$;

-- Dédéconnecte (best effort) tous les utilisateurs d'une entreprise : leurs sessions sont supprimées.
create or replace function public._deconnecter_entreprise(cid bigint) returns void
language plpgsql security definer set search_path = public, auth as $$
begin
  begin
    delete from auth.sessions where user_id in (select id from public.vip_profiles where company_id = cid);
  exception when others then null;
  end;
  begin
    delete from auth.refresh_tokens
      where user_id::text in (select id::text from public.vip_profiles where company_id = cid);
  exception when others then null;
  end;
end $$;

-- Crée le compte d'authentification (identifiant = téléphone ou nom d'utilisateur).
create or replace function public._creer_compte_auth(p_identifiant text, p_password text) returns uuid
language plpgsql security definer set search_path = public, auth, extensions as $$
declare
  uid uuid := gen_random_uuid();
  ident text := public.normaliser_identifiant(p_identifiant);
  mail text;
begin
  if ident is null or length(ident) < 3 then raise exception 'Identifiant invalide (3 caractères minimum)'; end if;
  if length(coalesce(p_password, '')) < 6 then raise exception 'Mot de passe trop court (6 caractères minimum)'; end if;
  mail := ident || '@vipcolis.app';
  if exists (select 1 from auth.users where email = mail) then
    raise exception 'Cet identifiant est déjà utilisé';
  end if;

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change, email_change_token_new)
  values (
    '00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', mail,
    crypt(p_password, gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '');

  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), uid, uid::text,
          jsonb_build_object('sub', uid::text, 'email', mail, 'email_verified', true),
          'email', now(), now(), now());
  return uid;
end $$;

-- Crée l'entreprise, ses paramètres et son administrateur.
create or replace function public._creer_entreprise(
  p_entreprise text, p_ville text, p_nom_admin text, p_identifiant text, p_password text,
  p_statut text, p_fin date, p_plan text, p_max integer)
returns bigint
language plpgsql security definer set search_path = public, auth, extensions as $$
declare
  cid bigint;
  uid uuid;
begin
  if length(trim(coalesce(p_entreprise, ''))) < 2 then raise exception 'Nom d''entreprise requis'; end if;
  if length(trim(coalesce(p_nom_admin, ''))) < 2 then raise exception 'Nom de l''administrateur requis'; end if;

  uid := public._creer_compte_auth(p_identifiant, p_password);

  insert into public.companies (nom, telephone, ville, statut, plan, abonnement_fin, max_utilisateurs)
  values (trim(p_entreprise), public.normaliser_identifiant(p_identifiant), nullif(trim(coalesce(p_ville, '')), ''),
          p_statut, coalesce(p_plan, 'standard'), p_fin, coalesce(p_max, 5))
  returning id into cid;

  insert into public.company_settings (company_id, nom, telephone, ville)
  values (cid, trim(p_entreprise), public.normaliser_identifiant(p_identifiant), coalesce(trim(p_ville), ''));

  perform set_config('vipcolis.bypass', 'on', true);
  insert into public.vip_profiles (id, nom, username, role, telephone, company_id)
  values (uid, trim(p_nom_admin), public.normaliser_identifiant(p_identifiant), 'admin',
          public.normaliser_identifiant(p_identifiant), cid);
  perform set_config('vipcolis.bypass', 'off', true);
  return cid;
end $$;

-- ───────────────────────── Garde-fous sur les écritures ─────────────────────────

create or replace function public.set_company_id() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if public.app_company_id() is not null then new.company_id := public.app_company_id(); end if;
  return new;
end $$;

drop trigger if exists gares_company on public.gares;
create trigger gares_company before insert on public.gares for each row execute function public.set_company_id();

create or replace function public.colis_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.numero := 'COL-' || extract(year from now())::int || '-' || nextval('public.colis_numero_seq');
  new.statut := 'enregistre';
  new.agent_id := coalesce(auth.uid(), new.agent_id);
  if public.app_company_id() is not null then new.company_id := public.app_company_id(); end if;
  return new;
end $$;

create or replace function public.colis_guard_update() returns trigger
language plpgsql as $$
begin
  if current_setting('vipcolis.bypass', true) is distinct from 'on' then
    new.numero := old.numero;
    new.statut := old.statut;
    new.agent_id := old.agent_id;
    new.company_id := old.company_id;
    new.retrait_nom := old.retrait_nom;
    new.retrait_telephone := old.retrait_telephone;
    new.retrait_piece_identite := old.retrait_piece_identite;
    new.retrait_signature := old.retrait_signature;
    new.retrait_date := old.retrait_date;
  end if;
  return new;
end $$;

create or replace function public.vip_profiles_guard_update() returns trigger
language plpgsql as $$
begin
  if current_setting('vipcolis.bypass', true) = 'on' then return new; end if;
  new.company_id := old.company_id;
  if public.app_role() = 'superadmin' then return new; end if;
  if new.role = 'superadmin' then new.role := old.role; end if;
  if public.app_role() is distinct from 'admin' then
    new.role := old.role;
    new.gare_id := old.gare_id;
    new.actif := old.actif;
    new.username := old.username;
  end if;
  return new;
end $$;

-- ───────────────────────── Sécurité (RLS) ─────────────────────────

alter table public.companies enable row level security;

drop policy if exists companies_select on public.companies;
drop policy if exists companies_write on public.companies;
create policy companies_select on public.companies for select to authenticated
  using (public.app_role() = 'superadmin' or id = public.app_company_id());
create policy companies_write on public.companies for all to authenticated
  using (public.app_role() = 'superadmin') with check (public.app_role() = 'superadmin');

drop policy if exists gares_select on public.gares;
drop policy if exists gares_write on public.gares;
create policy gares_select on public.gares for select to authenticated
  using (public.app_role() is not null and company_id = public.app_company_id());
create policy gares_write on public.gares for all to authenticated
  using (public.app_role() = 'admin' and company_id = public.app_company_id())
  with check (public.app_role() = 'admin' and company_id = public.app_company_id());

drop policy if exists vip_profiles_select on public.vip_profiles;
drop policy if exists vip_profiles_update on public.vip_profiles;
drop policy if exists vip_profiles_delete on public.vip_profiles;
create policy vip_profiles_select on public.vip_profiles for select to authenticated
  using (id = auth.uid()
         or public.app_role() = 'superadmin'
         or (public.app_role() is not null and company_id = public.app_company_id()));
create policy vip_profiles_update on public.vip_profiles for update to authenticated
  using (id = auth.uid() or public.app_role() = 'superadmin'
         or (public.app_role() = 'admin' and company_id = public.app_company_id()))
  with check (id = auth.uid() or public.app_role() = 'superadmin'
         or (public.app_role() = 'admin' and company_id = public.app_company_id()));

drop policy if exists colis_select on public.colis;
drop policy if exists colis_insert on public.colis;
drop policy if exists colis_update on public.colis;
create policy colis_select on public.colis for select to authenticated using (
  public.app_role() in ('admin', 'chef_gare', 'agent') and company_id = public.app_company_id()
  and (public.app_role() = 'admin' or public.app_gare_id() in (gare_depart_id, gare_arrivee_id)));
create policy colis_insert on public.colis for insert to authenticated with check (
  public.app_role() in ('admin', 'chef_gare', 'agent')
  and (public.app_role() = 'admin' or public.app_gare_id() = gare_depart_id));
create policy colis_update on public.colis for update to authenticated using (
  public.app_role() in ('admin', 'chef_gare', 'agent') and company_id = public.app_company_id()
  and (public.app_role() = 'admin' or public.app_gare_id() in (gare_depart_id, gare_arrivee_id)));

drop policy if exists settings_select on public.company_settings;
drop policy if exists settings_update on public.company_settings;
create policy settings_select on public.company_settings for select to authenticated
  using (public.app_role() is not null and company_id = public.app_company_id());
create policy settings_update on public.company_settings for update to authenticated
  using (public.app_role() = 'admin' and company_id = public.app_company_id())
  with check (public.app_role() = 'admin' and company_id = public.app_company_id());

grant select on public.companies to authenticated;
grant update on public.companies to authenticated;

-- ───────────────────────── Actions métier (isolées par entreprise) ─────────────────────────

create or replace function public.changer_statut(p_id bigint, p_statut text, p_notes text default null)
returns public.colis
language plpgsql security definer set search_path = public as $$
declare
  c public.colis;
  ok boolean;
begin
  if app_role() is null or app_role() = 'superadmin' then raise exception 'Non autorisé'; end if;
  select * into c from public.colis where id = p_id and company_id = app_company_id();
  if not found then raise exception 'Colis non trouvé'; end if;
  if app_role() <> 'admin' and app_gare_id() not in (c.gare_depart_id, c.gare_arrivee_id) then
    raise exception 'Non autorisé';
  end if;

  ok := (c.statut = 'enregistre' and p_statut in ('charge','annule'))
     or (c.statut = 'charge'     and p_statut in ('en_route','annule'))
     or (c.statut = 'en_route'   and p_statut in ('arrive','annule'))
     or (c.statut = 'arrive'     and p_statut = 'annule');
  if not ok then raise exception 'Transition % → % impossible', c.statut, p_statut; end if;

  perform set_config('vipcolis.bypass', 'on', true);
  update public.colis set statut = p_statut where id = p_id returning * into c;
  perform set_config('vipcolis.bypass', 'off', true);

  insert into public.historique_colis (colis_id, statut, notes, agent_id)
  values (p_id, p_statut, p_notes, auth.uid());
  return c;
end $$;

create or replace function public.retirer_colis(
  p_id bigint, p_nom text, p_telephone text,
  p_piece text default null, p_signature text default null)
returns public.colis
language plpgsql security definer set search_path = public as $$
declare c public.colis;
begin
  if app_role() is null or app_role() = 'superadmin' then raise exception 'Non autorisé'; end if;
  select * into c from public.colis where id = p_id and company_id = app_company_id();
  if not found then raise exception 'Colis non trouvé'; end if;
  if app_role() <> 'admin' and app_gare_id() is distinct from c.gare_arrivee_id then
    raise exception 'Le retrait se fait à la gare d''arrivée';
  end if;
  if c.statut <> 'arrive' then raise exception 'Le colis doit être à l''état « Arrivé »'; end if;

  perform set_config('vipcolis.bypass', 'on', true);
  update public.colis set
    statut = 'retire', retrait_nom = p_nom, retrait_telephone = p_telephone,
    retrait_piece_identite = p_piece, retrait_signature = p_signature, retrait_date = now()
  where id = p_id returning * into c;
  perform set_config('vipcolis.bypass', 'off', true);

  insert into public.historique_colis (colis_id, statut, notes, agent_id)
  values (p_id, 'retire', 'Retiré par ' || p_nom, auth.uid());
  return c;
end $$;

create or replace function public.scan_lot(p_mode text, p_numeros text[], p_notes text default null)
returns table (r_numero text, r_ok boolean, r_message text, r_statut text)
language plpgsql security definer set search_path = public as $$
declare
  nums text[];
  n text;
  c public.colis;
begin
  if app_role() is null or app_role() = 'superadmin' then raise exception 'Non autorisé'; end if;
  if p_mode not in ('embarquement', 'dechargement') then raise exception 'Mode inconnu : %', p_mode; end if;

  select coalesce(array_agg(distinct upper(trim(x))), '{}') into nums
  from unnest(coalesce(p_numeros, '{}')) as x where trim(x) <> '';

  foreach n in array nums loop
    select * into c from public.colis where colis.numero = n and colis.company_id = app_company_id();
    if not found then
      return query select n, false, 'Colis introuvable'::text, null::text;
      continue;
    end if;
    if app_role() <> 'admin' and app_gare_id() not in (c.gare_depart_id, c.gare_arrivee_id) then
      return query select n, false, 'Colis d''une autre gare'::text, c.statut;
      continue;
    end if;

    if p_mode = 'embarquement' then
      if c.statut <> 'enregistre' then
        return query select n, false, ('Statut actuel : ' || c.statut)::text, c.statut;
        continue;
      end if;
      perform set_config('vipcolis.bypass', 'on', true);
      update public.colis set statut = 'charge' where id = c.id;
      perform set_config('vipcolis.bypass', 'off', true);
      insert into public.historique_colis (colis_id, statut, notes, agent_id)
      values (c.id, 'charge', coalesce(p_notes, 'Embarquement (scan rapide)'), auth.uid());
      return query select n, true, 'Embarqué'::text, 'charge'::text;
    else
      if c.statut not in ('charge', 'en_route') then
        return query select n, false, ('Statut actuel : ' || c.statut)::text, c.statut;
        continue;
      end if;
      if c.statut = 'charge' then
        insert into public.historique_colis (colis_id, statut, notes, agent_id)
        values (c.id, 'en_route', 'Départ (ajouté automatiquement au déchargement)', auth.uid());
      end if;
      perform set_config('vipcolis.bypass', 'on', true);
      update public.colis set statut = 'arrive' where id = c.id;
      perform set_config('vipcolis.bypass', 'off', true);
      insert into public.historique_colis (colis_id, statut, notes, agent_id)
      values (c.id, 'arrive', coalesce(p_notes, 'Déchargement (scan rapide)'), auth.uid());
      return query select n, true, 'Déchargé'::text, 'arrive'::text;
    end if;
  end loop;
end $$;

-- ───────────────────────── Comptes utilisateurs d'une entreprise ─────────────────────────

drop function if exists public.admin_creer_utilisateur(text, text, text, text, bigint, text);
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
  if p_role not in ('admin', 'chef_gare', 'agent') then raise exception 'Rôle invalide'; end if;
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

create or replace function public.admin_changer_mot_de_passe(p_user uuid, p_password text)
returns void
language plpgsql security definer set search_path = public, auth, extensions as $$
begin
  if app_role() is distinct from 'admin'
     or not exists (select 1 from public.vip_profiles where id = p_user and company_id = app_company_id()) then
    raise exception 'Réservé aux administrateurs de l''entreprise';
  end if;
  if length(p_password) < 6 then raise exception 'Mot de passe trop court (6 caractères minimum)'; end if;
  update auth.users set encrypted_password = crypt(p_password, gen_salt('bf')), updated_at = now() where id = p_user;
  -- le changement de mot de passe force la reconnexion de cet utilisateur
  begin delete from auth.sessions where user_id = p_user; exception when others then null; end;
end $$;

-- ───────────────────────── Inscription, abonnements, super administrateur ─────────────────────────

-- Une entreprise s'inscrit seule (appelable sans être connecté). Elle reste « en_attente » jusqu'à validation.
create or replace function public.inscrire_entreprise(
  p_entreprise text, p_ville text, p_nom_admin text, p_telephone text, p_password text)
returns bigint
language plpgsql security definer set search_path = public, auth, extensions as $$
begin
  if public.normaliser_identifiant(p_telephone) !~ '^[0-9]{8,15}$' then
    raise exception 'Numéro de téléphone invalide';
  end if;
  return public._creer_entreprise(p_entreprise, p_ville, p_nom_admin, p_telephone, p_password,
                                  'en_attente', null, 'standard', 5);
end $$;

create or replace function public.sa_creer_entreprise(
  p_entreprise text, p_ville text, p_nom_admin text, p_telephone text, p_password text,
  p_fin date default null, p_plan text default 'standard', p_max integer default 5)
returns bigint
language plpgsql security definer set search_path = public, auth, extensions as $$
begin
  if app_role() is distinct from 'superadmin' then raise exception 'Réservé au super administrateur'; end if;
  return public._creer_entreprise(p_entreprise, p_ville, p_nom_admin, p_telephone, p_password,
                                  'actif', p_fin, p_plan, p_max);
end $$;

-- Valide, suspend, prolonge ou modifie l'abonnement d'une entreprise.
create or replace function public.sa_definir_abonnement(
  p_company bigint, p_statut text, p_fin date, p_plan text default null, p_max integer default null)
returns public.companies
language plpgsql security definer set search_path = public as $$
declare c public.companies;
begin
  if app_role() is distinct from 'superadmin' then raise exception 'Réservé au super administrateur'; end if;
  if p_statut not in ('en_attente', 'actif', 'suspendu') then raise exception 'Statut invalide'; end if;
  update public.companies set
    statut = p_statut,
    abonnement_fin = p_fin,
    plan = coalesce(p_plan, plan),
    max_utilisateurs = coalesce(p_max, max_utilisateurs)
  where id = p_company returning * into c;
  if not found then raise exception 'Entreprise introuvable'; end if;
  if p_statut <> 'actif' or (p_fin is not null and p_fin < current_date) then
    perform public._deconnecter_entreprise(p_company);
  end if;
  return c;
end $$;

create or replace function public.sa_stats() returns json
language sql stable security definer set search_path = public as $$
  select case when app_role() = 'superadmin' then json_build_object(
    'entreprises', (select count(*) from public.companies),
    'en_attente',  (select count(*) from public.companies where statut = 'en_attente'),
    'actives',     (select count(*) from public.companies where statut = 'actif'
                      and (abonnement_fin is null or abonnement_fin >= current_date)),
    'expirees',    (select count(*) from public.companies where statut = 'actif' and abonnement_fin < current_date),
    'suspendues',  (select count(*) from public.companies where statut = 'suspendu'),
    'utilisateurs',(select count(*) from public.vip_profiles where role <> 'superadmin')
  ) end
$$;

-- Nombre d'utilisateurs par entreprise, pour la console du superadmin.
create or replace view public.companies_detail with (security_invoker = true) as
select c.*,
       (select count(*) from public.vip_profiles p where p.company_id = c.id and p.actif) as nb_utilisateurs,
       (select p.nom from public.vip_profiles p where p.company_id = c.id and p.role = 'admin' order by p.created_at limit 1) as admin_nom,
       (select p.username from public.vip_profiles p where p.company_id = c.id and p.role = 'admin' order by p.created_at limit 1) as admin_identifiant,
       case when c.statut = 'actif' and c.abonnement_fin is not null and c.abonnement_fin < current_date
            then 'expire' else c.statut end as statut_effectif
from public.companies c;
grant select on public.companies_detail to authenticated;

-- Appelée par l'app à chaque (re)connexion : le compte et l'abonnement sont-ils toujours valides ?
create or replace function public.ma_session() returns json
language plpgsql stable security definer set search_path = public as $$
declare
  p public.vip_profiles;
  c public.companies;
  valide boolean := false;
  motif text := null;
begin
  select * into p from public.vip_profiles where id = auth.uid();
  if not found then
    return json_build_object('valide', false, 'motif', 'profil_introuvable');
  end if;
  if not p.actif then
    motif := 'compte_desactive';
  elsif p.role = 'superadmin' then
    valide := true;
  else
    select * into c from public.companies where id = p.company_id;
    if not found then motif := 'entreprise_introuvable';
    elsif c.statut = 'en_attente' then motif := 'en_attente';
    elsif c.statut = 'suspendu' then motif := 'suspendu';
    elsif c.abonnement_fin is not null and c.abonnement_fin < current_date then motif := 'abonnement_expire';
    else valide := true;
    end if;
  end if;
  return json_build_object(
    'valide', valide,
    'motif', motif,
    'profil', row_to_json(p),
    'entreprise', case when c.id is null then null else row_to_json(c) end);
end $$;

-- Création du super administrateur : à exécuter UNE fois dans le SQL Editor (rôle postgres).
-- Non appelable depuis l'application.
create or replace function public.creer_superadmin(p_identifiant text, p_password text, p_nom text)
returns uuid
language plpgsql security definer set search_path = public, auth, extensions as $$
declare uid uuid;
begin
  uid := public._creer_compte_auth(p_identifiant, p_password);
  perform set_config('vipcolis.bypass', 'on', true);
  insert into public.vip_profiles (id, nom, username, role, telephone, company_id)
  values (uid, trim(p_nom), public.normaliser_identifiant(p_identifiant), 'superadmin',
          case when public.normaliser_identifiant(p_identifiant) ~ '^[0-9]+$' then public.normaliser_identifiant(p_identifiant) end, null);
  perform set_config('vipcolis.bypass', 'off', true);
  return uid;
end $$;

-- ───────────────────────── Droits d'exécution ─────────────────────────

revoke execute on function public._deconnecter_entreprise(bigint) from public, anon, authenticated;
revoke execute on function public._creer_compte_auth(text, text) from public, anon, authenticated;
revoke execute on function public._creer_entreprise(text, text, text, text, text, text, date, text, integer) from public, anon, authenticated;
revoke execute on function public.creer_superadmin(text, text, text) from public, anon, authenticated;
revoke execute on function public.sa_creer_entreprise(text, text, text, text, text, date, text, integer) from public, anon;
revoke execute on function public.sa_definir_abonnement(bigint, text, date, text, integer) from public, anon;
revoke execute on function public.sa_stats() from public, anon;
revoke execute on function public.ma_session() from public, anon;
revoke execute on function public.admin_creer_utilisateur(text, text, text, text, bigint, text) from public, anon;
revoke execute on function public.admin_changer_mot_de_passe(uuid, text) from public, anon;
revoke execute on function public.changer_statut(bigint, text, text) from public, anon;
revoke execute on function public.retirer_colis(bigint, text, text, text, text) from public, anon;
revoke execute on function public.scan_lot(text, text[], text) from public, anon;
grant execute on function public.inscrire_entreprise(text, text, text, text, text) to anon, authenticated;
grant execute on function public.sa_creer_entreprise(text, text, text, text, text, date, text, integer) to authenticated;
grant execute on function public.sa_definir_abonnement(bigint, text, date, text, integer) to authenticated;
grant execute on function public.sa_stats() to authenticated;
grant execute on function public.ma_session() to authenticated;
grant execute on function public.admin_creer_utilisateur(text, text, text, text, bigint, text) to authenticated;
grant execute on function public.admin_changer_mot_de_passe(uuid, text) to authenticated;
grant execute on function public.changer_statut(bigint, text, text) to authenticated;
grant execute on function public.retirer_colis(bigint, text, text, text, text) to authenticated;
grant execute on function public.scan_lot(text, text[], text) to authenticated;

-- ═══ 20261015000000_mises_a_jour_app ═══
-- Mises à jour de l'application distribuées par votre propre serveur.
-- Le super administrateur publie une version (numéro de build + lien de l'APK) ; l'application vérifie
-- au démarrage s'il existe une version plus récente et propose de l'installer (obligatoire ou non).

create table if not exists public.app_versions (
  id           bigint generated always as identity primary key,
  plateforme   text not null default 'android' check (plateforme in ('android')),
  version_name text not null,
  build_number integer not null check (build_number > 0),
  apk_url      text not null,
  notes        text,
  obligatoire  boolean not null default false,
  actif        boolean not null default true,
  created_at   timestamptz not null default now(),
  unique (plateforme, build_number)
);

alter table public.app_versions enable row level security;

drop policy if exists app_versions_select on public.app_versions;
drop policy if exists app_versions_write on public.app_versions;
-- Lecture ouverte (même avant connexion) pour les versions actives ; le superadmin voit tout.
create policy app_versions_select on public.app_versions for select to anon, authenticated
  using (actif or public.app_role() = 'superadmin');
create policy app_versions_write on public.app_versions for all to authenticated
  using (public.app_role() = 'superadmin') with check (public.app_role() = 'superadmin');

grant select on public.app_versions to anon, authenticated;
grant insert, update, delete on public.app_versions to authenticated;

-- Dossier de stockage public pour les APK (téléversement par le superadmin ou par le workflow GitHub).
-- Attention : la taille maximale d'un fichier est aussi limitée par la configuration globale du service
-- Storage de votre Supabase (FILE_SIZE_LIMIT, 50 Mo par défaut) : augmentez-la si votre APK est plus gros.
do $$ begin
  begin
    insert into storage.buckets (id, name, public, file_size_limit)
    values ('app-releases', 'app-releases', true, 314572800)
    on conflict (id) do update set public = true, file_size_limit = excluded.file_size_limit;
  exception when undefined_column then
    insert into storage.buckets (id, name, public) values ('app-releases', 'app-releases', true)
    on conflict (id) do update set public = true;
  end;
exception when undefined_table or invalid_schema_name then
  raise notice 'Schéma storage absent : créez à la main un bucket public « app-releases ».';
end $$;

-- ═══ 20261016000000_hors_ligne ═══
-- Mode hors ligne : les colis créés sans internet reçoivent un identifiant client (client_ref) et un numéro
-- provisoire (LOC-XXXXXXXX) imprimé sur le reçu. À la synchronisation, le serveur attribue le vrai numéro COL-…
-- et conserve le numéro provisoire pour que l'étiquette déjà collée reste scannable.

alter table public.colis add column if not exists client_ref uuid;
alter table public.colis add column if not exists numero_provisoire text;

-- Évite les doublons si l'envoi est rejoué après une coupure réseau.
create unique index if not exists colis_client_ref_uidx on public.colis (client_ref) where client_ref is not null;
create index if not exists colis_numero_provisoire_idx on public.colis (company_id, numero_provisoire) where numero_provisoire is not null;

-- Scan rapide : accepte aussi le numéro provisoire (étiquette imprimée hors ligne).
create or replace function public.scan_lot(p_mode text, p_numeros text[], p_notes text default null)
returns table (r_numero text, r_ok boolean, r_message text, r_statut text)
language plpgsql security definer set search_path = public as $$
declare
  nums text[];
  n text;
  c public.colis;
begin
  if app_role() is null or app_role() = 'superadmin' then raise exception 'Non autorisé'; end if;
  if p_mode not in ('embarquement', 'dechargement') then raise exception 'Mode inconnu : %', p_mode; end if;

  select coalesce(array_agg(distinct upper(trim(x))), '{}') into nums
  from unnest(coalesce(p_numeros, '{}')) as x where trim(x) <> '';

  foreach n in array nums loop
    select * into c from public.colis
    where (colis.numero = n or colis.numero_provisoire = n) and colis.company_id = app_company_id()
    limit 1;
    if not found then
      return query select n, false, 'Colis introuvable'::text, null::text;
      continue;
    end if;
    if app_role() <> 'admin' and app_gare_id() not in (c.gare_depart_id, c.gare_arrivee_id) then
      return query select n, false, 'Colis d''une autre gare'::text, c.statut;
      continue;
    end if;

    if p_mode = 'embarquement' then
      if c.statut <> 'enregistre' then
        return query select n, false, ('Statut actuel : ' || c.statut)::text, c.statut;
        continue;
      end if;
      perform set_config('vipcolis.bypass', 'on', true);
      update public.colis set statut = 'charge' where id = c.id;
      perform set_config('vipcolis.bypass', 'off', true);
      insert into public.historique_colis (colis_id, statut, notes, agent_id)
      values (c.id, 'charge', coalesce(p_notes, 'Embarquement (scan rapide)'), auth.uid());
      return query select n, true, 'Embarqué'::text, 'charge'::text;
    else
      if c.statut not in ('charge', 'en_route') then
        return query select n, false, ('Statut actuel : ' || c.statut)::text, c.statut;
        continue;
      end if;
      if c.statut = 'charge' then
        insert into public.historique_colis (colis_id, statut, notes, agent_id)
        values (c.id, 'en_route', 'Départ (ajouté automatiquement au déchargement)', auth.uid());
      end if;
      perform set_config('vipcolis.bypass', 'on', true);
      update public.colis set statut = 'arrive' where id = c.id;
      perform set_config('vipcolis.bypass', 'off', true);
      insert into public.historique_colis (colis_id, statut, notes, agent_id)
      values (c.id, 'arrive', coalesce(p_notes, 'Déchargement (scan rapide)'), auth.uid());
      return query select n, true, 'Déchargé'::text, 'arrive'::text;
    end if;
  end loop;
end $$;

-- ═══ 20261017000000_barragistes_et_rapports_par_gare ═══
-- 1) Nouveau rôle « barragiste » : il ne peut que scanner (embarquement / déchargement).
-- 2) Les rapports d'un chef de gare / agent ne concernent que sa gare.

alter table public.vip_profiles drop constraint if exists vip_profiles_role_check;
alter table public.vip_profiles add constraint vip_profiles_role_check
  check (role in ('superadmin', 'admin', 'chef_gare', 'agent', 'barragiste', 'guichet', 'convoyeur', 'comptable'));

-- Création de compte : le barragiste est autorisé (la gare est facultative pour lui).
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
  if p_role not in ('admin', 'chef_gare', 'agent', 'barragiste') then raise exception 'Rôle invalide'; end if;
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

-- Le barragiste ne change pas les statuts à la main et ne gère pas les retraits.
create or replace function public.changer_statut(p_id bigint, p_statut text, p_notes text default null)
returns public.colis
language plpgsql security definer set search_path = public as $$
declare
  c public.colis;
  ok boolean;
begin
  if app_role() is null or app_role() in ('superadmin', 'barragiste') then raise exception 'Non autorisé'; end if;
  select * into c from public.colis where id = p_id and company_id = app_company_id();
  if not found then raise exception 'Colis non trouvé'; end if;
  if app_role() <> 'admin' and app_gare_id() not in (c.gare_depart_id, c.gare_arrivee_id) then
    raise exception 'Non autorisé';
  end if;

  ok := (c.statut = 'enregistre' and p_statut in ('charge','annule'))
     or (c.statut = 'charge'     and p_statut in ('en_route','annule'))
     or (c.statut = 'en_route'   and p_statut in ('arrive','annule'))
     or (c.statut = 'arrive'     and p_statut = 'annule');
  if not ok then raise exception 'Transition % → % impossible', c.statut, p_statut; end if;

  perform set_config('vipcolis.bypass', 'on', true);
  update public.colis set statut = p_statut where id = p_id returning * into c;
  perform set_config('vipcolis.bypass', 'off', true);

  insert into public.historique_colis (colis_id, statut, notes, agent_id)
  values (p_id, p_statut, p_notes, auth.uid());
  return c;
end $$;

create or replace function public.retirer_colis(
  p_id bigint, p_nom text, p_telephone text,
  p_piece text default null, p_signature text default null)
returns public.colis
language plpgsql security definer set search_path = public as $$
declare c public.colis;
begin
  if app_role() is null or app_role() in ('superadmin', 'barragiste') then raise exception 'Non autorisé'; end if;
  select * into c from public.colis where id = p_id and company_id = app_company_id();
  if not found then raise exception 'Colis non trouvé'; end if;
  if app_role() <> 'admin' and app_gare_id() is distinct from c.gare_arrivee_id then
    raise exception 'Le retrait se fait à la gare d''arrivée';
  end if;
  if c.statut <> 'arrive' then raise exception 'Le colis doit être à l''état « Arrivé »'; end if;

  perform set_config('vipcolis.bypass', 'on', true);
  update public.colis set
    statut = 'retire', retrait_nom = p_nom, retrait_telephone = p_telephone,
    retrait_piece_identite = p_piece, retrait_signature = p_signature, retrait_date = now()
  where id = p_id returning * into c;
  perform set_config('vipcolis.bypass', 'off', true);

  insert into public.historique_colis (colis_id, statut, notes, agent_id)
  values (p_id, 'retire', 'Retiré par ' || p_nom, auth.uid());
  return c;
end $$;

-- Scan rapide : le barragiste scanne les colis de toute l'entreprise (il est sur la route, pas dans une gare).
create or replace function public.scan_lot(p_mode text, p_numeros text[], p_notes text default null)
returns table (r_numero text, r_ok boolean, r_message text, r_statut text)
language plpgsql security definer set search_path = public as $$
declare
  nums text[];
  n text;
  c public.colis;
begin
  if app_role() is null or app_role() = 'superadmin' then raise exception 'Non autorisé'; end if;
  if p_mode not in ('embarquement', 'dechargement') then raise exception 'Mode inconnu : %', p_mode; end if;

  select coalesce(array_agg(distinct upper(trim(x))), '{}') into nums
  from unnest(coalesce(p_numeros, '{}')) as x where trim(x) <> '';

  foreach n in array nums loop
    select * into c from public.colis
    where (colis.numero = n or colis.numero_provisoire = n) and colis.company_id = app_company_id()
    limit 1;
    if not found then
      return query select n, false, 'Colis introuvable'::text, null::text;
      continue;
    end if;
    if app_role() not in ('admin', 'barragiste') and app_gare_id() not in (c.gare_depart_id, c.gare_arrivee_id) then
      return query select n, false, 'Colis d''une autre gare'::text, c.statut;
      continue;
    end if;

    if p_mode = 'embarquement' then
      if c.statut <> 'enregistre' then
        return query select n, false, ('Statut actuel : ' || c.statut)::text, c.statut;
        continue;
      end if;
      perform set_config('vipcolis.bypass', 'on', true);
      update public.colis set statut = 'charge' where id = c.id;
      perform set_config('vipcolis.bypass', 'off', true);
      insert into public.historique_colis (colis_id, statut, notes, agent_id)
      values (c.id, 'charge', coalesce(p_notes, 'Embarquement (scan rapide)'), auth.uid());
      return query select n, true, 'Embarqué'::text, 'charge'::text;
    else
      if c.statut not in ('charge', 'en_route') then
        return query select n, false, ('Statut actuel : ' || c.statut)::text, c.statut;
        continue;
      end if;
      if c.statut = 'charge' then
        insert into public.historique_colis (colis_id, statut, notes, agent_id)
        values (c.id, 'en_route', 'Départ (ajouté automatiquement au déchargement)', auth.uid());
      end if;
      perform set_config('vipcolis.bypass', 'on', true);
      update public.colis set statut = 'arrive' where id = c.id;
      perform set_config('vipcolis.bypass', 'off', true);
      insert into public.historique_colis (colis_id, statut, notes, agent_id)
      values (c.id, 'arrive', coalesce(p_notes, 'Déchargement (scan rapide)'), auth.uid());
      return query select n, true, 'Déchargé'::text, 'arrive'::text;
    end if;
  end loop;
end $$;

-- Informations minimales d'un colis pour le scan (le barragiste n'a pas accès aux données des clients).
create or replace function public.colis_scan_info(p_numero text)
returns table (numero text, statut text, gare_arrivee_nom text)
language sql stable security definer set search_path = public as $$
  select c.numero, c.statut, g.nom
  from public.colis c left join public.gares g on g.id = c.gare_arrivee_id
  where app_role() is not null and app_role() <> 'superadmin'
    and c.company_id = app_company_id()
    and (c.numero = upper(trim(p_numero)) or c.numero_provisoire = upper(trim(p_numero)))
  limit 1
$$;
revoke execute on function public.colis_scan_info(text) from public, anon;
grant execute on function public.colis_scan_info(text) to authenticated;

-- ───────────────────────── Rapports limités à la gare ─────────────────────────
-- (la sécurité des lignes de `colis` limite déjà les colis visibles aux gares de départ / d'arrivée de l'utilisateur ;
--  ici on limite aussi les recettes — encaissées au départ — et les listes de gares / d'agents.)

create or replace function public.dashboard_stats() returns json
language sql stable set search_path = public as $$
  select json_build_object(
    'total_colis',         (select count(*) from colis),
    'colis_aujourd_hui',   (select count(*) from colis where date_envoi = current_date),
    'colis_en_route',      (select count(*) from colis where statut = 'en_route'),
    'colis_arrives',       (select count(*) from colis where statut = 'arrive'),
    'colis_non_retires',   (select count(*) from colis where statut = 'arrive'),
    'recette_totale',      coalesce((select sum(prix) from colis
                             where statut <> 'annule' and (app_role() = 'admin' or gare_depart_id = app_gare_id())), 0),
    'recette_aujourd_hui', coalesce((select sum(prix) from colis
                             where statut <> 'annule' and date_envoi = current_date
                               and (app_role() = 'admin' or gare_depart_id = app_gare_id())), 0),
    'total_gares',         (select count(*) from gares where app_role() = 'admin' or id = app_gare_id()),
    'total_agents',        (select count(*) from vip_profiles
                             where actif and role <> 'superadmin'
                               and (app_role() = 'admin' or gare_id = app_gare_id()))
  )
$$;

create or replace function public.colis_par_jour(p_debut date default null, p_fin date default null)
returns table (date date, total bigint, recette numeric)
language sql stable set search_path = public as $$
  select date_envoi, count(*),
         coalesce(sum(prix) filter (where app_role() = 'admin' or gare_depart_id = app_gare_id()), 0)
  from colis
  where (p_debut is null or date_envoi >= p_debut) and (p_fin is null or date_envoi <= p_fin)
  group by date_envoi order by date_envoi
$$;

create or replace function public.recettes_par_gare()
returns table (gare_id bigint, gare_nom text, total_colis bigint, recette_totale numeric)
language sql stable set search_path = public as $$
  select g.id, g.nom, count(c.id), coalesce(sum(c.prix), 0)
  from gares g left join colis c on c.gare_depart_id = g.id
  where app_role() = 'admin' or g.id = app_gare_id()
  group by g.id, g.nom order by g.nom
$$;

create or replace function public.recettes_par_agent()
returns table (agent_id uuid, agent_nom text, total_colis bigint, recette_totale numeric)
language sql stable set search_path = public as $$
  select p.id, p.nom, count(c.id), coalesce(sum(c.prix), 0)
  from vip_profiles p left join colis c on c.agent_id = p.id
  where p.role = 'agent' and (app_role() = 'admin' or p.gare_id = app_gare_id())
  group by p.id, p.nom order by p.nom
$$;

-- ═══ 20261018000000_televersement_apk ═══
-- Le super administrateur peut téléverser l'APK depuis l'application (écran « Mises à jour »).
-- Le dossier « app-releases » est public en lecture ; seule l'écriture est réservée au super administrateur.
do $$ begin
  drop policy if exists app_releases_super_insert on storage.objects;
  drop policy if exists app_releases_super_update on storage.objects;
  drop policy if exists app_releases_super_delete on storage.objects;
  create policy app_releases_super_insert on storage.objects for insert to authenticated
    with check (bucket_id = 'app-releases' and public.app_role() = 'superadmin');
  create policy app_releases_super_update on storage.objects for update to authenticated
    using (bucket_id = 'app-releases' and public.app_role() = 'superadmin')
    with check (bucket_id = 'app-releases' and public.app_role() = 'superadmin');
  create policy app_releases_super_delete on storage.objects for delete to authenticated
    using (bucket_id = 'app-releases' and public.app_role() = 'superadmin');
exception when undefined_table or invalid_schema_name or insufficient_privilege then
  raise notice 'Stockage indisponible : ajoutez à la main une règle d''écriture pour le super administrateur sur le bucket app-releases.';
end $$;

-- Recharge le cache de schéma de l'API (évite « could not find the column … in the schema cache »).
notify pgrst, 'reload schema';

-- ═══ 20261019000000_billets_guichet_clients ═══
-- Billetterie : nouveaux rôles « guichet » et « convoyeur », billets de transport, fichier clients
-- (retrouver un client dès qu'on tape son téléphone ou son nom).
--
--   guichet    : travaille dans une gare comme un agent (colis) et vend des billets de cette gare.
--   convoyeur  : vend des billets à bord et scanne les colis (embarquement / déchargement) ; aucun accès aux données des clients.
--   admin      : tout, y compris annuler un billet.

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
  if p_role not in ('admin', 'chef_gare', 'agent', 'barragiste', 'guichet', 'convoyeur') then raise exception 'Rôle invalide'; end if;
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

-- Le guichet voit / crée / modifie les colis de sa gare comme un agent.
drop policy if exists colis_select on public.colis;
drop policy if exists colis_insert on public.colis;
drop policy if exists colis_update on public.colis;
create policy colis_select on public.colis for select to authenticated using (
  public.app_role() in ('admin', 'chef_gare', 'agent', 'guichet') and company_id = public.app_company_id()
  and (public.app_role() = 'admin' or public.app_gare_id() in (gare_depart_id, gare_arrivee_id)));
create policy colis_insert on public.colis for insert to authenticated with check (
  public.app_role() in ('admin', 'chef_gare', 'agent', 'guichet')
  and (public.app_role() = 'admin' or public.app_gare_id() = gare_depart_id));
create policy colis_update on public.colis for update to authenticated using (
  public.app_role() in ('admin', 'chef_gare', 'agent', 'guichet') and company_id = public.app_company_id()
  and (public.app_role() = 'admin' or public.app_gare_id() in (gare_depart_id, gare_arrivee_id)));

-- Le convoyeur ne change pas les statuts à la main et ne gère pas les retraits ; il scanne partout (comme le barragiste).
create or replace function public.changer_statut(p_id bigint, p_statut text, p_notes text default null)
returns public.colis
language plpgsql security definer set search_path = public as $$
declare
  c public.colis;
  ok boolean;
begin
  if app_role() is null or app_role() in ('superadmin', 'barragiste', 'convoyeur') then raise exception 'Non autorisé'; end if;
  select * into c from public.colis where id = p_id and company_id = app_company_id();
  if not found then raise exception 'Colis non trouvé'; end if;
  if app_role() <> 'admin' and app_gare_id() not in (c.gare_depart_id, c.gare_arrivee_id) then
    raise exception 'Non autorisé';
  end if;

  ok := (c.statut = 'enregistre' and p_statut in ('charge','annule'))
     or (c.statut = 'charge'     and p_statut in ('en_route','annule'))
     or (c.statut = 'en_route'   and p_statut in ('arrive','annule'))
     or (c.statut = 'arrive'     and p_statut = 'annule');
  if not ok then raise exception 'Transition % → % impossible', c.statut, p_statut; end if;

  perform set_config('vipcolis.bypass', 'on', true);
  update public.colis set statut = p_statut where id = p_id returning * into c;
  perform set_config('vipcolis.bypass', 'off', true);

  insert into public.historique_colis (colis_id, statut, notes, agent_id)
  values (p_id, p_statut, p_notes, auth.uid());
  return c;
end $$;

create or replace function public.retirer_colis(
  p_id bigint, p_nom text, p_telephone text,
  p_piece text default null, p_signature text default null)
returns public.colis
language plpgsql security definer set search_path = public as $$
declare c public.colis;
begin
  if app_role() is null or app_role() in ('superadmin', 'barragiste', 'convoyeur') then raise exception 'Non autorisé'; end if;
  select * into c from public.colis where id = p_id and company_id = app_company_id();
  if not found then raise exception 'Colis non trouvé'; end if;
  if app_role() <> 'admin' and app_gare_id() is distinct from c.gare_arrivee_id then
    raise exception 'Le retrait se fait à la gare d''arrivée';
  end if;
  if c.statut <> 'arrive' then raise exception 'Le colis doit être à l''état « Arrivé »'; end if;

  perform set_config('vipcolis.bypass', 'on', true);
  update public.colis set
    statut = 'retire', retrait_nom = p_nom, retrait_telephone = p_telephone,
    retrait_piece_identite = p_piece, retrait_signature = p_signature, retrait_date = now()
  where id = p_id returning * into c;
  perform set_config('vipcolis.bypass', 'off', true);

  insert into public.historique_colis (colis_id, statut, notes, agent_id)
  values (p_id, 'retire', 'Retiré par ' || p_nom, auth.uid());
  return c;
end $$;

create or replace function public.scan_lot(p_mode text, p_numeros text[], p_notes text default null)
returns table (r_numero text, r_ok boolean, r_message text, r_statut text)
language plpgsql security definer set search_path = public as $$
declare
  nums text[];
  n text;
  c public.colis;
begin
  if app_role() is null or app_role() = 'superadmin' then raise exception 'Non autorisé'; end if;
  if p_mode not in ('embarquement', 'dechargement') then raise exception 'Mode inconnu : %', p_mode; end if;

  select coalesce(array_agg(distinct upper(trim(x))), '{}') into nums
  from unnest(coalesce(p_numeros, '{}')) as x where trim(x) <> '';

  foreach n in array nums loop
    select * into c from public.colis
    where (colis.numero = n or colis.numero_provisoire = n) and colis.company_id = app_company_id()
    limit 1;
    if not found then
      return query select n, false, 'Colis introuvable'::text, null::text;
      continue;
    end if;
    if app_role() not in ('admin', 'barragiste', 'convoyeur') and app_gare_id() not in (c.gare_depart_id, c.gare_arrivee_id) then
      return query select n, false, 'Colis d''une autre gare'::text, c.statut;
      continue;
    end if;

    if p_mode = 'embarquement' then
      if c.statut <> 'enregistre' then
        return query select n, false, ('Statut actuel : ' || c.statut)::text, c.statut;
        continue;
      end if;
      perform set_config('vipcolis.bypass', 'on', true);
      update public.colis set statut = 'charge' where id = c.id;
      perform set_config('vipcolis.bypass', 'off', true);
      insert into public.historique_colis (colis_id, statut, notes, agent_id)
      values (c.id, 'charge', coalesce(p_notes, 'Embarquement (scan rapide)'), auth.uid());
      return query select n, true, 'Embarqué'::text, 'charge'::text;
    else
      if c.statut not in ('charge', 'en_route') then
        return query select n, false, ('Statut actuel : ' || c.statut)::text, c.statut;
        continue;
      end if;
      if c.statut = 'charge' then
        insert into public.historique_colis (colis_id, statut, notes, agent_id)
        values (c.id, 'en_route', 'Départ (ajouté automatiquement au déchargement)', auth.uid());
      end if;
      perform set_config('vipcolis.bypass', 'on', true);
      update public.colis set statut = 'arrive' where id = c.id;
      perform set_config('vipcolis.bypass', 'off', true);
      insert into public.historique_colis (colis_id, statut, notes, agent_id)
      values (c.id, 'arrive', coalesce(p_notes, 'Déchargement (scan rapide)'), auth.uid());
      return query select n, true, 'Déchargé'::text, 'arrive'::text;
    end if;
  end loop;
end $$;

-- ───────────────────────── Fichier clients ─────────────────────────
-- Alimenté automatiquement par chaque colis (expéditeur, destinataire) et chaque billet : un client est retrouvé
-- par son numéro de téléphone (chiffres seuls) ou par son nom.

create table if not exists public.clients (
  id                 bigint generated always as identity primary key,
  company_id         bigint not null references public.companies(id) on delete cascade,
  nom                text not null,
  telephone          text not null,
  nb_colis           integer not null default 0,
  nb_tickets         integer not null default 0,
  dernier_depart_id  bigint references public.gares(id) on delete set null,
  dernier_arrivee_id bigint references public.gares(id) on delete set null,
  derniere_activite  timestamptz not null default now(),
  created_at         timestamptz not null default now(),
  unique (company_id, telephone)
);
create index if not exists clients_nom_idx on public.clients (company_id, lower(nom));

alter table public.clients enable row level security;
drop policy if exists clients_select on public.clients;
create policy clients_select on public.clients for select to authenticated using (
  public.app_role() in ('admin', 'chef_gare', 'agent', 'guichet', 'convoyeur')
  and company_id = public.app_company_id());
grant select on public.clients to authenticated;

create or replace function public._maj_client(
  p_company bigint, p_nom text, p_tel text,
  p_depart bigint default null, p_arrivee bigint default null,
  p_colis integer default 0, p_tickets integer default 0)
returns void
language plpgsql security definer set search_path = public as $$
declare tel text := regexp_replace(coalesce(p_tel, ''), '[^0-9]', '', 'g');
begin
  if p_company is null or length(tel) < 6 or length(trim(coalesce(p_nom, ''))) = 0 then return; end if;
  insert into public.clients (company_id, nom, telephone, nb_colis, nb_tickets, dernier_depart_id, dernier_arrivee_id)
  values (p_company, trim(p_nom), tel, p_colis, p_tickets, p_depart, p_arrivee)
  on conflict (company_id, telephone) do update set
    nom = excluded.nom,
    nb_colis = public.clients.nb_colis + p_colis,
    nb_tickets = public.clients.nb_tickets + p_tickets,
    dernier_depart_id = coalesce(excluded.dernier_depart_id, public.clients.dernier_depart_id),
    dernier_arrivee_id = coalesce(excluded.dernier_arrivee_id, public.clients.dernier_arrivee_id),
    derniere_activite = now();
end $$;

create or replace function public.colis_after_insert_client() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public._maj_client(new.company_id, new.expediteur_nom, new.expediteur_telephone, new.gare_depart_id, new.gare_arrivee_id, 1, 0);
  perform public._maj_client(new.company_id, new.destinataire_nom, new.destinataire_telephone, null, null, 1, 0);
  return new;
end $$;
drop trigger if exists colis_client_maj on public.colis;
create trigger colis_client_maj after insert on public.colis
  for each row execute function public.colis_after_insert_client();

-- Reprise de l'existant : les clients des colis déjà enregistrés.
insert into public.clients (company_id, nom, telephone, nb_colis, derniere_activite)
select company_id, (array_agg(nom order by d desc))[1], tel, count(*), max(d)
from (
  select company_id, expediteur_nom as nom, regexp_replace(expediteur_telephone, '[^0-9]', '', 'g') as tel, created_at as d from public.colis
  union all
  select company_id, destinataire_nom, regexp_replace(destinataire_telephone, '[^0-9]', '', 'g'), created_at from public.colis
) x
where company_id is not null and length(tel) >= 6 and length(trim(nom)) > 0
group by company_id, tel
on conflict (company_id, telephone) do nothing;

-- Suggestions pendant la frappe (téléphone ou nom) : 8 clients maximum, les plus récents d'abord.
create or replace function public.clients_suggestions(p_terme text)
returns table (nom text, telephone text, nb_colis integer, nb_tickets integer,
               dernier_depart_id bigint, dernier_arrivee_id bigint)
language sql stable set search_path = public as $$
  with t as (select trim(coalesce(p_terme, '')) as txt, regexp_replace(coalesce(p_terme, ''), '[^0-9]', '', 'g') as chiffres)
  select c.nom, c.telephone, c.nb_colis, c.nb_tickets, c.dernier_depart_id, c.dernier_arrivee_id
  from public.clients c, t
  where length(t.txt) >= 2
    and ((t.chiffres <> '' and c.telephone like '%' || t.chiffres || '%') or c.nom ilike '%' || t.txt || '%')
  order by (t.chiffres <> '' and c.telephone like t.chiffres || '%') desc, c.derniere_activite desc
  limit 8
$$;

-- ───────────────────────── Billets de transport ─────────────────────────

create sequence if not exists public.ticket_numero_seq start 1000;

create table if not exists public.tickets (
  id                 bigint generated always as identity primary key,
  company_id         bigint not null references public.companies(id) on delete cascade,
  numero             text not null unique,
  client_nom         text not null,
  client_telephone   text not null,
  gare_depart_id     bigint not null references public.gares(id),
  gare_arrivee_id    bigint not null references public.gares(id),
  date_voyage        date not null default current_date,
  heure_depart       text,
  siege              text,
  prix               numeric(12, 2) not null check (prix >= 0),
  statut             text not null default 'emis' check (statut in ('emis', 'annule')),
  vendeur_id         uuid references auth.users(id),
  notes              text,
  client_ref         uuid,
  numero_provisoire  text,
  created_at         timestamptz not null default now()
);
create unique index if not exists tickets_client_ref_uidx on public.tickets (client_ref) where client_ref is not null;
create index if not exists tickets_company_date_idx on public.tickets (company_id, date_voyage desc);

create or replace function public.tickets_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.numero := 'BIL-' || extract(year from now())::int || '-' || nextval('public.ticket_numero_seq');
  new.statut := 'emis';
  new.vendeur_id := coalesce(auth.uid(), new.vendeur_id);
  if public.app_company_id() is not null then new.company_id := public.app_company_id(); end if;
  return new;
end $$;
drop trigger if exists tickets_before_insert on public.tickets;
create trigger tickets_before_insert before insert on public.tickets
  for each row execute function public.tickets_before_insert();

create or replace function public.tickets_after_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public._maj_client(new.company_id, new.client_nom, new.client_telephone, new.gare_depart_id, new.gare_arrivee_id, 0, 1);
  return new;
end $$;
drop trigger if exists tickets_after_insert on public.tickets;
create trigger tickets_after_insert after insert on public.tickets
  for each row execute function public.tickets_after_insert();

create or replace view public.tickets_detail with (security_invoker = true) as
select t.*, gd.nom as gare_depart_nom, ga.nom as gare_arrivee_nom, p.nom as vendeur_nom
from public.tickets t
left join public.gares gd on gd.id = t.gare_depart_id
left join public.gares ga on ga.id = t.gare_arrivee_id
left join public.vip_profiles p on p.id = t.vendeur_id;

alter table public.tickets enable row level security;
drop policy if exists tickets_select on public.tickets;
drop policy if exists tickets_insert on public.tickets;
create policy tickets_select on public.tickets for select to authenticated using (
  company_id = public.app_company_id() and (
    public.app_role() = 'admin'
    or (public.app_role() in ('chef_gare', 'guichet') and public.app_gare_id() in (gare_depart_id, gare_arrivee_id))
    or (public.app_role() = 'convoyeur' and vendeur_id = auth.uid())));
create policy tickets_insert on public.tickets for insert to authenticated with check (
  public.app_role() in ('admin', 'guichet', 'convoyeur')
  and (public.app_role() in ('admin', 'convoyeur') or public.app_gare_id() = gare_depart_id));

grant select, insert on public.tickets to authenticated;
grant select on public.tickets_detail to authenticated;
grant usage, select on sequence public.ticket_numero_seq to authenticated;
grant usage, select on all sequences in schema public to authenticated;

-- Annulation d'un billet : administrateur, ou guichet de la gare de départ.
create or replace function public.annuler_ticket(p_id bigint)
returns void
language plpgsql security definer set search_path = public as $$
declare t public.tickets;
begin
  select * into t from public.tickets where id = p_id and company_id = public.app_company_id();
  if not found then raise exception 'Billet introuvable'; end if;
  if public.app_role() is distinct from 'admin'
     and not (public.app_role() = 'guichet' and public.app_gare_id() = t.gare_depart_id) then
    raise exception 'Non autorisé';
  end if;
  update public.tickets set statut = 'annule' where id = p_id;
end $$;
revoke execute on function public.annuler_ticket(bigint) from public, anon;
grant execute on function public.annuler_ticket(bigint) to authenticated;
revoke execute on function public.clients_suggestions(text) from public, anon;
grant execute on function public.clients_suggestions(text) to authenticated;

-- Fonctions internes (déclencheurs) : jamais appelables directement par les utilisateurs.
revoke execute on function public._maj_client(bigint, text, text, bigint, bigint, integer, integer) from public, anon, authenticated;
revoke execute on function public.colis_after_insert_client() from public, anon, authenticated;
revoke execute on function public.tickets_before_insert() from public, anon, authenticated;
revoke execute on function public.tickets_after_insert() from public, anon, authenticated;

-- Temps réel : les listes de billets se rafraîchissent toutes seules.
do $$ begin
  alter publication supabase_realtime add table public.tickets;
exception when others then null;
end $$;

notify pgrst, 'reload schema';

-- ═══ 20261020000000_sms_smsbus ═══
-- SMS automatiques (passerelle SMSBUS / 3MI, API HTTP GET) lors de l'envoi et de la réception des colis,
-- et à la vente d'un billet. Les identifiants SMSBUS restent côté serveur (jamais envoyés à l'application).
-- L'envoi passe par l'extension pg_net (incluse dans Supabase) ; sans elle, les SMS restent en file avec l'erreur.

do $$ begin
  create extension if not exists pg_net;
exception when others then null;
end $$;

create table if not exists public.sms_settings (
  company_id       bigint primary key references public.companies(id) on delete cascade,
  actif            boolean not null default false,
  username         text not null default '',
  password         text not null default '',
  sender           text not null default '',
  port             integer not null default 7170,
  indicatif        text not null default '226',
  sms_colis_envoi  boolean not null default true,   -- à l'enregistrement : expéditeur + destinataire
  sms_colis_arrive boolean not null default true,   -- à l'arrivée : destinataire
  sms_colis_retire boolean not null default true,   -- au retrait : expéditeur
  sms_billet       boolean not null default true,
  tpl_envoi_exp    text not null default '{entreprise} : votre colis {numero} pour {destinataire} ({arrivee}) est enregistre a {depart}. Merci de votre confiance.',
  tpl_envoi_dest   text not null default '{entreprise} : un colis {numero} de {expediteur} vous est envoye vers {arrivee}. Vous serez prevenu a son arrivee.',
  tpl_arrive       text not null default '{entreprise} : votre colis {numero} est arrive a {arrivee}. Presentez-vous avec une piece d''identite pour le retirer.',
  tpl_retire       text not null default '{entreprise} : votre colis {numero} a ete retire par {retrait}. Merci de votre confiance.',
  tpl_billet       text not null default '{entreprise} : billet {numero} {depart} -> {arrivee} le {date}. Bon voyage !',
  updated_at       timestamptz not null default now()
);

create table if not exists public.sms_outbox (
  id          bigint generated always as identity primary key,
  company_id  bigint not null references public.companies(id) on delete cascade,
  type        text not null check (type in ('envoi_exp', 'envoi_dest', 'arrive', 'retire', 'billet', 'test')),
  colis_id    bigint references public.colis(id) on delete cascade,
  ticket_id   bigint references public.tickets(id) on delete cascade,
  telephone   text not null,
  message     text not null,
  statut      text not null default 'attente' check (statut in ('attente', 'envoye', 'echec')),
  reponse     text,
  request_id  bigint,
  created_at  timestamptz not null default now()
);
create unique index if not exists sms_outbox_colis_type_uidx on public.sms_outbox (colis_id, type) where colis_id is not null;
create unique index if not exists sms_outbox_ticket_type_uidx on public.sms_outbox (ticket_id, type) where ticket_id is not null;
create index if not exists sms_outbox_company_idx on public.sms_outbox (company_id, created_at desc);

alter table public.sms_settings enable row level security;
alter table public.sms_outbox enable row level security;
drop policy if exists sms_settings_select on public.sms_settings;
create policy sms_settings_select on public.sms_settings for select to authenticated
  using (public.app_role() = 'admin' and company_id = public.app_company_id());
drop policy if exists sms_outbox_select on public.sms_outbox;
create policy sms_outbox_select on public.sms_outbox for select to authenticated
  using (public.app_role() = 'admin' and company_id = public.app_company_id());

-- Le mot de passe SMSBUS n'est jamais lisible par l'application.
revoke all on public.sms_settings from public, anon, authenticated;
grant select (company_id, actif, username, sender, port, indicatif, sms_colis_envoi, sms_colis_arrive, sms_colis_retire,
              sms_billet, tpl_envoi_exp, tpl_envoi_dest, tpl_arrive, tpl_retire, tpl_billet, updated_at)
  on public.sms_settings to authenticated;
revoke all on public.sms_outbox from public, anon, authenticated;
grant select on public.sms_outbox to authenticated;

-- ───────────────────────── Outils ─────────────────────────

create or replace function public._sms_urlencode(t text) returns text
language sql immutable as $$
  select coalesce(string_agg(
    case when b between 48 and 57 or b between 65 and 90 or b between 97 and 122 or b in (45, 46, 95, 126)
         then chr(b) else '%' || upper(lpad(to_hex(b), 2, '0')) end, '' order by i), '')
  from (select get_byte(convert_to(coalesce(t, ''), 'UTF8'), i) as b, i
        from generate_series(0, octet_length(convert_to(coalesce(t, ''), 'UTF8')) - 1) as i) x
$$;

-- Numéro au format international sans « + » ni « 00 » (8 chiffres = numéro local : on ajoute l'indicatif).
create or replace function public._sms_numero(p_tel text, p_indicatif text) returns text
language plpgsql immutable as $$
declare n text := regexp_replace(coalesce(p_tel, ''), '[^0-9]', '', 'g');
begin
  if n like '00%' then n := substr(n, 3);
  elsif length(n) <= 9 then n := regexp_replace(coalesce(p_indicatif, ''), '[^0-9]', '', 'g') || n; end if;
  return n;
end $$;

create or replace function public._sms_remplir(p_tpl text, p_vals jsonb) returns text
language plpgsql immutable as $$
declare r text := p_tpl; k text;
begin
  for k in select jsonb_object_keys(p_vals) loop
    r := replace(r, '{' || k || '}', coalesce(p_vals ->> k, ''));
  end loop;
  return r;
end $$;

-- Envoie un SMS de la file (requête HTTP asynchrone via pg_net).
create or replace function public._sms_envoyer(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare o public.sms_outbox; s public.sms_settings; url text; rid bigint;
begin
  select * into o from public.sms_outbox where id = p_id;
  select * into s from public.sms_settings where company_id = o.company_id;
  if not found or not s.actif or s.username = '' or s.sender = '' then
    update public.sms_outbox set statut = 'echec', reponse = 'SMS non configurés' where id = p_id; return;
  end if;
  url := 'https://www.lesmsbus.com:' || s.port || '/ines.smsbus/smsbusMt'
      || '?to=' || public._sms_urlencode(public._sms_numero(o.telephone, s.indicatif))
      || '&text=' || public._sms_urlencode(o.message)
      || '&username=' || public._sms_urlencode(s.username)
      || '&password=' || public._sms_urlencode(s.password)
      || '&from=' || public._sms_urlencode(s.sender)
      || '&jca=0';
  execute 'select net.http_get(url := $1)' into rid using url;
  update public.sms_outbox set request_id = rid where id = p_id;
exception when others then
  update public.sms_outbox set statut = 'echec', reponse = left(sqlerrm, 300) where id = p_id;
end $$;

-- Met en file puis envoie un SMS (ne fait jamais échouer l'opération appelante).
create or replace function public._sms_poster(p_company bigint, p_type text, p_colis bigint, p_ticket bigint, p_tel text, p_msg text)
returns void
language plpgsql security definer set search_path = public as $$
declare id bigint;
begin
  if length(regexp_replace(coalesce(p_tel, ''), '[^0-9]', '', 'g')) < 6 then return; end if;
  insert into public.sms_outbox (company_id, type, colis_id, ticket_id, telephone, message)
  values (p_company, p_type, p_colis, p_ticket, p_tel, p_msg)
  on conflict do nothing
  returning sms_outbox.id into id;
  if id is not null then perform public._sms_envoyer(id); end if;
exception when others then null;
end $$;

-- ───────────────────────── Déclencheurs ─────────────────────────

create or replace function public._sms_colis_vals(c public.colis) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'entreprise', coalesce((select nom from public.companies where id = c.company_id), 'Colis'),
    'numero', c.numero, 'expediteur', c.expediteur_nom, 'destinataire', c.destinataire_nom,
    'depart', coalesce((select nom from public.gares where id = c.gare_depart_id), ''),
    'arrivee', coalesce((select nom from public.gares where id = c.gare_arrivee_id), ''),
    'retrait', coalesce(c.retrait_nom, c.destinataire_nom),
    'prix', c.prix::text)
$$;

create or replace function public.colis_sms_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare s public.sms_settings; v jsonb;
begin
  select * into s from public.sms_settings where company_id = new.company_id and actif;
  if not found or not s.sms_colis_envoi then return new; end if;
  v := public._sms_colis_vals(new);
  perform public._sms_poster(new.company_id, 'envoi_exp', new.id, null, new.expediteur_telephone, public._sms_remplir(s.tpl_envoi_exp, v));
  perform public._sms_poster(new.company_id, 'envoi_dest', new.id, null, new.destinataire_telephone, public._sms_remplir(s.tpl_envoi_dest, v));
  return new;
exception when others then return new;
end $$;
drop trigger if exists colis_sms_insert on public.colis;
create trigger colis_sms_insert after insert on public.colis
  for each row execute function public.colis_sms_insert();

create or replace function public.colis_sms_statut() returns trigger
language plpgsql security definer set search_path = public as $$
declare s public.sms_settings; v jsonb;
begin
  if new.statut is not distinct from old.statut then return new; end if;
  select * into s from public.sms_settings where company_id = new.company_id and actif;
  if not found then return new; end if;
  v := public._sms_colis_vals(new);
  if new.statut = 'arrive' and s.sms_colis_arrive then
    perform public._sms_poster(new.company_id, 'arrive', new.id, null, new.destinataire_telephone, public._sms_remplir(s.tpl_arrive, v));
  elsif new.statut = 'retire' and s.sms_colis_retire then
    perform public._sms_poster(new.company_id, 'retire', new.id, null, new.expediteur_telephone, public._sms_remplir(s.tpl_retire, v));
  end if;
  return new;
exception when others then return new;
end $$;
drop trigger if exists colis_sms_statut on public.colis;
create trigger colis_sms_statut after update of statut on public.colis
  for each row execute function public.colis_sms_statut();

create or replace function public.tickets_sms_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare s public.sms_settings; v jsonb;
begin
  select * into s from public.sms_settings where company_id = new.company_id and actif;
  if not found or not s.sms_billet then return new; end if;
  v := jsonb_build_object(
    'entreprise', coalesce((select nom from public.companies where id = new.company_id), 'Billet'),
    'numero', new.numero, 'nom', new.client_nom,
    'depart', coalesce((select nom from public.gares where id = new.gare_depart_id), ''),
    'arrivee', coalesce((select nom from public.gares where id = new.gare_arrivee_id), ''),
    'date', to_char(new.date_voyage, 'DD/MM/YYYY') || coalesce(' ' || nullif(new.heure_depart, ''), ''),
    'siege', coalesce(new.siege, ''), 'prix', new.prix::text);
  perform public._sms_poster(new.company_id, 'billet', null, new.id, new.client_telephone, public._sms_remplir(s.tpl_billet, v));
  return new;
exception when others then return new;
end $$;
drop trigger if exists tickets_sms_insert on public.tickets;
create trigger tickets_sms_insert after insert on public.tickets
  for each row execute function public.tickets_sms_insert();

-- ───────────────────────── Fonctions pour l'application (administrateur) ─────────────────────────

-- Enregistre la configuration ; le mot de passe n'est modifié que s'il est fourni.
create or replace function public.sms_enregistrer(p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare cid bigint := public.app_company_id();
begin
  if public.app_role() is distinct from 'admin' or cid is null then raise exception 'Non autorisé'; end if;
  insert into public.sms_settings (company_id) values (cid) on conflict do nothing;
  update public.sms_settings set
    actif = coalesce((p ->> 'actif')::boolean, actif),
    username = coalesce(p ->> 'username', username),
    password = coalesce(nullif(p ->> 'password', ''), password),
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
    updated_at = now()
  where company_id = cid;
end $$;

-- Reprend le résultat des requêtes HTTP (0000|OK… = accepté par SMSBUS) et le met dans la file.
create or replace function public.sms_rafraichir() returns void
language plpgsql security definer set search_path = public as $$
begin
  if public.app_role() is distinct from 'admin' then raise exception 'Non autorisé'; end if;
  begin
    execute $q$
      update public.sms_outbox o set
        statut = case when r.content like '0000%' then 'envoye' else 'echec' end,
        reponse = left(coalesce(r.content, r.error_msg, 'Pas de réponse'), 300)
      from net._http_response r
      where r.id = o.request_id and o.statut = 'attente' and o.company_id = public.app_company_id()
    $q$;
  exception when others then null;
  end;
end $$;

-- Renvoie un SMS en échec.
create or replace function public.sms_renvoyer(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  if public.app_role() is distinct from 'admin' then raise exception 'Non autorisé'; end if;
  update public.sms_outbox set statut = 'attente', reponse = null, request_id = null
  where id = p_id and company_id = public.app_company_id();
  perform public._sms_envoyer(p_id);
end $$;

-- SMS de test vers un numéro.
create or replace function public.sms_tester(p_tel text) returns void
language plpgsql security definer set search_path = public as $$
declare cid bigint := public.app_company_id(); id bigint;
begin
  if public.app_role() is distinct from 'admin' or cid is null then raise exception 'Non autorisé'; end if;
  insert into public.sms_outbox (company_id, type, telephone, message)
  values (cid, 'test', p_tel, 'Test SMS : la configuration SMSBUS fonctionne.') returning sms_outbox.id into id;
  perform public._sms_envoyer(id);
end $$;

revoke execute on function public.sms_enregistrer(jsonb), public.sms_rafraichir(), public.sms_renvoyer(bigint), public.sms_tester(text)
  from public, anon;
grant execute on function public.sms_enregistrer(jsonb), public.sms_rafraichir(), public.sms_renvoyer(bigint), public.sms_tester(text)
  to authenticated;
revoke execute on function public._sms_urlencode(text), public._sms_numero(text, text), public._sms_remplir(text, jsonb),
  public._sms_envoyer(bigint), public._sms_poster(bigint, text, bigint, bigint, text, text),
  public._sms_colis_vals(public.colis), public.colis_sms_insert(), public.colis_sms_statut(), public.tickets_sms_insert()
  from public, anon, authenticated;

notify pgrst, 'reload schema';

-- ═══ 20261021000000_trajets_verification_valeur ═══
-- Trajets (prix et heures de départ fixés par l'administrateur), vérification des billets à l'embarquement
-- (plusieurs fois possible, utilisable hors ligne grâce à la liste des billets mise en mémoire sur les téléphones)
-- et valeur déclarée des colis.

-- ───────────────────────── Trajets : prix et horaires ─────────────────────────

create table if not exists public.trajets (
  id               bigint generated always as identity primary key,
  company_id       bigint not null references public.companies(id) on delete cascade,
  gare_depart_id   bigint not null references public.gares(id) on delete cascade,
  gare_arrivee_id  bigint not null references public.gares(id) on delete cascade,
  prix             numeric(12, 2) not null check (prix >= 0),
  horaires         text[] not null default '{}',          -- heures de départ : '06:30', '14:00'…
  created_at       timestamptz not null default now(),
  check (gare_depart_id <> gare_arrivee_id),
  unique (company_id, gare_depart_id, gare_arrivee_id)
);

alter table public.trajets enable row level security;
drop policy if exists trajets_select on public.trajets;
drop policy if exists trajets_admin on public.trajets;
create policy trajets_select on public.trajets for select to authenticated using (
  company_id = public.app_company_id()
  and public.app_role() in ('admin', 'chef_gare', 'agent', 'guichet', 'convoyeur'));
create policy trajets_admin on public.trajets for all to authenticated
  using (public.app_role() = 'admin' and company_id = public.app_company_id())
  with check (public.app_role() = 'admin' and company_id = public.app_company_id());
grant select, insert, update, delete on public.trajets to authenticated;

create or replace function public.trajets_before_write() returns trigger
language plpgsql security definer set search_path = public as $$
declare h text; ok text[] := '{}';
begin
  if public.app_company_id() is not null then new.company_id := public.app_company_id(); end if;
  -- heures valides (HH:MM), triées, sans doublon
  foreach h in array coalesce(new.horaires, '{}') loop
    h := trim(h);
    if h ~ '^([01]?[0-9]|2[0-3]):[0-5][0-9]$' then ok := ok || lpad(h, 5, '0'); end if;
  end loop;
  new.horaires := coalesce((select array_agg(distinct x order by x) from unnest(ok) x), '{}');
  return new;
end $$;
drop trigger if exists trajets_before_write on public.trajets;
create trigger trajets_before_write before insert or update on public.trajets
  for each row execute function public.trajets_before_write();
revoke execute on function public.trajets_before_write() from public, anon, authenticated;

do $$ begin
  alter publication supabase_realtime add table public.trajets;
exception when others then null;
end $$;

-- ───────────────────────── Valeur déclarée des colis ─────────────────────────

alter table public.colis add column if not exists valeur numeric(12, 2) check (valeur is null or valeur >= 0);

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

-- ───────────────────────── Vérification des billets ─────────────────────────

alter table public.tickets add column if not exists nb_verifications integer not null default 0;
alter table public.tickets add column if not exists derniere_verification timestamptz;

drop view if exists public.tickets_detail;
create view public.tickets_detail with (security_invoker = true) as
select t.*, gd.nom as gare_depart_nom, ga.nom as gare_arrivee_nom, p.nom as vendeur_nom
from public.tickets t
left join public.gares gd on gd.id = t.gare_depart_id
left join public.gares ga on ga.id = t.gare_arrivee_id
left join public.vip_profiles p on p.id = t.vendeur_id;
grant select on public.tickets_detail to authenticated;

create table if not exists public.ticket_verifications (
  id          bigint generated always as identity primary key,
  ticket_id   bigint not null references public.tickets(id) on delete cascade,
  company_id  bigint not null references public.companies(id) on delete cascade,
  user_id     uuid references auth.users(id),
  verifie_le  timestamptz not null default now(),
  ref         uuid                                  -- identifiant de l'appareil : évite les doublons à la synchronisation
);
create unique index if not exists ticket_verifications_ref_uidx on public.ticket_verifications (ref) where ref is not null;
create index if not exists ticket_verifications_ticket_idx on public.ticket_verifications (ticket_id);
alter table public.ticket_verifications enable row level security;
drop policy if exists ticket_verifications_select on public.ticket_verifications;
create policy ticket_verifications_select on public.ticket_verifications for select to authenticated
  using (public.app_role() in ('admin', 'chef_gare') and company_id = public.app_company_id());
grant select on public.ticket_verifications to authenticated;

-- Billets à vérifier (récents et à venir de l'entreprise) : copie gardée sur chaque téléphone pour vérifier sans internet.
create or replace function public.billets_a_verifier()
returns table (id bigint, numero text, client_nom text, client_telephone text,
               gare_depart_nom text, gare_arrivee_nom text, date_voyage date, heure_depart text,
               siege text, statut text, nb_verifications integer)
language plpgsql stable security definer set search_path = public as $$
begin
  if public.app_role() is null or public.app_role() not in ('admin', 'chef_gare', 'agent', 'guichet', 'convoyeur') then
    raise exception 'Non autorisé';
  end if;
  return query
    select t.id, t.numero, t.client_nom, t.client_telephone, gd.nom, ga.nom, t.date_voyage, t.heure_depart,
           t.siege, t.statut, t.nb_verifications
    from public.tickets t
    left join public.gares gd on gd.id = t.gare_depart_id
    left join public.gares ga on ga.id = t.gare_arrivee_id
    where t.company_id = public.app_company_id()
      and t.date_voyage >= current_date - 2
    order by t.date_voyage, t.heure_depart nulls last, t.id
    limit 5000;
end $$;

-- Vérifie un billet (autant de fois qu'on veut) : renvoie ses informations et le nombre de vérifications, celle-ci comprise.
create or replace function public.verifier_billet(p_numero text, p_ref uuid default null, p_at timestamptz default null)
returns table (id bigint, numero text, client_nom text, client_telephone text,
               gare_depart_nom text, gare_arrivee_nom text, date_voyage date, heure_depart text,
               siege text, statut text, nb_verifications integer)
language plpgsql security definer set search_path = public as $$
declare t public.tickets; n integer;
begin
  if public.app_role() is null or public.app_role() not in ('admin', 'chef_gare', 'agent', 'guichet', 'convoyeur') then
    raise exception 'Non autorisé';
  end if;
  select * into t from public.tickets x
   where x.numero = upper(trim(p_numero)) and x.company_id = public.app_company_id();
  if not found then return; end if;
  insert into public.ticket_verifications (ticket_id, company_id, user_id, verifie_le, ref)
  values (t.id, t.company_id, auth.uid(), coalesce(p_at, now()), p_ref)
  on conflict (ref) where ref is not null do nothing;
  get diagnostics n = row_count;
  if n > 0 then
    update public.tickets x set nb_verifications = x.nb_verifications + 1,
      derniere_verification = greatest(coalesce(x.derniere_verification, '-infinity'), coalesce(p_at, now()))
    where x.id = t.id;
  end if;
  return query
    select x.id, x.numero, x.client_nom, x.client_telephone, gd.nom, ga.nom, x.date_voyage, x.heure_depart,
           x.siege, x.statut, x.nb_verifications
    from public.tickets x
    left join public.gares gd on gd.id = x.gare_depart_id
    left join public.gares ga on ga.id = x.gare_arrivee_id
    where x.id = t.id;
end $$;

revoke execute on function public.billets_a_verifier(), public.verifier_billet(text, uuid, timestamptz) from public, anon;
grant execute on function public.billets_a_verifier(), public.verifier_billet(text, uuid, timestamptz) to authenticated;

notify pgrst, 'reload schema';

-- ═══ 20261022000000_sms_solde ═══
-- Solde SMS SMSBUS : affiché dans Paramètres (API « Balance » de la passerelle, identifiant Terminal Web).

alter table public.sms_settings add column if not exists terminal_id text not null default '';
alter table public.sms_settings add column if not exists solde_request_id bigint;
alter table public.sms_settings add column if not exists solde_texte text;
alter table public.sms_settings add column if not exists solde_le timestamptz;

grant select (terminal_id, solde_texte, solde_le) on public.sms_settings to authenticated;

-- Reprend sms_enregistrer avec le champ « terminal_id ».
create or replace function public.sms_enregistrer(p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare cid bigint := public.app_company_id();
begin
  if public.app_role() is distinct from 'admin' or cid is null then raise exception 'Non autorisé'; end if;
  insert into public.sms_settings (company_id) values (cid) on conflict do nothing;
  update public.sms_settings set
    actif = coalesce((p ->> 'actif')::boolean, actif),
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
    updated_at = now()
  where company_id = cid;
end $$;

-- Demande le solde à SMSBUS (requête asynchrone).
create or replace function public.sms_solde_demander() returns void
language plpgsql security definer set search_path = public as $$
declare s public.sms_settings; rid bigint;
begin
  if public.app_role() is distinct from 'admin' then raise exception 'Non autorisé'; end if;
  select * into s from public.sms_settings where company_id = public.app_company_id();
  if not found or s.terminal_id = '' then
    raise exception 'Renseignez l''identifiant Terminal Web SMSBUS pour afficher le solde';
  end if;
  execute 'select net.http_get(url := $1)' into rid
    using 'https://www.lesmsbus.com:' || s.port || '/ines.smsbus/Balance?id=' || public._sms_urlencode(s.terminal_id);
  update public.sms_settings set solde_request_id = rid where company_id = s.company_id;
end $$;

-- Lit la réponse (« 2500-USD ») et la garde ; renvoie le dernier solde connu.
create or replace function public.sms_solde_lire()
returns table (solde text, mis_a_jour timestamptz)
language plpgsql security definer set search_path = public as $$
declare s public.sms_settings; contenu text;
begin
  if public.app_role() is distinct from 'admin' then raise exception 'Non autorisé'; end if;
  select * into s from public.sms_settings where company_id = public.app_company_id();
  if not found then return; end if;
  if s.solde_request_id is not null then
    begin
      execute 'select content from net._http_response where id = $1' into contenu using s.solde_request_id;
    exception when others then contenu := null;
    end;
    if contenu is not null then
      update public.sms_settings set solde_texte = left(trim(contenu), 200), solde_le = now(), solde_request_id = null
      where company_id = s.company_id;
    end if;
  end if;
  return query select t.solde_texte, t.solde_le from public.sms_settings t where t.company_id = s.company_id;
end $$;

revoke execute on function public.sms_solde_demander(), public.sms_solde_lire() from public, anon;
grant execute on function public.sms_solde_demander(), public.sms_solde_lire() to authenticated;

notify pgrst, 'reload schema';

-- ═══ 20261023000000_sms_plateforme ═══
-- SMS pour toutes les entreprises avec UN compte SMSBUS de la plateforme (géré par le superadmin).
-- Chaque entreprise l'utilise par défaut ; son administrateur peut choisir son propre compte SMSBUS.
-- Le superadmin peut bloquer les SMS d'une entreprise, changer le compte de la plateforme, ou imposer le compte
-- de la plateforme à une entreprise.

create table if not exists public.sms_global (
  id           integer primary key default 1 check (id = 1),
  actif        boolean not null default false,
  username     text not null default '',
  password     text not null default '',
  sender       text not null default '',
  port         integer not null default 7170,
  indicatif    text not null default '226',
  terminal_id  text not null default '',
  solde_request_id bigint,
  solde_texte  text,
  solde_le     timestamptz,
  updated_at   timestamptz not null default now()
);
insert into public.sms_global (id) values (1) on conflict do nothing;
alter table public.sms_global enable row level security;
revoke all on public.sms_global from public, anon, authenticated;

alter table public.sms_settings add column if not exists source text not null default 'global'
  check (source in ('global', 'propre'));
alter table public.sms_settings add column if not exists bloque boolean not null default false;
-- Les entreprises créées à partir de maintenant ont les SMS actifs par défaut.
alter table public.sms_settings alter column actif set default true;
-- Les entreprises déjà configurées avec leur propre compte le gardent.
update public.sms_settings set source = 'propre' where username <> '' and password <> '';

-- Les entreprises jamais configurées (aucun identifiant saisi) reçoivent les SMS de la plateforme.
update public.sms_settings set actif = true where username = '' and password = '';

-- Toutes les entreprises existantes ont une ligne de réglages (SMS actifs, compte de la plateforme).
insert into public.sms_settings (company_id) select id from public.companies on conflict do nothing;

grant select (source, bloque) on public.sms_settings to authenticated;

-- Réglages d'une entreprise (créés à la volée s'ils n'existent pas).
create or replace function public._sms_reglages(p_company bigint) returns public.sms_settings
language plpgsql security definer set search_path = public as $$
declare s public.sms_settings;
begin
  insert into public.sms_settings (company_id) values (p_company) on conflict do nothing;
  select * into s from public.sms_settings where company_id = p_company;
  return s;
end $$;

-- Les déclencheurs passent par _sms_reglages : plus besoin de configurer chaque entreprise.
create or replace function public.colis_sms_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare s public.sms_settings; v jsonb;
begin
  s := public._sms_reglages(new.company_id);
  if not s.actif or s.bloque or not s.sms_colis_envoi then return new; end if;
  v := public._sms_colis_vals(new);
  perform public._sms_poster(new.company_id, 'envoi_exp', new.id, null, new.expediteur_telephone, public._sms_remplir(s.tpl_envoi_exp, v));
  perform public._sms_poster(new.company_id, 'envoi_dest', new.id, null, new.destinataire_telephone, public._sms_remplir(s.tpl_envoi_dest, v));
  return new;
exception when others then return new;
end $$;

create or replace function public.colis_sms_statut() returns trigger
language plpgsql security definer set search_path = public as $$
declare s public.sms_settings; v jsonb;
begin
  if new.statut is not distinct from old.statut then return new; end if;
  s := public._sms_reglages(new.company_id);
  if not s.actif or s.bloque then return new; end if;
  v := public._sms_colis_vals(new);
  if new.statut = 'arrive' and s.sms_colis_arrive then
    perform public._sms_poster(new.company_id, 'arrive', new.id, null, new.destinataire_telephone, public._sms_remplir(s.tpl_arrive, v));
  elsif new.statut = 'retire' and s.sms_colis_retire then
    perform public._sms_poster(new.company_id, 'retire', new.id, null, new.expediteur_telephone, public._sms_remplir(s.tpl_retire, v));
  end if;
  return new;
exception when others then return new;
end $$;

create or replace function public.tickets_sms_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare s public.sms_settings; v jsonb;
begin
  s := public._sms_reglages(new.company_id);
  if not s.actif or s.bloque or not s.sms_billet then return new; end if;
  v := jsonb_build_object(
    'entreprise', coalesce((select nom from public.companies where id = new.company_id), 'Billet'),
    'numero', new.numero, 'nom', new.client_nom,
    'depart', coalesce((select nom from public.gares where id = new.gare_depart_id), ''),
    'arrivee', coalesce((select nom from public.gares where id = new.gare_arrivee_id), ''),
    'date', to_char(new.date_voyage, 'DD/MM/YYYY') || coalesce(' ' || nullif(new.heure_depart, ''), ''),
    'siege', coalesce(new.siege, ''), 'prix', new.prix::text);
  perform public._sms_poster(new.company_id, 'billet', null, new.id, new.client_telephone, public._sms_remplir(s.tpl_billet, v));
  return new;
exception when others then return new;
end $$;

-- Envoi : compte propre de l'entreprise s'il est choisi et renseigné, sinon compte de la plateforme.
create or replace function public._sms_envoyer(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare o public.sms_outbox; s public.sms_settings; g public.sms_global;
        u text; pw text; fr text; pt integer; ind text; url text; rid bigint;
begin
  select * into o from public.sms_outbox where id = p_id;
  s := public._sms_reglages(o.company_id);
  if s.bloque then
    update public.sms_outbox set statut = 'echec', reponse = 'SMS désactivés pour cette entreprise' where id = p_id; return;
  end if;
  if s.source = 'propre' and s.username <> '' and s.password <> '' then
    u := s.username; pw := s.password; fr := s.sender; pt := s.port; ind := s.indicatif;
  else
    select * into g from public.sms_global where id = 1;
    if not g.actif then
      update public.sms_outbox set statut = 'echec', reponse = 'SMS de la plateforme désactivés' where id = p_id; return;
    end if;
    u := g.username; pw := g.password; fr := g.sender; pt := g.port; ind := coalesce(nullif(s.indicatif, ''), g.indicatif);
  end if;
  if coalesce(u, '') = '' or coalesce(fr, '') = '' then
    update public.sms_outbox set statut = 'echec', reponse = 'SMS non configurés' where id = p_id; return;
  end if;
  url := 'https://www.lesmsbus.com:' || pt || '/ines.smsbus/smsbusMt'
      || '?to=' || public._sms_urlencode(public._sms_numero(o.telephone, ind))
      || '&text=' || public._sms_urlencode(o.message)
      || '&username=' || public._sms_urlencode(u)
      || '&password=' || public._sms_urlencode(pw)
      || '&from=' || public._sms_urlencode(fr)
      || '&jca=0';
  execute 'select net.http_get(url := $1)' into rid using url;
  update public.sms_outbox set request_id = rid where id = p_id;
exception when others then
  update public.sms_outbox set statut = 'echec', reponse = left(sqlerrm, 300) where id = p_id;
end $$;

-- L'administrateur choisit le compte (plateforme ou propre) ; le blocage reste réservé au superadmin.
create or replace function public.sms_enregistrer(p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare cid bigint := public.app_company_id();
begin
  if public.app_role() is distinct from 'admin' or cid is null then raise exception 'Non autorisé'; end if;
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
    updated_at = now()
  where company_id = cid and not (bloque and (p ->> 'actif')::boolean is true);
end $$;

-- Le solde d'une entreprise n'a de sens que pour son propre compte.
create or replace function public.sms_solde_demander() returns void
language plpgsql security definer set search_path = public as $$
declare s public.sms_settings; rid bigint;
begin
  if public.app_role() is distinct from 'admin' then raise exception 'Non autorisé'; end if;
  select * into s from public.sms_settings where company_id = public.app_company_id();
  if not found or s.source <> 'propre' then
    raise exception 'Le solde est géré par la plateforme (compte SMSBUS partagé)';
  end if;
  if s.terminal_id = '' then
    raise exception 'Renseignez l''identifiant Terminal Web SMSBUS pour afficher le solde';
  end if;
  execute 'select net.http_get(url := $1)' into rid
    using 'https://www.lesmsbus.com:' || s.port || '/ines.smsbus/Balance?id=' || public._sms_urlencode(s.terminal_id);
  update public.sms_settings set solde_request_id = rid where company_id = s.company_id;
end $$;

-- ───────────────────────── Superadmin : compte de la plateforme ─────────────────────────

create or replace function public.sms_global_lire()
returns table (actif boolean, username text, sender text, port integer, indicatif text, terminal_id text,
               mot_de_passe_defini boolean, solde_texte text, solde_le timestamptz)
language plpgsql security definer set search_path = public as $$
declare g public.sms_global; contenu text;
begin
  if public.app_role() is distinct from 'superadmin' then raise exception 'Non autorisé'; end if;
  select * into g from public.sms_global where id = 1;
  if g.solde_request_id is not null then
    begin
      execute 'select content from net._http_response where id = $1' into contenu using g.solde_request_id;
    exception when others then contenu := null;
    end;
    if contenu is not null then
      update public.sms_global set solde_texte = left(trim(contenu), 200), solde_le = now(), solde_request_id = null where id = 1;
      select * into g from public.sms_global where id = 1;
    end if;
  end if;
  return query select g.actif, g.username, g.sender, g.port, g.indicatif, g.terminal_id,
                      g.password <> '', g.solde_texte, g.solde_le;
end $$;

create or replace function public.sms_global_enregistrer(p jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if public.app_role() is distinct from 'superadmin' then raise exception 'Non autorisé'; end if;
  update public.sms_global set
    actif = coalesce((p ->> 'actif')::boolean, actif),
    username = coalesce(p ->> 'username', username),
    password = coalesce(nullif(p ->> 'password', ''), password),
    sender = coalesce(left(p ->> 'sender', 18), sender),
    port = coalesce((p ->> 'port')::integer, port),
    indicatif = coalesce(p ->> 'indicatif', indicatif),
    terminal_id = coalesce(p ->> 'terminal_id', terminal_id),
    updated_at = now()
  where id = 1;
end $$;

create or replace function public.sms_global_solde_demander() returns void
language plpgsql security definer set search_path = public as $$
declare g public.sms_global; rid bigint;
begin
  if public.app_role() is distinct from 'superadmin' then raise exception 'Non autorisé'; end if;
  select * into g from public.sms_global where id = 1;
  if g.terminal_id = '' then raise exception 'Renseignez l''identifiant Terminal Web SMSBUS'; end if;
  execute 'select net.http_get(url := $1)' into rid
    using 'https://www.lesmsbus.com:' || g.port || '/ines.smsbus/Balance?id=' || public._sms_urlencode(g.terminal_id);
  update public.sms_global set solde_request_id = rid where id = 1;
end $$;

-- Test d'envoi avec le compte de la plateforme (n'importe quelle entreprise : la première).
create or replace function public.sms_global_tester(p_tel text) returns void
language plpgsql security definer set search_path = public as $$
declare cid bigint; oid bigint;
begin
  if public.app_role() is distinct from 'superadmin' then raise exception 'Non autorisé'; end if;
  select id into cid from public.companies order by id limit 1;
  insert into public.sms_outbox (company_id, type, telephone, message)
  values (cid, 'test', p_tel, 'Test SMS : le compte SMSBUS de la plateforme fonctionne.') returning sms_outbox.id into oid;
  perform public._sms_envoyer(oid);
end $$;

-- Liste des entreprises avec leur situation SMS.
create or replace function public.sms_entreprises()
returns table (company_id bigint, nom text, actif boolean, bloque boolean, source text, nb_envoyes bigint, nb_echecs bigint)
language plpgsql security definer set search_path = public as $$
begin
  if public.app_role() is distinct from 'superadmin' then raise exception 'Non autorisé'; end if;
  return query
    select c.id, c.nom, coalesce(s.actif, true), coalesce(s.bloque, false), coalesce(s.source, 'global'),
           (select count(*) from public.sms_outbox o where o.company_id = c.id and o.statut = 'envoye'),
           (select count(*) from public.sms_outbox o where o.company_id = c.id and o.statut = 'echec')
    from public.companies c
    left join public.sms_settings s on s.company_id = c.id
    order by c.nom;
end $$;

-- Bloquer / autoriser les SMS d'une entreprise, ou lui imposer le compte de la plateforme.
create or replace function public.sms_entreprise_regler(p_company bigint, p_bloque boolean, p_source text default null)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if public.app_role() is distinct from 'superadmin' then raise exception 'Non autorisé'; end if;
  perform public._sms_reglages(p_company);
  update public.sms_settings set
    bloque = coalesce(p_bloque, bloque),
    source = case when p_source in ('global', 'propre') then p_source else source end,
    updated_at = now()
  where company_id = p_company;
end $$;

revoke execute on function public.sms_global_lire(), public.sms_global_enregistrer(jsonb), public.sms_global_solde_demander(),
  public.sms_global_tester(text), public.sms_entreprises(), public.sms_entreprise_regler(bigint, boolean, text),
  public._sms_reglages(bigint) from public, anon;
grant execute on function public.sms_global_lire(), public.sms_global_enregistrer(jsonb), public.sms_global_solde_demander(),
  public.sms_global_tester(text), public.sms_entreprises(), public.sms_entreprise_regler(bigint, boolean, text) to authenticated;
revoke execute on function public._sms_reglages(bigint) from authenticated;

-- Nouvelles entreprises : ligne de réglages créée automatiquement.
create or replace function public.companies_sms_reglages() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.sms_settings (company_id) values (new.id) on conflict do nothing;
  return new;
end $$;
drop trigger if exists companies_sms_reglages on public.companies;
create trigger companies_sms_reglages after insert on public.companies
  for each row execute function public.companies_sms_reglages();
revoke execute on function public.companies_sms_reglages() from public, anon, authenticated;

notify pgrst, 'reload schema';

-- ═══ 20261024000000_colis_billet_lie ═══
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

-- ═══ 20261025000000_reinitialisation_apprentissage ═══
-- Fin de la période d'apprentissage : l'administrateur efface toutes les saisies de son entreprise
-- (colis, billets, vérifications, historique, journal SMS, clients mémorisés).
-- Les utilisateurs, gares, trajets et réglages ne sont PAS touchés.

create table if not exists public.reinitialisations (
  id          bigint generated always as identity primary key,
  company_id  bigint not null references public.companies(id) on delete cascade,
  user_id     uuid references auth.users(id) on delete set null,
  fait_le     timestamptz not null default now(),
  nb_colis    integer not null default 0,
  nb_billets  integer not null default 0,
  nb_clients  integer not null default 0
);
alter table public.reinitialisations enable row level security;
drop policy if exists reinitialisations_select on public.reinitialisations;
create policy reinitialisations_select on public.reinitialisations for select to authenticated
  using (public.app_role() = 'admin' and company_id = public.app_company_id());
revoke all on public.reinitialisations from public, anon, authenticated;
grant select on public.reinitialisations to authenticated;

create or replace function public.reinitialiser_donnees(p_confirmation text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare cid bigint := public.app_company_id(); nc integer; nb integer; ncl integer;
begin
  if public.app_role() is distinct from 'admin' or cid is null then raise exception 'Non autorisé'; end if;
  if upper(trim(coalesce(p_confirmation, ''))) <> 'EFFACER' then
    raise exception 'Confirmation incorrecte : tapez EFFACER pour confirmer';
  end if;
  delete from public.ticket_verifications where company_id = cid;
  delete from public.sms_outbox where company_id = cid;
  delete from public.tickets where company_id = cid;
  get diagnostics nb = row_count;
  delete from public.colis where company_id = cid;      -- l'historique des colis part avec (cascade)
  get diagnostics nc = row_count;
  delete from public.clients where company_id = cid;
  get diagnostics ncl = row_count;
  insert into public.reinitialisations (company_id, user_id, nb_colis, nb_billets, nb_clients)
  values (cid, auth.uid(), nc, nb, ncl);
  return jsonb_build_object('colis', nc, 'billets', nb, 'clients', ncl);
end $$;

revoke execute on function public.reinitialiser_donnees(text) from public, anon;
grant execute on function public.reinitialiser_donnees(text) to authenticated;

notify pgrst, 'reload schema';

-- ═══ 20261026000000_places_comptable_rapport_sms ═══
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

-- ═══ 20261027000000_comptabilite ═══
-- Module « Comptabilité » : dépenses, employés, bulletins de salaire, documents (décharges, factures, reçus, contrats).
-- Activable entreprise par entreprise par le super administrateur ; accessible à l'administrateur et au comptable.

alter table public.companies add column if not exists module_finance boolean not null default false;

-- Identité légale, imprimée sur les documents officiels.
alter table public.company_settings add column if not exists ifu text not null default '';
alter table public.company_settings add column if not exists rccm text not null default '';
alter table public.company_settings add column if not exists regime_fiscal text not null default '';
alter table public.company_settings add column if not exists compte_bancaire text not null default '';
alter table public.company_settings add column if not exists numero_cnss text not null default '';
alter table public.company_settings add column if not exists representant_nom text not null default '';
alter table public.company_settings add column if not exists representant_fonction text not null default 'Directeur général';
alter table public.company_settings add column if not exists tva_taux numeric(5, 2) not null default 0;
alter table public.company_settings add column if not exists cnss_taux numeric(5, 2) not null default 5.5;

-- La vue des entreprises (écran du super administrateur) doit exposer la nouvelle colonne.
drop view if exists public.companies_detail;
create view public.companies_detail with (security_invoker = true) as
select c.*,
       (select count(*) from public.vip_profiles p where p.company_id = c.id and p.actif) as nb_utilisateurs,
       (select p.nom from public.vip_profiles p where p.company_id = c.id and p.role = 'admin' order by p.created_at limit 1) as admin_nom,
       (select p.username from public.vip_profiles p where p.company_id = c.id and p.role = 'admin' order by p.created_at limit 1) as admin_identifiant,
       case when c.statut = 'actif' and c.abonnement_fin is not null and c.abonnement_fin < current_date
            then 'expire' else c.statut end as statut_effectif
from public.companies c;
grant select on public.companies_detail to authenticated;

-- Le module est-il ouvert pour mon entreprise, et suis-je administrateur ou comptable ?
create or replace function public.finance_ok() returns boolean
language sql stable security definer set search_path = public as $$
  select public.app_role() in ('admin', 'comptable')
     and coalesce((select c.module_finance from public.companies c where c.id = public.app_company_id()), false)
$$;
revoke execute on function public.finance_ok() from public, anon;
grant execute on function public.finance_ok() to authenticated;

-- Le super administrateur active / désactive le module d'une entreprise.
create or replace function public.entreprise_module_finance(p_company bigint, p_actif boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if public.app_role() is distinct from 'superadmin' then raise exception 'Réservé au super administrateur'; end if;
  update public.companies set module_finance = p_actif where id = p_company;
end $$;
revoke execute on function public.entreprise_module_finance(bigint, boolean) from public, anon;
grant execute on function public.entreprise_module_finance(bigint, boolean) to authenticated;

-- ───────────────────────── Employés ─────────────────────────

create table if not exists public.finance_employes (
  id                bigint generated always as identity primary key,
  company_id        bigint not null references public.companies(id) on delete cascade,
  matricule         text not null default '',
  nom               text not null,
  poste             text not null default '',
  telephone         text not null default '',
  adresse           text not null default '',
  date_naissance    date,
  piece_identite    text not null default '',
  date_embauche     date,
  type_contrat      text not null default 'CDI',
  date_fin_contrat  date,
  salaire_base      numeric(12, 2) not null default 0 check (salaire_base >= 0),
  indemnite_transport numeric(12, 2) not null default 0 check (indemnite_transport >= 0),
  indemnite_logement  numeric(12, 2) not null default 0 check (indemnite_logement >= 0),
  numero_cnss       text not null default '',
  compte_bancaire   text not null default '',
  gare_id           bigint references public.gares(id) on delete set null,
  actif             boolean not null default true,
  notes             text not null default '',
  created_at        timestamptz not null default now()
);
create index if not exists finance_employes_company_idx on public.finance_employes (company_id, actif);

-- ───────────────────────── Dépenses ─────────────────────────

create table if not exists public.finance_depenses (
  id             bigint generated always as identity primary key,
  company_id     bigint not null references public.companies(id) on delete cascade,
  date_depense   date not null default current_date,
  categorie      text not null default 'Autres',
  libelle        text not null,
  beneficiaire   text not null default '',
  montant        numeric(12, 2) not null check (montant >= 0),
  mode_paiement  text not null default 'Espèces',
  reference      text not null default '',
  gare_id        bigint references public.gares(id) on delete set null,
  notes          text not null default '',
  created_by     uuid references auth.users(id) on delete set null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index if not exists finance_depenses_date_idx on public.finance_depenses (company_id, date_depense desc);

-- ───────────────────────── Bulletins de salaire ─────────────────────────

create table if not exists public.finance_bulletins (
  id              bigint generated always as identity primary key,
  company_id      bigint not null references public.companies(id) on delete cascade,
  employe_id      bigint not null references public.finance_employes(id) on delete cascade,
  mois            date not null,                                  -- 1er jour du mois
  salaire_base    numeric(12, 2) not null default 0,
  primes          jsonb not null default '[]',                    -- [{libelle, montant}]
  retenues        jsonb not null default '[]',                    -- [{libelle, montant}]
  brut            numeric(12, 2) not null default 0,
  total_retenues  numeric(12, 2) not null default 0,
  net             numeric(12, 2) not null default 0,
  statut          text not null default 'brouillon' check (statut in ('brouillon', 'paye')),
  date_paiement   date,
  mode_paiement   text not null default 'Espèces',
  notes           text not null default '',
  created_by      uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (employe_id, mois)
);
create index if not exists finance_bulletins_mois_idx on public.finance_bulletins (company_id, mois);

-- ───────────────────────── Documents (décharges, factures, reçus, contrats) ─────────────────────────

create table if not exists public.finance_documents (
  id          bigint generated always as identity primary key,
  company_id  bigint not null references public.companies(id) on delete cascade,
  type        text not null check (type in ('decharge', 'facture', 'recu', 'contrat')),
  numero      text not null,
  seq         integer not null,
  date_doc    date not null default current_date,
  titre       text not null default '',                           -- libellé court affiché dans la liste
  montant     numeric(14, 2) not null default 0,
  statut      text not null default 'emis',                       -- facture : emis / payee / annulee
  data        jsonb not null default '{}',                        -- tous les champs du document
  employe_id  bigint references public.finance_employes(id) on delete set null,
  created_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (company_id, numero)
);
create index if not exists finance_documents_idx on public.finance_documents (company_id, type, date_doc desc);

-- Numérotation : DEC-2026-0001, FAC-2026-0001, REC-…, CTR-… (par entreprise, type et année).
create or replace function public.finance_documents_avant() returns trigger
language plpgsql security definer set search_path = public as $$
declare an integer := extract(year from coalesce(new.date_doc, current_date))::integer; pre text;
begin
  if tg_op = 'INSERT' then
    new.company_id := public.app_company_id();
    new.created_by := coalesce(auth.uid(), new.created_by);
    perform pg_advisory_xact_lock(hashtextextended(new.company_id || '|' || new.type || '|' || an, 7));
    select coalesce(max(seq), 0) + 1 into new.seq from public.finance_documents
     where company_id = new.company_id and type = new.type and extract(year from date_doc)::integer = an;
    pre := case new.type when 'decharge' then 'DEC' when 'facture' then 'FAC' when 'recu' then 'REC' else 'CTR' end;
    new.numero := pre || '-' || an || '-' || lpad(new.seq::text, 4, '0');
  else
    new.company_id := old.company_id;
    new.numero := old.numero;
    new.seq := old.seq;
    new.type := old.type;
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists finance_documents_avant on public.finance_documents;
create trigger finance_documents_avant before insert or update on public.finance_documents
  for each row execute function public.finance_documents_avant();

-- Entreprise et auteur imposés par le serveur sur les autres tables.
create or replace function public.finance_avant() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.company_id := public.app_company_id();
    if tg_table_name in ('finance_depenses', 'finance_bulletins') then new.created_by := coalesce(auth.uid(), new.created_by); end if;
  else
    new.company_id := old.company_id;
  end if;
  if tg_table_name in ('finance_depenses', 'finance_bulletins') then new.updated_at := now(); end if;
  return new;
end $$;
drop trigger if exists finance_employes_avant on public.finance_employes;
create trigger finance_employes_avant before insert or update on public.finance_employes
  for each row execute function public.finance_avant();
drop trigger if exists finance_depenses_avant on public.finance_depenses;
create trigger finance_depenses_avant before insert or update on public.finance_depenses
  for each row execute function public.finance_avant();
drop trigger if exists finance_bulletins_avant on public.finance_bulletins;
create trigger finance_bulletins_avant before insert or update on public.finance_bulletins
  for each row execute function public.finance_avant();
revoke execute on function public.finance_documents_avant(), public.finance_avant() from public, anon, authenticated;

-- ───────────────────────── Sécurité ─────────────────────────

do $$
declare t text;
begin
  foreach t in array array['finance_employes', 'finance_depenses', 'finance_bulletins', 'finance_documents'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_tout', t);
    execute format(
      'create policy %I on public.%I for all to authenticated using (public.finance_ok() and company_id = public.app_company_id()) '
      'with check (public.finance_ok() and company_id = public.app_company_id())', t || '_tout', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
  end loop;
end $$;
grant usage, select on all sequences in schema public to authenticated;

notify pgrst, 'reload schema';

-- ═══ 20261028000000_rapports_confidentiels ═══
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

-- ═══ 20261029000000_paiement_cloture ═══
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
