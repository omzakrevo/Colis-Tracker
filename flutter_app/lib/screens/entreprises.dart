import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/identifiant.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../data/repo.dart';
import '../widgets/common.dart';

final _entreprisesProvider = FutureProvider<List<Company>>(
  (ref) => Repo.entreprises(),
);
final _saStatsProvider = FutureProvider<Map<String, dynamic>>(
  (ref) => Repo.saStats(),
);
final _filtreProvider = NotifierProvider<_FiltreNotifier, String?>(
  _FiltreNotifier.new,
);

class _FiltreNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? v) => state = v;
}

Color _couleurStatut(String s) => switch (s) {
  'actif' => const Color(0xFF16A34A),
  'en_attente' => const Color(0xFFCA8A04),
  'expire' => const Color(0xFFEA580C),
  _ => const Color(0xFFDC2626),
};

String _libelleStatut(String s) => switch (s) {
  'actif' => 'Actif',
  'en_attente' => 'En attente',
  'expire' => 'Expiré',
  _ => 'Suspendu',
};

/// Console du super administrateur : valider, prolonger, suspendre ou créer des entreprises.
class EntreprisesScreen extends ConsumerWidget {
  const EntreprisesScreen({super.key});

  void _refresh(WidgetRef ref) {
    ref.invalidate(_entreprisesProvider);
    ref.invalidate(_saStatsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(_entreprisesProvider);
    final stats = ref.watch(_saStatsProvider);
    final filtre = ref.watch(_filtreProvider);

    return RefreshIndicator(
      onRefresh: () async => _refresh(ref),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          PageHeader(
            'Entreprises',
            subtitle: 'Abonnements de la plateforme',
            actions: [
              FilledButton.icon(
                onPressed: () => _creer(context, ref),
                icon: const Icon(Icons.add_business_rounded),
                label: const Text('Nouvelle'),
              ),
            ],
          ),
          AsyncView<Map<String, dynamic>>(
            value: stats,
            loading: const Skeleton(height: 84),
            builder: (s) => Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _Kpi('Entreprises', s['entreprises'], Brand.emerald),
                _Kpi('En attente', s['en_attente'], const Color(0xFFCA8A04)),
                _Kpi('Actives', s['actives'], const Color(0xFF16A34A)),
                _Kpi('Expirées', s['expirees'], const Color(0xFFEA580C)),
                _Kpi('Suspendues', s['suspendues'], const Color(0xFFDC2626)),
                _Kpi(
                  'Utilisateurs',
                  s['utilisateurs'],
                  const Color(0xFF2563EB),
                ),
              ],
            ),
          ).reveal(),
          const SizedBox(height: 14),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final f in const [
                  (null, 'Toutes'),
                  ('en_attente', 'En attente'),
                  ('actif', 'Actives'),
                  ('expire', 'Expirées'),
                  ('suspendu', 'Suspendues'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f.$2),
                      selected: filtre == f.$1,
                      onSelected: (_) =>
                          ref.read(_filtreProvider.notifier).set(f.$1),
                      selectedColor: Brand.emerald,
                      labelStyle: TextStyle(
                        color: filtre == f.$1 ? Colors.white : Brand.ink,
                        fontWeight: FontWeight.w700,
                      ),
                      showCheckmark: false,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AsyncView<List<Company>>(
            value: list,
            onRetry: () => _refresh(ref),
            builder: (all) {
              final items = filtre == null
                  ? all
                  : all.where((c) => c.statutReel == filtre).toList();
              if (items.isEmpty)
                return const EmptyState(
                  icon: Icons.business_outlined,
                  text: 'Aucune entreprise',
                );
              return Column(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _CompanyCard(
                        items[i],
                        onChanged: () => _refresh(ref),
                      ).reveal(i < 10 ? i : 10),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _creer(BuildContext context, WidgetRef ref) async {
    final ent = TextEditingController(), ville = TextEditingController();
    final nom = TextEditingController(),
        tel = TextEditingController(),
        pass = TextEditingController();
    final key = GlobalKey<FormState>();
    var fin = DateTime.now().add(const Duration(days: 30));
    var max = 5;
    String? req(String? v) => (v ?? '').trim().isEmpty ? 'Requis' : null;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text(
            'Nouvelle entreprise',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: SizedBox(
            width: 440,
            child: Form(
              key: key,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: ent,
                      decoration: const InputDecoration(
                        labelText: 'Entreprise *',
                      ),
                      validator: req,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: ville,
                      decoration: const InputDecoration(labelText: 'Ville'),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: nom,
                      decoration: const InputDecoration(
                        labelText: 'Nom de l\'administrateur *',
                      ),
                      validator: req,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: tel,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Téléphone de l\'administrateur *',
                      ),
                      validator: (v) =>
                          estTelephone(v ?? '') ? null : 'Numéro invalide',
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: pass,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Mot de passe *',
                      ),
                      validator: (v) =>
                          (v ?? '').length < 6 ? '6 caractères minimum' : null,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: fin,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(
                            const Duration(days: 3650),
                          ),
                        );
                        if (d != null) setS(() => fin = d);
                      },
                      icon: const Icon(Icons.event_rounded, size: 18),
                      label: Text('Abonnement jusqu\'au ${dateFr(fin)}'),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Utilisateurs maximum',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        IconButton(
                          onPressed: max > 1 ? () => setS(() => max--) : null,
                          icon: const Icon(Icons.remove_circle_outline_rounded),
                        ),
                        Text(
                          '$max',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        IconButton(
                          onPressed: () => setS(() => max++),
                          icon: const Icon(Icons.add_circle_outline_rounded),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () {
                if (key.currentState!.validate()) Navigator.pop(ctx, true);
              },
              child: const Text('Créer'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await Repo.creerEntreprise(
        entreprise: ent.text.trim(),
        ville: ville.text.trim(),
        nomAdmin: nom.text.trim(),
        telephone: tel.text.trim(),
        password: pass.text,
        fin: fin,
        max: max,
      );
      _refresh(ref);
      if (context.mounted) toast(context, 'Entreprise créée et activée');
    } catch (e) {
      if (context.mounted) toast(context, errMsg(e), error: true);
    }
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value, this.color);
  final String label;
  final Object? value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 150,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Brand.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CountUp(
          (value as num?) ?? 0,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        Text(label, style: const TextStyle(color: Brand.muted, fontSize: 12.5)),
      ],
    ),
  );
}

class _CompanyCard extends ConsumerWidget {
  const _CompanyCard(this.c, {required this.onChanged});
  final Company c;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statut = c.statutReel;
    final color = _couleurStatut(statut);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    c.nom,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    _libelleStatut(statut),
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${c.adminNom ?? '—'} · ${c.adminIdentifiant ?? c.telephone ?? '—'}${c.ville != null ? ' · ${c.ville}' : ''}',
              style: const TextStyle(color: Brand.muted, fontSize: 13),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 18,
              runSpacing: 6,
              children: [
                _Info(
                  Icons.groups_rounded,
                  '${c.nbUtilisateurs ?? 0} / ${c.maxUtilisateurs} utilisateurs',
                ),
                _Info(
                  Icons.event_rounded,
                  c.abonnementFin == null
                      ? 'Sans limite de date'
                      : 'Jusqu\'au ${dateFr(c.abonnementFin!)}',
                ),
                _Info(Icons.workspace_premium_rounded, c.plan),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (c.statut != 'actif' || statut == 'expire')
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      backgroundColor: const Color(0xFF16A34A),
                    ),
                    onPressed: () => _abonnement(
                      context,
                      ref,
                      c.statut == 'en_attente' ? 'Valider' : 'Réactiver',
                    ),
                    icon: const Icon(Icons.check_circle_rounded, size: 18),
                    label: Text(
                      c.statut == 'en_attente' ? 'Valider' : 'Réactiver',
                    ),
                  ),
                if (c.statut == 'actif')
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 40),
                    ),
                    onPressed: () =>
                        _abonnement(context, ref, 'Prolonger / modifier'),
                    icon: const Icon(Icons.update_rounded, size: 18),
                    label: const Text('Prolonger / modifier'),
                  ),
                FilterChip(
                  avatar: Icon(Icons.account_balance_rounded, size: 18, color: c.moduleFinance ? const Color(0xFF16A34A) : Brand.muted),
                  label: Text(c.moduleFinance ? 'Comptabilité activée' : 'Comptabilité désactivée'),
                  selected: c.moduleFinance,
                  onSelected: (v) async {
                    try {
                      await Repo.definirModuleFinance(c.id, v);
                      onChanged();
                      if (context.mounted) toast(context, v ? 'Module Comptabilité activé pour ${c.nom}' : 'Module Comptabilité désactivé pour ${c.nom}');
                    } catch (e) {
                      if (context.mounted) toast(context, errMsg(e), error: true);
                    }
                  },
                ),
                if (c.statut != 'suspendu')
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      foregroundColor: const Color(0xFFDC2626),
                    ),
                    onPressed: () => _suspendre(context),
                    icon: const Icon(Icons.block_rounded, size: 18),
                    label: const Text('Suspendre'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _abonnement(
    BuildContext context,
    WidgetRef ref,
    String titre,
  ) async {
    var fin =
        (c.abonnementFin != null && c.abonnementFin!.isAfter(DateTime.now()))
        ? c.abonnementFin!
        : DateTime.now().add(const Duration(days: 30));
    var max = c.maxUtilisateurs;
    final plan = TextEditingController(text: c.plan);
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(
            '$titre — ${c.nom}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Abonnement jusqu\'au',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: fin,
                      firstDate: DateTime(2024),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                    );
                    if (d != null) setS(() => fin = d);
                  },
                  icon: const Icon(Icons.event_rounded, size: 18),
                  label: Text(dateFr(fin)),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final m in const [
                      (1, '+1 mois'),
                      (3, '+3 mois'),
                      (6, '+6 mois'),
                      (12, '+1 an'),
                    ])
                      ActionChip(
                        label: Text(m.$2),
                        onPressed: () {
                          final base = fin.isAfter(DateTime.now())
                              ? fin
                              : DateTime.now();
                          setS(
                            () => fin = DateTime(
                              base.year,
                              base.month + m.$1,
                              base.day,
                            ),
                          );
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: plan,
                  decoration: const InputDecoration(
                    labelText: 'Formule (plan)',
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Utilisateurs maximum',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      onPressed: max > 1 ? () => setS(() => max--) : null,
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                    ),
                    Text(
                      '$max',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    IconButton(
                      onPressed: () => setS(() => max++),
                      icon: const Icon(Icons.add_circle_outline_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Activer'),
            ),
          ],
        ),
      ),
    );
    if (res != true) return;
    try {
      await Repo.definirAbonnement(
        c.id,
        'actif',
        fin,
        plan: plan.text.trim().isEmpty ? null : plan.text.trim(),
        max: max,
      );
      onChanged();
      if (context.mounted) toast(context, 'Abonnement mis à jour');
    } catch (e) {
      if (context.mounted) toast(context, errMsg(e), error: true);
    }
  }

  Future<void> _suspendre(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Suspendre cette entreprise ?'),
        content: Text(
          'Tous les utilisateurs de « ${c.nom} » seront déconnectés et ne pourront plus accéder à l\'application.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              minimumSize: const Size(0, 44),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Suspendre'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Repo.definirAbonnement(c.id, 'suspendu', c.abonnementFin);
      onChanged();
      if (context.mounted) toast(context, 'Entreprise suspendue');
    } catch (e) {
      if (context.mounted) toast(context, errMsg(e), error: true);
    }
  }
}

class _Info extends StatelessWidget {
  const _Info(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: Brand.muted),
      const SizedBox(width: 5),
      Text(text, style: const TextStyle(fontSize: 13)),
    ],
  );
}
