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

-- Un profil par compte Supabase Auth. Connexion par « username » :
-- l'e-mail technique est <username>@vipcolis.app (jamais affiché).
create table if not exists public.profiles (
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
  agent_id                uuid references public.profiles(id) on delete set null,
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
  agent_id         uuid references public.profiles(id) on delete set null,
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
insert into public.company_settings (id) values (1) on conflict do nothing;

-- ───────────────────────── Fonctions utilitaires ─────────────────────────

create or replace function public.app_role() returns text
language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid() and actif
$$;

create or replace function public.app_gare_id() returns bigint
language sql stable security definer set search_path = public as $$
  select gare_id from public.profiles where id = auth.uid() and actif
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
create or replace function public.profiles_guard_update() returns trigger
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

drop trigger if exists profiles_guard_update on public.profiles;
create trigger profiles_guard_update before update on public.profiles
  for each row execute function public.profiles_guard_update();

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
  insert into public.profiles (id, nom, username, role, gare_id, telephone)
  values (uid, p_nom, lower(trim(p_username)), p_role, p_gare_id, p_telephone);
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
left join public.profiles p on p.id = c.agent_id;

create or replace view public.historique_detail with (security_invoker = true) as
select h.*, p.nom as agent_nom
from public.historique_colis h
left join public.profiles p on p.id = h.agent_id;

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
    'total_agents',        (select count(*) from profiles where actif)
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
  from profiles p left join colis c on c.agent_id = p.id
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
alter table public.profiles enable row level security;
alter table public.colis enable row level security;
alter table public.historique_colis enable row level security;
alter table public.company_settings enable row level security;

drop policy if exists gares_select on public.gares;
drop policy if exists gares_write on public.gares;
create policy gares_select on public.gares for select to authenticated using (true);
create policy gares_write on public.gares for all to authenticated
  using (app_role() = 'admin') with check (app_role() = 'admin');

drop policy if exists profiles_select on public.profiles;
drop policy if exists profiles_update on public.profiles;
drop policy if exists profiles_delete on public.profiles;
create policy profiles_select on public.profiles for select to authenticated using (true);
create policy profiles_update on public.profiles for update to authenticated
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
grant select, insert, update, delete on public.gares, public.profiles, public.colis, public.company_settings to authenticated;
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
