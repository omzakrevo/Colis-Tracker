import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/finance_models.dart';
import '../data/finance_repo.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../widgets/common.dart';
import 'finance_ui.dart';

/// Dépenses de l'entreprise : saisie, modification, suppression, totaux par catégorie.
class FinanceDepensesScreen extends ConsumerStatefulWidget {
  const FinanceDepensesScreen({super.key});

  @override
  ConsumerState<FinanceDepensesScreen> createState() => _DepensesState();
}

class _DepensesState extends ConsumerState<FinanceDepensesScreen> {
  DateTime _debut = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _fin = DateTime.now();
  String? _categorie;
  List<Depense>? _liste;
  String? _erreur;
  bool _charge = false;

  @override
  void initState() {
    super.initState();
    _recharger();
  }

  Future<void> _recharger() async {
    setState(() {
      _charge = true;
      _erreur = null;
    });
    try {
      final l = await FinanceRepo.depenses(debut: _debut, fin: _fin, categorie: _categorie);
      if (mounted) setState(() => _liste = l);
    } catch (e) {
      if (mounted) setState(() => _erreur = errMsg(e));
    } finally {
      if (mounted) setState(() => _charge = false);
    }
  }

  Future<void> _editer([Depense? d]) async {
    final gares = ref.read(garesProvider).value ?? const <Gare>[];
    final ok = await ouvrirEditeur<bool>(
      context,
      titre: d == null ? 'Nouvelle dépense' : 'Modifier la dépense',
      contenu: (ctx) => _EditeurDepense(depense: d, gares: gares),
    );
    if (ok == true) _recharger();
  }

