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
