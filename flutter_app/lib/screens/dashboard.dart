import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../widgets/colis_tile.dart';
import '../widgets/common.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(profilProvider).value;
    final stats = ref.watch(dashboardProvider);
    final recents = ref.watch(recentColisProvider);
    final statuts = ref.watch(statutsProvider);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    // Agent / guichet : uniquement leur propre activité du jour.
    final perso = me != null && !me.voitRapportsGlobaux;
    final activite = ref.watch(monActiviteProvider);

    final hour = DateTime.now().hour;
    final salut = hour < 18 ? 'Bonjour' : 'Bonsoir';

    return RefreshIndicator(
      onRefresh: () async {
        ref.read(tickProvider.notifier).bump();
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          PageHeader(
            '$salut, ${(me?.nom ?? '').split(' ').first} 👋',
            subtitle: perso
                ? 'Votre activité d\'aujourd\'hui.'
                : 'Aperçu en temps réel de l\'activité du réseau.',
            actions: wide
                ? [
                    FilledButton.icon(
                      onPressed: () => context.push('/colis/nouveau'),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Nouveau colis'),
                    ),
                  ]
                : const [],
          ),
          if (perso)
            AsyncView<Map<String, int>>(
              value: activite,
              onRetry: () => ref.invalidate(monActiviteProvider),
              loading: const _StatsSkeleton(),
              builder: (a) => _MonActivite(a),
            )
          else
            AsyncView<DashboardStats>(
              value: stats,
              onRetry: () => ref.invalidate(dashboardProvider),
              loading: const _StatsSkeleton(),
              builder: (s) => _StatsGrid(s),
            ),
          const SizedBox(height: 24),
          if (perso)
            _Recents(recents)
          else if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: _Recents(recents)),
                const SizedBox(width: 20),
                Expanded(flex: 2, child: _StatutsChart(statuts)),
              ],
            )
          else ...[
            _StatutsChart(statuts),
            const SizedBox(height: 20),
            _Recents(recents),
          ],
        ],
      ),
    );
  }
}

/// Compteurs personnels du jour (colis envoyés, colis réceptionnés, billets vendus) + accès à la fin de journée.
class _MonActivite extends StatelessWidget {
  const _MonActivite(this.a);
  final Map<String, int> a;

  @override
  Widget build(BuildContext context) {
    final cards = <_Stat>[
      _Stat('Colis envoyés', (a['colis_envoyes'] ?? 0).toDouble(), Icons.outbox_rounded, Brand.orange),
      _Stat('Colis réceptionnés', (a['colis_recus'] ?? 0).toDouble(), Icons.move_to_inbox_rounded, const Color(0xFF16A34A)),
      _Stat('Billets vendus', (a['billets_vendus'] ?? 0).toDouble(), Icons.confirmation_number_rounded, const Color(0xFF2563EB)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            const gap = 12.0;
            final cols = c.maxWidth >= 560 ? 3 : 2;
            final w = (c.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [for (var i = 0; i < cards.length; i++) SizedBox(width: w, child: _StatCard(cards[i]).reveal(i))],
            );
          },
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () => context.push('/cloture'),
          icon: const Icon(Icons.receipt_long_rounded),
          label: const Text('Fin de journée : voir et imprimer mon rapport'),
        ),
      ],
    );
  }
}

