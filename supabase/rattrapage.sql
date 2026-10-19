-- RATTRAPAGE : à coller en une seule fois dans Supabase Studio > SQL Editor puis « Run ». Peut être relancé sans risque.

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
  check (role in ('superadmin', 'admin', 'chef_gare', 'agent', 'barragiste'));

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
