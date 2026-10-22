import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../data/repo.dart';
import '../widgets/colis_tile.dart';
import '../widgets/common.dart';
import 'rapport_pdf.dart';

final _nonRetiresProvider = FutureProvider<List<Colis>>((ref) {
  ref.watch(tickProvider);
  return Repo.listColis(const ColisFilter(statut: 'arrive', ancienFirst: true));
});

class RapportsScreen extends ConsumerWidget {
  const RapportsScreen({super.key});

  /// Génère le rapport PDF (avec les signatures des retraits) de la période affichée.
  Future<void> _telecharger(BuildContext context, WidgetRef ref) async {
    final p = ref.read(rapportPeriodeProvider);
    final me = ref.read(profilProvider).value;
    if (me == null) return;
    toast(context, 'Préparation du rapport…');
    try {
      final colis = await Repo.listColis(
        ColisFilter(debut: p.debut, fin: p.fin),
        maGareId: me.gareId,
      );
      final gares = await ref.read(recettesGareProvider.future);
      final agents = await ref.read(recettesAgentProvider.future);
      final co = await ref.read(settingsProvider.future);
      final garesListe = await ref.read(garesProvider.future);
      final gare = garesListe.where((g) => g.id == me.gareId).firstOrNull;
      final pdf = await rapportPdf(
        co: co,
        me: me,
        perimetre: me.voitToutLeReseau ? 'Toutes les gares' : (gare?.nom ?? 'Ma gare'),
        debut: p.debut,
        fin: p.fin,
        colis: colis,
        gares: gares,
        agents: agents,
      );
      await telechargerRapport(pdf, debut: p.debut, fin: p.fin);
    } catch (e) {
      if (context.mounted) toast(context, errMsg(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(rapportPeriodeProvider);
    final jours = ref.watch(colisParJourProvider);
    final gares = ref.watch(recettesGareProvider);
    final agents = ref.watch(recettesAgentProvider);
    final nonRetires = ref.watch(_nonRetiresProvider);
    final wide = MediaQuery.sizeOf(context).width >= 900;

    Future<void> pick(bool debut) async {
      final d = await showDatePicker(
        context: context,
        initialDate: (debut ? p.debut : p.fin) ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 365)),
      );
      if (d != null) {
        ref
            .read(rapportPeriodeProvider.notifier)
            .set(RapportPeriode(debut ? d : p.debut, debut ? p.fin : d));
      }
    }

    final cJours = SectionCard(
      title: 'Colis par jour',
      icon: Icons.bar_chart_rounded,
      child: AsyncView<List<JourStat>>(
        value: jours,
        loading: const Skeleton(height: 220),
        builder: (list) => list.isEmpty
            ? const EmptyState(
                icon: Icons.bar_chart_rounded,
                text: 'Aucune donnée sur la période',
              )
            : Column(
                children: [
                  SizedBox(height: 220, child: _BarJours(list)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 24,
                    children: [
                      _Kpi(
                        'Colis',
                        nombre(list.fold<int>(0, (a, b) => a + b.total)),
                      ),
                      _Kpi(
                        'Recette',
                        fcfa(list.fold<double>(0, (a, b) => a + b.recette)),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );

    final cGares = SectionCard(
      title: 'Recettes par gare',
      icon: Icons.location_city_rounded,
      accent: const Color(0xFF2563EB),
      child: AsyncView<List<LigneStat>>(
        value: gares,
        loading: const Skeleton(height: 120),
        builder: (l) => _Lignes(l),
      ),
    );
    final cAgents = SectionCard(
      title: 'Recettes par agent',
      icon: Icons.badge_rounded,
      accent: const Color(0xFF7C3AED),
      child: AsyncView<List<LigneStat>>(
        value: agents,
        loading: const Skeleton(height: 120),
        builder: (l) => _Lignes(l),
      ),
    );
    final cNon = SectionCard(
      title: 'Colis non retirés',
      icon: Icons.hourglass_bottom_rounded,
      accent: const Color(0xFFDC2626),
      child: AsyncView<List<Colis>>(
        value: nonRetires,
        loading: const Skeleton(height: 100),
        builder: (l) => l.isEmpty
            ? const Text(
                'Aucun colis en attente de retrait 🎉',
                style: TextStyle(color: Brand.muted),
              )
            : Column(
                children: [
                  for (final c in l.take(8))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ColisTile(c),
                    ),
                ],
              ),
      ),
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        PageHeader('Rapports', subtitle: 'Activité et recettes du réseau.'),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: () => pick(true),
              icon: const Icon(Icons.event_rounded, size: 18),
              label: Text('Du ${p.debut == null ? '…' : dateFr(p.debut!)}'),
            ),
            OutlinedButton.icon(
              onPressed: () => pick(false),
              icon: const Icon(Icons.event_rounded, size: 18),
              label: Text('Au ${p.fin == null ? '…' : dateFr(p.fin!)}'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
              onPressed: () => context.push('/rapports/detail'),
              icon: const Icon(Icons.table_chart_rounded, size: 18),
              label: const Text('Rapports détaillés (PDF / Excel)'),
            ),
            FilledButton.icon(
              onPressed: () => _telecharger(context, ref),
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
              label: const Text('Télécharger (PDF)'),
            ),
          ],
        ).reveal(),
        const SizedBox(height: 16),
        cJours.reveal(1),
        const SizedBox(height: 14),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: cGares.reveal(2)),
              const SizedBox(width: 14),
              Expanded(child: cAgents.reveal(3)),
            ],
          )
        else ...[
          cGares.reveal(2),
          const SizedBox(height: 14),
          cAgents.reveal(3),
        ],
        const SizedBox(height: 14),
        cNon.reveal(4),
      ],
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: Brand.muted, fontSize: 12)),
      Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
      ),
    ],
  );
}

