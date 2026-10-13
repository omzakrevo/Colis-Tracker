-- Mises à jour de l'application distribuées par votre propre serveur.
-- Le super administrateur publie une version (numéro de build + lien de l'APK) ; l'application vérifie
-- au démarrage s'il existe une version plus récente et propose de l'installer (obligatoire ou non).

create table if not exists public.app_versions (
  id           bigint generated always as identity primary key,
  plateforme   text not null default 'android' check (plateforme in ('android')),
  version_name text not null,
  build_number integer not null check (build_number > 0),
  apk_url      text not null,
  notes        text,
  obligatoire  boolean not null default false,
  actif        boolean not null default true,
  created_at   timestamptz not null default now(),
  unique (plateforme, build_number)
);

alter table public.app_versions enable row level security;

drop policy if exists app_versions_select on public.app_versions;
drop policy if exists app_versions_write on public.app_versions;
-- Lecture ouverte (même avant connexion) pour les versions actives ; le superadmin voit tout.
create policy app_versions_select on public.app_versions for select to anon, authenticated
  using (actif or public.app_role() = 'superadmin');
create policy app_versions_write on public.app_versions for all to authenticated
  using (public.app_role() = 'superadmin') with check (public.app_role() = 'superadmin');

grant select on public.app_versions to anon, authenticated;
grant insert, update, delete on public.app_versions to authenticated;

-- Dossier de stockage public pour les APK (téléversement par le superadmin ou par le workflow GitHub).
-- Attention : la taille maximale d'un fichier est aussi limitée par la configuration globale du service
-- Storage de votre Supabase (FILE_SIZE_LIMIT, 50 Mo par défaut) : augmentez-la si votre APK est plus gros.
do $$ begin
  begin
    insert into storage.buckets (id, name, public, file_size_limit)
    values ('app-releases', 'app-releases', true, 314572800)
    on conflict (id) do update set public = true, file_size_limit = excluded.file_size_limit;
  exception when undefined_column then
    insert into storage.buckets (id, name, public) values ('app-releases', 'app-releases', true)
    on conflict (id) do update set public = true;
  end;
exception when undefined_table or invalid_schema_name then
  raise notice 'Schéma storage absent : créez à la main un bucket public « app-releases ».';
end $$;
