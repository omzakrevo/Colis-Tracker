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

/// Réglage des deux imprimantes de CET appareil : tickets clients (papier simple) et étiquettes colis
/// (papier autocollant). Chacune s'imprime directement, sans fenêtre, et peut partir toute seule.
class ImprimanteScreen extends ConsumerStatefulWidget {
  const ImprimanteScreen({super.key});

  @override
  ConsumerState<ImprimanteScreen> createState() => _ImprimanteScreenState();
}

class _ImprimanteScreenState extends ConsumerState<ImprimanteScreen> with WidgetsBindingObserver {
  final _cfg = {for (final r in RoleImprimante.values) r: const ImprimanteConfig()};
  List<BluetoothInfo> _bt = [];
  List<Printer> _sys = [];
  bool _charge = false, _recherche = false, _ouvertReglages = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    () async {
      for (final r in RoleImprimante.values) {
        _cfg[r] = await Imprimante.lire(r);
      }
      if (!mounted) return;
      setState(() {});
      // Sur téléphone / ordinateur, la liste des imprimantes s'affiche tout de suite.
      if (Imprimante.bluetoothPossible || Imprimante.systemePossible) _chercher();
    }();
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

  Future<void> _choisir(RoleImprimante r, ImprimanteConfig c) async {
    await Imprimante.enregistrer(r, c);
    if (mounted) setState(() => _cfg[r] = c);
  }

