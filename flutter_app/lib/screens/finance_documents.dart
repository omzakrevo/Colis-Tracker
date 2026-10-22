import 'dart:typed_data';

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

Future<Uint8List> construireDocument(FinanceDoc d, CompanySettings co, IdentiteLegale id, {Employe? employe}) => switch (d.type) {
  TypeDoc.decharge => dechargePdf(d, co, id),
  TypeDoc.facture => facturePdf(d, co, id),
  TypeDoc.recu => recuPaiementPdf(d, co, id),
  TypeDoc.contrat => contratPdf(d, co, id),
};

/// Liste des documents comptables (décharges, factures, reçus, contrats) avec création, modification et impression.
class FinanceDocumentsScreen extends ConsumerStatefulWidget {
  const FinanceDocumentsScreen({super.key});

  @override
  ConsumerState<FinanceDocumentsScreen> createState() => _DocumentsState();
}

class _DocumentsState extends ConsumerState<FinanceDocumentsScreen> {
  TypeDoc? _type;
  List<FinanceDoc>? _liste;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _recharger();
  }

  Future<void> _recharger() async {
    try {
      final l = await FinanceRepo.documents(type: _type);
      if (mounted) {
        setState(() {
          _liste = l;
          _erreur = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _erreur = errMsg(e));
    }
  }

  Future<void> _ouvrir(TypeDoc t, [FinanceDoc? d]) async {
    await ouvrirEditeurDocument(context, ref, type: t, doc: d);
    _recharger();
  }

  @override
  Widget build(BuildContext context) {
    final l = _liste;
    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        Row(
          children: [
            IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.arrow_back_rounded)),
            const Expanded(child: PageHeader('Documents', subtitle: 'Décharges, factures, reçus : créez, modifiez, imprimez.')),
          ],
        ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(onPressed: () => _ouvrir(TypeDoc.decharge), icon: const Icon(Icons.add_rounded), label: const Text('Décharge')),
            FilledButton.icon(onPressed: () => _ouvrir(TypeDoc.facture), icon: const Icon(Icons.add_rounded), label: const Text('Facture')),
            FilledButton.icon(onPressed: () => _ouvrir(TypeDoc.recu), icon: const Icon(Icons.add_rounded), label: const Text('Reçu de paiement')),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            ChoiceChip(label: const Text('Tous'), selected: _type == null, onSelected: (_) => setState(() {
              _type = null;
              _liste = null;
              _recharger();
            })),
            for (final t in TypeDoc.values)
              ChoiceChip(label: Text(t.pluriel), selected: _type == t, onSelected: (_) => setState(() {
                _type = t;
                _liste = null;
                _recharger();
              })),
          ],
        ),
        const SizedBox(height: 14),
        if (_erreur != null) Text(_erreur!, style: const TextStyle(color: Colors.red)),
        if (l == null && _erreur == null) const SkeletonList(count: 4, height: 64),
        if (l != null && l.isEmpty) const Padding(padding: EdgeInsets.all(24), child: EmptyState(icon: Icons.description_rounded, text: 'Aucun document pour le moment.')),
        if (l != null)
          for (final d in l)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                onTap: () => _ouvrir(d.type, d),
                leading: Icon(switch (d.type) {
                  TypeDoc.decharge => Icons.assignment_turned_in_rounded,
                  TypeDoc.facture => Icons.receipt_long_rounded,
                  TypeDoc.recu => Icons.payments_rounded,
                  TypeDoc.contrat => Icons.badge_rounded,
                }, color: Brand.orange),
                title: Text('${d.numero} · ${d.titre.isEmpty ? d.type.libelle : d.titre}', style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('${d.type.libelle} · ${dateFr(d.date)}${d.type == TypeDoc.facture ? ' · ${d.statut == 'payee' ? 'payée' : d.statut == 'annulee' ? 'annulée' : 'à payer'}' : ''}'),
                trailing: d.montant > 0 ? Text(fcfa(d.type == TypeDoc.facture ? totauxFacture(d).ttc : d.montant), style: const TextStyle(fontWeight: FontWeight.w800)) : null,
              ),
            ),
      ],
    );
  }
}

