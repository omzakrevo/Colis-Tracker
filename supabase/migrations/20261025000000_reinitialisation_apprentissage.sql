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