  Future<void> _tester(RoleImprimante r) => avecMessage(context, () async {
    final co = ref.read(settingsProvider).value ?? CompanySettings.defaults;
    final c = _cfg[r]!;
    final ok = await Imprimante.imprimerDirect(r, 'Test', (format) async {
      final doc = pw.Document();
      doc.addPage(
        pw.Page(
          pageFormat: format.copyWith(marginLeft: 7, marginRight: 7, marginTop: 10, marginBottom: 14),
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                pdfTexte(co.nom.toUpperCase()),
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'TEST - ${pdfTexte(r.libelle.toUpperCase())}',
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 6),
              pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: 'TCHI-TEST', width: 80, height: 80),
              pw.SizedBox(height: 6),
              pw.Text(
                'Imprimante : ${pdfTexte(c.nom)}',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
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

  Future<void> _testerConnexion(RoleImprimante r) => avecMessage(context, () async {
    await Imprimante.verifierConnexion(r);
    if (mounted) toast(context, 'Imprimante connectée');
  });

  Widget _carte(RoleImprimante r, IconData icone, String aide) {
    final c = _cfg[r]!;
    final bt = Imprimante.bluetoothPossible;
    final sys = Imprimante.systemePossible;
    return SectionCard(
      title: '${r.libelle} · ${r.papier}',
      icon: icone,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(aide, style: const TextStyle(color: Brand.muted, fontSize: 13)),
          const SizedBox(height: 10),
          if (c.configuree)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A)),
              title: Text(c.nom, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(
                '${c.type == 'bluetooth' ? 'Bluetooth' : 'Imprimante de l\'ordinateur'} · papier ${c.largeurMm} mm',
              ),
              trailing: TextButton(
                onPressed: () => _choisir(r, const ImprimanteConfig()),
                child: const Text('Retirer'),
              ),
            )
          else
            const Text(
              'Aucune imprimante réglée : la fenêtre d\'impression s\'ouvre à chaque fois.',
              style: TextStyle(color: Brand.muted),
            ),
          const SizedBox(height: 10),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 58, label: Text('Papier 58 mm')),
              ButtonSegment(value: 80, label: Text('Papier 80 mm')),
            ],
            selected: {c.largeurMm},
            onSelectionChanged: (s) => _choisir(r, c.avec(largeurMm: s.first)),
          ),
          if (bt) ...[
            const SizedBox(height: 10),
            const Text(
              'Cadence d\'envoi — texte ou QR code décalés : essayez « Lente » ; si des bandes blanches apparaissent : « Rapide ».',
              style: TextStyle(fontSize: 13, color: Brand.muted),
            ),
            const SizedBox(height: 6),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Rapide')),
                ButtonSegment(value: 1, label: Text('Normale')),
                ButtonSegment(value: 2, label: Text('Lente')),
              ],
              selected: {c.vitesse},
              onSelectionChanged: (s) => _choisir(r, c.avec(vitesse: s.first)),
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: c.auto,
            onChanged: c.configuree ? (v) => _choisir(r, c.avec(auto: v)) : null,
            title: const Text('Imprimer automatiquement'),
            subtitle: Text(
              r == RoleImprimante.client
                  ? 'Dès l\'enregistrement d\'un colis ou d\'un billet'
                  : 'Dès l\'enregistrement d\'un colis',
            ),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (bt && c.configuree)
                OutlinedButton.icon(
                  onPressed: () => _testerConnexion(r),
                  icon: const Icon(Icons.bluetooth_connected_rounded),
                  label: const Text('Tester la connexion'),
                ),
              OutlinedButton.icon(
                onPressed: c.configuree ? () => _tester(r) : null,
                icon: const Icon(Icons.receipt_long_rounded),
                label: const Text('Imprimer un test'),
              ),
            ],
          ),
          if (_charge && bt) ...[
            const SizedBox(height: 10),
            Text('Choisir l\'imprimante :', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.grey.shade800)),
            if (_bt.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Aucun appareil appairé. Touchez « Appairer une imprimante » ci-dessus.'),
              ),
            for (final b in _bt)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.print_rounded),
                title: Text(b.name),
                subtitle: Text(b.macAdress),
                selected: c.adresse == b.macAdress,
                onTap: () => _choisir(
                  r,
                  ImprimanteConfig(
                    type: 'bluetooth',
                    nom: b.name,
                    adresse: b.macAdress,
                    largeurMm: c.largeurMm,
                    auto: c.auto,
                    vitesse: c.vitesse,
                  ),
                ),
              ),
          ],
          if (_charge && sys) ...[
            const SizedBox(height: 10),
            Text('Choisir l\'imprimante :', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.grey.shade800)),
            if (_sys.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Aucune imprimante installée sur cet ordinateur. Branchez-la (câble USB), installez son pilote '
                  'dans Windows (Paramètres > Imprimantes et scanners), puis touchez « Chercher les imprimantes ».',
                ),
              ),
            for (final p in _sys)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.print_rounded),
                title: Text(p.name),
                subtitle: Text(
                  [
                    if (p.isDefault) 'Imprimante par défaut de Windows',
                    if (!p.isAvailable) 'Hors ligne ou débranchée',
                    if ((p.model ?? '').isNotEmpty) p.model!,
                  ].join(' · '),
                ),
                trailing: c.adresse == p.url ? const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A)) : null,
                selected: c.adresse == p.url,
                onTap: () => _choisir(
                  r,
                  ImprimanteConfig(
                    type: 'systeme',
                    nom: p.name,
                    adresse: p.url,
                    largeurMm: c.largeurMm,
                    auto: c.auto,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bt = Imprimante.bluetoothPossible;
    final sys = Imprimante.systemePossible;
    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        const PageHeader(
          'Imprimantes',
          subtitle: 'Deux imprimantes : tickets clients et étiquettes à coller sur les colis.',
        ),
        SectionCard(
          title: 'Recherche',
          icon: Icons.search_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              if (sys)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Branchez l\'imprimante par câble (USB) et installez-la dans Windows : elle apparaît alors '
                    'dans la liste de chaque imprimante ci-dessous, où il suffit de la sélectionner.',
                    style: TextStyle(color: Brand.muted, fontSize: 13),
                  ),
                ),
              if (bt)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    '1) Allumez l\'imprimante. 2) Touchez « Appairer une imprimante » et choisissez-la dans la liste '
                    '(code 0000 ou 1234). 3) Revenez ici : elle apparaît dans la liste de chaque imprimante ci-dessous.',
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
        const SizedBox(height: 14),
        _carte(
          RoleImprimante.client,
          Icons.receipt_long_rounded,
          'Imprime le ticket de voyage et le ticket remis au client quand on enregistre un colis.',
        ),
        const SizedBox(height: 14),
        _carte(
          RoleImprimante.colis,
          Icons.label_rounded,
          'Imprime l\'étiquette autocollante à coller sur le colis. Si elle n\'est pas connectée, vous pourrez '
          'l\'imprimer plus tard depuis la fiche du colis.',
        ),
      ],
    );
  }
}
