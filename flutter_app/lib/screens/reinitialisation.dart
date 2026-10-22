import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../data/providers.dart';
import '../data/repo.dart';
import '../widgets/common.dart';

/// Fin de l'apprentissage : l'administrateur efface toutes les saisies de test avant de commencer les vraies données.
class ReinitialisationCard extends ConsumerWidget {
  const ReinitialisationCard({super.key});

  Future<void> _lancer(BuildContext context, WidgetRef ref) async {
    final saisie = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626)),
              SizedBox(width: 10),
              Expanded(child: Text('Effacer les données d\'apprentissage ?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Sera effacé, pour toute l\'entreprise :', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                const Text('• tous les colis et leur historique\n• tous les billets et leurs vérifications\n• le journal des SMS\n• les clients mémorisés (rappel automatique)'),
                const SizedBox(height: 10),
                const Text('Sera conservé :', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                const Text('• les utilisateurs\n• les gares\n• les trajets, prix et horaires\n• les paramètres, SMS et imprimantes'),
                const SizedBox(height: 12),
                const Text(
                  'Cette action est définitive. Avant de continuer, vérifiez que tous les téléphones ont fini de se synchroniser : '
                  'un colis créé hors ligne et pas encore envoyé réapparaîtrait.',
                  style: TextStyle(color: Brand.muted, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: saisie,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) => setS(() {}),
                  decoration: const InputDecoration(labelText: 'Tapez EFFACER pour confirmer'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
              onPressed: saisie.text.trim().toUpperCase() == 'EFFACER' ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Tout effacer'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      final r = await Repo.reinitialiserDonnees('EFFACER');
      ref.read(tickProvider.notifier).bump();
      ref.invalidate(ticketsProvider);
      if (context.mounted) {
        toast(context, 'Données effacées : ${r['colis'] ?? 0} colis, ${r['billets'] ?? 0} billets, ${r['clients'] ?? 0} clients');
      }
    } catch (e) {
      if (context.mounted) toast(context, errMsg(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => SectionCard(
    title: 'Fin de l\'apprentissage',
    icon: Icons.cleaning_services_rounded,
    accent: const Color(0xFFDC2626),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quand la formation est terminée, effacez toutes les saisies de test (colis, billets, clients, SMS) pour commencer avec les vraies données. '
          'Les utilisateurs, gares et trajets sont conservés.',
          style: TextStyle(color: Brand.muted, height: 1.4),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFDC2626), side: const BorderSide(color: Color(0xFFDC2626))),
          onPressed: () => _lancer(context, ref),
          icon: const Icon(Icons.delete_forever_rounded),
          label: const Text('Effacer les données d\'apprentissage'),
        ),
      ],
    ),
  );
}
