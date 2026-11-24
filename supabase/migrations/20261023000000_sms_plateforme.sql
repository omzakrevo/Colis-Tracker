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
