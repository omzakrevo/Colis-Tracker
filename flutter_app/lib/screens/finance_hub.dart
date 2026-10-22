import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../data/providers.dart';
import '../widgets/common.dart';
import 'finance_ui.dart';

/// Accueil de la comptabilité : dépenses, documents, employés, paie, rapports et bilans.
class FinanceHubScreen extends ConsumerWidget {
  const FinanceHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!moduleFinanceOuvert(ref)) {
      return const EmptyState(icon: Icons.lock_rounded, text: 'Le module Comptabilité n\'est pas activé pour votre entreprise.\nDemandez-le au super administrateur.');
    }
    final identite = ref.watch(identiteProvider);
    final me = ref.watch(profilProvider).value;
    final manque = identite.maybeWhen(data: (i) => i.ifu.isEmpty || i.rccm.isEmpty, orElse: () => false);
    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        const PageHeader('Comptabilité', subtitle: 'Dépenses, documents officiels, employés, paie et bilans.'),
        if (manque)
          Card(
            color: const Color(0xFFFFF7ED),
            child: ListTile(
              leading: const Icon(Icons.info_rounded, color: Brand.orange),
              title: const Text('Numéro IFU et RCCM non renseignés', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(
                me?.isAdmin == true
                    ? 'Ajoutez-les dans Paramètres, « Identité légale », pour qu\'ils figurent sur vos factures, décharges et contrats.'
                    : 'Demandez à l\'administrateur de les ajouter dans Paramètres : ils figureront sur les documents officiels.',
              ),
              trailing: me?.isAdmin == true ? TextButton(onPressed: () => context.go('/parametres'), child: const Text('Renseigner')) : null,
            ),
          ),
        if (manque) const SizedBox(height: 14),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 14,
          runSpacing: 14,
          children: [
            TuileFinance(icone: Icons.payments_rounded, titre: 'Dépenses', detail: 'Enregistrer et suivre toutes les dépenses', onTap: () => context.push('/finance/depenses'), couleur: const Color(0xFFDC2626)),
            TuileFinance(icone: Icons.description_rounded, titre: 'Documents', detail: 'Décharges, factures, reçus', onTap: () => context.push('/finance/documents'), couleur: const Color(0xFF2563EB)),
            TuileFinance(icone: Icons.badge_rounded, titre: 'Employés et contrats', detail: 'Fiches du personnel, contrats de travail', onTap: () => context.push('/finance/employes'), couleur: const Color(0xFF7C3AED)),
            TuileFinance(icone: Icons.request_quote_rounded, titre: 'Paie', detail: 'Bulletins de salaire, paiement, émargement', onTap: () => context.push('/finance/paie'), couleur: const Color(0xFF16A34A)),
            TuileFinance(icone: Icons.insights_rounded, titre: 'Bilans et rapports', detail: 'Dépenses, bilan, rapport financier complet', onTap: () => context.push('/rapports/detail'), couleur: Brand.orange),
          ],
        ),
      ],
    );
  }
}
