import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../data/repo.dart';
import '../widgets/colis_tile.dart';
import '../widgets/common.dart';

class RechercheScreen extends ConsumerStatefulWidget {
  const RechercheScreen({super.key});

  @override
  ConsumerState<RechercheScreen> createState() => _RechercheScreenState();
}

class _RechercheScreenState extends ConsumerState<RechercheScreen> {
  final _ctl = TextEditingController();
  Timer? _debounce;
  String _q = '';
  AsyncValue<List<Colis>> _res = const AsyncData([]);
  int _seq = 0;

  void _run(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final mine = ++_seq;
      setState(() => _q = q.trim());
      if (_q.length < 2) {
        setState(() => _res = const AsyncData([]));
        return;
      }
      setState(() => _res = const AsyncLoading<List<Colis>>());
      final r = await AsyncValue.guard(
        () => Repo.listColis(ColisFilter(search: _q)),
      );
      if (mounted && mine == _seq) setState(() => _res = r);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const PageHeader('Recherche', subtitle: 'Par numéro, nom ou téléphone.'),
      TextField(
        controller: _ctl,
        autofocus: false,
        onChanged: _run,
        decoration: const InputDecoration(
          hintText: 'COL-2026-…, Moussa, +226 70…',
          prefixIcon: Icon(Icons.search_rounded),
        ),
      ),
      const SizedBox(height: 16),
      Expanded(
        child: _q.length < 2
            ? const EmptyState(
                icon: Icons.manage_search_rounded,
                text: 'Tapez au moins 2 caractères',
              )
            : AsyncView<List<Colis>>(
                value: _res,
                builder: (items) => items.isEmpty
                    ? const EmptyState(
                        icon: Icons.search_off_rounded,
                        text: 'Aucun résultat',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 100),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) =>
                            ColisTile(items[i]).reveal(i < 10 ? i : 10),
                      ),
              ),
      ),
    ],
  );
}
