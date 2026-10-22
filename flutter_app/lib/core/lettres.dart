// Nombres en toutes lettres, en français (pour « la somme de … francs CFA » sur les décharges, factures, bulletins).

const _unites = [
  'zéro', 'un', 'deux', 'trois', 'quatre', 'cinq', 'six', 'sept', 'huit', 'neuf', 'dix', 'onze', 'douze', 'treize',
  'quatorze', 'quinze', 'seize', 'dix-sept', 'dix-huit', 'dix-neuf',
];
const _dizaines = ['', '', 'vingt', 'trente', 'quarante', 'cinquante', 'soixante'];

/// 0 à 99. `final` : vrai si le nombre termine le groupe (donne « quatre-vingts » mais « quatre-vingt-un »).
String _moinsDeCent(int n, {required bool fin}) {
  if (n < 20) return _unites[n];
  final d = n ~/ 10, u = n % 10;
  if (d == 7 || d == 9) {
    // 70-79 : soixante-dix… ; 90-99 : quatre-vingt-dix…
    final base = d == 7 ? 'soixante' : 'quatre-vingt';
    final reste = 10 + u;
    if (d == 7 && u == 1) return 'soixante et onze';
    return '$base-${_unites[reste]}';
  }
  if (d == 8) return u == 0 ? (fin ? 'quatre-vingts' : 'quatre-vingt') : 'quatre-vingt-${_unites[u]}';
  final base = _dizaines[d];
  if (u == 0) return base;
  if (u == 1) return '$base et un';
  return '$base-${_unites[u]}';
}

/// 0 à 999.
String _moinsDeMille(int n, {required bool fin}) {
  if (n < 100) return _moinsDeCent(n, fin: fin);
  final c = n ~/ 100, r = n % 100;
  final centaines = c == 1 ? 'cent' : '${_unites[c]} cent${r == 0 && fin ? 's' : ''}';
  if (r == 0) return centaines;
  return '$centaines ${_moinsDeCent(r, fin: fin)}';
}

/// Écrit un entier positif en lettres (jusqu'aux milliers de milliards).
String enLettres(int n) {
  if (n < 0) return 'moins ${enLettres(-n)}';
  if (n == 0) return 'zéro';
  final parts = <String>[];
  var reste = n;
  const noms = ['', 'mille', 'million', 'milliard', 'billion'];
  final groupes = <int>[];
  while (reste > 0) {
    groupes.add(reste % 1000);
    reste ~/= 1000;
  }
  for (var i = groupes.length - 1; i >= 0; i--) {
    final g = groupes[i];
    if (g == 0) continue;
    final dernier = i == 0;
    if (i == 1) {
      // mille : invariable, et « un mille » ne se dit pas
      parts.add(g == 1 ? 'mille' : '${_moinsDeMille(g, fin: false)} mille');
    } else if (i >= 2) {
      final nom = noms[i];
      parts.add('${_moinsDeMille(g, fin: false)} $nom${g > 1 ? 's' : ''}');
    } else {
      parts.add(_moinsDeMille(g, fin: dernier));
    }
  }
  return parts.join(' ');
}

/// « Cent vingt mille francs CFA » (première lettre en majuscule).
String montantEnLettres(num montant, {String devise = 'francs CFA'}) {
  final n = montant.round();
  final t = '${enLettres(n)} ${n > 1 ? devise : devise.replaceFirst('francs', 'franc')}';
  return t[0].toUpperCase() + t.substring(1);
}