class _BarJours extends StatelessWidget {
  const _BarJours(this.list);
  final List<JourStat> list;

  @override
  Widget build(BuildContext context) {
    final max = list
        .map((e) => e.total)
        .reduce((a, b) => a > b ? a : b)
        .toDouble();
    return BarChart(
      BarChartData(
        maxY: max * 1.2 + 1,
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: Brand.line, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (v, m) => v % 1 == 0
                  ? Text(
                      '${v.toInt()}',
                      style: const TextStyle(fontSize: 10, color: Brand.muted),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (v, m) {
                final i = v.toInt();
                if (i < 0 || i >= list.length) return const SizedBox.shrink();
                final step = (list.length / 6).ceil();
                if (i % step != 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${list[i].date.day}/${list[i].date.month}',
                    style: const TextStyle(fontSize: 10, color: Brand.muted),
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (g, gi, r, ri) => BarTooltipItem(
              '${dateFr(list[gi].date)}\n${list[gi].total} colis · ${fcfa(list[gi].recette)}',
              const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < list.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: list[i].total.toDouble(),
                  width: list.length > 20 ? 6 : 14,
                  borderRadius: BorderRadius.circular(5),
                  gradient: const LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Brand.orange, Color(0xFFFFB066)],
                  ),
                ),
              ],
            ),
        ],
      ),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
    );
  }
}

class _Lignes extends StatelessWidget {
  const _Lignes(this.list);
  final List<LigneStat> list;

  @override
  Widget build(BuildContext context) {
    if (list.isEmpty)
      return const Text('Aucune donnée.', style: TextStyle(color: Brand.muted));
    final max = list
        .map((e) => e.recette)
        .fold<double>(0, (a, b) => a > b ? a : b);
    return Column(
      children: [
        for (final l in list)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.nom,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                    Text(
                      '${l.total} colis · ${fcfa(l.recette)}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Brand.muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: max == 0 ? 0 : l.recette / max),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, _) => ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: LinearProgressIndicator(
                      value: v,
                      minHeight: 8,
                      backgroundColor: Brand.line,
                      color: Brand.orange,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
