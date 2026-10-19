import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../data/repo.dart';
import '../widgets/common.dart';

/// Vérification (facultative) des billets à l'embarquement : on scanne le QR code du billet, autant de fois
/// que nécessaire. Fonctionne sans internet grâce à la copie des billets gardée sur le téléphone.
class BilletVerifScreen extends ConsumerStatefulWidget {
  const BilletVerifScreen({super.key});

  @override
  ConsumerState<BilletVerifScreen> createState() => _BilletVerifScreenState();
}

class _BilletVerifScreenState extends ConsumerState<BilletVerifScreen> {
  final _ctl = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  final _manual = TextEditingController();
  VerifResultat? _res;
  String? _numero;
  bool _busy = false;
  String? _lastCode;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    // Met à jour la copie des billets dès l'ouverture (si le réseau est là).
    Repo.rafraichirBilletsAVerifier();
  }

  @override
  void dispose() {
    _ctl.dispose();
    _manual.dispose();
    super.dispose();
  }

  Future<void> _verifier(String raw, {bool camera = false}) async {
    final numero = raw.trim().toUpperCase();
    if (numero.isEmpty || _busy) return;
    final now = DateTime.now();
    if (camera && numero == _lastCode && now.difference(_lastAt).inMilliseconds < 3000) return;
    _lastCode = numero;
    _lastAt = now;
    setState(() => _busy = true);
    try {
      final r = await Repo.verifierBillet(numero);
      if (!mounted) return;
      final b = r.billet;
      if (b == null || b.annule) {
        HapticFeedback.heavyImpact();
      } else {
        HapticFeedback.mediumImpact();
      }
      setState(() {
        _res = r;
        _numero = numero;
      });
      if (b != null) ref.read(tickProvider.notifier).bump();
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final camera = ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _ctl,
            onDetect: (cap) {
              final v = cap.barcodes.firstOrNull?.rawValue;
              if (v != null) _verifier(v, camera: true);
            },
            errorBuilder: (_, _) => Container(
              color: Brand.emerald,
              padding: const EdgeInsets.all(24),
              alignment: Alignment.center,
              child: const Text(
                'Caméra indisponible.\nAutorisez l\'accès ou saisissez le numéro.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
          Center(
            child: FractionallySizedBox(
              widthFactor: .6,
              heightFactor: .6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Brand.orange, width: 3),
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
          if (_busy)
            Container(
              color: Colors.black38,
              child: const Center(child: CircularProgressIndicator(color: Colors.white)),
            ),
        ],
      ),
    );

    final panneau = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _manual,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.done,
                onSubmitted: (v) {
                  _verifier(v);
                  _manual.clear();
                },
                decoration: const InputDecoration(
                  hintText: 'Saisir ou scanner : BIL-2026-1000',
                  prefixIcon: Icon(Icons.keyboard_rounded),
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(52, 52)),
              onPressed: () {
                _verifier(_manual.text);
                _manual.clear();
              },
              child: const Icon(Icons.check_rounded),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(child: SingleChildScrollView(child: _Resultat(res: _res, numero: _numero))),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader(
          'Vérifier les billets',
          subtitle: 'Scannez le QR code du billet à l\'embarquement. Fonctionne sans internet.',
        ),
        Expanded(
          child: wide
              ? Row(
                  children: [
                    Expanded(child: camera),
                    const SizedBox(width: 24),
                    Expanded(child: panneau),
                  ],
                )
              : Column(
                  children: [
                    SizedBox(height: 240, child: camera),
                    const SizedBox(height: 14),
                    Expanded(child: panneau),
                  ],
                ),
        ),
      ],
    );
  }
}

class _Resultat extends StatelessWidget {
  const _Resultat({required this.res, required this.numero});
  final VerifResultat? res;
  final String? numero;

  @override
  Widget build(BuildContext context) {
    final r = res;
    if (r == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text('En attente d\'un billet…', style: TextStyle(color: Brand.muted)),
        ),
      );
    }
    final b = r.billet;
    if (b == null) {
      return _Carte(
        couleur: Colors.red,
        icone: Icons.cancel_rounded,
        titre: 'BILLET INCONNU',
        lignes: [numero ?? '', r.message ?? ''],
      );
    }
    final autreJour = b.autreJour(DateTime.now());
    final (couleur, icone, titre) = b.annule
        ? (Colors.red, Icons.cancel_rounded, 'BILLET ANNULÉ')
        : autreJour
        ? (const Color(0xFFEA580C), Icons.warning_amber_rounded, 'BILLET POUR UN AUTRE JOUR')
        : (const Color(0xFF16A34A), Icons.check_circle_rounded, 'BILLET VALIDE');
    return _Carte(
      couleur: couleur,
      icone: icone,
      titre: titre,
      lignes: [
        b.numero,
        b.clientNom,
        '${b.gareDepartNom ?? '—'} → ${b.gareArriveeNom ?? '—'}',
        '${dateFr(b.dateVoyage)}${(b.heureDepart ?? '').isEmpty ? '' : ' · ${b.heureDepart}'}'
            '${(b.siege ?? '').isEmpty ? '' : ' · place ${b.siege}'}',
        b.nbVerifications > 1
            ? 'Vérifié ${b.nbVerifications} fois'
            : 'Première vérification',
        if (r.horsLigne) 'Vérifié sans internet — sera enregistré au retour du réseau',
      ],
    );
  }
}

class _Carte extends StatelessWidget {
  const _Carte({
    required this.couleur,
    required this.icone,
    required this.titre,
    required this.lignes,
  });
  final Color couleur;
  final IconData icone;
  final String titre;
  final List<String> lignes;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: couleur.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: couleur, width: 2),
    ),
    child: Column(
      children: [
        Icon(icone, size: 56, color: couleur),
        const SizedBox(height: 8),
        Text(
          titre,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: couleur),
        ),
        const SizedBox(height: 10),
        for (final l in lignes.where((l) => l.isNotEmpty))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(l, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
          ),
      ],
    ),
  );
}
