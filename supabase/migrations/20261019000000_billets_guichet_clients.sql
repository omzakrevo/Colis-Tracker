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