/// Ouvre l'éditeur d'un document (nouveau ou existant). Pour un contrat, `employe` pré-remplit les champs.
Future<void> ouvrirEditeurDocument(BuildContext context, WidgetRef ref, {required TypeDoc type, FinanceDoc? doc, Employe? employe}) async {
  final co = await ref.read(settingsProvider.future);
  final id = await ref.read(identiteProvider.future);
  final me = ref.read(profilProvider).value;
  final gares = ref.read(garesProvider).value ?? const <Gare>[];
  if (!context.mounted) return;
  await ouvrirEditeur<void>(
    context,
    titre: doc == null ? 'Nouveau : ${type.libelle.toLowerCase()}' : '${type.libelle} ${doc.numero}',
    contenu: (ctx) => _EditeurDoc(type: type, doc: doc, employe: employe, co: co, identite: id, moi: me?.nom ?? '', gares: gares),
  );
}

class _LigneEdit {
  _LigneEdit(String d, String q, String p)
      : designation = TextEditingController(text: d),
        quantite = TextEditingController(text: q),
        prix = TextEditingController(text: p);
  final TextEditingController designation, quantite, prix;
  double get total => (double.tryParse(quantite.text.replaceAll(',', '.')) ?? 0) * lireMontant(prix);
}

class _EditeurDoc extends StatefulWidget {
  const _EditeurDoc({required this.type, required this.doc, required this.employe, required this.co, required this.identite, required this.moi, required this.gares});
  final TypeDoc type;
  final FinanceDoc? doc;
  final Employe? employe;
  final CompanySettings co;
  final IdentiteLegale identite;
  final String moi;
  final List<Gare> gares;

  @override
  State<_EditeurDoc> createState() => _EditeurDocState();
}

class _EditeurDocState extends State<_EditeurDoc> {
  final _form = GlobalKey<FormState>();
  final _c = <String, TextEditingController>{};
  final _lignes = <_LigneEdit>[];
  late DateTime _date = widget.doc?.date ?? DateTime.now();
  late String _statut = widget.doc?.statut ?? 'emis';
  late String _mode = widget.doc?.s('mode').isNotEmpty == true ? widget.doc!.s('mode') : (widget.doc?.s('mode_paiement').isNotEmpty == true ? widget.doc!.s('mode_paiement') : 'Espèces');
  late String _typeContrat = widget.doc?.s('type').isNotEmpty == true ? widget.doc!.s('type') : (widget.employe?.typeContrat ?? 'CDI');
  FinanceDoc? _enregistre;
  bool _saving = false;

  TextEditingController c(String k) => _c.putIfAbsent(k, () => TextEditingController(text: _initial(k)));

  String _initial(String k) {
    final d = widget.doc;
    if (d != null && d.data.containsKey(k)) return '${d.data[k]}';
    final e = widget.employe;
    final id = widget.identite;
    switch (k) {
      case 'comptable':
        return widget.moi;
      case 'responsable':
        return id.representantNom;
      case 'lieu':
        return widget.type == TypeDoc.contrat ? (e?.gareId == null ? '' : (widget.gares.where((g) => g.id == e!.gareId).firstOrNull?.nom ?? '')) : widget.co.ville;
      case 'lieu_signature':
        return widget.co.ville;
      case 'tva_taux':
        return id.tvaTaux == 0 ? '0' : '${id.tvaTaux}'.replaceAll(RegExp(r'\.0$'), '');
      case 'employe_nom':
        return e?.nom ?? '';
      case 'naissance':
        return e?.dateNaissance == null ? '' : dateFr(e!.dateNaissance!);
      case 'adresse':
        return e?.adresse ?? '';
      case 'piece':
        return e?.pieceIdentite ?? '';
      case 'telephone':
        return e?.telephone ?? '';
      case 'poste':
        return e?.poste ?? '';
      case 'salaire':
        return e == null ? '' : '${e.salaireBase.round()}';
      case 'date_debut':
        return e?.dateEmbauche == null ? '' : dateFr(e!.dateEmbauche!);
      case 'date_fin':
        return e?.dateFinContrat == null ? '' : dateFr(e!.dateFinContrat!);
      case 'avantages':
        return [
          if ((e?.indemniteTransport ?? 0) > 0) 'indemnité de transport ${nombre(e!.indemniteTransport)} F',
          if ((e?.indemniteLogement ?? 0) > 0) 'indemnité de logement ${nombre(e!.indemniteLogement)} F',
        ].join(', ');
      case 'heures':
        return '40';
      case 'conges':
        return '2,5';
      case 'preavis':
        return '1 mois';
      case 'essai_mois':
        return (e?.typeContrat ?? 'CDI') == 'CDI' ? '3' : '1';
    }
    return '';
  }

