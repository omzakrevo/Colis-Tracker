/// Configuration de la connexion Supabase.
///
/// Valeurs par défaut = votre VPS ; surchargeables à la compilation :
///   flutter run -d chrome \
///     --dart-define=SUPABASE_URL=https://supabase.mon-domaine.com \
///     --dart-define=SUPABASE_ANON_KEY=eyJ...
class AppConfig {
  /// Nom commercial de la plateforme.
  static const appName = 'Tchi';
  static const appSlogan = 'La gestion de vos colis, simplement.';

  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://vps-ef39f3a3.vps.ovh.ca',
  );
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    // Clé « anon » publique (rôle anon, protégée par les règles RLS) : sans danger dans l'app.
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzkxNzYwNDE2LCJleHAiOjE5NDk0NDA0MTZ9.-vOE-tocfgxzGsgyJapk406z8f55e8merKLYIy9oq7w',
  );

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Domaine technique des comptes : la connexion se fait par « username »,
  /// Supabase Auth reçoit `<username>@vipcolis.app`.
  static const emailDomain = 'vipcolis.app';
}
