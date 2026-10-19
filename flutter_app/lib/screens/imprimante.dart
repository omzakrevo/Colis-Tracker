import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:printing/printing.dart';

import '../core/imprimante.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../widgets/common.dart';
import 'receipt.dart' show pdfTexte;

/// Réglage de l'imprimante à tickets de CET appareil : les reçus et billets partent directement dessus.
class ImprimanteScreen extends ConsumerStatefulWidget {
  const ImprimanteScreen({super.key});

  @override
  ConsumerState<ImprimanteScreen> createState() => _ImprimanteScreenState();
}

class _ImprimanteScreenState extends ConsumerState<ImprimanteScreen>
    with WidgetsBindingObserver {
  ImprimanteConfig _cfg = const ImprimanteConfig();
  List<BluetoothInfo> _bt = [];
  List<Printer> _sys = [];
  bool _charge = false, _recherche = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Imprimante.lire().then((c) {
      if (mounted) setState(() => _cfg = c);
      // Sur téléphone, la liste des imprimantes appairées s'affiche tout de suite.
      if (Imprimante.bluetoothPossible || Imprimante.systemePossible) _chercher();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Retour depuis les réglages Bluetooth du téléphone : on relit la liste (l'imprimante vient d'être appairée).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && Imprimante.bluetoothPossible && _ouvertReglages) {
      _ouvertReglages = false;
      _chercher();
    }
  }

  bool _ouvertReglages = false;

  Future<void> _ouvrirReglagesBluetooth() async {
    _ouvertReglages = true;
    try {
      await const AndroidIntent(action: 'android.settings.BLUETOOTH_SETTINGS').launch();
    } catch (_) {
      _ouvertReglages = false;
      if (mounted) {
        toast(context, 'Ouvrez les réglages Bluetooth du téléphone et appairez l\'imprimante.', error: true);
      }
    }
  }

  Future<void> _testerConnexion() => avecMessage(context, () async {
    await Imprimante.verifierConnexion();
    if (mounted) toast(context, 'Imprimante connectée');
  });

  Future<void> _chercher() async {
    setState(() {
      _recherche = true;
      _erreur = null;
    });
    try {
      if (Imprimante.bluetoothPossible) {
        _bt = await Imprimante.appareilsBluetooth();
      } else if (Imprimante.systemePossible) {
        _sys = await Imprimante.imprimantesSysteme();
      }
      _charge = true;
    } catch (e) {
      _erreur = errMsg(e);
    } finally {
      if (mounted) setState(() => _recherche = false);
    }
  }

  Future<void> _choisir(ImprimanteConfig c) async {
    await Imprimante.enregistrer(c);
    if (mounted) setState(() => _cfg = c);
  }

  Future<void> _tester() => avecMessage(context, () async {
    final co = ref.read(settingsProvider).value ?? CompanySettings.defaults;
    final ok = await Imprimante.imprimerDirect('Test', (format) async {
      final doc = pw.Document();
      doc.addPage(
        pw.Page(
          pageFormat: format.copyWith(
            marginLeft: 7,
            marginRight: 7,
            marginTop: 10,
            marginBottom: 10,
          ),
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                pdfTexte(co.nom.toUpperCase()),
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 6),
              pw.Text('Test d\'impression', style: const pw.TextStyle(fontSize: 11)),
              pw.SizedBox(height: 6),
              pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: 'TCHI-TEST',
                width: 80,
                height: 80,
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'Imprimante : ${pdfTexte(_cfg.nom)}',
                style: const pw.TextStyle(fontSize: 9),
              ),
            ],
          ),
        ),
      );
      return doc.save();
    });
    if (!ok && mounted) {
      toast(context, 'Choisissez d\'abord une imprimante.', error: true);
    } else if (mounted) {
      toast(context, 'Test envoyé à l\'imprimante');
    }
  });

  @override
  Widget build(BuildContext context) {
    final bt = Imprimante.bluetoothPossible;
    final sys = Imprimante.systemePossible;
    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        const PageHeader(
          'Imprimante',
          subtitle: 'Les tickets (reçus de colis et billets) s\'impriment directement, sans fenêtre.',
        ),
        SectionCard(
          title: 'Imprimante de cet appareil',
          icon: Icons.print_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_cfg.configuree)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A)),
                  title: Text(
                    _cfg.nom,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '${_cfg.type == 'bluetooth' ? 'Bluetooth' : 'Imprimante de l\'ordinateur'} · papier ${_cfg.largeurMm} mm',
                  ),
                  trailing: TextButton(
                    onPressed: () => _choisir(const ImprimanteConfig()),
                    child: const Text('Retirer'),
                  ),
                )
              else
                const Text(
                  'Aucune imprimante réglée : la fenêtre d\'impression s\'ouvre à chaque fois.',
                  style: TextStyle(color: Brand.muted),
                ),
              const SizedBox(height: 14),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 58, label: Text('Papier 58 mm')),
                  ButtonSegment(value: 80, label: Text('Papier 80 mm')),
                ],
                selected: {_cfg.largeurMm},
                onSelectionChanged: (s) => _choisir(
                  ImprimanteConfig(
                    type: _cfg.type,
                    nom: _cfg.nom,
                    adresse: _cfg.adresse,
                    largeurMm: s.first,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (bt || sys)
                    FilledButton.icon(
                      onPressed: _recherche ? null : _chercher,
                      icon: _recherche
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.search_rounded),
                      label: Text(bt ? 'Chercher les imprimantes Bluetooth' : 'Chercher les imprimantes'),
                    ),
                  if (bt)
                    OutlinedButton.icon(
                      onPressed: _ouvrirReglagesBluetooth,
                      icon: const Icon(Icons.bluetooth_searching_rounded),
                      label: const Text('Appairer une imprimante'),
                    ),
                  if (bt && _cfg.configuree)
                    OutlinedButton.icon(
                      onPressed: _testerConnexion,
                      icon: const Icon(Icons.bluetooth_connected_rounded),
                      label: const Text('Tester la connexion'),
                    ),
                  OutlinedButton.icon(
                    onPressed: _cfg.configuree ? _tester : null,
                    icon: const Icon(Icons.receipt_long_rounded),
                    label: const Text('Imprimer un test'),
                  ),
                ],
              ),
              if (!bt && !sys)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Sur le site web, l\'impression passe par la fenêtre du navigateur. '
                    'Pour imprimer directement, utilisez l\'application Android ou Windows.',
                    style: TextStyle(color: Brand.muted),
                  ),
                ),
              if (bt)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    '1) Allumez l\'imprimante (MS-B58A…). 2) Touchez « Appairer une imprimante » et choisissez-la '
                    'dans la liste (code 0000 ou 1234). 3) Revenez ici : elle apparaît dans « Appareils appairés », touchez-la.',
                    style: TextStyle(color: Brand.muted, fontSize: 13),
                  ),
                ),
              if (_erreur != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_erreur!, style: const TextStyle(color: Colors.red)),
                ),
            ],
          ),
        ),
        if (_charge && bt) ...[
          const SizedBox(height: 14),
          SectionCard(
            title: 'Appareils appairés',
            icon: Icons.bluetooth_rounded,
            child: _bt.isEmpty
                ? const Text('Aucun appareil appairé. Appairez d\'abord l\'imprimante dans les réglages Bluetooth.')
                : Column(
                    children: [
                      for (final b in _bt)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.print_rounded),
                          title: Text(b.name),
                          subtitle: Text(b.macAdress),
                          selected: _cfg.adresse == b.macAdress,
                          onTap: () => _choisir(
                            ImprimanteConfig(
                              type: 'bluetooth',
                              nom: b.name,
                              adresse: b.macAdress,
                              largeurMm: _cfg.largeurMm,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
        if (_charge && sys) ...[
          const SizedBox(height: 14),
          SectionCard(
            title: 'Imprimantes de l\'ordinateur',
            icon: Icons.computer_rounded,
            child: _sys.isEmpty
                ? const Text('Aucune imprimante installée sur cet ordinateur.')
                : Column(
                    children: [
                      for (final p in _sys)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.print_rounded),
                          title: Text(p.name),
                          selected: _cfg.adresse == p.url,
                          onTap: () => _choisir(
                            ImprimanteConfig(
                              type: 'systeme',
                              nom: p.name,
                              adresse: p.url,
                              largeurMm: _cfg.largeurMm,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ],
    );
  }
}