  @override
  Widget build(BuildContext context) {
    final l = _liste ?? const <Depense>[];
    final total = l.fold<double>(0, (a, d) => a + d.montant);
    final parCat = <String, double>{};
    for (final d in l) {
      parCat[d.categorie] = (parCat[d.categorie] ?? 0) + d.montant;
    }
    final cats = parCat.keys.toList()..sort((a, b) => parCat[b]!.compareTo(parCat[a]!));

    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        Row(
          children: [
            IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.arrow_back_rounded)),
            const Expanded(child: PageHeader('Dépenses', subtitle: 'Toutes les sorties d\'argent de l\'entreprise.')),
          ],
        ),
        SelecteurPeriode(
          debut: _debut,
          fin: _fin,
          onChanged: (d, f) {
            setState(() {
              _debut = d;
              _fin = f;
            });
            _recharger();
          },
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 280,
              child: DropdownButtonFormField<String?>(
                initialValue: _categorie,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Catégorie'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Toutes les catégories')),
                  for (final c in categoriesDepenses) DropdownMenuItem<String?>(value: c, child: Text(c)),
                ],
                onChanged: (v) {
                  setState(() => _categorie = v);
                  _recharger();
                },
              ),
            ),
            FilledButton.icon(onPressed: () => _editer(), icon: const Icon(Icons.add_rounded), label: const Text('Nouvelle dépense')),
            OutlinedButton.icon(
              onPressed: () => context.push('/rapports/detail', extra: 'depenses'),
              icon: const Icon(Icons.table_chart_rounded),
              label: const Text('Rapport des dépenses (PDF / Excel)'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_erreur != null) Text(_erreur!, style: const TextStyle(color: Colors.red)),
        if (_charge && _liste == null) const SkeletonList(count: 4, height: 64),
        if (_liste != null) ...[
          SectionCard(
            title: 'Total : ${fcfa(total)}',
            icon: Icons.payments_rounded,
            accent: const Color(0xFFDC2626),
            child: cats.isEmpty
                ? const Text('Aucune dépense sur cette période.', style: TextStyle(color: Brand.muted))
                : Column(
                    children: [
                      for (final c in cats)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(child: Text(c)),
                              Text(fcfa(parCat[c]!), style: const TextStyle(fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 14),
          for (final d in l)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                onTap: () => _editer(d),
                leading: const Icon(Icons.north_east_rounded, color: Color(0xFFDC2626)),
                title: Text(d.libelle, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('${dateFr(d.date)} · ${d.categorie}${d.beneficiaire.isEmpty ? '' : ' · ${d.beneficiaire}'} · ${d.modePaiement}'),
                trailing: Text(fcfa(d.montant), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
        ],
      ],
    );
  }
}

class _EditeurDepense extends StatefulWidget {
  const _EditeurDepense({required this.depense, required this.gares});
  final Depense? depense;
  final List<Gare> gares;

  @override
  State<_EditeurDepense> createState() => _EditeurDepenseState();
}

class _EditeurDepenseState extends State<_EditeurDepense> {
  final _form = GlobalKey<FormState>();
  late final _libelle = TextEditingController(text: widget.depense?.libelle ?? '');
  late final _montant = TextEditingController(text: widget.depense == null ? '' : '${widget.depense!.montant.round()}');
  late final _benef = TextEditingController(text: widget.depense?.beneficiaire ?? '');
  late final _ref = TextEditingController(text: widget.depense?.reference ?? '');
  late final _notes = TextEditingController(text: widget.depense?.notes ?? '');
  late DateTime _date = widget.depense?.date ?? DateTime.now();
  late String _cat = widget.depense?.categorie ?? 'Autres';
  late String _mode = widget.depense?.modePaiement ?? 'Espèces';
  late int? _gare = widget.depense?.gareId;
  bool _saving = false;

  Future<void> _enregistrer() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await FinanceRepo.enregistrerDepense(
        Depense(
          id: widget.depense?.id,
          date: _date,
          categorie: _cat,
          libelle: _libelle.text.trim(),
          beneficiaire: _benef.text.trim(),
          montant: lireMontant(_montant),
          modePaiement: _mode,
          reference: _ref.text.trim(),
          gareId: _gare,
          notes: _notes.text.trim(),
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
      setState(() => _saving = false);
    }
  }

  Future<void> _supprimer() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Supprimer cette dépense ?'),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Non')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Supprimer'))],
      ),
    );
    if (ok != true) return;
    try {
      await FinanceRepo.supprimerDepense(widget.depense!.id!);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        champTexte(_libelle, 'Libellé (objet de la dépense)', requis: true),
        const SizedBox(height: 12),
        champMontant(_montant, 'Montant', requis: true),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _cat,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Catégorie'),
          items: [for (final c in categoriesDepenses) DropdownMenuItem(value: c, child: Text(c))],
          onChanged: (v) => setState(() => _cat = v ?? _cat),
        ),
        const SizedBox(height: 12),
        ChampDate(libelle: 'Date', valeur: _date, onChanged: (d) => setState(() => _date = d ?? _date)),
        const SizedBox(height: 12),
        champTexte(_benef, 'Bénéficiaire / fournisseur'),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _mode,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Mode de paiement'),
          items: [for (final m in modesPaiement) DropdownMenuItem(value: m, child: Text(m))],
          onChanged: (v) => setState(() => _mode = v ?? _mode),
        ),
        const SizedBox(height: 12),
        champTexte(_ref, 'Référence (n° de facture, chèque…)'),
        if (widget.gares.length > 1) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            initialValue: _gare,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Gare concernée'),
            items: [const DropdownMenuItem<int?>(value: null, child: Text('— Toute l\'entreprise —')), for (final g in widget.gares) DropdownMenuItem<int?>(value: g.id, child: Text(g.nom))],
            onChanged: (v) => setState(() => _gare = v),
          ),
        ],
        const SizedBox(height: 12),
        champTexte(_notes, 'Notes', lignes: 2),
        const SizedBox(height: 18),
        Row(
          children: [
            if (widget.depense != null)
              TextButton.icon(onPressed: _supprimer, icon: const Icon(Icons.delete_rounded, color: Colors.red), label: const Text('Supprimer', style: TextStyle(color: Colors.red))),
            const Spacer(),
            FilledButton.icon(onPressed: _saving ? null : _enregistrer, icon: const Icon(Icons.check_rounded), label: const Text('Enregistrer')),
          ],
        ),
      ],
    ),
  );
}
