import 'dart:convert';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Comment l'appareil imprime les tickets : 'aucune' (fenêtre d'impression), 'bluetooth' (imprimante à tickets
/// appairée, Android) ou 'systeme' (imprimante installée sur l'ordinateur).
class ImprimanteConfig {
  const ImprimanteConfig({
    this.type = 'aucune',
    this.nom = '',
    this.adresse = '',
    this.largeurMm = 58,
  });

  final String type, nom, adresse;

  /// Largeur du papier : 58 ou 80 mm.
  final int largeurMm;

  bool get configuree => type != 'aucune' && adresse.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'type': type,
    'nom': nom,
    'adresse': adresse,
    'largeur': largeurMm,
  };

  factory ImprimanteConfig.fromJson(Map<String, dynamic> j) => ImprimanteConfig(
    type: j['type'] as String? ?? 'aucune',
    nom: j['nom'] as String? ?? '',
    adresse: j['adresse'] as String? ?? '',
    largeurMm: (j['largeur'] as num?)?.toInt() ?? 58,
  );
}

class Imprimante {
  static const _cle = 'tchi_imprimante';

  /// Réglage propre à l'appareil (pas à l'utilisateur) : l'imprimante reste branchée au même téléphone.
  static Future<ImprimanteConfig> lire() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_cle);
      if (raw == null) return const ImprimanteConfig();
      return ImprimanteConfig.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return const ImprimanteConfig();
    }
  }

  static Future<void> enregistrer(ImprimanteConfig c) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_cle, jsonEncode(c.toJson()));
  }

  static bool get bluetoothPossible =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

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

  /// Imprimantes installées sur l'ordinateur.
  static Future<List<Printer>> imprimantesSysteme() async =>
      systemePossible ? await Printing.listPrinters() : <Printer>[];

  static PdfPageFormat _format(ImprimanteConfig c) =>
      PdfPageFormat(c.largeurMm * PdfPageFormat.mm, double.infinity);

  /// Imprime directement sur l'imprimante réglée, sans fenêtre d'impression.
  /// Renvoie `false` si aucune imprimante n'est réglée (l'appelant ouvre alors la fenêtre classique).
  static Future<bool> imprimerDirect(
    String nom,
    Future<Uint8List> Function(PdfPageFormat format) pdf,
  ) async {
    final c = await lire();
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

  /// Transforme la page PDF en image puis l'envoie en ESC/POS (le texte accentué s'imprime ainsi sans souci de police).
  static Future<void> _imprimerBluetooth(ImprimanteConfig c, Uint8List pdf) async {
    final points = c.largeurMm >= 80 ? 576 : 384;
    img.Image? page;
    await for (final r in Printing.raster(pdf, pages: [0], dpi: 300)) {
      page = img.decodePng(await r.toPng());
      break;
    }
    if (page == null) throw 'Le document n\'a pas pu être préparé pour l\'impression.';
    final image = img.grayscale(
      img.copyResize(page, width: points, interpolation: img.Interpolation.average),
    );

    final gen = Generator(
      c.largeurMm >= 80 ? PaperSize.mm80 : PaperSize.mm58,
      await CapabilityProfile.load(),
    );
    final octets = <int>[...gen.reset()];
    // Par tranches : les petites imprimantes ont une mémoire tampon limitée.
    const tranche = 160;
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

    if (!await PrintBluetoothThermal.connectionStatus) {
      final ok = await PrintBluetoothThermal.connect(macPrinterAddress: c.adresse);
      if (!ok) {
        throw 'Impossible de se connecter à « ${c.nom} ». Vérifiez qu\'elle est allumée, appairée et à portée.';
      }
    }
    // Envoi par morceaux pour ne pas saturer la liaison Bluetooth.
    const bloc = 4096;
    for (var i = 0; i < octets.length; i += bloc) {
      final fin = (i + bloc > octets.length) ? octets.length : i + bloc;
      final ok = await PrintBluetoothThermal.writeBytes(octets.sublist(i, fin));
      if (!ok) throw 'L\'envoi à l\'imprimante a échoué. Réessayez.';
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  }
}
