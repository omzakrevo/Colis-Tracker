import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'repo.dart' show ColisFilter;

/// Mémoire locale de l'appareil (JSON), cloisonnée par utilisateur : un autre compte sur le même
/// téléphone ne voit jamais les données ni les opérations en attente du premier.
class LocalStore {
  static SharedPreferences? _p;

  /// Préfixe propre à l'utilisateur connecté (remplaçable dans les tests).
  static String Function() namespace = () =>
      Supabase.instance.client.auth.currentUser?.id ?? 'anon';

  static Future<SharedPreferences> get _prefs async =>
      _p ??= await SharedPreferences.getInstance();

  static String _k(String key) => 'tchi_${namespace()}_$key';

  static Future<Object?> read(String key) async {
    try {
      final raw = (await _prefs).getString(_k(key));
      return raw == null ? null : jsonDecode(raw);
    } catch (_) {
      return null; // donnée illisible : comme si elle n'existait pas
    }
  }

  static Future<void> write(String key, Object? value) async {
    try {
      await (await _prefs).setString(_k(key), jsonEncode(value));
    } catch (_) {
      // stockage plein ou indisponible : le mode hors ligne se dégrade, l'application continue
    }
  }

  static Future<void> remove(String key) async {
    try {
      await (await _prefs).remove(_k(key));
    } catch (_) {}
  }

  /// Enregistre `value` sous `prefix_id` en ne gardant que les `cap` plus récentes entrées du préfixe.
  static Future<void> writeCapped(
    String prefix,
    Object id,
    Object? value, {
    int cap = 40,
  }) async {
    final idxKey = '${prefix}_idx';
    final idx = List<String>.from(
      ((await read(idxKey)) as List?) ?? const <String>[],
    );
    final cle = id.toString();
    idx.remove(cle);
    idx.add(cle);
    while (idx.length > cap) {
      await remove('${prefix}_${idx.removeAt(0)}');
    }
    await write('${prefix}_$cle', value);
    await write(idxKey, idx);
  }

  static Future<Object?> readCapped(String prefix, Object id) =>
      read('${prefix}_$id');
}

/// Une opération faite hors connexion, en attente d'être envoyée au serveur.
class OutboxOp {
  OutboxOp({
    required this.id,
    required this.type,
    required this.payload,
    required this.createdAt,
    this.erreur,
  });

  /// 'creer' | 'statut' | 'retirer' | 'scan'
  final String id, type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  /// Motif du refus par le serveur (opération rejetée).
  final String? erreur;

  OutboxOp avecErreur(String message) => OutboxOp(
    id: id,
    type: type,
    payload: payload,
    createdAt: createdAt,
    erreur: message,
  );

  String get libelle => switch (type) {
    'creer' => 'Création du colis ${payload['numero_provisoire'] ?? ''}',
    'statut' => 'Changement de statut',
    'retirer' => 'Retrait du colis',
    'ticket' => 'Billet ${payload['numero_provisoire'] ?? ''}',
    'verif' => 'Vérification du billet ${payload['numero'] ?? ''}',
    'scan' =>
      payload['mode'] == 'embarquement' ? 'Embarquement' : 'Déchargement',
    _ => type,
  };

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'payload': payload,
    'created_at': createdAt.toIso8601String(),
    'erreur': erreur,
  };

  factory OutboxOp.fromJson(Map<String, dynamic> j) => OutboxOp(
    id: j['id'] as String,
    type: j['type'] as String,
    payload: Map<String, dynamic>.from(j['payload'] as Map),
    createdAt: DateTime.parse(j['created_at'] as String),
    erreur: j['erreur'] as String?,
  );
}

/// File d'attente persistante des opérations faites sans internet, et calcul de ce qu'elles
/// changent à l'écran (colis créés / statuts modifiés) en attendant la synchronisation.
class Outbox {
  static const _kOps = 'outbox';
  static const _kRejets = 'outbox_rejets';
  static const _kRefs = 'outbox_refs';

  /// Incrémenté à chaque modification de la file (le service de synchronisation l'écoute).
  static final changes = ValueNotifier<int>(0);

