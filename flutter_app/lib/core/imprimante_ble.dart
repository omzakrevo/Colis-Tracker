import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:image/image.dart' as img;

/// Imprimante découverte en Bluetooth basse consommation (BLE).
class AppareilBle {
  AppareilBle(this.id, this.nom, this.signal);
  final String id, nom;
  final int signal;

  /// Les mini-imprimantes « chat » (MXW01…) s'annoncent avec ce genre de nom.
  bool get probableImprimante {
    final n = nom.toUpperCase();
    return n.startsWith('MXW') || n.startsWith('MX') || n.contains('PRINT') || n.contains('POS') || n.contains('CAT');
  }
}

/// État de l'imprimante « chat » renvoyé par la commande « statut ».
class StatutChat {
  StatutChat(this.batterie, this.temperature, this.ok, this.detail);
  final int batterie, temperature;
  final bool ok;
  final String detail;

  String get resume => ok ? 'Prête · batterie $batterie %' : '$detail · batterie $batterie %';
}

/// Impression en Bluetooth basse consommation, directement depuis l'application (sans passer par les réglages
/// Bluetooth du téléphone).
///
/// Deux familles d'imprimantes :
///  - « chat » (MXW01, service AE30) : protocole propre au fabricant, image de 384 points en 1 bit par point ;
///  - « escpos » : imprimantes BLE ordinaires qui acceptent les commandes ESC/POS sur une caractéristique d'écriture.
class ImprimanteBle {
  static final _service = Guid('AE30');
  static final _carCommande = Guid('AE01');
  static final _carNotif = Guid('AE02');
  static final _carDonnees = Guid('AE03');

  /// Largeur de l'imprimante « chat » : 384 points = 48 octets par ligne.
  static const pointsParLigne = 384;
  static const octetsParLigne = pointsParLigne ~/ 8;

  static BluetoothDevice? _appareil;
  static BluetoothCharacteristic? _commande, _donnees, _ecriture;
  static StreamSubscription<List<int>>? _abonnement;
  static final Map<int, Completer<List<int>>> _attentes = {};
  static String _protocole = '';

  // ── Commandes du protocole « chat » ──

  static final List<int> _tableCrc = () {
    final t = List<int>.filled(256, 0);
    for (var i = 0; i < 256; i++) {
      var c = i;
      for (var b = 0; b < 8; b++) {
        c = (c & 0x80) != 0 ? ((c << 1) ^ 0x07) & 0xFF : (c << 1) & 0xFF;
      }
      t[i] = c;
    }
    return t;
  }();

  static int crc8(List<int> donnees) {
    var crc = 0;
    for (final d in donnees) {
      crc = _tableCrc[crc ^ (d & 0xFF)];
    }
    return crc;
  }

  /// Trame : 22 21 · commande · 00 · taille (2 octets, petit-boutiste) · données · CRC8 des données · FF.
  static Uint8List commande(int id, List<int> donnees) => Uint8List.fromList([
    0x22, 0x21, id, 0x00, donnees.length & 0xFF, (donnees.length >> 8) & 0xFF,
    ...donnees,
    crc8(donnees), 0xFF,
  ]);

  /// Image noir et blanc de 384 points de large → lignes de 48 octets (bit de poids faible = point de gauche, 1 = noir).
  static List<Uint8List> lignes(img.Image image) {
    final sortie = <Uint8List>[];
    for (var y = 0; y < image.height; y++) {
      final l = Uint8List(octetsParLigne);
      for (var x = 0; x < pointsParLigne && x < image.width; x++) {
        final p = image.getPixel(x, y);
        if (p.r < 128) l[x >> 3] |= 1 << (x & 7);
      }
      sortie.add(l);
    }
    return sortie;
  }

  // ── Recherche et connexion ──

