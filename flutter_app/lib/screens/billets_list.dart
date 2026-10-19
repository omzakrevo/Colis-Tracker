import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../widgets/common.dart';

class BilletsListScreen extends ConsumerStatefulWidget {
  const BilletsListScreen({super.key});

  @override
  ConsumerState<BilletsListScreen> createState() => _BilletsListScreenState();
}

class _BilletsListScreenState extends ConsumerState<BilletsListScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(ticketsProvider);
    final me = ref.watch(profilProvider).value;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final q = _search.text.trim().toLowerCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          'Billets',
          subtitle: list.hasValue ? '${list.value!.length} billets' : 'Chargement…',
          actions: wide && (me?.peutVendreBillets ?? false)
              ? [
                  FilledButton.icon(
                    onPressed: () => context.push('/billets/nouveau'),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Vendre un billet'),
                  ),
                ]
              : const [],
        ),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'Numéro, nom, téléphone…',
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: AsyncView<List<Ticket>>(
            value: list,
            onRetry: () => ref.invalidate(ticketsProvider),
            builder: (tous) {
              final l = tous.where((t) {
                if (q.isEmpty) return true;
                return [t.numero, t.clientNom, t.clientTelephone]
                    .any((x) => x.toLowerCase().contains(q));
              }).toList();
              if (l.isEmpty) {
                return const EmptyState(
                  icon: Icons.confirmation_number_outlined,
                  text: 'Aucun billet',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.only(bottom: 90),
                itemCount: l.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _BilletTile(l[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _BilletTile extends StatelessWidget {
  const _BilletTile(this.t);
  final Ticket t;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => context.push('/billets/${t.id}'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Brand.orange.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.confirmation_number_rounded, color: Brand.orange),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          t.numero,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (t.annule) ...[
                        const SizedBox(width: 8),
                        const Text(
                          'ANNULÉ',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ],
                      if (t.enAttente) ...[
                        const SizedBox(width: 8),
                        const EnAttenteChip(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${t.clientNom} · ${t.gareDepartNom ?? '—'} → ${t.gareArriveeNom ?? '—'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Brand.muted, fontSize: 13),
                  ),
                  Text(
                    dateFr(t.dateVoyage),
                    style: const TextStyle(color: Brand.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            Text(
              fcfa(t.prix),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                decoration: t.annule ? TextDecoration.lineThrough : null,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
