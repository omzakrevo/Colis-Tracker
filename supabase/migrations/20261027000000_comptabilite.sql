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