  /// Cherche les appareils BLE à proximité (quelques secondes).
  static Future<List<AppareilBle>> chercher({Duration duree = const Duration(seconds: 8)}) async {
    if (!await FlutterBluePlus.isSupported) throw 'Ce téléphone ne gère pas le Bluetooth basse consommation.';
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (_) {
        throw 'Activez le Bluetooth du téléphone.';
      }
    }
    final trouves = <String, AppareilBle>{};
    final abo = FlutterBluePlus.scanResults.listen((liste) {
      for (final r in liste) {
        final nom = r.advertisementData.advName.isNotEmpty ? r.advertisementData.advName : r.device.platformName;
        if (nom.isEmpty) continue;
        trouves[r.device.remoteId.str] = AppareilBle(r.device.remoteId.str, nom, r.rssi);
      }
    });
    try {
      await FlutterBluePlus.startScan(timeout: duree);
      await FlutterBluePlus.isScanning.where((e) => !e).first;
    } finally {
      await abo.cancel();
    }
    final l = trouves.values.toList()
      ..sort((a, b) {
        if (a.probableImprimante != b.probableImprimante) return a.probableImprimante ? -1 : 1;
        return b.signal.compareTo(a.signal);
      });
    return l;
  }

  static const _servicesSansEcriture = {'1800', '1801', '180A', '180F'};

  /// Se connecte (ou réutilise la connexion) et renvoie la famille de l'imprimante : « chat » ou « escpos ».
  static Future<String> connecter(String id) async {
    if (_appareil != null && _appareil!.remoteId.str == id && _appareil!.isConnected && _protocole.isNotEmpty) {
      return _protocole;
    }
    await deconnecter();
    final d = BluetoothDevice.fromId(id);
    try {
      await d.connect(timeout: const Duration(seconds: 20), mtu: 512);
      final services = await d.discoverServices();
      BluetoothService? chat;
      for (final s in services) {
        if (s.serviceUuid == _service) chat = s;
      }
      if (chat != null) {
        BluetoothCharacteristic? cmd, notif, don;
        for (final c in chat.characteristics) {
          if (c.characteristicUuid == _carCommande) cmd = c;
          if (c.characteristicUuid == _carNotif) notif = c;
          if (c.characteristicUuid == _carDonnees) don = c;
        }
        if (cmd == null || notif == null || don == null) {
          throw 'Cette imprimante n\'a pas les canaux attendus (AE01, AE02, AE03).';
        }
        _commande = cmd;
        _donnees = don;
        await notif.setNotifyValue(true);
        _abonnement = notif.onValueReceived.listen(_recu);
        _protocole = 'chat';
      } else {
        BluetoothCharacteristic? choix;
        for (final s in services) {
          if (_servicesSansEcriture.contains(s.serviceUuid.str.toUpperCase())) continue;
          for (final c in s.characteristics) {
            if (c.properties.writeWithoutResponse || c.properties.write) {
              // On préfère l'écriture sans réponse (plus rapide).
              if (choix == null || (c.properties.writeWithoutResponse && !choix.properties.writeWithoutResponse)) choix = c;
            }
          }
        }
        if (choix == null) throw 'Aucun canal d\'écriture trouvé sur cet appareil : ce n\'est probablement pas une imprimante.';
        _ecriture = choix;
        _protocole = 'escpos';
      }
      _appareil = d;
      return _protocole;
    } catch (e) {
      try {
        await d.disconnect();
      } catch (_) {}
      _reinitialiser();
      if (e is String) rethrow;
      throw 'Connexion impossible. Vérifiez que l\'imprimante est allumée et proche, fermez l\'application du fabricant '
          '(« Fun print ») qui garde la connexion, éteignez puis rallumez l\'imprimante, et réessayez.';
    }
  }

  static void _reinitialiser() {
    _abonnement?.cancel();
    _abonnement = null;
    _appareil = null;
    _commande = _donnees = _ecriture = null;
    _protocole = '';
    for (final a in _attentes.values) {
      if (!a.isCompleted) a.completeError('Connexion perdue avec l\'imprimante.');
    }
    _attentes.clear();
  }

  static Future<void> deconnecter() async {
    final d = _appareil;
    _reinitialiser();
    try {
      await d?.disconnect();
    } catch (_) {}
  }

  // ── Imprimante « chat » ──

  static void _recu(List<int> v) {
    if (v.length < 7 || v[0] != 0x22 || v[1] != 0x21) return;
    final a = _attentes.remove(v[2]);
    if (a != null && !a.isCompleted) a.complete(v);
  }

  static Future<void> _envoyer(int id, List<int> donnees) async {
    await _commande!.write(commande(id, donnees), withoutResponse: true);
  }

  static Future<List<int>> _demander(int id, List<int> donnees, {Duration delai = const Duration(seconds: 10)}) async {
    final c = Completer<List<int>>();
    _attentes[id] = c;
    await _envoyer(id, donnees);
    return c.future.timeout(delai, onTimeout: () {
      _attentes.remove(id);
      throw 'L\'imprimante ne répond pas. Éteignez-la, rallumez-la et réessayez.';
    });
  }

  /// Batterie, température, papier…
  static Future<StatutChat> statut() async {
    final v = await _demander(0xA1, [0]);
    final ok = v.length > 12 ? v[12] == 0 : true;
    var detail = 'Prête';
    if (!ok && v.length > 13) {
      detail = switch (v[13]) {
        0x01 || 0x09 => 'Plus de papier',
        0x04 => 'Trop chaude',
        0x08 => 'Batterie faible',
        _ => 'Erreur',
      };
    }
    return StatutChat(v.length > 9 ? v[9] : 0, v.length > 10 ? v[10] : 0, ok, detail);
  }

  /// Imprime une image noir et blanc de 384 points de large.
  /// [intensite] 0 à 100 (noirceur) ; [pauseMs] pause entre deux lignes (0 = le plus rapide).
  static Future<void> imprimerChat(img.Image image, {int intensite = 80, int pauseMs = 0}) async {
    final l = lignes(image);
    if (l.isEmpty) return;
    if (l.length > 60000) throw 'L\'étiquette est trop longue pour l\'imprimante.';
    final s = await statut();
    if (!s.ok) throw 'Imprimante : ${s.detail.toLowerCase()}.';

    await _envoyer(0xA2, [intensite.clamp(0, 100)]);
    final n = l.length;
    final rep = await _demander(0xA9, [n & 0xFF, (n >> 8) & 0xFF, 0x30, 0x00]);
    if (rep.length > 6 && rep[6] != 0) throw 'L\'imprimante a refusé l\'impression (papier, batterie ou couvercle ?).';

    final fin = Completer<List<int>>();
    _attentes[0xAA] = fin;
    final maxOctets = (_appareil!.mtuNow - 3).clamp(20, octetsParLigne);
    for (var i = 0; i < n; i++) {
      final ligne = l[i];
      for (var o = 0; o < ligne.length; o += maxOctets) {
        final f = o + maxOctets > ligne.length ? ligne.length : o + maxOctets;
        await _donnees!.write(ligne.sublist(o, f), withoutResponse: true);
      }
      if (pauseMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: pauseMs));
      } else if (i % 8 == 7) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    await _envoyer(0xAD, [0]);
    await fin.future.timeout(Duration(seconds: 20 + n ~/ 20), onTimeout: () {
      _attentes.remove(0xAA);
      throw 'L\'impression ne se termine pas. Vérifiez le papier et réessayez.';
    });
  }

  // ── Imprimantes BLE ESC/POS ──

  /// Envoie des octets bruts (ESC/POS) par petits blocs ; [pauseMs] entre deux blocs.
  static Future<void> ecrire(List<int> octets, {int pauseMs = 0}) async {
    final c = _ecriture;
    if (c == null || _appareil == null) throw 'Imprimante non connectée.';
    final taille = (_appareil!.mtuNow - 3).clamp(20, 240);
    final sans = c.properties.writeWithoutResponse;
    for (var i = 0; i < octets.length; i += taille) {
      final f = i + taille > octets.length ? octets.length : i + taille;
      await c.write(octets.sublist(i, f), withoutResponse: sans);
      if (pauseMs > 0) await Future<void>.delayed(Duration(milliseconds: pauseMs));
    }
  }
}
