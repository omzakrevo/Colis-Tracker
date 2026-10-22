import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../data/repo.dart';
import '../widgets/common.dart';

/// Trajets : l'administrateur fixe le prix et les heures de départ entre deux gares.
class TrajetsScreen extends ConsumerWidget {
  const TrajetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trajets = ref.watch(trajetsProvider);
    final gares = ref.watch(garesProvider).value ?? const <Gare>[];
    String nom(int id) => gares.where((g) => g.id == id).firstOrNull?.nom ?? '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          'Trajets et prix',
          subtitle: 'Prix et heures de départ proposés à la vente des billets.',
          actions: [
            FilledButton.icon(
              onPressed: () => _editer(context, ref, null, gares),
              icon: const Icon(Icons.add_road_rounded),
              label: const Text('Ajouter'),
            ),
          ],
        ),
        Expanded(
          child: AsyncView<List<Trajet>>(
            value: trajets,
            onRetry: () => ref.invalidate(trajetsProvider),
            builder: (l) {
              if (l.isEmpty) {
                return const EmptyState(
                  icon: Icons.route_rounded,
                  text: 'Aucun trajet. Ajoutez le premier pour fixer un prix.',
                );
              }
              final tri = [...l]..sort(
                (a, b) => '${nom(a.gareDepartId)}${nom(a.gareArriveeId)}'
                    .compareTo('${nom(b.gareDepartId)}${nom(b.gareArriveeId)}'),
              );
              return ListView.separated(
                padding: const EdgeInsets.only(bottom: 100),
                itemCount: tri.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final t = tri[i];
                  return Card(
                    child: ListTile(
                      onTap: () => _editer(context, ref, t, gares),
                      leading: const Icon(Icons.route_rounded, color: Brand.orange),
                      title: Text(
                        '${nom(t.gareDepartId)} → ${nom(t.gareArriveeId)}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${t.capacite} places · ${t.horaires.isEmpty ? 'aucune heure de départ' : 'départs : ${t.horaires.join(' · ')}'}',
                      ),
                      trailing: Text(
                        fcfa(t.prix),
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _editer(
    BuildContext context,
    WidgetRef ref,
    Trajet? t,
    List<Gare> gares,
  ) async {
    int? depart = t?.gareDepartId, arrivee = t?.gareArriveeId;
    final prix = TextEditingController(text: t == null ? '' : '${t.prix.round()}');
    final capacite = TextEditingController(text: '${t?.capacite ?? 50}');
    final heures = [...?t?.horaires];
    final heure = TextEditingController();
    var retour = false;
    final form = GlobalKey<FormState>();

    void ajouterHeure(StateSetter setS) {
      final h = heure.text.trim().replaceAll('h', ':').replaceAll('H', ':');
      final m = RegExp(r'^([01]?\d|2[0-3]):([0-5]\d)$').firstMatch(h);
      if (m == null) return;
      final ok = '${m.group(1)!.padLeft(2, '0')}:${m.group(2)}';
      if (!heures.contains(ok)) setS(() => heures..add(ok)..sort());
      heure.clear();
    }

    final enregistre = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(
            t == null ? 'Nouveau trajet' : 'Modifier le trajet',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          content: SizedBox(
            width: 440,
            child: Form(
              key: form,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: depart,
                      decoration: const InputDecoration(labelText: 'Gare de départ *'),
                      items: [
                        for (final g in gares)
                          DropdownMenuItem(value: g.id, child: Text(g.nom)),
                      ],
                      onChanged: t == null ? (v) => setS(() => depart = v) : null,
                      validator: (v) => v == null ? 'Choisissez une gare' : null,
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      initialValue: arrivee,
                      decoration: const InputDecoration(labelText: 'Gare d\'arrivée *'),
                      items: [
                        for (final g in gares)
                          DropdownMenuItem(value: g.id, child: Text(g.nom)),
                      ],
                      onChanged: t == null ? (v) => setS(() => arrivee = v) : null,
                      validator: (v) => v == null
                          ? 'Choisissez une gare'
                          : (v == depart ? 'Doit différer du départ' : null),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: prix,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Prix du billet (FCFA) *'),
                      validator: (v) => (v == null || v.isEmpty) ? 'Prix requis' : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: capacite,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Nombre de places du bus',
                        helperText: 'Les places sont numérotées automatiquement ; trajet « plein » à ce nombre',
                      ),
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        return n == null || n < 1 || n > 200 ? 'Entre 1 et 200' : null;
                      },
                    ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final h in heures)
                            InputChip(
                              label: Text(h),
                              onDeleted: () => setS(() => heures.remove(h)),
                            ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: heure,
                            keyboardType: TextInputType.datetime,
                            onSubmitted: (_) => ajouterHeure(setS),
                            decoration: const InputDecoration(
                              labelText: 'Heure de départ',
                              hintText: '06:30',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          onPressed: () => ajouterHeure(setS),
                          icon: const Icon(Icons.add_rounded),
                          tooltip: 'Ajouter l\'heure',
                        ),
                      ],
                    ),
                    if (t == null)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: retour,
                        onChanged: (v) => setS(() => retour = v ?? false),
                        title: const Text('Créer aussi le trajet retour (même prix)'),
                      ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            if (t != null)
              TextButton(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: ctx,
                    builder: (c2) => AlertDialog(
                      title: const Text('Supprimer ce trajet ?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c2, false), child: const Text('Non')),
                        FilledButton(onPressed: () => Navigator.pop(c2, true), child: const Text('Supprimer')),
                      ],
                    ),
                  );
                  if (ok == true) {
                    try {
                      await Repo.supprimerTrajet(t.id);
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } catch (e) {
                      if (ctx.mounted) toast(ctx, errMsg(e), error: true);
                    }
                  }
                },
                child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            FilledButton(
              onPressed: () async {
                if (!form.currentState!.validate()) return;
                ajouterHeure(setS);
                final places = int.parse(capacite.text);
                final data = {
                  'gare_depart_id': depart,
                  'gare_arrivee_id': arrivee,
                  'prix': double.parse(prix.text),
                  'horaires': heures,
                  // Envoyé seulement s'il sort de la valeur par défaut (serveur pas encore à jour : pas d'erreur).
                  if (places != 50 || (t?.capacite ?? 50) != 50) 'capacite': places,
                };
                try {
                  await Repo.enregistrerTrajet(t?.id, data);
                  if (retour) {
                    await Repo.enregistrerTrajet(null, {
                      ...data,
                      'gare_depart_id': arrivee,
                      'gare_arrivee_id': depart,
                    });
                  }
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  final dup = e is PostgrestException && e.code == '23505';
                  if (ctx.mounted) {
                    toast(ctx, dup ? 'Ce trajet existe déjà' : errMsg(e), error: true);
                  }
                }
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (enregistre == true) ref.invalidate(trajetsProvider);
  }
}
