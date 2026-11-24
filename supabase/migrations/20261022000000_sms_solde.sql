-- Solde SMS SMSBUS : affiché dans Paramètres (API « Balance » de la passerelle, identifiant Terminal Web).

alter table public.sms_settings add column if not exists terminal_id text not null default '';
alter table public.sms_settings add column if not exists solde_request_id bigint;
alter table public.sms_settings add column if not exists solde_texte text;
alter table public.sms_settings add column if not exists solde_le timestamptz;

grant select (terminal_id, solde_texte, solde_le) on public.sms_settings to authenticated;

-- Reprend sms_enregistrer avec le champ « terminal_id ».
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
  where company_id = cid;
end $$;

-- Demande le solde à SMSBUS (requête asynchrone).
create or replace function public.sms_solde_demander() returns void
language plpgsql security definer set search_path = public as $$
declare s public.sms_settings; rid bigint;
begin
  if public.app_role() is distinct from 'admin' then raise exception 'Non autorisé'; end if;
  select * into s from public.sms_settings where company_id = public.app_company_id();
  if not found or s.terminal_id = '' then
    raise exception 'Renseignez l''identifiant Terminal Web SMSBUS pour afficher le solde';
  end if;
  execute 'select net.http_get(url := $1)' into rid
    using 'https://www.lesmsbus.com:' || s.port || '/ines.smsbus/Balance?id=' || public._sms_urlencode(s.terminal_id);
  update public.sms_settings set solde_request_id = rid where company_id = s.company_id;
end $$;

-- Lit la réponse (« 2500-USD ») et la garde ; renvoie le dernier solde connu.
create or replace function public.sms_solde_lire()
returns table (solde text, mis_a_jour timestamptz)
language plpgsql security definer set search_path = public as $$
declare s public.sms_settings; contenu text;
begin
  if public.app_role() is distinct from 'admin' then raise exception 'Non autorisé'; end if;
  select * into s from public.sms_settings where company_id = public.app_company_id();
  if not found then return; end if;
  if s.solde_request_id is not null then
    begin
      execute 'select content from net._http_response where id = $1' into contenu using s.solde_request_id;
    exception when others then contenu := null;
    end;
    if contenu is not null then
      update public.sms_settings set solde_texte = left(trim(contenu), 200), solde_le = now(), solde_request_id = null
      where company_id = s.company_id;
    end if;
  end if;
  return query select t.solde_texte, t.solde_le from public.sms_settings t where t.company_id = s.company_id;
end $$;

revoke execute on function public.sms_solde_demander(), public.sms_solde_lire() from public, anon;
grant execute on function public.sms_solde_demander(), public.sms_solde_lire() to authenticated;

notify pgrst, 'reload schema';
