/// Configuration de la connexion Supabase.
///
/// Les valeurs sont injectées à la compilation :
///   flutter run -d chrome \
///     --dart-define=SUPABASE_URL=https://supabase.mon-domaine.com \
///     --dart-define=SUPABASE_ANON_KEY=eyJ...
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Domaine technique des comptes : la connexion se fait par « username »,
  /// Supabase Auth reçoit `<username>@vipcolis.app`.
  static const emailDomain = 'vipcolis.app';
}
