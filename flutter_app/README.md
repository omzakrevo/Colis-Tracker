# Tchi — application Flutter (web + mobile) sur Supabase

Refonte complète de l'application de gestion de colis : nouveau design, animations
(motion design) et connexion directe à votre Supabase auto-hébergé. Une seule base
de code Flutter pour **Web, Android et iOS**. Plus besoin du serveur Express :
l'app parle directement à Supabase (Auth + Postgres + Realtime) et la sécurité est
assurée par les règles RLS du schéma SQL.

## 1. Préparer Supabase (une seule fois)

1. Ouvrez **Supabase Studio** de votre VPS → *SQL Editor*.
2. *(Seulement si une ancienne version a déjà été essayée et a touché votre table `profiles` : exécutez d'abord `supabase/cleanup_profiles.sql`.)*
   Exécutez `supabase/migrations/20261012000000_vip_colis.sql` (tables, sécurité RLS,
   fonctions, temps réel). Les comptes de l'app sont dans la table dédiée `vip_profiles`,
   la table `profiles` éventuelle de vos autres applications n'est pas touchée.
3. *(Optionnel, pour tester)* exécutez `supabase/seed.sql` : crée 4 gares et les comptes
   `admin/admin123`, `chef_oua/chef123`, `agent_bobo/agent123`, `agent_ban/agent123`.
   **Changez ces mots de passe avant la production.**
4. Notez l'URL publique de votre API (ex. `https://supabase.mondomaine.com`) et la
   clé **anon** (`ANON_KEY` dans le `.env` de votre Supabase).

> **Premier admin sans seed :** créez un utilisateur dans *Authentication → Users* avec
> l'e-mail `admin@vipcolis.app`, puis dans le SQL Editor :
> `insert into profiles (id, nom, username, role) select id, 'Administrateur', 'admin', 'admin' from auth.users where email = 'admin@vipcolis.app';`

### Comment fonctionne la connexion
Les utilisateurs se connectent avec un **nom d'utilisateur** comme avant. En coulisses,
Supabase Auth reçoit `<username>@vipcolis.app` (jamais affiché). Les comptes se créent
depuis l'écran *Utilisateurs* de l'app (fonction SQL `admin_creer_utilisateur`).

## 2. Lancer l'application

L'URL de votre VPS (`https://vps-ef39f3a3.vps.ovh.ca`) et la clé anon sont déjà
intégrées par défaut : `flutter run -d chrome` suffit. Les `--dart-define` ci-dessous
servent à les remplacer.

```bash
cd flutter_app
flutter pub get

# Web
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://supabase.mondomaine.com \
  --dart-define=SUPABASE_ANON_KEY=eyJ...

# Mobile (appareil branché ou émulateur)
flutter run \
  --dart-define=SUPABASE_URL=https://supabase.mondomaine.com \
  --dart-define=SUPABASE_ANON_KEY=eyJ...
```

## 3. Construire pour la production

```bash
# Web → dossier build/web à servir (nginx, Caddy…)
flutter build web --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...

# Android
flutter build apk --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
# iOS (sur macOS)
flutter build ipa --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

Exemple Caddy pour héberger le web sur votre VPS :

```
colis.mondomaine.com {
  root * /var/www/vip-colis
  try_files {path} /index.html
  file_server
}
```

## 4. Fonctionnalités

- Connexion par nom d'utilisateur, 3 rôles : administrateur, chef de gare, agent.
- Tableau de bord animé (compteurs, graphique des statuts, derniers colis) en **temps réel**.
- Colis : création en 3 étapes, photo, liste avec recherche/filtres/tri, détail avec
  progression animée (camion), historique, QR code, changement de statut contrôlé,
  retrait avec signature, reçu PDF imprimable (ticket 80 mm).
- Scanner QR (caméra mobile ou web) avec **scan rapide par lot** : *Consulter* (ouvre le colis),
  *Embarquer* (Enregistré → Chargé) et *Décharger* (Chargé/En route → Arrivé). On scanne tous les
  colis (caméra, saisie ou lecteur Bluetooth), puis un seul bouton valide le lot. Nécessite la migration
  `20261013000000_scan_rapide.sql`.
- Rapports : colis/jour, recettes par gare et par agent, colis non retirés.
- Admin : gares, utilisateurs (création, rôle, activation, mot de passe), paramètres société + logo.
- Visibilité : l'admin voit tout ; chef de gare/agent ne voient que les colis de leur gare.

## 5. Points d'attention

- **Realtime** : le service *Realtime* de votre Supabase doit tourner pour les mises à
  jour automatiques (sinon l'app fonctionne, mais il faut tirer pour rafraîchir).
- **CORS** : en web, l'URL du site doit être autorisée par votre API Supabase.
- **Caméra / photos** : permissions Android/iOS à déclarer au moment de publier
  (`CAMERA`, `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`).
- Les photos et signatures sont stockées en base (base64), comme dans l'ancienne version.

## 6. Migrations automatiques via GitHub

Le workflow `.github/workflows/supabase-migrations.yml` applique `supabase/migrations/`
sur votre VPS à chaque push sur `main`, via un **runner GitHub auto-hébergé** installé
sur le VPS (la base n'est pas exposée sur internet).

1. GitHub → *Settings → Actions → Runners → New self-hosted runner* (Linux x64) : suivez les
   commandes affichées sur le VPS, avec un utilisateur non-root, puis installez-le comme service
   (`sudo ./svc.sh install && sudo ./svc.sh start`). Le runner doit avoir le label `linux`.
2. Secret `SUPABASE_DB_URL` (Repository secrets) :
   `postgresql://postgres.TENANT_ID:MOT_DE_PASSE@localhost:5432/postgres`
   (`TENANT_ID` = `POOLER_TENANT_ID` du `.env` Supabase ; encodez les caractères spéciaux du mot de passe).
3. Évolution du schéma : ajoutez `supabase/migrations/<AAAAMMJJHHMMSS>_nom.sql`, poussez sur `main`.
   Le `seed.sql` n'est jamais exécuté automatiquement.

## 7. Générer l'application mobile

- **Android (APK)** : GitHub → *Actions → Application mobile (Android) → Run workflow*. Au bout de
  quelques minutes, téléchargez `vip-colis-android` (l'APK) dans *Artifacts* en bas de la page du run.
  Installez-le sur le téléphone (autoriser « sources inconnues »). Un tag `v1.0.0` crée aussi une release avec l'APK.
- **En local** : `cd flutter_app && flutter build apk --release` (SDK Android requis).
- **iOS** : nécessite un Mac et un compte Apple Developer (`flutter build ipa --release`).
- L'APK est signé avec la clé de debug : suffisant pour installer et tester. Pour le Play Store,
  il faut créer une clé de signature de release.

## 8. Générer et publier l'application web

Workflow `.github/workflows/build-web.yml` : construit le web et le publie sur **GitHub Pages**
(`https://<utilisateur>.github.io/Colis-Tracker/`).

1. Une seule fois : GitHub → *Settings → Pages → Build and deployment → Source = GitHub Actions*.
2. *Actions → Application web → Run workflow* (ou push sur `main` modifiant `flutter_app/`).
3. Le dossier compilé est aussi téléchargeable dans *Artifacts* (`vip-colis-web`), pour l'héberger
   vous-même (par exemple avec Caddy sur le VPS, section 3).

## 9. SaaS : plusieurs entreprises et abonnements

- **Migration** `20261014000000_saas_multi_entreprises.sql` : chaque entreprise a ses propres gares, colis,
  utilisateurs et paramètres, isolés par la sécurité de la base (RLS). Les données existantes sont rattachées
  à une première entreprise « active ».
- **Super administrateur** (vous) : créez-le une fois avec `supabase/superadmin.sql` (après avoir remplacé
  le numéro, le mot de passe et le nom). Il voit uniquement l'écran **Entreprises** : valider une demande,
  fixer la date de fin d'abonnement et le nombre d'utilisateurs, prolonger, suspendre, créer une entreprise.
- **Inscription** : sur l'écran de connexion, « Créer mon entreprise » (nom, ville, administrateur,
  téléphone, mot de passe). L'entreprise reste **en attente** tant que le super administrateur ne l'a pas validée.
- **Utilisateurs** : l'administrateur de l'entreprise crée les comptes de ses employés (identifiant = numéro de téléphone),
  dans la limite du nombre d'utilisateurs de l'abonnement.
- **Connexion** : numéro de téléphone + mot de passe (un nom d'utilisateur reste possible pour les comptes de test).
- **Session mémorisée** : après la première connexion, l'application s'ouvre directement, même sans internet.
  Dès que le réseau revient (et toutes les 10 minutes), le compte et l'abonnement sont revérifiés ; en cas de
  problème (compte désactivé, entreprise suspendue, abonnement expiré, session révoquée), l'utilisateur est déconnecté.
- **Connexion hors ligne** : après une déconnexion volontaire, le compte reste mémorisé sur l'appareil
  (empreinte PBKDF2 salée du mot de passe, jamais le mot de passe) et permet de se reconnecter sans internet.
  Les écrans de données (colis, rapports…) nécessitent encore internet.
- Le seed (`supabase/seed.sql`) rattache les comptes de test à la première entreprise.

## 10. Mises à jour automatiques sur les téléphones (Shorebird)

[Shorebird](https://shorebird.dev) envoie les mises à jour du code Dart directement aux téléphones, sans
réinstaller l'APK ni passer par un store. Les téléphones téléchargent le patch au démarrage et l'appliquent au
démarrage suivant.

**Mise en place (une seule fois)**
1. Créez un compte sur shorebird.dev, installez la CLI sur votre ordinateur et lancez `shorebird login:ci` :
   elle affiche un jeton. Dans GitHub : *Settings → Secrets and variables → Actions → New repository secret*
   nommé `SHOREBIRD_TOKEN` (valeur = ce jeton).
2. *Actions → Shorebird - Publier une version → Run workflow*. Le premier lancement crée l'application chez Shorebird
   et affiche `shorebird.yaml` (avec l'`app_id`) dans le résumé du run : **ajoutez ce fichier dans `flutter_app/`
   et poussez-le** (sinon les versions suivantes créeraient une autre application).
3. Téléchargez l'APK `application-android-shorebird` et installez-le sur les téléphones : **c'est cet APK**
   (et non celui du workflow « Application mobile (Android) ») qui reçoit les mises à jour.

**Envoyer une mise à jour**
1. Modifiez le code Dart, fusionnez dans `main`.
2. *Actions → Shorebird - Envoyer une mise à jour → Run workflow*.
3. Les téléphones installés avec la même version reçoivent le patch automatiquement.

**Limites** : seul le code Dart se met à jour. Un nouveau plugin, un changement de permissions ou de code Android/iOS
natif, ou un changement de version majeure demande une nouvelle « Publier une version » et une réinstallation.
Shorebird est un service tiers (offre gratuite limitée, puis payante) : vérifiez ses conditions et tarifs.
