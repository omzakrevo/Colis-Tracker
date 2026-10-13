import 'config.dart';

/// Même règle que la fonction SQL `normaliser_identifiant` :
/// un numéro de téléphone devient une suite de chiffres, sinon c'est un nom d'utilisateur en minuscules.
String normaliserIdentifiant(String s) {
  final t = s.trim();
  if (RegExp(r'^[+0-9 .()-]+$').hasMatch(t))
    return t.replaceAll(RegExp(r'[^0-9]'), '');
  return t.toLowerCase();
}

/// Adresse technique envoyée à Supabase Auth (jamais affichée).
String emailDepuisIdentifiant(String s) =>
    '${normaliserIdentifiant(s)}@${AppConfig.emailDomain}';

bool estTelephone(String s) =>
    RegExp(r'^[0-9]{8,15}$').hasMatch(normaliserIdentifiant(s));

/// Détecte une panne de connexion (par opposition à une vraie erreur d'authentification).
bool estErreurReseau(Object e) {
  final t = e.runtimeType.toString();
  final m = e.toString();
  return t.contains('SocketException') ||
      t.contains('ClientException') ||
      t.contains('TimeoutException') ||
      t.contains('AuthRetryableFetchException') ||
      m.contains('Failed host lookup') ||
      m.contains('Failed to fetch') ||
      m.contains('ClientException') ||
      m.contains('SocketException') ||
      m.contains('TimeoutException') ||
      m.contains('NetworkError') ||
      m.contains('XMLHttpRequest error') ||
      m.contains('Network is unreachable') ||
      m.contains('Connection refused') ||
      m.contains('Connection closed');
}
