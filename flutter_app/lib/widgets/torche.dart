import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Bouton lampe torche posé sur l'image de la caméra (scan de nuit). Masqué si l'appareil n'a pas de lampe.
class BoutonTorche extends StatelessWidget {
  const BoutonTorche({super.key, required this.controller});
  final MobileScannerController controller;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<MobileScannerState>(
    valueListenable: controller,
    builder: (_, etat, _) {
      if (etat.torchState == TorchState.unavailable) return const SizedBox.shrink();
      final allumee = etat.torchState == TorchState.on;
      return Positioned(
        top: 12,
        right: 12,
        child: Material(
          color: allumee ? const Color(0xFFFACC15) : Colors.black54,
          shape: const CircleBorder(),
          child: IconButton(
            tooltip: allumee ? 'Éteindre la lampe' : 'Allumer la lampe',
            iconSize: 28,
            color: allumee ? Colors.black : Colors.white,
            icon: Icon(allumee ? Icons.flashlight_off_rounded : Icons.flashlight_on_rounded),
            onPressed: controller.toggleTorch,
          ),
        ),
      );
    },
  );
}
