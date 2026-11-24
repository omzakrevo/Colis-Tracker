# Tchi (colis + billets de bus + SMS + comptabilité) — notes de reprise

Application Flutter (Android / Windows / Web) + Supabase auto-hébergé sur le VPS de l'utilisateur.
L'utilisateur parle français (dictée vocale), n'est pas technique : répondre en français simple, sans jargon.

## Où est quoi
- App : `flutter_app/` (Riverpod, go_router, supabase_flutter, pdf/printing, esc_pos_utils_plus, print_bluetooth_thermal, flutter_blue_plus).
- Base de données : `supabase/migrations/*.sql` ; installeurs à coller dans Supabase Studio > SQL Editor :
  `supabase/installation_complete.sql` (tout) et `supabase/rattrapage.sql`. Quand on ajoute une migration, l'ajouter AUSSI
  à la fin de ces deux fichiers (marqueur `-- ═══ <nom> ═══`, puis `notify pgrst, 'reload schema';`). Dernière migration : 33 (modele_tickets).
- Impression : `flutter_app/lib/core/imprimante.dart` (+ `imprimante_ble.dart` pour les mini-imprimantes MXW01), tickets texte `core/ticket_texte.dart`,
  tickets image/PDF `screens/ticket_modele.dart` et `screens/receipt.dart`. Piège connu : `esc_pos_utils_plus.imageRaster` plante
  (« Cannot add to a fixed-length list ») si la largeur de l'image n'est pas un multiple de 8.
- Hors ligne : `data/offline.dart`, `data/reseau.dart` (délais courts, sonde réseau).
- Rôles : superadmin / admin / chef_gare / agent / barragiste / guichet / convoyeur / comptable ; rapports filtrés côté serveur (RPC `rapport_colis`, `rapport_billets`).
- Tests : `cd flutter_app && flutter test` (60+ tests). Analyse : `flutter analyze lib test`.

## Compilation (GitHub Actions, dépôt omzakrevo/Colis-Tracker)
- Android : workflow `build-mobile.yml` (lancer à la main sur la branche de travail). APK à télécharger dans « Artifacts » du run.
- Windows : `build-windows.yml`.
- Signature Android STABLE : secrets GitHub `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` (= tchi), `ANDROID_KEY_PASSWORD`.
  Le build échoue s'ils manquent (sauf option `cle_temporaire`). NE JAMAIS committer la clé ni ces valeurs (dépôt public).
- Option « publier » : envoie l'APK sur le Supabase de l'utilisateur (mise à jour intégrée). Exige les secrets `SUPABASE_URL` (adresse nue, sans /rest/v1)
  et `SUPABASE_SERVICE_KEY`, et que `FILE_SIZE_LIMIT` du Storage soit relevé (ex. 314572800) dans le `.env` de Supabase (50 Mo par défaut = erreur 413).

## Règles
- Dépôt public : jamais de secret, mot de passe, clé de signature, numéro de téléphone personnel dans le code.
- Jamais la clé `service_role` dans l'application. Mot de passe SMSBUS côté serveur uniquement.
- Branche de travail courante : `claude/ecstatic-lovelace-2iis86` (rien n'est fusionné dans `main` pour les dernières fonctions).
- Les migrations SQL ne s'appliquent pas toutes seules. Depuis le PC de l'utilisateur (Claude Code desktop), l'assistant a un accès SSH au VPS ;
  la base de Tchi est la base `postgres` du Supabase principal (conteneur `supabase-db`, adresse https://vps-ef39f3a3.vps.ovh.ca). Demander l'accord avant d'y écrire.
- VPS : ne jamais nommer un service docker compose `auth`, `rest`, `storage`, `functions` sur le réseau `supabase_default` (alias DNS en double →
  le Supabase de Tchi envoie des requêtes au mauvais conteneur : « No suitable key or wrong key type »).

## Modèle des tickets (admin)
- Écran `/modele-tickets` (`screens/modele_tickets.dart`), données `data/modele_ticket.dart`, colonne `company_settings.modele_tickets` (migration 33).
- Le même modèle pilote l'impression image (`ticketSelonModele` dans `screens/ticket_modele.dart`) et texte (`_selonModele` dans `core/ticket_texte.dart`).
- Hors imprimante directe, les tickets passent par la fenêtre d'impression au format ROULEAU (`formatRouleau`), jamais A4 (sinon texte minuscule).
- Flutter local : la version du PC (3.38) est trop ancienne ; le projet exige 3.47.7 (comme le workflow).

## Fait mais pas confirmé par l'utilisateur sur le terrain
Impression MXW01 en BLE, impression thermique avec logo/téléphones en grand/mention, envoi des SMS, pg_cron, scripts SQL
(`creer_comptes_vip.sql`, `ajouter_grille_tarifaire.sql` ne sont PAS dans le dépôt : ils étaient fournis à part).
