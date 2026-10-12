import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../data/repo.dart';
import '../widgets/common.dart';

class GaresScreen extends ConsumerWidget {
  const GaresScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gares = ref.watch(garesProvider);
    return Stack(children: [
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PageHeader('Gares', subtitle: 'Agences du réseau', actions: [
          FilledButton.icon(
              onPressed: () => _edit(context, ref, null),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Ajouter')),
        ]),
        Expanded(
          child: AsyncView<List<Gare>>(
            value: gares,
            onRetry: () => ref.invalidate(garesProvider),
            builder: (list) => list.isEmpty
                ? const EmptyState(icon: Icons.location_city_rounded, text: 'Aucune gare')
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 100),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final g = list[i];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(children: [
                            Container(
                              padding: const EdgeInsets.all(11),
                              decoration: BoxDecoration(color: const Color(0xFF2563EB).withValues(alpha: .1), borderRadius: BorderRadius.circular(14)),
                              child: const Icon(Icons.location_city_rounded, color: Color(0xFF2563EB)),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(g.nom, style: const TextStyle(fontWeight: FontWeight.w800)),
                                Text('${g.ville} · ${g.adresse}', style: const TextStyle(color: Brand.muted, fontSize: 12.5)),
                                if (g.responsable != null || g.telephone != null)
                                  Text([g.responsable, g.telephone].whereType<String>().join(' · '),
                                      style: const TextStyle(fontSize: 12.5)),
                              ]),
                            ),
                            IconButton(onPressed: () => _edit(context, ref, g), icon: const Icon(Icons.edit_rounded, size: 20)),
                            IconButton(
                                onPressed: () => _delete(context, ref, g),
                                icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFDC2626))),
                          ]),
                        ),
                      ).reveal(i < 10 ? i : 10);
                    },
                  ),
          ),
        ),
      ]),
    ]);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Gare g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la gare ?'),
        content: Text('« ${g.nom} » sera supprimée définitivement.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626), minimumSize: const Size(0, 44)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Repo.deleteGare(g.id);
      ref.invalidate(garesProvider);
    } catch (e) {
      if (context.mounted) {
        toast(context, 'Suppression impossible : des colis ou utilisateurs y sont rattachés.', error: true);
      }
    }
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Gare? g) async {
    final nom = TextEditingController(text: g?.nom);
    final ville = TextEditingController(text: g?.ville);
    final adresse = TextEditingController(text: g?.adresse);
    final resp = TextEditingController(text: g?.responsable);
    final tel = TextEditingController(text: g?.telephone);
    final key = GlobalKey<FormState>();
    String? req(String? v) => (v ?? '').trim().isEmpty ? 'Requis' : null;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(g == null ? 'Nouvelle gare' : 'Modifier la gare', style: const TextStyle(fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 420,
          child: Form(
            key: key,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(controller: nom, decoration: const InputDecoration(labelText: 'Nom *'), validator: req),
                const SizedBox(height: 10),
                TextFormField(controller: ville, decoration: const InputDecoration(labelText: 'Ville *'), validator: req),
                const SizedBox(height: 10),
                TextFormField(controller: adresse, decoration: const InputDecoration(labelText: 'Adresse *'), validator: req),
                const SizedBox(height: 10),
                TextFormField(controller: resp, decoration: const InputDecoration(labelText: 'Responsable')),
                const SizedBox(height: 10),
                TextFormField(controller: tel, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Téléphone')),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () {
                if (key.currentState!.validate()) Navigator.pop(ctx, true);
              },
              child: const Text('Enregistrer')),
        ],
      ),
    );
    if (ok != true) return;
    String? nn(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    try {
      await Repo.saveGare(g?.id, {
        'nom': nom.text.trim(),
        'ville': ville.text.trim(),
        'adresse': adresse.text.trim(),
        'responsable': nn(resp),
        'telephone': nn(tel),
      });
      ref.invalidate(garesProvider);
    } catch (e) {
      if (context.mounted) toast(context, errMsg(e), error: true);
    }
  }
}
