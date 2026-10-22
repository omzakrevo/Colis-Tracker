import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/format.dart';
import '../core/lettres.dart';
import '../core/theme.dart';
import '../data/finance_models.dart';
import '../data/finance_repo.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../widgets/common.dart';
import 'finance_pdf.dart';
import 'finance_ui.dart';

/// Paie du mois : bulletins de salaire des employés, paiement, fiche d'émargement.
class FinancePaieScreen extends ConsumerStatefulWidget {
  const FinancePaieScreen({super.key});

  @override
  ConsumerState<FinancePaieScreen> createState() => _PaieState();
}

class _PaieState extends ConsumerState<FinancePaieScreen> {
  DateTime _mois = DateTime(DateTime.now().year, DateTime.now().month);
  List<Bulletin>? _bulletins;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _recharger();
  }

  Future<void> _recharger() async {
    try {
      final b = await FinanceRepo.bulletins(mois: _mois);
      if (mounted) setState(() => (_bulletins = b, _erreur = null));
    } catch (e) {
      if (mounted) setState(() => _erreur = errMsg(e));
    }
  }

  void _changerMois(int delta) {
    setState(() {
      _mois = DateTime(_mois.year, _mois.month + delta);
      _bulletins = null;
    });
    _recharger();
  }

  Future<void> _generer(List<Employe> employes, IdentiteLegale id) async {
    final existants = {for (final b in _bulletins ?? const <Bulletin>[]) b.employeId};
    final manquants = employes.where((e) => e.actif && !existants.contains(e.id)).toList();
    if (manquants.isEmpty) {
      toast(context, 'Tous les employés actifs ont déjà un bulletin pour ce mois');
      return;
    }
    try {
      for (final e in manquants) {
        await FinanceRepo.enregistrerBulletin(Bulletin.pour(e, _mois, cnssTaux: id.cnssTaux));
      }
      if (mounted) toast(context, '${manquants.length} bulletin${manquants.length > 1 ? 's' : ''} créé${manquants.length > 1 ? 's' : ''}');
      _recharger();
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  Future<void> _toutPayer(Map<int, Employe> parId) async {
    final aPayer = (_bulletins ?? const <Bulletin>[]).where((b) => !b.paye).toList();
    if (aPayer.isEmpty) return;
    final total = aPayer.fold<double>(0, (a, b) => a + b.net);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Marquer tous les salaires payés ?'),
        content: Text('${aPayer.length} bulletin${aPayer.length > 1 ? 's' : ''}, ${fcfa(total)} au total, daté d\'aujourd\'hui.'),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Non')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirmer'))],
      ),
    );
    if (ok != true) return;
    try {
      for (final b in aPayer) {
        await FinanceRepo.enregistrerBulletin(b.copyWith(statut: 'paye', datePaiement: DateTime.now()));
      }
      _recharger();
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  Future<void> _ouvrir(Employe e, Bulletin? b, IdentiteLegale id) async {
    final base = b ?? Bulletin.pour(e, _mois, cnssTaux: id.cnssTaux);
    final co = await ref.read(settingsProvider.future);
    if (!mounted) return;
    await ouvrirEditeur<void>(
      context,
      titre: 'Bulletin de ${e.nom}',
      contenu: (ctx) => _EditeurBulletin(employe: e, bulletin: base, co: co, identite: id),
    );
    _recharger();
  }

  @override
  Widget build(BuildContext context) {
    final employes = ref.watch(employesProvider);
    final identite = ref.watch(identiteProvider);
    final moisNom = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'][_mois.month - 1];
    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        Row(
          children: [
            IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.arrow_back_rounded)),
            const Expanded(child: PageHeader('Paie', subtitle: 'Bulletins de salaire, paiement et émargement.')),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(onPressed: () => _changerMois(-1), icon: const Icon(Icons.chevron_left_rounded)),
            Text('${moisNom[0].toUpperCase()}${moisNom.substring(1)} ${_mois.year}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            IconButton(onPressed: () => _changerMois(1), icon: const Icon(Icons.chevron_right_rounded)),
          ],
        ),
        if (_erreur != null) Text(_erreur!, style: const TextStyle(color: Colors.red)),
        AsyncView<List<Employe>>(
          value: employes,
          onRetry: () => ref.invalidate(employesProvider),
          builder: (liste) {
            final id = identite.value ?? const IdentiteLegale();
            final parId = {for (final e in liste) e.id!: e};
            final bs = _bulletins;
            if (bs == null) return const SkeletonList(count: 4, height: 64);
            final lignes = [for (final e in liste.where((e) => e.actif)) (e, bs.where((b) => b.employeId == e.id).firstOrNull)];
            // bulletins d'anciens employés encore présents ce mois-là
            for (final b in bs) {
              final e = parId[b.employeId];
              if (e != null && !e.actif) lignes.add((e, b));
            }
            final totalNet = bs.fold<double>(0, (a, b) => a + b.net);
            final totalPaye = bs.where((b) => b.paye).fold<double>(0, (a, b) => a + b.net);
            return Column(
              children: [
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(onPressed: () => _generer(liste, id), icon: const Icon(Icons.auto_awesome_rounded), label: const Text('Générer les bulletins du mois')),
                    OutlinedButton.icon(onPressed: bs.any((b) => !b.paye) ? () => _toutPayer(parId) : null, icon: const Icon(Icons.done_all_rounded), label: const Text('Tout marquer payé')),
                    OutlinedButton.icon(
                      onPressed: bs.isEmpty
                          ? null
                          : () async {
                              final co = await ref.read(settingsProvider.future);
                              final l = [for (final b in bs) if (parId[b.employeId] != null) (parId[b.employeId]!, b)];
                              if (context.mounted) await imprimerPdf(context, () => emargementPdf(l, _mois, co, id), 'emargement-${_mois.year}-${_mois.month}');
                            },
                      icon: const Icon(Icons.fact_check_rounded),
                      label: const Text('Fiche d\'émargement'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SectionCard(
                  title: 'Masse salariale du mois : ${fcfa(totalNet)}',
                  icon: Icons.request_quote_rounded,
                  accent: const Color(0xFF16A34A),
                  child: Text('Payé : ${fcfa(totalPaye)} · Reste à payer : ${fcfa(totalNet - totalPaye)}', style: const TextStyle(color: Brand.muted)),
                ),
                const SizedBox(height: 14),
                if (lignes.isEmpty) const Padding(padding: EdgeInsets.all(24), child: EmptyState(icon: Icons.badge_rounded, text: 'Aucun employé. Ajoutez-les dans « Employés et contrats ».')),
                for (final (e, b) in lignes)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      onTap: () => _ouvrir(e, b, id),
                      leading: Icon(b == null ? Icons.radio_button_unchecked_rounded : (b.paye ? Icons.check_circle_rounded : Icons.edit_note_rounded), color: b == null ? Brand.muted : (b.paye ? const Color(0xFF16A34A) : Brand.orange)),
                      title: Text(e.nom, style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(b == null ? 'Pas de bulletin — touchez pour en créer un' : (b.paye ? 'Payé le ${b.datePaiement == null ? '' : dateFr(b.datePaiement!)}' : 'À payer')),
                      trailing: Text(b == null ? fcfa(e.salaireBase) : fcfa(b.net), style: TextStyle(fontWeight: FontWeight.w800, color: b == null ? Brand.muted : null)),
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

class _LigneEdit {
  _LigneEdit(String l, String m)
      : libelle = TextEditingController(text: l),
        montant = TextEditingController(text: m);
  final TextEditingController libelle, montant;
}

class _EditeurBulletin extends StatefulWidget {
  const _EditeurBulletin({required this.employe, required this.bulletin, required this.co, required this.identite});
  final Employe employe;
  final Bulletin bulletin;
  final CompanySettings co;
  final IdentiteLegale identite;

  @override
  State<_EditeurBulletin> createState() => _EditeurBulletinState();
}

class _EditeurBulletinState extends State<_EditeurBulletin> {
  late final _base = TextEditingController(text: '${widget.bulletin.salaireBase.round()}');
  late final _notes = TextEditingController(text: widget.bulletin.notes);
  late final List<_LigneEdit> _primes = [for (final l in widget.bulletin.primes) _LigneEdit(l.libelle, '${l.montant.round()}')];
  late final List<_LigneEdit> _retenues = [for (final l in widget.bulletin.retenues) _LigneEdit(l.libelle, '${l.montant.round()}')];
  late String _mode = widget.bulletin.modePaiement;
  late bool _paye = widget.bulletin.paye;
  late DateTime _datePaiement = widget.bulletin.datePaiement ?? DateTime.now();
  bool _saving = false;
  bool _enregistre = false;

  Bulletin _compose() => Bulletin(
    id: widget.bulletin.id,
    employeId: widget.bulletin.employeId,
    mois: widget.bulletin.mois,
    salaireBase: lireMontant(_base),
    primes: [for (final l in _primes) if (l.libelle.text.trim().isNotEmpty || lireMontant(l.montant) > 0) LigneMontant(l.libelle.text.trim().isEmpty ? 'Prime' : l.libelle.text.trim(), lireMontant(l.montant))],
    retenues: [for (final l in _retenues) if (l.libelle.text.trim().isNotEmpty || lireMontant(l.montant) > 0) LigneMontant(l.libelle.text.trim().isEmpty ? 'Retenue' : l.libelle.text.trim(), lireMontant(l.montant))],
    statut: _paye ? 'paye' : 'brouillon',
    datePaiement: _paye ? _datePaiement : null,
    modePaiement: _mode,
    notes: _notes.text.trim(),
  );

  Future<void> _enregistrer() async {
    setState(() => _saving = true);
    try {
      await FinanceRepo.enregistrerBulletin(_compose());
      if (mounted) {
        setState(() => _enregistre = true);
        toast(context, 'Bulletin enregistré');
      }
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _lignes(String titre, List<_LigneEdit> l, String vide) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(titre, style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      for (var i = 0; i < l.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(flex: 3, child: TextFormField(controller: l[i].libelle, decoration: const InputDecoration(labelText: 'Libellé'))),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: TextFormField(controller: l[i].montant, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Montant'), onChanged: (_) => setState(() {}))),
              IconButton(onPressed: () => setState(() => l.removeAt(i)), icon: const Icon(Icons.remove_circle_outline_rounded)),
            ],
          ),
        ),
      TextButton.icon(onPressed: () => setState(() => l.add(_LigneEdit('', ''))), icon: const Icon(Icons.add_rounded), label: Text(vide)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final b = _compose();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        champMontant(_base, 'Salaire de base', onChanged: (_) => setState(() {})),
        const SizedBox(height: 14),
        _lignes('Primes et indemnités', _primes, 'Ajouter une prime'),
        const SizedBox(height: 10),
        _lignes('Retenues (CNSS, impôt, avances…)', _retenues, 'Ajouter une retenue'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Brand.orangeSoft, borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Salaire brut'), Text(fcfa(b.brut), style: const TextStyle(fontWeight: FontWeight.w700))]),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Retenues'), Text('- ${fcfa(b.totalRetenues)}', style: const TextStyle(fontWeight: FontWeight.w700))]),
              const Divider(),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Net à payer', style: TextStyle(fontWeight: FontWeight.w800)), Text(fcfa(b.net), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))]),
              Align(alignment: Alignment.centerLeft, child: Text(montantEnLettres(b.net), style: const TextStyle(color: Brand.muted, fontStyle: FontStyle.italic, fontSize: 12.5))),
            ],
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: modesPaiement.contains(_mode) ? _mode : modesPaiement.first,
          decoration: const InputDecoration(labelText: 'Mode de paiement'),
          items: [for (final m in modesPaiement) DropdownMenuItem(value: m, child: Text(m))],
          onChanged: (v) => setState(() => _mode = v ?? _mode),
        ),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: _paye, onChanged: (v) => setState(() => _paye = v), title: const Text('Salaire payé')),
        if (_paye) ChampDate(libelle: 'Date de paiement', valeur: _datePaiement, onChanged: (d) => setState(() => _datePaiement = d ?? _datePaiement)),
        const SizedBox(height: 12),
        champTexte(_notes, 'Observations', lignes: 2),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(onPressed: _saving ? null : _enregistrer, icon: const Icon(Icons.check_rounded), label: const Text('Enregistrer')),
            BoutonsPdf(construire: () => bulletinPdf(_compose(), widget.employe, widget.co, widget.identite), nom: 'bulletin-${widget.employe.nom}-${widget.bulletin.mois.year}-${widget.bulletin.mois.month}'),
            if (widget.bulletin.id != null && !_enregistre)
              TextButton.icon(
                onPressed: () async {
                  try {
                    await FinanceRepo.supprimerBulletin(widget.bulletin.id!);
                    if (context.mounted) Navigator.pop(context);
                  } catch (e) {
                    if (context.mounted) toast(context, errMsg(e), error: true);
                  }
                },
                icon: const Icon(Icons.delete_rounded, color: Colors.red),
                label: const Text('Supprimer', style: TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ],
    );
  }
}
