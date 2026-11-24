-- Modèle des tickets réglé par l'administrateur (écran « Modèle des tickets ») : ordre des éléments, taille du texte,
-- alignement, traits, informations affichées, pour le ticket de voyage, le ticket colis et l'étiquette. Vide = modèle d'origine.
alter table public.company_settings add column if not exists modele_tickets jsonb;
alter table public.company_settings drop constraint if exists company_settings_modele_tickets_check;
alter table public.company_settings add constraint company_settings_modele_tickets_check
  check (modele_tickets is null or (jsonb_typeof(modele_tickets) = 'object' and pg_column_size(modele_tickets) <= 20000));
