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
import 'finance_documents.dart';
import 'finance_ui.dart';

/// Personnel de l'entreprise : fiches des employés et établissement des contrats de travail.
class FinanceEmployesScreen extends ConsumerStatefulWidget {
  const FinanceEmployesScreen({super.key});

  @override
  ConsumerState<FinanceEmployesScreen> createState() => _EmployesState();
}

class _EmployesState extends ConsumerState<FinanceEmployesScreen> {
  String _recherche = '';
  bool _inactifs = false;

  Future<void> _editer([Employe? e]) async {
    final gares = ref.read(garesProvider).value ?? const <Gare>[];
    await ouvrirEditeur<void>(
      context,
      titre: e == null ? 'Nouvel employé' : e.nom,
      contenu: (ctx) => _EditeurEmploye(employe: e, gares: gares, parent: this),
    );
    ref.invalidate(employesProvider);
  }

  Future<void> _contrat(Employe e) async {
    await ouvrirEditeurDocument(context, ref, type: TypeDoc.contrat, employe: e);
  }

  @override
  Widget build(BuildContext context) {
    final liste = ref.watch(employesProvider);
    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        Row(
          children: [
            IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.arrow_back_rounded)),
            const Expanded(child: PageHeader('Employés et contrats', subtitle: 'Personnel de l\'entreprise, contrats de travail.')),
          ],
        ),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(onPressed: () => _editer(), icon: const Icon(Icons.person_add_rounded), label: const Text('Nouvel employé')),
            SizedBox(width: 260, child: TextField(onChanged: (v) => setState(() => _recherche = v.toLowerCase()), decoration: const InputDecoration(hintText: 'Rechercher…', prefixIcon: Icon(Icons.search_rounded)))),
            FilterChip(label: const Text('Anciens employés'), selected: _inactifs, onSelected: (v) => setState(() => _inactifs = v)),
          ],
        ),
        const SizedBox(height: 14),
        AsyncView<List<Employe>>(
          value: liste,
          onRetry: () => ref.invalidate(employesProvider),
          builder: (l) {
            final f = l.where((e) => e.actif != _inactifs && (_recherche.isEmpty || e.nom.toLowerCase().contains(_recherche) || e.poste.toLowerCase().contains(_recherche) || e.matricule.toLowerCase().contains(_recherche))).toList();
            if (f.isEmpty) return const Padding(padding: EdgeInsets.all(24), child: EmptyState(icon: Icons.badge_rounded, text: 'Aucun employé.'));
            return Column(
              children: [
                for (final e in f)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      onTap: () => _editer(e),
                      leading: CircleAvatar(backgroundColor: Brand.orangeSoft, child: Text(e.nom.isEmpty ? '?' : e.nom[0].toUpperCase(), style: const TextStyle(color: Brand.orange, fontWeight: FontWeight.w800))),
                      title: Text(e.nom, style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('${e.poste.isEmpty ? 'Poste non renseigné' : e.poste} · ${e.typeContrat}${e.matricule.isEmpty ? '' : ' · ${e.matricule}'}'),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(fcfa(e.salaireBase), style: const TextStyle(fontWeight: FontWeight.w800)),
                          InkWell(onTap: () => _contrat(e), child: const Padding(padding: EdgeInsets.only(top: 2), child: Text('Contrat', style: TextStyle(color: Brand.orange, fontWeight: FontWeight.w700, fontSize: 12.5)))),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _EditeurEmploye extends StatefulWidget {
  const _EditeurEmploye({required this.employe, required this.gares, required this.parent});
  final Employe? employe;
  final List<Gare> gares;
  final _EmployesState parent;

  @override
  State<_EditeurEmploye> createState() => _EditeurEmployeState();
}

class _EditeurEmployeState extends State<_EditeurEmploye> {
  final _form = GlobalKey<FormState>();
  late final _nom = TextEditingController(text: widget.employe?.nom ?? '');
  late final _matricule = TextEditingController(text: widget.employe?.matricule ?? '');
  late final _poste = TextEditingController(text: widget.employe?.poste ?? '');
  late final _tel = TextEditingController(text: widget.employe?.telephone ?? '');
  late final _adresse = TextEditingController(text: widget.employe?.adresse ?? '');
  late final _piece = TextEditingController(text: widget.employe?.pieceIdentite ?? '');
  late final _salaire = TextEditingController(text: widget.employe == null ? '' : '${widget.employe!.salaireBase.round()}');
  late final _transport = TextEditingController(text: widget.employe == null || widget.employe!.indemniteTransport == 0 ? '' : '${widget.employe!.indemniteTransport.round()}');
  late final _logement = TextEditingController(text: widget.employe == null || widget.employe!.indemniteLogement == 0 ? '' : '${widget.employe!.indemniteLogement.round()}');
  late final _cnss = TextEditingController(text: widget.employe?.numeroCnss ?? '');
  late final _compte = TextEditingController(text: widget.employe?.compteBancaire ?? '');
  late final _notes = TextEditingController(text: widget.employe?.notes ?? '');
  late DateTime? _naissance = widget.employe?.dateNaissance;
  late DateTime? _embauche = widget.employe?.dateEmbauche;
  late DateTime? _finContrat = widget.employe?.dateFinContrat;
  late String _contrat = widget.employe?.typeContrat ?? 'CDI';
  late int? _gare = widget.employe?.gareId;
  late bool _actif = widget.employe?.actif ?? true;
  bool _saving = false;

  Future<void> _enregistrer() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await FinanceRepo.enregistrerEmploye(
        Employe(
          id: widget.employe?.id,
          matricule: _matricule.text.trim(),
          nom: _nom.text.trim(),
          poste: _poste.text.trim(),
          telephone: _tel.text.trim(),
          adresse: _adresse.text.trim(),
          dateNaissance: _naissance,
          pieceIdentite: _piece.text.trim(),
          dateEmbauche: _embauche,
          typeContrat: _contrat,
          dateFinContrat: _finContrat,
          salaireBase: lireMontant(_salaire),
          indemniteTransport: lireMontant(_transport),
          indemniteLogement: lireMontant(_logement),
          numeroCnss: _cnss.text.trim(),
          compteBancaire: _compte.text.trim(),
          gareId: _gare,
          actif: _actif,
          notes: _notes.text.trim(),
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
      setState(() => _saving = false);
    }
  }

  Future<void> _supprimer() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Supprimer cet employé ?'),
        content: const Text('Ses bulletins de salaire seront aussi supprimés. Pour un employé parti, préférez le marquer « ancien » (case Actif).'),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Non')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Supprimer'))],
      ),
    );
    if (ok != true) return;
    try {
      await FinanceRepo.supprimerEmploye(widget.employe!.id!);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    const esp = SizedBox(height: 12);
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          champTexte(_nom, 'Nom et prénoms', requis: true),
          esp,
          Row(children: [Expanded(child: champTexte(_matricule, 'Matricule')), const SizedBox(width: 10), Expanded(child: champTexte(_poste, 'Poste / fonction'))]),
          esp,
          champTexte(_tel, 'Téléphone', clavier: TextInputType.phone),
          esp,
          champTexte(_adresse, 'Adresse'),
          esp,
          ChampDate(libelle: 'Date de naissance', valeur: _naissance, facultatif: true, onChanged: (d) => setState(() => _naissance = d)),
          esp,
          champTexte(_piece, 'Pièce d\'identité (type et numéro)'),
          esp,
          DropdownButtonFormField<String>(
            initialValue: typesContrat.contains(_contrat) ? _contrat : 'CDI',
            decoration: const InputDecoration(labelText: 'Type de contrat'),
            items: [for (final t in typesContrat) DropdownMenuItem(value: t, child: Text(t))],
            onChanged: (v) => setState(() => _contrat = v ?? _contrat),
          ),
          esp,
          ChampDate(libelle: 'Date d\'embauche', valeur: _embauche, facultatif: true, onChanged: (d) => setState(() => _embauche = d)),
          if (_contrat != 'CDI') ...[esp, ChampDate(libelle: 'Fin du contrat', valeur: _finContrat, facultatif: true, onChanged: (d) => setState(() => _finContrat = d))],
          esp,
          champMontant(_salaire, 'Salaire mensuel de base', requis: true),
          esp,
          Row(children: [Expanded(child: champMontant(_transport, 'Indemnité transport')), const SizedBox(width: 10), Expanded(child: champMontant(_logement, 'Indemnité logement'))]),
          esp,
          Row(children: [Expanded(child: champTexte(_cnss, 'N° CNSS')), const SizedBox(width: 10), Expanded(child: champTexte(_compte, 'Compte bancaire / mobile money'))]),
          if (widget.gares.isNotEmpty) ...[
            esp,
            DropdownButtonFormField<int?>(
              initialValue: _gare,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Gare d\'affectation'),
              items: [const DropdownMenuItem<int?>(value: null, child: Text('— Aucune —')), for (final g in widget.gares) DropdownMenuItem<int?>(value: g.id, child: Text(g.nom))],
              onChanged: (v) => setState(() => _gare = v),
            ),
          ],
          esp,
          champTexte(_notes, 'Notes', lignes: 2),
          SwitchListTile(contentPadding: EdgeInsets.zero, value: _actif, onChanged: (v) => setState(() => _actif = v), title: const Text('Employé actif')),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(onPressed: _saving ? null : _enregistrer, icon: const Icon(Icons.check_rounded), label: const Text('Enregistrer')),
              if (widget.employe != null)
                OutlinedButton.icon(
                  onPressed: () async {
                    final e = widget.employe!;
                    Navigator.pop(context);
                    await widget.parent._contrat(e);
                  },
                  icon: const Icon(Icons.badge_rounded),
                  label: const Text('Établir un contrat de travail'),
                ),
              if (widget.employe != null) TextButton.icon(onPressed: _supprimer, icon: const Icon(Icons.delete_rounded, color: Colors.red), label: const Text('Supprimer', style: TextStyle(color: Colors.red))),
            ],
          ),
        ],
      ),
    );
  }
}
