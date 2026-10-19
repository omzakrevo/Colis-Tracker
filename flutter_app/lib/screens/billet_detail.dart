import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/format.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../data/repo.dart';
import '../widgets/common.dart';
import 'billet_pdf.dart';

class BilletDetailScreen extends ConsumerWidget {
  const BilletDetailScreen({super.key, required this.id});
  final int id;

  Future<void> _annuler(BuildContext context, WidgetRef ref, Ticket t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Annuler ce billet ?'),
        content: Text('Le billet ${t.numero} sera marqué comme annulé.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Non')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Annuler le billet')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Repo.annulerTicket(t.id);
      ref.read(tickProvider.notifier).bump();
    } catch (e) {
      if (context.mounted) toast(context, errMsg(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(ticketProvider(id));
    final me = ref.watch(profilProvider).value;
    final company = ref.watch(settingsProvider).value ?? CompanySettings.defaults;

    return AsyncView<Ticket>(
      value: value,
      onRetry: () => ref.invalidate(ticketProvider(id)),
      builder: (t) {
        final peutAnnuler = !t.annule &&
            !t.enAttente &&
            me != null &&
            (me.isAdmin || (me.isGuichet && me.gareId == t.gareDepartId));
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeader(
                t.numero,
                subtitle: t.annule ? 'Billet annulé' : 'Billet de transport',
                actions: [
                  IconButton(
                    onPressed: () => context.go('/billets'),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              if (t.enAttente) ...[
                const EnAttenteChip(),
                const SizedBox(height: 12),
              ],
              SectionCard(
                title: 'Passager',
                icon: Icons.person_rounded,
                child: Column(
                  children: [
                    InfoRow('Nom', t.clientNom, bold: true),
                    InfoRow('Téléphone', t.clientTelephone),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SectionCard(
                title: 'Voyage',
                icon: Icons.directions_bus_rounded,
                child: Column(
                  children: [
                    InfoRow('Départ', t.gareDepartNom ?? '—', bold: true),
                    InfoRow('Arrivée', t.gareArriveeNom ?? '—', bold: true),
                    InfoRow('Date', dateFr(t.dateVoyage)),
                    if ((t.heureDepart ?? '').isNotEmpty) InfoRow('Heure', t.heureDepart!),
                    if ((t.siege ?? '').isNotEmpty) InfoRow('Place', t.siege!),
                    InfoRow('Prix', fcfa(t.prix), bold: true),
                    if (t.vendeurNom != null) InfoRow('Vendu par', t.vendeurNom!),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => avecMessage(context, () => imprimerBillet(t, company, ticket: true)),
                    icon: const Icon(Icons.receipt_long_rounded),
                    label: const Text('Ticket'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => avecMessage(context, () => imprimerBillet(t, company)),
                    icon: const Icon(Icons.print_rounded),
                    label: const Text('Billet A4'),
                  ),
                  if (peutAnnuler)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                      onPressed: () => _annuler(context, ref, t),
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Annuler'),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
