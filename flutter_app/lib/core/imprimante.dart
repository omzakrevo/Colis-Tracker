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
    this.vitesse = 0,
  });

  final String type, nom, adresse;

  /// Largeur du papier : 58 ou 80 mm.
  final int largeurMm;

  /// Imprime tout seul dès l'enregistrement d'un colis ou d'un billet.
  final bool auto;

  /// Vitesse d'envoi Bluetooth : 0 normale, 1 lente, 2 très lente (à choisir si l'impression est décalée).
  final int vitesse;

  /// Octets envoyés d'un coup à l'imprimante selon la vitesse (les petites imprimantes perdent des octets
  /// quand on leur en envoie plus vite qu'elles n'impriment : l'image se décale).
  int get octetsParEnvoi => const [256, 128, 64][vitesse.clamp(0, 2)];

  bool get configuree => type != 'aucune' && adresse.isNotEmpty;

  ImprimanteConfig avec({int? largeurMm, bool? auto, int? vitesse}) => ImprimanteConfig(
    type: type,
    nom: nom,
    adresse: adresse,
    largeurMm: largeurMm ?? this.largeurMm,
    auto: auto ?? this.auto,
    vitesse: vitesse ?? this.vitesse,
  );

  Map<String, dynamic> toJson() => {
    'type': type,
    'nom': nom,
    'adresse': adresse,
    'largeur': largeurMm,
    'auto': auto,
    'vitesse': vitesse,
  };

  factory ImprimanteConfig.fromJson(Map<String, dynamic> j) => ImprimanteConfig(
    type: j['type'] as String? ?? 'aucune',
    nom: j['nom'] as String? ?? '',
    adresse: j['adresse'] as String? ?? '',
    largeurMm: (j['largeur'] as num?)?.toInt() ?? 58,
    auto: j['auto'] as bool? ?? true,
    vitesse: (j['vitesse'] as num?)?.toInt() ?? 0,
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
    Future<Uint8List> Function(PdfPageFormat format) pdf,
  ) async {
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
      await _imprimerBluetooth(c, await pdf(_format(c)));
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
    final octets = <int>[...gen.reset()];
    // Par tranches : les petites imprimantes ont une mémoire tampon limitée.
    const tranche = 24; // lignes par commande raster : petites, donc faciles à avaler pour l'imprimante
    for (var y = 0; y < image.height; y += tranche) {
      final h = (y + tranche > image.height) ? image.height - y : tranche;
      octets.addAll(
        gen.imageRaster(
          img.copyCrop(image, x: 0, y: y, width: image.width, height: h),
          align: PosAlign.left,
        ),
      );
    }
    octets.addAll(gen.feed(4));

    await _connecter(c);
    // Envoi par petits morceaux, plus lentement que l'imprimante n'imprime : sinon sa mémoire déborde,
    // des octets se perdent et les lignes (texte, QR code) se décalent.
    final bloc = c.octetsParEnvoi;
    for (var i = 0; i < octets.length; i += bloc) {
      final fin = (i + bloc > octets.length) ? octets.length : i + bloc;
      final ok = await PrintBluetoothThermal.writeBytes(octets.sublist(i, fin));
      if (!ok) {
        _macConnectee = null;
        throw 'L\'envoi à l\'imprimante a échoué. Réessayez.';
      }
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
  }
}
