import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/theme.dart';
import 'torche.dart';

/// Ouvre la caméra dans une fenêtre et renvoie le premier QR code lu (ex. numéro d'un billet), ou `null` si annulé.
Future<String?> scannerNumero(
  BuildContext context, {
  String titre = 'Scanner le QR code',
}) => showDialog<String>(
  context: context,
  builder: (_) => _ScanNumeroDialog(titre: titre),
);

class _ScanNumeroDialog extends StatefulWidget {
  const _ScanNumeroDialog({required this.titre});
  final String titre;

  @override
  State<_ScanNumeroDialog> createState() => _ScanNumeroDialogState();
}

class _ScanNumeroDialogState extends State<_ScanNumeroDialog> {
  final _ctl = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _pris = false;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.titre,
      style: const TextStyle(fontWeight: FontWeight.w800),
    ),
    content: SizedBox(
      width: 340,
      height: 340,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: _ctl,
              onDetect: (cap) {
                final v = cap.barcodes.firstOrNull?.rawValue;
                if (v == null || v.trim().isEmpty || _pris) return;
                _pris = true;
                Navigator.pop(context, v.trim().toUpperCase());
              },
              errorBuilder: (_, _) => Container(
                color: Brand.emerald,
                padding: const EdgeInsets.all(24),
                alignment: Alignment.center,
                child: const Text(
                  'Caméra indisponible.\nSaisissez le numéro à la main.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
            BoutonTorche(controller: _ctl),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
    ],
  );
}
