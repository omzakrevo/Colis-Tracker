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