  @override
  void initState() {
    super.initState();
    if (widget.type == TypeDoc.facture) {
      final l = widget.doc?.data['lignes'] as List? ?? const [];
      for (final x in l) {
        final f = LigneFacture.fromJson(Map<String, dynamic>.from(x as Map));
        _lignes.add(_LigneEdit(f.designation, f.quantite == f.quantite.roundToDouble() ? '${f.quantite.round()}' : '${f.quantite}', '${f.prixUnitaire.round()}'));
      }
      if (_lignes.isEmpty) _lignes.add(_LigneEdit('', '1', ''));
    }
    if (widget.type == TypeDoc.decharge && widget.doc == null) {
      // rien : la décharge se remplit à la main
    }
  }

  @override
  void dispose() {
    for (final x in _c.values) {
      x.dispose();
    }
    for (final l in _lignes) {
      l.designation.dispose();
      l.quantite.dispose();
      l.prix.dispose();
    }
    super.dispose();
  }

  FinanceDoc _compose() {
    final data = <String, dynamic>{for (final e in _c.entries) e.key: e.value.text.trim()};
    var montant = 0.0;
    var titre = '';
    switch (widget.type) {
      case TypeDoc.decharge:
        montant = lireMontant(c('montant'));
        data.remove('montant');
        data['mode'] = _mode;
        titre = c('beneficiaire').text.trim();
      case TypeDoc.recu:
        montant = lireMontant(c('montant'));
        data.remove('montant');
        data['mode'] = _mode;
        titre = c('payeur').text.trim();
      case TypeDoc.facture:
        data['lignes'] = [for (final l in _lignes) if (l.designation.text.trim().isNotEmpty) LigneFacture(l.designation.text.trim(), double.tryParse(l.quantite.text.replaceAll(',', '.')) ?? 0, lireMontant(l.prix)).toJson()];
        data['mode_paiement'] = _mode;
        data['remise'] = lireMontant(c('remise'));
        data['tva_taux'] = double.tryParse(c('tva_taux').text.replaceAll(',', '.')) ?? 0;
        titre = c('client_nom').text.trim();
      case TypeDoc.contrat:
        data['type'] = _typeContrat;
        data['mode_paiement'] = _mode;
        titre = c('employe_nom').text.trim();
        montant = lireMontant(c('salaire'));
    }
    final base = FinanceDoc(
      id: _enregistre?.id ?? widget.doc?.id,
      type: widget.type,
      numero: _enregistre?.numero ?? widget.doc?.numero ?? '',
      date: _date,
      titre: titre,
      statut: widget.type == TypeDoc.facture ? _statut : 'emis',
      data: data,
      employeId: widget.employe?.id ?? widget.doc?.employeId,
    );
    final m = widget.type == TypeDoc.facture ? totauxFacture(base).ttc : montant;
    return FinanceDoc(id: base.id, type: base.type, numero: base.numero, date: base.date, titre: base.titre, montant: m, statut: base.statut, data: base.data, employeId: base.employeId);
  }

