import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../data/repo.dart';
import '../widgets/colis_tile.dart';
import '../widgets/common.dart';

class ColisListScreen extends ConsumerStatefulWidget {
  const ColisListScreen({super.key});

  @override
  ConsumerState<ColisListScreen> createState() => _ColisListScreenState();
}

class _ColisListScreenState extends ConsumerState<ColisListScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search.text = ref.read(colisFilterProvider).search;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _setFilter(ColisFilter f) =>
      ref.read(colisFilterProvider.notifier).set(f);

  @override
  Widget build(BuildContext context) {
    final f = ref.watch(colisFilterProvider);
    final list = ref.watch(colisListProvider);
    final me = ref.watch(profilProvider).value;
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          'Colis',
          subtitle: list.hasValue
              ? '${list.value!.length} colis'
              : 'Chargement…',
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
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _search,
                onChanged: (v) {
                  _debounce?.cancel();
                  _debounce = Timer(
                    const Duration(milliseconds: 350),
                    () => _setFilter(f.copyWith(search: v)),
                  );
                },
                decoration: InputDecoration(
                  hintText: 'Numéro, nom, téléphone…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _search.clear();
                            _setFilter(f.copyWith(search: ''));
                            setState(() {});
                          },
                        ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Badge(
              isLabelVisible: f.activeCount > 0,
              label: Text('${f.activeCount}'),
              backgroundColor: Brand.orange,
              child: IconButton.filledTonal(
                style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
                onPressed: () => _openFilters(context, f, me),
                icon: const Icon(Icons.tune_rounded),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _Chip(
                'Tous',
                f.statut == null,
                () => _setFilter(f.copyWith(statut: null)),
              ),
              for (final s in Statut.values)
                _Chip(
                  s.label,
                  f.statut == s.code,
                  () => _setFilter(f.copyWith(statut: s.code)),
                  color: s.color,
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => ref.invalidate(colisListProvider),
            child: AsyncView<List<Colis>>(
              value: list,
              onRetry: () => ref.invalidate(colisListProvider),
              builder: (items) => items.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 40),
                        EmptyState(
                          icon: Icons.inventory_2_outlined,
                          text: 'Aucun colis trouvé',
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 100),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => ColisTile(items[i])
                          .animate()
                          .fadeIn(
                            delay: (30 * (i < 12 ? i : 12)).ms,
                            duration: 350.ms,
                          )
                          .slideY(
                            begin: .1,
                            end: 0,
                            delay: (30 * (i < 12 ? i : 12)).ms,
                            curve: Curves.easeOutCubic,
                          ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openFilters(
    BuildContext context,
    ColisFilter f,
    Profil? me,
  ) async {
    final res = await showModalBottomSheet<ColisFilter>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _FilterSheet(f, hasGare: me?.gareId != null),
    );
    if (res != null) _setFilter(res);
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.selected, this.onTap, {this.color});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Brand.emerald;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: 220.ms,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? c : Colors.white,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: selected ? c : Brand.line),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Brand.ink,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet(this.initial, {required this.hasGare});
  final ColisFilter initial;
  final bool hasGare;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late ColisFilter f = widget.initial;

  Future<void> _pick(bool debut) async {
    final d = await showDatePicker(
      context: context,
      initialDate: (debut ? f.debut : f.fin) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null)
      setState(() => f = debut ? f.copyWith(debut: d) : f.copyWith(fin: d));
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      0,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Filtres',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
          ),
          const SizedBox(height: 16),
          if (widget.hasGare) ...[
            const Text(
              'Mouvement',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String?>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: null, label: Text('Tous')),
                ButtonSegment(value: 'envoi', label: Text('Envois')),
                ButtonSegment(value: 'reception', label: Text('Réceptions')),
              ],
              selected: {f.direction},
              onSelectionChanged: (s) =>
                  setState(() => f = f.copyWith(direction: s.first)),
            ),
            const SizedBox(height: 16),
          ],
          const Text(
            'Période d\'envoi',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pick(true),
                  icon: const Icon(Icons.event_rounded, size: 18),
                  label: Text(f.debut == null ? 'Du…' : dateFr(f.debut!)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pick(false),
                  icon: const Icon(Icons.event_rounded, size: 18),
                  label: Text(f.fin == null ? 'Au…' : dateFr(f.fin!)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Tri', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('Plus récents')),
              ButtonSegment(value: true, label: Text('Plus anciens')),
            ],
            selected: {f.ancienFirst},
            onSelectionChanged: (s) =>
                setState(() => f = f.copyWith(ancienFirst: s.first)),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(
                    context,
                    f.copyWith(
                      direction: null,
                      debut: null,
                      fin: null,
                      ancienFirst: false,
                    ),
                  ),
                  child: const Text('Réinitialiser'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, f),
                  child: const Text('Appliquer'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
