-- Le super administrateur peut téléverser l'APK depuis l'application (écran « Mises à jour »).
-- Le dossier « app-releases » est public en lecture ; seule l'écriture est réservée au super administrateur.
do $$ begin
  drop policy if exists app_releases_super_insert on storage.objects;
  drop policy if exists app_releases_super_update on storage.objects;
  drop policy if exists app_releases_super_delete on storage.objects;
  create policy app_releases_super_insert on storage.objects for insert to authenticated
    with check (bucket_id = 'app-releases' and public.app_role() = 'superadmin');
  create policy app_releases_super_update on storage.objects for update to authenticated
    using (bucket_id = 'app-releases' and public.app_role() = 'superadmin')
    with check (bucket_id = 'app-releases' and public.app_role() = 'superadmin');
  create policy app_releases_super_delete on storage.objects for delete to authenticated
    using (bucket_id = 'app-releases' and public.app_role() = 'superadmin');
exception when undefined_table or invalid_schema_name or insufficient_privilege then
  raise notice 'Stockage indisponible : ajoutez à la main une règle d''écriture pour le super administrateur sur le bucket app-releases.';
end $$;

-- Recharge le cache de schéma de l'API (évite « could not find the column … in the schema cache »).
notify pgrst, 'reload schema';
