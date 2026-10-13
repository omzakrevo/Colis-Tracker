import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/models.dart';

/// Compte mémorisé sur l'appareil pour pouvoir se connecter sans internet.
/// Le mot de passe n'est JAMAIS stocké : seulement une empreinte PBKDF2 salée.
class LocalAccount {
  LocalAccount({
    required this.identifiant,
    required this.salt,
    required this.hash,
    required this.profil,
    this.company,
  });
  final String identifiant;
  final List<int> salt, hash;
  final Profil profil;
  final Company? company;

  Map<String, dynamic> toJson() => {
    'identifiant': identifiant,
    'salt': base64Encode(salt),
    'hash': base64Encode(hash),
    'profil': profil.toJson(),
    'company': company?.toJson(),
  };

  factory LocalAccount.fromJson(Map<String, dynamic> j) => LocalAccount(
    identifiant: j['identifiant'] as String,
    salt: base64Decode(j['salt'] as String),
    hash: base64Decode(j['hash'] as String),
    profil: Profil.fromJson(Map<String, dynamic>.from(j['profil'] as Map)),
    company: j['company'] == null
        ? null
        : Company.fromJson(Map<String, dynamic>.from(j['company'] as Map)),
  );
}

class LocalAuth {
  static const _key = 'vipcolis_comptes_v1';
  static const _storage = FlutterSecureStorage();
  static final _pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 60000,
    bits: 256,
  );

  static Future<Map<String, LocalAccount>> _load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return {};
      final m = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return {
        for (final e in m.entries)
          e.key: LocalAccount.fromJson(
            Map<String, dynamic>.from(e.value as Map),
          ),
      };
    } catch (_) {
      return {};
    }
  }

  static Future<void> _save(Map<String, LocalAccount> m) async {
    try {
      await _storage.write(
        key: _key,
        value: jsonEncode({for (final e in m.entries) e.key: e.value.toJson()}),
      );
    } catch (_) {}
  }

  static Future<List<int>> _hash(String password, List<int> salt) async =>
      (await _pbkdf2.deriveKeyFromPassword(
        password: password,
        nonce: salt,
      )).extractBytes();

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var r = 0;
    for (var i = 0; i < a.length; i++) {
      r |= a[i] ^ b[i];
    }
    return r == 0;
  }

  /// Mémorise (ou met à jour) le compte après une connexion réussie en ligne.
  static Future<void> remember(
    String identifiant,
    String password,
    Profil profil,
    Company? company,
  ) async {
    final salt = SecretKeyData.random(length: 16).bytes;
    final m = await _load();
    m[identifiant] = LocalAccount(
      identifiant: identifiant,
      salt: salt,
      hash: await _hash(password, salt),
      profil: profil,
      company: company,
    );
    await _save(m);
  }

  /// Met à jour le profil/l'entreprise d'un compte déjà mémorisé (sans toucher à l'empreinte).
  static Future<void> refresh(
    String identifiant,
    Profil profil,
    Company? company,
  ) async {
    final m = await _load();
    final a = m[identifiant];
    if (a == null) return;
    m[identifiant] = LocalAccount(
      identifiant: a.identifiant,
      salt: a.salt,
      hash: a.hash,
      profil: profil,
      company: company,
    );
    await _save(m);
  }

  /// Connexion hors ligne : vérifie l'empreinte du mot de passe.
  static Future<LocalAccount?> verify(
    String identifiant,
    String password,
  ) async {
    final a = (await _load())[identifiant];
    if (a == null) return null;
    return _same(await _hash(password, a.salt), a.hash) ? a : null;
  }

  static Future<LocalAccount?> get(String identifiant) async =>
      (await _load())[identifiant];

  /// Compte mémorisé dont l'identifiant d'utilisateur (uuid) est donné.
  static Future<LocalAccount?> byUserId(String uid) async {
    for (final a in (await _load()).values) {
      if (a.profil.id == uid) return a;
    }
    return null;
  }

  static Future<void> forget(String identifiant) async {
    final m = await _load();
    m.remove(identifiant);
    await _save(m);
  }

  static Future<void> forgetAll() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
  }
}
