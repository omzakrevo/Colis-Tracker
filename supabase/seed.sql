-- Données de démonstration (facultatif) — à exécuter APRÈS la migration, en tant que postgres.
-- Comptes : admin / admin123, chef_oua / chef123, agent_bobo / agent123, agent_ban / agent123
-- ⚠️ Supprimez ces comptes ou changez leurs mots de passe avant la mise en production.

insert into public.gares (nom, ville, adresse, responsable, telephone)
select * from (values
  ('Gare Ouagadougou',   'Ouagadougou',   'Avenue Kwame Nkrumah', 'Issa Ouédraogo', '+226 70 00 00 01'),
  ('Gare Bobo-Dioulasso','Bobo-Dioulasso','Route de Banfora',     'Awa Traoré',     '+226 70 00 00 02'),
  ('Gare Banfora',       'Banfora',       'Quartier Commercial',  'Salif Sanou',    '+226 70 00 00 03'),
  ('Gare Koudougou',     'Koudougou',     'Rue du Marché',        null,             null)
) as v(nom, ville, adresse, responsable, telephone)
where not exists (select 1 from public.gares);

create or replace function pg_temp.seed_user(p_username text, p_password text, p_nom text, p_role text, p_ville text)
returns void language plpgsql as $$
declare
  uid uuid := gen_random_uuid();
  mail text := p_username || '@vipcolis.app';
begin
  if exists (select 1 from public.profiles where username = p_username) then return; end if;

  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change, email_change_token_new)
  values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', mail,
    crypt(p_password, gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '');

  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), uid, uid::text,
    jsonb_build_object('sub', uid::text, 'email', mail, 'email_verified', true), 'email', now(), now(), now());

  insert into public.profiles (id, nom, username, role, gare_id)
  values (uid, p_nom, p_username, p_role, (select id from public.gares where ville = p_ville limit 1));
end $$;

select pg_temp.seed_user('admin',      'admin123', 'Administrateur',  'admin',     null);
select pg_temp.seed_user('chef_oua',   'chef123',  'Issa Ouédraogo',  'chef_gare', 'Ouagadougou');
select pg_temp.seed_user('agent_bobo', 'agent123', 'Agent Bobo',      'agent',     'Bobo-Dioulasso');
select pg_temp.seed_user('agent_ban',  'agent123', 'Agent Banfora',   'agent',     'Banfora');
