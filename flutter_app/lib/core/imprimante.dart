import 'dart:convert';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Les deux imprimantes de l'appareil : « client » (papier simple : tickets de voyage et tickets remis au client)
/// et « colis » (papier autocollant : étiquettes à coller sur les colis).
enum RoleImprimante {
  client('client', 'Tickets clients', 'papier simple'),
  colis('colis', 'Étiquettes colis', 'papier autocollant');

  const RoleImprimante(this.code, this.libelle, this.papier);
  final String code, libelle, papier;
}

/// Comment l'appareil imprime pour un rôle : 'aucune' (fenêtre d'impression), 'bluetooth' (imprimante à tickets
/// appairée, Android) ou 'systeme' (imprimante installée sur l'ordinateur).
class ImprimanteConfig {
  const ImprimanteConfig({
    this.type = 'aucune',
    this.nom = '',
    this.adresse = '',
    this.largeurMm = 58,
    this.auto = true,
    this.vitesse = 1,
    this.mode = 2,
  });

  final String type, nom, adresse;

  /// Largeur du papier : 58 ou 80 mm.
  final int largeurMm;

  /// Imprime tout seul dès l'enregistrement d'un colis ou d'un billet.
  final bool auto;

  /// Cadence d'envoi Bluetooth : 0 rapide, 1 normale, 2 lente. Chaque bloc d'image est envoyé d'un seul coup
  /// (les petites imprimantes abandonnent un bloc s'il arrive au compte-gouttes), puis on attend le temps
  /// qu'elle l'imprime avant d'envoyer le suivant (sinon sa mémoire déborde et les lignes se décalent).
  final int vitesse;

  /// Façon d'imprimer en Bluetooth : 2 « texte » (polices et QR code de l'imprimante : quelques centaines d'octets,
  /// le plus fiable), 0 « colonnes » (image en lignes de 24 points ESC *), 1 « raster » (image en blocs GS v 0).
  /// Les modes image envoient ~50 Ko : les petites imprimantes n'arrivent pas à suivre (bandes blanches).
  final int mode;

  /// Attente (en ms) par ligne d'image imprimée entre deux blocs.
  double get msParLigne => const [0.8, 1.3, 1.8][vitesse.clamp(0, 2)];

  bool get configuree => type != 'aucune' && adresse.isNotEmpty;

  ImprimanteConfig avec({int? largeurMm, bool? auto, int? vitesse, int? mode}) => ImprimanteConfig(
    type: type,
    nom: nom,
    adresse: adresse,
    largeurMm: largeurMm ?? this.largeurMm,
    auto: auto ?? this.auto,
    vitesse: vitesse ?? this.vitesse,
    mode: mode ?? this.mode,
  );

  Map<String, dynamic> toJson() => {
    'type': type,
    'nom': nom,
    'adresse': adresse,
    'largeur': largeurMm,
    'auto': auto,
    'debit': vitesse,
    'format': mode,
  };

  factory ImprimanteConfig.fromJson(Map<String, dynamic> j) => ImprimanteConfig(
    type: j['type'] as String? ?? 'aucune',
    nom: j['nom'] as String? ?? '',
    adresse: j['adresse'] as String? ?? '',
    largeurMm: (j['largeur'] as num?)?.toInt() ?? 58,
    auto: j['auto'] as bool? ?? true,
    vitesse: (j['debit'] as num?)?.toInt() ?? 1,
    mode: (j['format'] as num?)?.toInt() ?? 2,
  );
}

/// Convertit une page rendue (RGBA, souvent à fond TRANSPARENT) en image noir et blanc pure pour l'imprimante.
/// Les pixels transparents sont posés sur du blanc : sans cela, ils étaient lus comme du noir et toute la
/// feuille sortait noire.
img.Image versNoirEtBlanc(img.Image source, {int seuil = 165}) {
  final sortie = img.Image(width: source.width, height: source.height, numChannels: 3);
  img.fill(sortie, color: img.ColorRgb8(255, 255, 255));
  final noir = img.ColorRgb8(0, 0, 0);
  for (final p in source) {
    final max = p.maxChannelValue;
    final a = source.hasAlpha ? p.a / max : 1.0;
    final lum = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b) / max; // 0 noir … 1 blanc
    final v = lum * a + (1 - a); // pose sur fond blanc
    if (v * 255 < seuil) sortie.setPixel(p.x, p.y, noir);
  }
  return sortie;
}

