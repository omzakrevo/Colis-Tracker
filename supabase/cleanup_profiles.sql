-- À exécuter UNE SEULE FOIS, avant la nouvelle migration, si vous avez déjà essayé une
-- ancienne version qui touchait à votre table existante « public.profiles ».
-- Cela retire uniquement ce que VIP Colis y avait ajouté (déclencheur, règles de sécurité,
-- contrainte et index). Vos données ne sont pas modifiées.

drop trigger  if exists profiles_guard_update on public.profiles;
drop function if exists public.profiles_guard_update();
drop policy   if exists profiles_select on public.profiles;
drop policy   if exists profiles_update on public.profiles;
drop policy   if exists profiles_delete on public.profiles;
alter table public.profiles drop constraint if exists profiles_role_check;
drop index    if exists public.profiles_vip_username_key;

-- Si plus aucune règle de sécurité n'existe sur la table, la sécurité par ligne (RLS) n'a été
-- activée que par VIP Colis : on la désactive pour retrouver l'état d'origine.
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'profiles') then
    alter table public.profiles disable row level security;
  end if;
end $$;

-- Les colonnes ajoutées par l'ancienne version (nom, role, gare_id, telephone, actif, username)
-- sont inoffensives et laissées en place : supprimez-les seulement si vous êtes certain
-- qu'elles n'existaient pas avant et ne servent pas à votre autre application.
