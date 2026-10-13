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
  check (role in ('superadmin', 'admin', 'chef_gare', 'agent'));
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