class Imprimante {
  static String _cle(RoleImprimante r) => 'tchi_imprimante_${r.code}';

  /// Réglage propre à l'appareil (pas à l'utilisateur) : les imprimantes restent branchées au même téléphone.
  static Future<ImprimanteConfig> lire(RoleImprimante role) async {
    try {
      final p = await SharedPreferences.getInstance();
      // Ancienne version : une seule imprimante, reprise comme imprimante « clients ».
      final raw = p.getString(_cle(role)) ?? (role == RoleImprimante.client ? p.getString('tchi_imprimante') : null);
      if (raw == null) return const ImprimanteConfig();
      return ImprimanteConfig.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return const ImprimanteConfig();
    }
  }

  static Future<void> enregistrer(RoleImprimante role, ImprimanteConfig c) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_cle(role), jsonEncode(c.toJson()));
  }

  static bool get bluetoothPossible => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get systemePossible =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  /// Imprimantes Bluetooth déjà appairées dans les réglages du téléphone.
  static Future<List<BluetoothInfo>> appareilsBluetooth() async {
    if (!bluetoothPossible) return [];
    if (!await PrintBluetoothThermal.isPermissionBluetoothGranted) {
      // la demande d'autorisation s'affiche lors du premier accès
      await PrintBluetoothThermal.pairedBluetooths;
      if (!await PrintBluetoothThermal.isPermissionBluetoothGranted) {
        throw 'Autorisez l\'accès au Bluetooth pour Tchi dans les réglages du téléphone.';
      }
    }
    if (!await PrintBluetoothThermal.bluetoothEnabled) {
      throw 'Activez le Bluetooth du téléphone.';
    }
    return PrintBluetoothThermal.pairedBluetooths;
  }

  /// Vérifie que l'imprimante Bluetooth réglée pour ce rôle répond (allumée, appairée, à portée).
  static Future<void> verifierConnexion(RoleImprimante role) async {
    final c = await lire(role);
    if (c.type != 'bluetooth' || !c.configuree) {
      throw 'Aucune imprimante Bluetooth n\'est réglée.';
    }
    await _connecter(c);
  }

  /// Imprimantes installées sur l'ordinateur.
  static Future<List<Printer>> imprimantesSysteme() async =>
      systemePossible ? await Printing.listPrinters() : <Printer>[];

  static PdfPageFormat _format(ImprimanteConfig c) =>
      PdfPageFormat(c.largeurMm * PdfPageFormat.mm, double.infinity);

  /// Imprime directement sur l'imprimante réglée pour ce rôle, sans fenêtre d'impression.
  /// Renvoie `false` si aucune imprimante n'est réglée (l'appelant ouvre alors la fenêtre classique).
  static Future<bool> imprimerDirect(
    RoleImprimante role,
    String nom,
    Future<Uint8List> Function(PdfPageFormat format) pdf, {
    List<int> Function(Generator g, int colonnes)? texte,
  }) async {
    final c = await lire(role);
    if (!c.configuree) return false;
    if (c.type == 'systeme' && systemePossible) {
      final ok = await Printing.directPrintPdf(
        printer: Printer(url: c.adresse, name: c.nom),
        name: nom,
        format: _format(c),
        onLayout: pdf,
      );
      if (!ok) throw 'L\'impression sur « ${c.nom} » a échoué.';
      return true;
    }
    if (c.type == 'bluetooth' && bluetoothPossible) {
      if (c.mode == 2 && texte != null) {
        await _imprimerTexte(c, texte);
      } else {
        await _imprimerBluetooth(c, await pdf(_format(c)));
      }
      return true;
    }
    return false;
  }

  /// Adresse de l'imprimante Bluetooth actuellement connectée (le téléphone n'en tient qu'une à la fois).
  static String? _macConnectee;

  static Future<void> _connecter(ImprimanteConfig c) async {
    if (_macConnectee == c.adresse && await PrintBluetoothThermal.connectionStatus) return;
    // Autre imprimante (ou liaison perdue) : on ferme la liaison actuelle avant d'ouvrir la bonne.
    try {
      await PrintBluetoothThermal.disconnect;
    } catch (_) {}
    _macConnectee = null;
    final ok = await PrintBluetoothThermal.connect(macPrinterAddress: c.adresse);
    if (!ok) {
      throw 'Impossible de se connecter à « ${c.nom} ». Vérifiez qu\'elle est allumée, appairée et à portée.';
    }
    _macConnectee = c.adresse;
  }

  /// Mode texte : l'imprimante imprime elle-même texte et QR code (très peu de données à envoyer).
  static Future<void> _imprimerTexte(
    ImprimanteConfig c,
    List<int> Function(Generator g, int colonnes) texte,
  ) async {
    final gen = Generator(
      c.largeurMm >= 80 ? PaperSize.mm80 : PaperSize.mm58,
      await CapabilityProfile.load(),
    );
    final octets = <int>[...gen.reset(), ...texte(gen, c.largeurMm >= 80 ? 48 : 32)];
    await _connecter(c);
    // Petits envois ; ces imprimantes avalent sans souci quelques centaines d'octets.
    const bloc = 512;
    for (var i = 0; i < octets.length; i += bloc) {
      final fin = (i + bloc > octets.length) ? octets.length : i + bloc;
      final ok = await PrintBluetoothThermal.writeBytes(octets.sublist(i, fin));
      if (!ok) {
        _macConnectee = null;
        throw 'L\'envoi à l\'imprimante a échoué. Réessayez.';
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  /// Transforme la page PDF en image puis l'envoie en ESC/POS (le texte accentué s'imprime ainsi sans souci de police).
  static Future<void> _imprimerBluetooth(ImprimanteConfig c, Uint8List pdf) async {
    final points = c.largeurMm >= 80 ? 576 : 384;
    img.Image? page;
    await for (final r in Printing.raster(pdf, pages: [0], dpi: 300)) {
      page = img.decodePng(await r.toPng());
      break;
    }
    if (page == null) throw 'Le document n\'a pas pu être préparé pour l\'impression.';
    final image = versNoirEtBlanc(
      img.copyResize(page, width: points, interpolation: img.Interpolation.average),
    );

    final gen = Generator(
      c.largeurMm >= 80 ? PaperSize.mm80 : PaperSize.mm58,
      await CapabilityProfile.load(),
    );

    await _connecter(c);
    Future<void> envoyer(List<int> octets) async {
      final ok = await PrintBluetoothThermal.writeBytes(octets);
      if (!ok) {
        _macConnectee = null;
        throw 'L\'envoi à l\'imprimante a échoué. Réessayez.';
      }
    }

    await envoyer(gen.reset());
    // Mode « colonnes » (ESC *) : lignes de 24 points ; mode « raster » (GS v 0) : blocs de 96 lignes.
    // Chaque commande part d'un seul coup (une commande coupée en morceaux espacés est abandonnée par ces
    // imprimantes), et on regroupe ~96 lignes par envoi puis on attend le temps de les imprimer.
    final colonnes = c.mode == 0;
    final tranche = colonnes ? 24 : 96;
    var groupe = <int>[];
    var lignesGroupe = 0;
    Future<void> vider() async {
      if (groupe.isEmpty) return;
      final debut = DateTime.now();
      await envoyer(groupe);
      final attente = (lignesGroupe * c.msParLigne).round() - DateTime.now().difference(debut).inMilliseconds;
      if (attente > 0) await Future<void>.delayed(Duration(milliseconds: attente));
      groupe = <int>[];
      lignesGroupe = 0;
    }

    for (var y = 0; y < image.height; y += tranche) {
      final h = (y + tranche > image.height) ? image.height - y : tranche;
      final part = img.copyCrop(image, x: 0, y: y, width: image.width, height: h);
      groupe.addAll(colonnes ? gen.image(part, align: PosAlign.left) : gen.imageRaster(part, align: PosAlign.left));
      lignesGroupe += h;
      if (lignesGroupe >= 96) await vider();
    }
    await vider();
    await envoyer(gen.feed(4));
  }
}