  static final _rnd = Random.secure();

  /// Identifiant unique (v4) généré sur l'appareil.
  static String nouvelleRef() {
    final b = List<int>.generate(16, (_) => _rnd.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// Numéro provisoire imprimé sur le reçu d'un colis créé hors ligne.
  static String provisoire(String ref) =>
      'LOC-${ref.replaceAll('-', '').substring(0, 8).toUpperCase()}';

  /// Identifiant local (toujours négatif, donc jamais confondu avec un vrai colis) dérivé de la référence.
  static int idLocal(String ref) =>
      -(int.parse(ref.replaceAll('-', '').substring(0, 7), radix: 16) + 1);

  static Future<List<OutboxOp>> _lire(String key) async {
    final raw = await LocalStore.read(key);
    if (raw is! List) return [];
    final out = <OutboxOp>[];
    for (final e in raw) {
      try {
        out.add(OutboxOp.fromJson(Map<String, dynamic>.from(e as Map)));
      } catch (_) {}
    }
    return out;
  }

  static Future<List<OutboxOp>> pending() => _lire(_kOps);
  static Future<List<OutboxOp>> rejected() => _lire(_kRejets);

  static Future<void> _ecrire(String key, List<OutboxOp> ops) =>
      LocalStore.write(key, ops.map((o) => o.toJson()).toList());

  static Future<OutboxOp> ajouter(
    String type,
    Map<String, dynamic> payload,
  ) async {
    final op = OutboxOp(
      id: nouvelleRef(),
      type: type,
      payload: payload,
      createdAt: DateTime.now(),
    );
    final ops = await pending();
    ops.add(op);
    await _ecrire(_kOps, ops);
    changes.value++;
    return op;
  }

  /// L'opération a été envoyée : on l'enlève de la file.
  static Future<void> terminer(String id) async {
    final ops = await pending();
    ops.removeWhere((o) => o.id == id);
    await _ecrire(_kOps, ops);
    changes.value++;
  }

  /// Le serveur a refusé l'opération : elle quitte la file mais reste visible pour l'utilisateur.
  static Future<void> rejeter(OutboxOp op, String message) async {
    final ops = await pending();
    ops.removeWhere((o) => o.id == op.id);
    await _ecrire(_kOps, ops);
    final rejets = await rejected();
    rejets.add(op.avecErreur(message));
    await _ecrire(_kRejets, rejets);
    changes.value++;
  }

  static Future<void> oublierRejet(String id) async {
    final rejets = await rejected();
    rejets.removeWhere((o) => o.id == id);
    await _ecrire(_kRejets, rejets);
    changes.value++;
  }

  /// Correspondance référence locale → vrai identifiant, une fois le colis créé sur le serveur.
  static Future<int?> idReel(String ref) async {
    final m = await LocalStore.read(_kRefs);
    return m is Map ? (m[ref] as num?)?.toInt() : null;
  }

  static Future<void> memoriserIdReel(String ref, int id) async {
    final m = await LocalStore.read(_kRefs);
    final map = m is Map ? Map<String, dynamic>.from(m) : <String, dynamic>{};
    map.remove(ref);
    map[ref] = id;
    while (map.length > 200) {
      map.remove(map.keys.first); // on ne garde que les plus récents
    }
    await LocalStore.write(_kRefs, map);
  }

  /// Vrai identifiant d'un colis dont on ne connaît que l'identifiant local (déjà envoyé depuis).
  static Future<int?> idReelPourLocal(int idLoc) async {
    final m = await LocalStore.read(_kRefs);
    if (m is! Map) return null;
    for (final e in m.entries) {
      if (idLocal(e.key as String) == idLoc) return (e.value as num).toInt();
    }
    return null;
  }

  /// Référence d'un colis créé hors ligne, retrouvée à partir de son identifiant local négatif.
  static Future<String?> refPourId(int idLoc) async {
    for (final o in await pending()) {
      if (o.type != 'creer') continue;
      final ref = o.payload['client_ref'] as String;
      if (idLocal(ref) == idLoc) return ref;
    }
    return null;
  }

  // ── Effet des opérations en attente sur l'affichage ──

  /// Colis tel qu'il apparaît localement juste après sa création hors ligne.
  static Colis colisLocal(
    Map<String, dynamic> data, {
    required Map<int, String> garesNoms,
    String? agentNom,
  }) {
    final ref = data['client_ref'] as String;
    final now = DateTime.now();
    return Colis(
      id: idLocal(ref),
      numero: data['numero_provisoire'] as String,
      expediteurNom: data['expediteur_nom'] as String,
      expediteurTelephone: data['expediteur_telephone'] as String,
      destinataireNom: data['destinataire_nom'] as String,
      destinataireTelephone: data['destinataire_telephone'] as String,
      gareDepartId: data['gare_depart_id'] as int,
      gareArriveeId: data['gare_arrivee_id'] as int,
      gareDepartNom: garesNoms[data['gare_depart_id']],
      gareArriveeNom: garesNoms[data['gare_arrivee_id']],
      description: data['description'] as String,
      nombre: data['nombre'] as int,
      poids: (data['poids'] as num?)?.toDouble(),
      valeur: (data['valeur'] as num?)?.toDouble(),
      prix: (data['prix'] as num).toDouble(),
      statut: 'enregistre',
      dateEnvoi: DateTime.parse(data['date_envoi'] as String),
      agentNom: agentNom,
      photo: data['photo'] as String?,
      notes: data['notes'] as String?,
      createdAt: now,
      enAttente: true,
      clientRef: ref,
    );
  }

  /// Billet tel qu'il apparaît localement juste après sa vente hors ligne.
  static Ticket ticketLocal(
    Map<String, dynamic> data, {
    required Map<int, String> garesNoms,
    String? vendeurNom,
    DateTime? createdAt,
  }) {
    final ref = data['client_ref'] as String;
    return Ticket(
      id: idLocal(ref),
      numero: data['numero_provisoire'] as String,
      clientNom: data['client_nom'] as String,
      clientTelephone: data['client_telephone'] as String,
      gareDepartId: data['gare_depart_id'] as int,
      gareArriveeId: data['gare_arrivee_id'] as int,
      gareDepartNom: garesNoms[data['gare_depart_id']],
      gareArriveeNom: garesNoms[data['gare_arrivee_id']],
      dateVoyage: DateTime.parse(data['date_voyage'] as String),
      heureDepart: data['heure_depart'] as String?,
      siege: data['siege'] as String?,
      prix: (data['prix'] as num).toDouble(),
      statut: 'emis',
      vendeurNom: vendeurNom,
      notes: data['notes'] as String?,
      createdAt: createdAt ?? DateTime.now(),
      clientRef: ref,
      enAttente: true,
    );
  }

  /// Ajoute à la liste des billets ceux vendus hors ligne et pas encore envoyés.
  static List<Ticket> appliquerTickets(
    List<Ticket> base,
    List<OutboxOp> ops, {
    Map<int, String> garesNoms = const {},
  }) {
    final liste = [...base];
    for (final op in ops.where((o) => o.type == 'ticket')) {
      final ref = op.payload['client_ref'] as String;
      if (liste.any((t) => t.clientRef == ref)) continue;
      liste.insert(
        0,
        ticketLocal(
          op.payload,
          garesNoms: garesNoms,
          vendeurNom: op.payload['_vendeur_nom'] as String?,
          createdAt: op.createdAt,
        ),
      );
    }
    return liste;
  }

  static bool _vise(Colis c, Map<String, dynamic> p) {
    final id = (p['id'] as num?)?.toInt();
    if (id != null && c.id == id) return true;
    final ref = p['ref'] as String?;
    return ref != null && c.clientRef == ref;
  }

  /// Applique les opérations en attente à une liste de colis (création, changements de statut, retraits, scans).
  static List<Colis> appliquer(
    List<Colis> base,
    List<OutboxOp> ops, {
    Map<int, String> garesNoms = const {},
  }) {
    if (ops.isEmpty) return base;
    final liste = [...base];
    for (final op in ops) {
      final p = op.payload;
      switch (op.type) {
        case 'creer':
          final data = Map<String, dynamic>.from(p);
          final ref = data['client_ref'] as String;
          if (liste.any((c) => c.clientRef == ref)) break;
          liste.insert(
            0,
            colisLocal(
              data,
              garesNoms: garesNoms,
              agentNom: p['_agent_nom'] as String?,
            ),
          );
        case 'statut':
          for (var i = 0; i < liste.length; i++) {
            if (_vise(liste[i], p)) {
              liste[i] = liste[i].copyWith(
                statut: p['statut'] as String,
                enAttente: true,
              );
            }
          }
        case 'retirer':
          for (var i = 0; i < liste.length; i++) {
            if (_vise(liste[i], p)) {
              liste[i] = liste[i].copyWith(
                statut: 'retire',
                retraitNom: p['nom'] as String?,
                retraitTelephone: p['telephone'] as String?,
                retraitPieceIdentite: p['piece'] as String?,
                retraitSignature: p['signature'] as String?,
                retraitDate: op.createdAt,
                enAttente: true,
              );
            }
          }
        case 'scan':
          final embarque = p['mode'] == 'embarquement';
          final numeros = List<String>.from(p['numeros'] as List);
          for (var i = 0; i < liste.length; i++) {
            if (!numeros.contains(liste[i].numero)) continue;
            final s = liste[i].statut;
            if (embarque && s == 'enregistre') {
              liste[i] = liste[i].copyWith(statut: 'charge', enAttente: true);
            } else if (!embarque && (s == 'charge' || s == 'en_route')) {
              liste[i] = liste[i].copyWith(statut: 'arrive', enAttente: true);
            }
          }
      }
    }
    return liste;
  }

  /// Ajoute à l'historique d'un colis les changements de statut encore en attente.
  static List<Historique> historiqueLocal(
    Colis? colis,
    List<Historique> base,
    List<OutboxOp> ops,
  ) {
    final liste = [...base];
    if (colis == null) return liste;
    var n = 0;
    for (final op in ops) {
      final p = op.payload;
      if (op.type == 'creer' && p['client_ref'] == colis.clientRef) {
        liste.add(
          Historique(
            id: --n,
            statut: 'enregistre',
            date: op.createdAt,
            notes: 'Enregistré hors ligne',
          ),
        );
      } else if ((op.type == 'statut' || op.type == 'retirer') &&
          _vise(colis, p)) {
        liste.add(
          Historique(
            id: --n,
            statut: op.type == 'retirer' ? 'retire' : p['statut'] as String,
            date: op.createdAt,
            notes: p['notes'] as String? ?? 'En attente d\'envoi',
          ),
        );
      }
    }
    return liste;
  }

  /// Recherche, filtres et tri appliqués localement (mêmes règles que la requête serveur).
  static List<Colis> filtrer(List<Colis> tous, ColisFilter f, {int? maGareId}) {
    final s = f.search.trim().toLowerCase();
    DateTime jour(DateTime d) => DateTime(d.year, d.month, d.day);
    final liste =
        tous.where((c) {
          if (f.statut != null && c.statut != f.statut) return false;
          final d = jour(c.dateEnvoi);
          if (f.debut != null && d.isBefore(jour(f.debut!))) return false;
          if (f.fin != null && d.isAfter(jour(f.fin!))) return false;
          if (maGareId != null &&
              f.direction == 'envoi' &&
              c.gareDepartId != maGareId)
            return false;
          if (maGareId != null &&
              f.direction == 'reception' &&
              c.gareArriveeId != maGareId)
            return false;
          if (s.isNotEmpty) {
            final champs = [
              c.numero,
              c.expediteurNom,
              c.destinataireNom,
              c.expediteurTelephone,
              c.destinataireTelephone,
            ];
            if (!champs.any((x) => x.toLowerCase().contains(s))) return false;
          }
          return true;
        }).toList()..sort(
          (a, b) => f.ancienFirst
              ? a.createdAt.compareTo(b.createdAt)
              : b.createdAt.compareTo(a.createdAt),
        );
    return liste.length > 500 ? liste.sublist(0, 500) : liste;
  }
}
