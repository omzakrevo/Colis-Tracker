import 'package:flutter/material.dart';

/// Choix du mode de paiement avant de valider (espèces ou Orange Money).
class ModePaiementChoix extends StatelessWidget {
  const ModePaiementChoix({super.key, required this.valeur, required this.onChanged});
  final String valeur;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Paiement *', style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 6),
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'especes', icon: Icon(Icons.payments_rounded), label: Text('Espèces')),
            ButtonSegment(value: 'orange_money', icon: Icon(Icons.phone_android_rounded), label: Text('Orange Money')),
          ],
          selected: {valeur},
          onSelectionChanged: (s) => onChanged(s.first),
        ),
      ),
    ],
  );
}
