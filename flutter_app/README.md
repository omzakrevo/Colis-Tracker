# VIP Colis — application Flutter (web + mobile) sur Supabase

Refonte complète de l'application de gestion de colis : nouveau design, animations
(motion design) et connexion directe à votre Supabase auto-hébergé. Une seule base
de code Flutter pour **Web, Android et iOS**. Plus besoin du serveur Express :
l'app parle directement à Supabase (Auth + Postgres + Realtime) et la sécurité est
assurée par les règles RLS du schéma SQL.

## 1. Préparer Supabase (une seule fois)

1. Ouvrez **Supabase Studio** de votre VPS → *SQL Editor*.
2. Exécutez `supabase/migrations/20261012000000_vip_colis.sql` (tables, sécurité RLS,
   fonctions, temps réel).
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
- Scanner QR (caméra mobile ou web) + saisie manuelle du numéro.
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

Le workflow `.github/workflows/supabase-migrations.yml` applique les fichiers de
`supabase/migrations/` sur votre VPS à chaque push sur `main` (dry-run sur les PR).

1. Dans GitHub : *Settings → Secrets and variables → Actions → New repository secret*
   `SUPABASE_DB_URL` = `postgresql://postgres:MOT_DE_PASSE@vps-ef39f3a3.vps.ovh.ca:5432/postgres`
2. Le port Postgres du VPS doit être joignable depuis internet (ou utilisez un runner
   GitHub auto-hébergé sur le VPS, plus sûr).
3. Pour une évolution du schéma : ajoutez un fichier `supabase/migrations/<AAAAMMJJHHMMSS>_nom.sql`,
   poussez, c'est appliqué. Le `seed.sql` n'est jamais exécuté automatiquement.