  Future<void> _enregistrer() async {
    if (!_form.currentState!.validate()) return;
    if (widget.type == TypeDoc.facture && _lignes.every((l) => l.designation.text.trim().isEmpty)) {
      toast(context, 'Ajoutez au moins une ligne à la facture', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final d = await FinanceRepo.enregistrerDocument(_compose());
      if (mounted) {
        setState(() => _enregistre = d);
        toast(context, '${widget.type.libelle} ${d.numero} enregistré');
      }
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _supprimer() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Supprimer ce document ?'),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Non')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Supprimer'))],
      ),
    );
    if (ok != true) return;
    try {
      await FinanceRepo.supprimerDocument(_enregistre?.id ?? widget.doc!.id!);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  Widget _modeDropdown([String libelle = 'Mode de paiement']) => DropdownButtonFormField<String>(
    initialValue: modesPaiement.contains(_mode) ? _mode : modesPaiement.first,
    isExpanded: true,
    decoration: InputDecoration(labelText: libelle),
    items: [for (final m in modesPaiement) DropdownMenuItem(value: m, child: Text(m))],
    onChanged: (v) => setState(() => _mode = v ?? _mode),
  );

  List<Widget> _champs() {
    const esp = SizedBox(height: 12);
    switch (widget.type) {
      case TypeDoc.decharge:
        return [
          champTexte(c('beneficiaire'), 'Nom du bénéficiaire', requis: true),
          esp,
          champTexte(c('piece'), 'Pièce d\'identité (type et numéro)'),
          esp,
          champTexte(c('telephone'), 'Téléphone', clavier: TextInputType.phone),
          esp,
          champMontant(c('montant'), 'Montant remis', requis: true, onChanged: (_) => setState(() {})),
          if (lireMontant(c('montant')) > 0) Padding(padding: const EdgeInsets.only(top: 4), child: Text(montantEnLettres(lireMontant(c('montant'))), style: const TextStyle(color: Brand.muted, fontStyle: FontStyle.italic))),
          esp,
          champTexte(c('motif'), 'Motif de la remise', requis: true, lignes: 2),
          esp,
          _modeDropdown('Mode de remise'),
          esp,
          champTexte(c('reference'), 'Référence (n° de chèque, virement…)'),
          esp,
          champTexte(c('lieu'), 'Fait à'),
          esp,
          ChampDate(libelle: 'Date', valeur: _date, onChanged: (d) => setState(() => _date = d ?? _date)),
          esp,
          const Text('Signataires', style: TextStyle(fontWeight: FontWeight.w800)),
          esp,
          champTexte(c('comptable'), 'Comptable'),
          esp,
          champTexte(c('chef_gare'), 'Chef de gare'),
          esp,
          champTexte(c('responsable'), 'Responsable de la compagnie'),
          esp,
          champTexte(c('observations'), 'Observations', lignes: 2),
        ];
      case TypeDoc.recu:
        return [
          champTexte(c('payeur'), 'Reçu de (nom du payeur)', requis: true),
          esp,
          champMontant(c('montant'), 'Montant reçu', requis: true, onChanged: (_) => setState(() {})),
          if (lireMontant(c('montant')) > 0) Padding(padding: const EdgeInsets.only(top: 4), child: Text(montantEnLettres(lireMontant(c('montant'))), style: const TextStyle(color: Brand.muted, fontStyle: FontStyle.italic))),
          esp,
          champTexte(c('objet'), 'Objet du paiement', requis: true, lignes: 2),
          esp,
          _modeDropdown(),
          esp,
          champTexte(c('facture'), 'Facture concernée (numéro)'),
          esp,
          champTexte(c('reference'), 'Référence'),
          esp,
          ChampDate(libelle: 'Date', valeur: _date, onChanged: (d) => setState(() => _date = d ?? _date)),
          esp,
          champTexte(c('comptable'), 'Établi par (comptable)'),
          esp,
          champTexte(c('observations'), 'Observations', lignes: 2),
        ];
      case TypeDoc.facture:
        final tot = totauxFacture(_compose());
        return [
          champTexte(c('client_nom'), 'Client', requis: true),
          esp,
          champTexte(c('client_adresse'), 'Adresse du client'),
          esp,
          champTexte(c('client_tel'), 'Téléphone du client', clavier: TextInputType.phone),
          esp,
          champTexte(c('client_ifu'), 'IFU du client'),
          esp,
          ChampDate(libelle: 'Date de la facture', valeur: _date, onChanged: (d) => setState(() => _date = d ?? _date)),
          esp,
          champTexte(c('echeance'), 'Échéance (ex. 30 jours, ou une date)'),
          esp,
          const Text('Lignes de la facture', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          for (var i = 0; i < _lignes.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: TextFormField(controller: _lignes[i].designation, decoration: const InputDecoration(labelText: 'Désignation'), onChanged: (_) => setState(() {}))),
                const SizedBox(width: 8),
                SizedBox(width: 64, child: TextFormField(controller: _lignes[i].quantite, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Qté'), onChanged: (_) => setState(() {}))),
                const SizedBox(width: 8),
                Expanded(flex: 3, child: TextFormField(controller: _lignes[i].prix, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Prix unit.'), onChanged: (_) => setState(() {}))),
                IconButton(onPressed: _lignes.length == 1 ? null : () => setState(() => _lignes.removeAt(i)), icon: const Icon(Icons.remove_circle_outline_rounded)),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => setState(() => _lignes.add(_LigneEdit('', '1', ''))), icon: const Icon(Icons.add_rounded), label: const Text('Ajouter une ligne'))),
          esp,
          Row(
            children: [
              Expanded(child: champMontant(c('remise'), 'Remise', onChanged: (_) => setState(() {}))),
              const SizedBox(width: 10),
              Expanded(child: champTexte(c('tva_taux'), 'TVA (%)', clavier: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}))),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Brand.orangeSoft, borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Total HT'), Text(fcfa(tot.ht), style: const TextStyle(fontWeight: FontWeight.w700))]),
                if (tot.tva > 0) Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('TVA'), Text(fcfa(tot.tva), style: const TextStyle(fontWeight: FontWeight.w700))]),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Total à payer', style: TextStyle(fontWeight: FontWeight.w800)), Text(fcfa(tot.ttc), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))]),
              ],
            ),
          ),
          esp,
          _modeDropdown(),
          esp,
          champTexte(c('conditions'), 'Conditions de paiement'),
          esp,
          DropdownButtonFormField<String>(
            initialValue: _statut,
            decoration: const InputDecoration(labelText: 'Statut'),
            items: const [
              DropdownMenuItem(value: 'emis', child: Text('À payer')),
              DropdownMenuItem(value: 'payee', child: Text('Payée')),
              DropdownMenuItem(value: 'annulee', child: Text('Annulée')),
            ],
            onChanged: (v) => setState(() => _statut = v ?? _statut),
          ),
          esp,
          champTexte(c('responsable'), 'Signataire de l\'entreprise'),
          esp,
          champTexte(c('notes'), 'Notes', lignes: 2),
        ];
      case TypeDoc.contrat:
        return [
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text('Modèle standard : faites-le valider par votre conseil juridique ou l\'inspection du travail avant signature. Tous les champs sont modifiables.', style: TextStyle(color: Brand.muted, fontSize: 12.5)),
          ),
          champTexte(c('employe_nom'), 'Nom du salarié', requis: true),
          esp,
          champTexte(c('naissance'), 'Date de naissance (jj/mm/aaaa)'),
          esp,
          champTexte(c('adresse'), 'Adresse'),
          esp,
          champTexte(c('piece'), 'Pièce d\'identité'),
          esp,
          champTexte(c('telephone'), 'Téléphone', clavier: TextInputType.phone),
          esp,
          champTexte(c('poste'), 'Poste / fonction', requis: true),
          esp,
          champTexte(c('missions'), 'Missions principales', lignes: 2),
          esp,
          champTexte(c('lieu'), 'Lieu de travail'),
          esp,
          DropdownButtonFormField<String>(
            initialValue: typesContrat.contains(_typeContrat) ? _typeContrat : 'CDI',
            decoration: const InputDecoration(labelText: 'Type de contrat'),
            items: [for (final t in typesContrat) DropdownMenuItem(value: t, child: Text(t))],
            onChanged: (v) => setState(() => _typeContrat = v ?? _typeContrat),
          ),
          esp,
          Row(
            children: [
              Expanded(child: champTexte(c('date_debut'), 'Début (jj/mm/aaaa)')),
              const SizedBox(width: 10),
              Expanded(child: champTexte(c('date_fin'), 'Fin (si CDD)')),
            ],
          ),
          esp,
          champTexte(c('essai_mois'), 'Période d\'essai (mois, 0 = aucune)', clavier: TextInputType.number),
          esp,
          champMontant(c('salaire'), 'Salaire mensuel brut', requis: true),
          esp,
          champTexte(c('avantages'), 'Indemnités et avantages', lignes: 2),
          esp,
          _modeDropdown('Paiement du salaire'),
          esp,
          Row(
            children: [
              Expanded(child: champTexte(c('heures'), 'Heures / semaine', clavier: TextInputType.number)),
              const SizedBox(width: 10),
              Expanded(child: champTexte(c('conges'), 'Congés (jours / mois)')),
            ],
          ),
          esp,
          champTexte(c('preavis'), 'Préavis'),
          esp,
          champTexte(c('clauses'), 'Clauses particulières (facultatif)', lignes: 3),
          esp,
          champTexte(c('lieu_signature'), 'Fait à'),
          esp,
          ChampDate(libelle: 'Date du contrat', valeur: _date, onChanged: (d) => setState(() => _date = d ?? _date)),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final numero = _enregistre?.numero ?? widget.doc?.numero ?? '';
    final enregistre = _enregistre != null || widget.doc != null;
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (numero.isNotEmpty)
            Padding(padding: const EdgeInsets.only(bottom: 12), child: Text('N° $numero', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Brand.orange))),
          ..._champs(),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(onPressed: _saving ? null : _enregistrer, icon: const Icon(Icons.check_rounded), label: Text(enregistre ? 'Enregistrer les modifications' : 'Enregistrer')),
              if (enregistre)
                BoutonsPdf(
                  construire: () => construireDocument(_compose(), widget.co, widget.identite),
                  nom: '${widget.type.code}-$numero',
                ),
              if (enregistre)
                TextButton.icon(onPressed: _supprimer, icon: const Icon(Icons.delete_rounded, color: Colors.red), label: const Text('Supprimer', style: TextStyle(color: Colors.red))),
            ],
          ),
          if (!enregistre)
            const Padding(padding: EdgeInsets.only(top: 8), child: Text('Enregistrez d\'abord : le numéro est attribué automatiquement, puis vous pourrez imprimer.', style: TextStyle(color: Brand.muted, fontSize: 12.5))),
        ],
      ),
    );
  }
}
