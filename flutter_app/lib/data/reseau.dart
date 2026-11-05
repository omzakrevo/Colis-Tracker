import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../core/identifiant.dart';

/// État du réseau, appris à l'usage : dès qu'un appel au serveur échoue (ou que le téléphone n'a plus de réseau),
/// l'application passe tout de suite en mode « hors ligne » : les formulaires s'enregistrent sur l'appareil sans
/// attendre la fin des délais d'attente, et une petite sonde vérifie régulièrement si le serveur répond de nouveau.
class Reseau {
  /// Vrai tant que le serveur répond.
  static final ValueNotifier<bool> enLigne = ValueNotifier(true);

  static bool get horsLigne => !enLigne.value;

  static final _retour = StreamController<void>.broadcast();

  /// Émet à chaque retour du serveur (sert à envoyer ce qui a été gardé sur l'appareil).
  static Stream<void> get retour => _retour.stream;

  static StreamSubscription<List<ConnectivityResult>>? _conn;
  static Timer? _sonde;
  static bool _demarre = false;

  /// À appeler une fois au lancement.
  static void demarrer() {
    if (_demarre) return;
    _demarre = true;
    _conn = Connectivity().onConnectivityChanged.listen((r) {
      if (r.contains(ConnectivityResult.none) || r.isEmpty) {
        echec();
      } else {
        // Réseau revenu : on vérifie que le serveur répond vraiment.
        _verifier();
      }
    });
    Connectivity()
        .checkConnectivity()
        .then((r) {
          if (r.contains(ConnectivityResult.none) || r.isEmpty) echec();
        })
        .catchError((_) {});
  }

  /// Un appel au serveur a réussi.
  static void succes() {
    if (enLigne.value) return;
    enLigne.value = true;
    _sonde?.cancel();
    _sonde = null;
    _retour.add(null);
  }

  /// Un appel au serveur a échoué faute de réseau.
  static void echec() {
    if (!enLigne.value) return;
    enLigne.value = false;
    _sonde?.cancel();
    _sonde = Timer.periodic(const Duration(seconds: 7), (_) => _verifier());
  }

  /// Sert à ne pas lancer un appel inutile quand on sait déjà que le serveur ne répond pas.
  static void exiger() {
    if (horsLigne) throw TimeoutException('Hors ligne');
  }

  static bool _enCours = false;

  static Future<void> _verifier() async {
    if (_enCours || !AppConfig.isConfigured) return;
    _enCours = true;
    try {
      // N'importe quelle réponse HTTP (même un refus) prouve que le serveur est joignable.
      await http
          .get(
            Uri.parse('${AppConfig.supabaseUrl}/auth/v1/health'),
            headers: {'apikey': AppConfig.supabaseAnonKey},
          )
          .timeout(const Duration(seconds: 4));
      succes();
    } catch (_) {
      if (enLigne.value) echec();
    } finally {
      _enCours = false;
    }
  }

  static Future<void> arreter() async {
    await _conn?.cancel();
    _sonde?.cancel();
    _demarre = false;
  }
}

/// Appel au serveur avec délai court ; mémorise s'il a répondu ou non pour accélérer les appels suivants.
extension AppelReseau<T> on Future<T> {
  Future<T> reseau(Duration delai) async {
    if (Reseau.horsLigne) {
      // L'appel est déjà parti : on ignore son résultat tardif.
      unawaited(then<void>((_) {}, onError: (_) {}));
      throw TimeoutException('Hors ligne');
    }
    try {
      final v = await timeout(delai);
      Reseau.succes();
      return v;
    } catch (e) {
      if (estErreurReseau(e)) Reseau.echec();
      rethrow;
    }
  }
}
