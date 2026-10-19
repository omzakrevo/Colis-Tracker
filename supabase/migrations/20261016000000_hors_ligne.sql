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
