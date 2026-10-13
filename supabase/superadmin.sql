-- Création du super administrateur de la plateforme (vous).
-- À exécuter UNE SEULE FOIS dans le SQL Editor de Supabase Studio, APRÈS les migrations.
-- ⚠️ Remplacez les 3 valeurs ci-dessous AVANT d'exécuter, et ne publiez jamais ce fichier rempli.
--   1) votre numéro de téléphone (avec l'indicatif, ex. 22670112233) : c'est votre identifiant de connexion
--   2) un mot de passe long et unique
--   3) votre nom
select public.creer_superadmin('VOTRE_NUMERO', 'VOTRE_MOT_DE_PASSE', 'VOTRE_NOM');
