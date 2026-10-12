import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/theme.dart';
import '../data/providers.dart';
import '../data/repo.dart';
import '../widgets/common.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final _ctl = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  final _manual = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _ctl.dispose();
    _manual.dispose();
    super.dispose();
  }

  Future<void> _open(String numero) async {
    if (_busy || numero.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final c = await Repo.getColisByNumero(numero);
      if (!mounted) return;
      if (c == null) {
        toast(context, 'Colis introuvable : ${numero.trim()}', error: true);
        await Future<void>.delayed(const Duration(seconds: 2));
      } else {
        HapticFeedback.mediumImpact();
        await context.push('/colis/${c.id}');
      }
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.only(bottom: 100), children: [
        const PageHeader('Scanner QR', subtitle: 'Scannez le QR code du reçu pour ouvrir le colis.'),
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Stack(fit: StackFit.expand, children: [
              MobileScanner(
                controller: _ctl,
                onDetect: (cap) {
                  final v = cap.barcodes.firstOrNull?.rawValue;
                  if (v != null) _open(v);
                },
                errorBuilder: (_, e) => Container(
                  color: Brand.emerald,
                  padding: const EdgeInsets.all(24),
                  alignment: Alignment.center,
                  child: const Text(
                    'Caméra indisponible.\nAutorisez l\'accès ou saisissez le numéro ci-dessous.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
              const _Overlay(),
              if (_busy) Container(color: Colors.black38, child: const Center(child: CircularProgressIndicator(color: Colors.white))),
            ]),
          ),
        ).reveal(),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _manual,
              textCapitalization: TextCapitalization.characters,
              onSubmitted: _open,
              decoration: const InputDecoration(hintText: 'Ou saisir : COL-2026-123456', prefixIcon: Icon(Icons.keyboard_rounded)),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(56, 52)),
            onPressed: () => _open(_manual.text),
            child: const Icon(Icons.arrow_forward_rounded),
          ),
        ]).reveal(1),
      ]);
}

class _Overlay extends StatelessWidget {
  const _Overlay();

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final box = c.maxWidth * .66;
        final left = (c.maxWidth - box) / 2;
        final top = (c.maxHeight - box) / 2;
        return Stack(children: [
          Positioned(
            left: left, top: top, width: box, height: box,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Brand.orange, width: 3),
                borderRadius: BorderRadius.circular(24),
              ),
            ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(begin: const Offset(.97, .97), end: const Offset(1.02, 1.02), duration: 1100.ms),
          ),
          Positioned(
            left: left + 14, width: box - 28, top: top + 14,
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                color: Brand.orange,
                borderRadius: BorderRadius.circular(9),
                boxShadow: [BoxShadow(color: Brand.orange.withValues(alpha: .8), blurRadius: 12)],
              ),
            ).animate(onPlay: (c) => c.repeat(reverse: true)).moveY(begin: 0, end: box - 34, duration: 1700.ms, curve: Curves.easeInOut),
          ),
        ]);
      });
}