class _StatsSkeleton extends StatelessWidget {
  const _StatsSkeleton();
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 12,
    children: [
      for (var i = 0; i < 8; i++)
        const SizedBox(width: 160, child: Skeleton(height: 112)),
    ],
  );
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid(this.s);
  final DashboardStats s;

  @override
  Widget build(BuildContext context) {
    final cards = <_Stat>[
      _Stat(
        'Colis du jour',
        s.v('colis_aujourd_hui'),
        Icons.today_rounded,
        Brand.orange,
      ),
      _Stat(
        'En route',
        s.v('colis_en_route'),
        Icons.local_shipping_rounded,
        const Color(0xFFCA8A04),
      ),
      _Stat(
        'Arrivés',
        s.v('colis_arrives'),
        Icons.where_to_vote_rounded,
        const Color(0xFF16A34A),
      ),
      _Stat(
        'Non retirés',
        s.v('colis_non_retires'),
        Icons.hourglass_bottom_rounded,
        const Color(0xFF64748B),
      ),
      _Stat(
        'Recette du jour',
        s.v('recette_aujourd_hui'),
        Icons.payments_rounded,
        const Color(0xFF16A34A),
        money: true,
      ),
      _Stat(
        'Recette totale',
        s.v('recette_totale'),
        Icons.account_balance_wallet_rounded,
        Brand.orange,
        money: true,
      ),
      _Stat(
        'Gares',
        s.v('total_gares'),
        Icons.location_city_rounded,
        const Color(0xFF2563EB),
      ),
      _Stat(
        'Agents',
        s.v('total_agents'),
        Icons.groups_rounded,
        const Color(0xFF7C3AED),
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 900 ? 4 : (c.maxWidth >= 560 ? 3 : 2);
        const gap = 12.0;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < cards.length; i++)
              SizedBox(width: w, child: _StatCard(cards[i]).reveal(i)),
          ],
        );
      },
    );
  }
}

class _Stat {
  _Stat(this.title, this.value, this.icon, this.color, {this.money = false});
  final String title;
  final double value;
  final IconData icon;
  final Color color;
  final bool money;
}

class _StatCard extends StatelessWidget {
  const _StatCard(this.s);
  final _Stat s;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: s.color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(s.icon, size: 19, color: s.color),
          ),
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: CountUp(
              s.value,
              format: s.money ? fcfa : nombre,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -.5,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            s.title,
            style: const TextStyle(color: Brand.muted, fontSize: 13),
          ),
        ],
      ),
    ),
  );
}

class _Recents extends StatelessWidget {
  const _Recents(this.recents);
  final AsyncValue<List<Colis>> recents;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(
              'Derniers colis',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
          ),
          TextButton(
            onPressed: () => context.go('/colis'),
            child: const Text('Tout voir'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      AsyncView<List<Colis>>(
        value: recents,
        builder: (list) => list.isEmpty
            ? const EmptyState(
                icon: Icons.inventory_2_outlined,
                text: 'Aucun colis pour le moment',
              )
            : Column(
                children: [
                  for (var i = 0; i < list.take(6).length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ColisTile(list[i]).reveal(i),
                    ),
                ],
              ),
      ),
    ],
  );
}

class _StatutsChart extends StatelessWidget {
  const _StatutsChart(this.data);
  final AsyncValue<Map<String, int>> data;

  @override
  Widget build(BuildContext context) => SectionCard(
    title: 'Répartition des statuts',
    icon: Icons.donut_large_rounded,
    child: AsyncView<Map<String, int>>(
      value: data,
      loading: const Skeleton(height: 200),
      builder: (m) {
        final total = m.values.fold<int>(0, (a, b) => a + b);
        if (total == 0) {
          return const EmptyState(
            icon: Icons.pie_chart_outline_rounded,
            text: 'Pas encore de données',
          );
        }
        return Column(
          children: [
            SizedBox(
              height: 190,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 3,
                  centerSpaceRadius: 52,
                  sections: [
                    for (final s in Statut.values)
                      if ((m[s.code] ?? 0) > 0)
                        PieChartSectionData(
                          value: m[s.code]!.toDouble(),
                          color: s.color,
                          radius: 26,
                          showTitle: false,
                        ),
                  ],
                ),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 14,
              runSpacing: 8,
              children: [
                for (final s in Statut.values)
                  if ((m[s.code] ?? 0) > 0)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: s.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${s.label} · ${m[s.code]}',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ],
                    ),
              ],
            ),
          ],
        );
      },
    ),
  ).reveal(2);
}
