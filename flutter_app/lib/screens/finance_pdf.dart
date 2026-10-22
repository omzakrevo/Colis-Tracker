import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/format.dart';
import '../core/lettres.dart';
import '../data/finance_models.dart';
import '../data/models.dart';
import 'receipt.dart' show pdfImage, pdfTexte;

// Documents comptables imprimables (A4) : décharge, facture, reçu, contrat de travail, bulletin de salaire, émargement.
// Tous portent l'en-tête de l'entreprise avec son IFU et son RCCM pour être des documents officiels.

String _t(String s) => pdfTexte(s);
String _fcfaDoc(num v) => '${nombre(v)} F CFA';
String _jour(DateTime d) => dateFr(d);
String _moisNom(DateTime d) {
  const m = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];
  return '${m[d.month - 1]} ${d.year}';
}

pw.TextStyle _gras(double s) => pw.TextStyle(fontSize: s, fontWeight: pw.FontWeight.bold);
pw.TextStyle _norm(double s) => pw.TextStyle(fontSize: s);

/// En-tête officiel : logo, nom, coordonnées et identifiants légaux de l'entreprise.
pw.Widget _entete(CompanySettings co, IdentiteLegale id) {
  final logo = pdfImage(co.logo);
  final coord = [
    [co.adresse, co.ville, co.pays].where((x) => x.trim().isNotEmpty).join(', '),
    [if (co.telephone.isNotEmpty) 'Tél : ${co.telephone}', if (co.email.isNotEmpty) co.email].join('  ·  '),
  ].where((x) => x.isNotEmpty);
  final legal = [
    if (id.ifu.isNotEmpty) 'IFU : ${id.ifu}',
    if (id.rccm.isNotEmpty) 'RCCM : ${id.rccm}',
    if (id.regimeFiscal.isNotEmpty) 'Régime : ${id.regimeFiscal}',
    if (id.numeroCnss.isNotEmpty) 'N° CNSS : ${id.numeroCnss}',
  ];
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (logo != null) ...[pw.Image(logo, height: 52), pw.SizedBox(width: 12)],
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(_t(co.nom.toUpperCase()), style: _gras(17)),
                if (co.slogan.trim().isNotEmpty) pw.Text(_t(co.slogan), style: pw.TextStyle(fontSize: 8.5, fontStyle: pw.FontStyle.italic)),
                for (final c in coord) pw.Text(_t(c), style: _norm(9)),
              ],
            ),
          ),
          if (legal.isNotEmpty)
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [for (final l in legal) pw.Text(_t(l), style: _gras(9))],
            ),
        ],
      ),
      pw.SizedBox(height: 6),
      pw.Divider(thickness: 1.2, color: PdfColors.grey800),
    ],
  );
}

pw.Widget _titre(String t, {String? numero, String? sous}) => pw.Column(
  children: [
    pw.SizedBox(height: 6),
    pw.Center(child: pw.Text(_t(t.toUpperCase()), style: _gras(18))),
    if (numero != null) pw.Center(child: pw.Text(_t('N° $numero'), style: _gras(11))),
    if (sous != null) pw.Center(child: pw.Text(_t(sous), style: _norm(10))),
    pw.SizedBox(height: 12),
  ],
);

/// Ligne « libellé : valeur ».
pw.Widget _champ(String libelle, String valeur, {double largeur = 130}) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 4),
  child: pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.SizedBox(width: largeur, child: pw.Text(_t(libelle), style: _norm(10))),
      pw.Expanded(child: pw.Text(_t(valeur.isEmpty ? '-' : valeur), style: _gras(10.5))),
    ],
  ),
);

/// Cases de signature (titre, nom facultatif, espace pour signer).
pw.Widget _signatures(List<(String, String)> blocs, {double hauteur = 70}) => pw.Row(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    for (final b in blocs)
      pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.symmetric(horizontal: 3),
          height: hauteur + 34,
          padding: const pw.EdgeInsets.all(6),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey600, width: .6)),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(_t(b.$1), style: _gras(9)),
              if (b.$2.isNotEmpty) pw.Text(_t(b.$2), style: _norm(8.5)),
              pw.Spacer(),
              pw.Text(_t('Nom, date et signature'), style: pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
            ],
          ),
        ),
      ),
  ],
);

pw.Document _doc() => pw.Document();

pw.Widget _pied(String texte) => pw.Align(
  alignment: pw.Alignment.centerRight,
  child: pw.Text(_t(texte), style: pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
);

// ─────────────────────────── Décharge ───────────────────────────

/// Décharge pour une somme remise : bénéficiaire, comptable, chef de gare et responsable de la compagnie signent.
Future<Uint8List> dechargePdf(FinanceDoc d, CompanySettings co, IdentiteLegale id) {
  final doc = _doc();
  final montant = d.montant;
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _entete(co, id),
          _titre('Décharge', numero: d.numero, sous: 'Fait à ${d.s('lieu').isEmpty ? co.ville : d.s('lieu')}, le ${_jour(d.date)}'),
          pw.Text(
            _t('Je soussigné(e) ${d.s('beneficiaire').toUpperCase()}'
                '${d.s('piece').isNotEmpty ? ', titulaire de la pièce d\'identité ${d.s('piece')}' : ''}'
                '${d.s('telephone').isNotEmpty ? ', joignable au ${d.s('telephone')}' : ''}, '
                'reconnais avoir reçu de la société ${co.nom.toUpperCase()}, représentée par ${d.s('responsable').isEmpty ? 'son responsable' : d.s('responsable')}, '
                'la somme de :'),
            style: _norm(11),
            textAlign: pw.TextAlign.justify,
          ),
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(border: pw.Border.all(width: 1.2), color: PdfColors.grey200),
            child: pw.Column(
              children: [
                pw.Text(_t(_fcfaDoc(montant)), style: _gras(20)),
                pw.SizedBox(height: 4),
                pw.Text(_t('(${montantEnLettres(montant)})'), style: pw.TextStyle(fontSize: 11, fontStyle: pw.FontStyle.italic), textAlign: pw.TextAlign.center),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          _champ('Motif', d.s('motif')),
          _champ('Mode de remise', d.s('mode').isEmpty ? 'Espèces' : d.s('mode')),
          if (d.s('reference').isNotEmpty) _champ('Référence', d.s('reference')),
          if (d.s('observations').isNotEmpty) _champ('Observations', d.s('observations')),
          pw.SizedBox(height: 10),
          pw.Text(
            _t('La présente décharge vaut reçu et quittance pour la somme ci-dessus. Elle est établie pour servir et valoir ce que de droit.'),
            style: _norm(10.5),
            textAlign: pw.TextAlign.justify,
          ),
          pw.Spacer(),
          _signatures([
            ('Le bénéficiaire', d.s('beneficiaire')),
            ('Le comptable', d.s('comptable')),
            ('Le chef de gare', d.s('chef_gare')),
            ('Le responsable de la compagnie', d.s('responsable')),
          ]),
          pw.SizedBox(height: 6),
          _pied('${co.nom} · décharge n° ${d.numero}'),
        ],
      ),
    ),
  );
  return doc.save();
}

// ─────────────────────────── Facture ───────────────────────────

({double ht, double remise, double tva, double ttc}) totauxFacture(FinanceDoc d) {
  final lignes = [for (final l in (d.data['lignes'] as List? ?? const [])) LigneFacture.fromJson(Map<String, dynamic>.from(l as Map))];
  final ht = lignes.fold<double>(0, (a, l) => a + l.total);
  final remise = double.tryParse('${d.data['remise'] ?? 0}') ?? 0;
  final base = (ht - remise) < 0 ? 0.0 : ht - remise;
  final taux = double.tryParse('${d.data['tva_taux'] ?? 0}') ?? 0;
  final tva = (base * taux / 100).roundToDouble();
  return (ht: ht, remise: remise, tva: tva, ttc: base + tva);
}

Future<Uint8List> facturePdf(FinanceDoc d, CompanySettings co, IdentiteLegale id) {
  final doc = _doc();
  final lignes = [for (final l in (d.data['lignes'] as List? ?? const [])) LigneFacture.fromJson(Map<String, dynamic>.from(l as Map))];
  final tot = totauxFacture(d);
  final taux = double.tryParse('${d.data['tva_taux'] ?? 0}') ?? 0;
  final payee = d.statut == 'payee';
  final annulee = d.statut == 'annulee';

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (_) => _entete(co, id),
      build: (_) => [
        _titre(annulee ? 'Facture annulée' : 'Facture', numero: d.numero),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey600, width: .6)),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(_t('FACTURÉ À'), style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                    pw.Text(_t(d.s('client_nom').toUpperCase()), style: _gras(12)),
                    if (d.s('client_adresse').isNotEmpty) pw.Text(_t(d.s('client_adresse')), style: _norm(10)),
                    if (d.s('client_tel').isNotEmpty) pw.Text(_t('Tél : ${d.s('client_tel')}'), style: _norm(10)),
                    if (d.s('client_ifu').isNotEmpty) pw.Text(_t('IFU : ${d.s('client_ifu')}'), style: _norm(10)),
                  ],
                ),
              ),
            ),
            pw.SizedBox(width: 14),
            pw.Container(
              width: 190,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _champ('Date', _jour(d.date), largeur: 70),
                  if (d.s('echeance').isNotEmpty) _champ('Échéance', d.s('echeance'), largeur: 70),
                  _champ('Statut', annulee ? 'Annulée' : (payee ? 'PAYÉE' : 'À payer'), largeur: 70),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.TableHelper.fromTextArray(
          headers: ['Désignation', 'Qté', 'Prix unitaire', 'Total'].map(_t).toList(),
          data: [
            for (final l in lignes) [_t(l.designation), l.quantite == l.quantite.roundToDouble() ? '${l.quantite.round()}' : '${l.quantite}', nombre(l.prixUnitaire), nombre(l.total)],
          ],
          columnWidths: {0: const pw.FlexColumnWidth(5), 1: const pw.FlexColumnWidth(1), 2: const pw.FlexColumnWidth(2), 3: const pw.FlexColumnWidth(2)},
          cellAlignments: {1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight},
          headerStyle: _gras(10),
          cellStyle: _norm(10),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          border: pw.TableBorder.all(color: PdfColors.grey500, width: .5),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        ),
        pw.SizedBox(height: 8),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.SizedBox(
            width: 240,
            child: pw.Column(
              children: [
                _ligneTotal('Total HT', nombre(tot.ht)),
                if (tot.remise > 0) _ligneTotal('Remise', '- ${nombre(tot.remise)}'),
                if (taux > 0) _ligneTotal('TVA ($taux %)'.replaceAll('.0 %', ' %'), nombre(tot.tva)),
                pw.Container(
                  color: PdfColors.grey300,
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [pw.Text(_t(taux > 0 ? 'TOTAL TTC' : 'TOTAL À PAYER'), style: _gras(11)), pw.Text(_t(_fcfaDoc(tot.ttc)), style: _gras(12))],
                  ),
                ),
              ],
            ),
          ),
        ),
        pw.SizedBox(height: 10),
        pw.Text(_t('Arrêtée la présente facture à la somme de : ${montantEnLettres(tot.ttc)}.'), style: pw.TextStyle(fontSize: 10.5, fontStyle: pw.FontStyle.italic)),
        pw.SizedBox(height: 8),
        if (d.s('mode_paiement').isNotEmpty) _champ('Mode de paiement', d.s('mode_paiement'), largeur: 110),
        if (id.compteBancaire.isNotEmpty) _champ('Compte bancaire', id.compteBancaire, largeur: 110),
        if (d.s('conditions').isNotEmpty) _champ('Conditions', d.s('conditions'), largeur: 110),
        if (d.s('notes').isNotEmpty) _champ('Notes', d.s('notes'), largeur: 110),
        pw.SizedBox(height: 24),
        _signatures([('Le client', d.s('client_nom')), ('Pour ${co.nom} (cachet et signature)', d.s('responsable'))], hauteur: 50),
      ],
    ),
  );
  return doc.save();
}

pw.Widget _ligneTotal(String l, String v) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
  child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text(_t(l), style: _norm(10.5)), pw.Text(_t(v), style: _gras(10.5))]),
);

// ─────────────────────────── Reçu de paiement ───────────────────────────

Future<Uint8List> recuPaiementPdf(FinanceDoc d, CompanySettings co, IdentiteLegale id) {
  final doc = _doc();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _entete(co, id),
          _titre('Reçu de paiement', numero: d.numero, sous: 'Le ${_jour(d.date)}'),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(border: pw.Border.all(width: 1), color: PdfColors.grey200),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [pw.Text(_t('Montant reçu'), style: _gras(12)), pw.Text(_t(_fcfaDoc(d.montant)), style: _gras(20))],
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            _t('Nous avons reçu de ${d.s('payeur').toUpperCase()} la somme de ${montantEnLettres(d.montant)}.'),
            style: _norm(11.5),
          ),
          pw.SizedBox(height: 10),
          _champ('Objet du paiement', d.s('objet')),
          _champ('Mode de paiement', d.s('mode').isEmpty ? 'Espèces' : d.s('mode')),
          if (d.s('reference').isNotEmpty) _champ('Référence', d.s('reference')),
          if (d.s('facture').isNotEmpty) _champ('Facture concernée', d.s('facture')),
          if (d.s('observations').isNotEmpty) _champ('Observations', d.s('observations')),
          pw.SizedBox(height: 14),
          pw.Text(_t('Ce reçu vaut quittance pour la somme ci-dessus, sous réserve de bonne fin pour les règlements par chèque ou virement.'), style: _norm(10)),
          pw.Spacer(),
          _signatures([('Le payeur', d.s('payeur')), ('Pour ${co.nom} (cachet et signature)', d.s('comptable'))], hauteur: 55),
          pw.SizedBox(height: 6),
          _pied('${co.nom} · reçu n° ${d.numero}'),
        ],
      ),
    ),
  );
  return doc.save();
}

// ─────────────────────────── Contrat de travail ───────────────────────────

Future<Uint8List> contratPdf(FinanceDoc d, CompanySettings co, IdentiteLegale id) {
  final doc = _doc();
  String v(String k, [String defaut = '']) => d.s(k).isEmpty ? defaut : d.s(k);
  final cdd = v('type', 'CDI') != 'CDI';
  final salaire = double.tryParse(v('salaire', '0')) ?? 0;
  final art = <(String, String)>[
    (
      'Engagement et fonctions',
      '${co.nom} engage ${v('employe_nom').toUpperCase()} en qualité de ${v('poste', '...')}'
          '${v('lieu').isEmpty ? '' : ', avec pour lieu de travail principal ${v('lieu')}'}. '
          'Le salarié exerce ses fonctions sous l\'autorité de la direction et s\'engage à se consacrer à l\'exécution de ses tâches avec soin et loyauté. '
          '${v('missions').isEmpty ? '' : 'Missions principales : ${v('missions')}.'}',
    ),
    (
      'Durée du contrat',
      cdd
          ? 'Le présent contrat est conclu pour une durée déterminée (${v('type')}) à compter du ${v('date_debut', '...')}'
              '${v('date_fin').isEmpty ? '' : ' jusqu\'au ${v('date_fin')}'}. Il prend fin de plein droit à son terme.'
          : 'Le présent contrat est conclu pour une durée indéterminée à compter du ${v('date_debut', '...')}.',
    ),
    (
      'Période d\'essai',
      v('essai_mois', '0') == '0' || v('essai_mois').isEmpty
          ? 'Le présent contrat ne comporte pas de période d\'essai.'
          : 'Le contrat est soumis à une période d\'essai de ${v('essai_mois')} mois, durant laquelle chaque partie peut y mettre fin dans les conditions prévues par la réglementation en vigueur.',
    ),
    (
      'Rémunération',
      'Le salarié perçoit un salaire mensuel brut de ${_fcfaDoc(salaire)} (${montantEnLettres(salaire)}).'
          '${v('avantages').isEmpty ? '' : ' Avantages et indemnités : ${v('avantages')}.'} '
          'Le salaire est payé à la fin de chaque mois, par ${v('mode_paiement', 'espèces').toLowerCase()}, contre bulletin de paie. Les cotisations sociales et retenues légales sont prélevées conformément à la réglementation.',
    ),
    (
      'Durée et horaires de travail',
      'La durée hebdomadaire de travail est de ${v('heures', '40')} heures, selon les horaires définis par la direction en fonction des besoins du service. '
          'Les heures supplémentaires éventuelles sont effectuées sur demande de la direction et rémunérées conformément à la réglementation.',
    ),
    (
      'Congés',
      'Le salarié bénéficie des congés payés prévus par la réglementation en vigueur (${v('conges', '2,5')} jours ouvrables par mois de service effectif, sauf dispositions plus favorables).',
    ),
    (
      'Obligations du salarié',
      'Le salarié s\'engage à respecter le règlement intérieur, les consignes de sécurité, la discrétion sur les informations de l\'entreprise et de ses clients, '
          'ainsi qu\'à prendre soin du matériel et des biens (véhicules, colis, fonds) qui lui sont confiés.',
    ),
    (
      'Rupture du contrat',
      'Chacune des parties peut mettre fin au contrat dans le respect de la réglementation du travail et du préavis applicable (${v('preavis', 'selon la loi')}). '
          'La faute grave ou lourde peut entraîner une rupture immédiate dans les conditions prévues par la loi.',
    ),
    if (v('clauses').isNotEmpty) ('Clauses particulières', v('clauses')),
    (
      'Dispositions générales',
      'Le présent contrat est régi par la législation du travail en vigueur au ${co.pays.isEmpty ? 'Burkina Faso' : co.pays} et par les conventions applicables à l\'entreprise. '
          'Toute modification fait l\'objet d\'un avenant écrit signé des deux parties. Fait en deux exemplaires originaux, un pour chaque partie.',
    ),
  ];

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (_) => _entete(co, id),
      footer: (c) => _pied('${co.nom} · contrat ${d.numero} · page ${c.pageNumber}/${c.pagesCount}'),
      build: (_) => [
        _titre('Contrat de travail', numero: d.numero, sous: cdd ? 'À durée déterminée' : 'À durée indéterminée'),
        pw.Text(_t('ENTRE LES SOUSSIGNÉS :'), style: _gras(11)),
        pw.SizedBox(height: 4),
        pw.Text(
          _t('La société ${co.nom.toUpperCase()}${id.rccm.isEmpty ? '' : ', RCCM ${id.rccm}'}${id.ifu.isEmpty ? '' : ', IFU ${id.ifu}'}, '
              'dont le siège est à ${[co.adresse, co.ville].where((x) => x.isNotEmpty).join(', ')}, '
              'représentée par ${id.representantNom.isEmpty ? '...' : id.representantNom}, ${id.representantFonction}, ci-après « l\'Employeur »,'),
          style: _norm(10.5),
          textAlign: pw.TextAlign.justify,
        ),
        pw.SizedBox(height: 4),
        pw.Text(_t('ET'), style: _gras(10.5)),
        pw.SizedBox(height: 4),
        pw.Text(
          _t('${v('employe_nom').toUpperCase()}'
              '${v('naissance').isEmpty ? '' : ', né(e) le ${v('naissance')}'}'
              '${v('adresse').isEmpty ? '' : ', demeurant à ${v('adresse')}'}'
              '${v('piece').isEmpty ? '' : ', pièce d\'identité ${v('piece')}'}'
              '${v('telephone').isEmpty ? '' : ', tél. ${v('telephone')}'}, ci-après « le Salarié ».'),
          style: _norm(10.5),
          textAlign: pw.TextAlign.justify,
        ),
        pw.SizedBox(height: 8),
        pw.Text(_t('IL A ÉTÉ CONVENU ET ARRÊTÉ CE QUI SUIT :'), style: _gras(11)),
        pw.SizedBox(height: 6),
        for (var i = 0; i < art.length; i++)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 7),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(_t('Article ${i + 1} : ${art[i].$1}'), style: _gras(10.5)),
                pw.SizedBox(height: 2),
                pw.Text(_t(art[i].$2), style: _norm(10.5), textAlign: pw.TextAlign.justify),
              ],
            ),
          ),
        pw.SizedBox(height: 6),
        pw.Text(_t('Fait à ${v('lieu_signature', co.ville)}, le ${_jour(d.date)}'), style: _norm(10.5)),
        pw.SizedBox(height: 10),
        _signatures([
          ('Le Salarié (lu et approuvé)', v('employe_nom')),
          ('L\'Employeur (cachet et signature)', id.representantNom),
        ], hauteur: 60),
      ],
    ),
  );
  return doc.save();
}

// ─────────────────────────── Bulletin de salaire ───────────────────────────

Future<Uint8List> bulletinPdf(Bulletin b, Employe e, CompanySettings co, IdentiteLegale id) {
  final doc = _doc();
  final gains = [LigneMontant('Salaire de base', b.salaireBase), ...b.primes];
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _entete(co, id),
          _titre('Bulletin de salaire', sous: 'Période : ${_moisNom(b.mois)}'),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey600, width: .6)),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(children: [
                    _champ('Employé(e)', e.nom.toUpperCase(), largeur: 90),
                    _champ('Matricule', e.matricule, largeur: 90),
                    _champ('Poste', e.poste, largeur: 90),
                  ]),
                ),
                pw.Expanded(
                  child: pw.Column(children: [
                    _champ('Date d\'embauche', e.dateEmbauche == null ? '' : _jour(e.dateEmbauche!), largeur: 100),
                    _champ('Contrat', e.typeContrat, largeur: 100),
                    _champ('N° CNSS', e.numeroCnss, largeur: 100),
                  ]),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          _tableauLignes('Gains', gains, 'Salaire brut', b.brut),
          pw.SizedBox(height: 10),
          _tableauLignes('Retenues', b.retenues, 'Total des retenues', b.totalRetenues),
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(border: pw.Border.all(width: 1.2), color: PdfColors.grey200),
            child: pw.Column(
              children: [
                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text(_t('NET À PAYER'), style: _gras(13)), pw.Text(_t(_fcfaDoc(b.net)), style: _gras(18))]),
                pw.SizedBox(height: 3),
                pw.Align(alignment: pw.Alignment.centerLeft, child: pw.Text(_t('Arrêté à la somme de : ${montantEnLettres(b.net)}'), style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic))),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          _champ('Mode de paiement', b.modePaiement, largeur: 110),
          _champ('Statut', b.paye ? 'Payé le ${b.datePaiement == null ? '' : _jour(b.datePaiement!)}' : 'À payer', largeur: 110),
          if (b.notes.isNotEmpty) _champ('Observations', b.notes, largeur: 110),
          pw.Spacer(),
          pw.Text(_t('Pour valoir ce que de droit. Conservez ce bulletin sans limitation de durée.'), style: pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
          pw.SizedBox(height: 6),
          _signatures([('L\'employé(e) (pour réception)', e.nom), ('L\'employeur (cachet et signature)', id.representantNom)], hauteur: 50),
        ],
      ),
    ),
  );
  return doc.save();
}

pw.Widget _tableauLignes(String titre, List<LigneMontant> lignes, String libelleTotal, double total) => pw.TableHelper.fromTextArray(
  headers: [_t(titre), _t('Montant (F CFA)')],
  data: [
    for (final l in lignes) [_t(l.libelle), nombre(l.montant)],
    [_t(libelleTotal.toUpperCase()), nombre(total)],
  ],
  columnWidths: {0: const pw.FlexColumnWidth(4), 1: const pw.FlexColumnWidth(2)},
  cellAlignments: {1: pw.Alignment.centerRight},
  headerStyle: _gras(10),
  cellStyle: _norm(10.5),
  headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
  border: pw.TableBorder.all(color: PdfColors.grey500, width: .5),
  cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
);

// ─────────────────────────── Fiche d'émargement des salaires ───────────────────────────

Future<Uint8List> emargementPdf(List<(Employe, Bulletin)> lignes, DateTime mois, CompanySettings co, IdentiteLegale id) {
  final doc = _doc();
  final total = lignes.fold<double>(0, (a, l) => a + l.$2.net);
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(28),
      header: (_) => _entete(co, id),
      footer: (c) => _pied('${co.nom} · émargement ${_moisNom(mois)} · page ${c.pageNumber}/${c.pagesCount}'),
      build: (_) => [
        _titre('Fiche d\'émargement des salaires', sous: 'Mois de ${_moisNom(mois)}'),
        pw.Text(_t('Je soussigné(e) reconnais avoir reçu le montant net indiqué en face de mon nom, en paiement de mon salaire du mois.'), style: _norm(9.5)),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headers: ['N°', 'Matricule', 'Nom et prénoms', 'Poste', 'Net à payer (F CFA)', 'Mode', 'Date', 'Signature'].map(_t).toList(),
          data: [
            for (var i = 0; i < lignes.length; i++)
              [
                '${i + 1}',
                _t(lignes[i].$1.matricule),
                _t(lignes[i].$1.nom),
                _t(lignes[i].$1.poste),
                nombre(lignes[i].$2.net),
                _t(lignes[i].$2.modePaiement),
                lignes[i].$2.datePaiement == null ? '' : _jour(lignes[i].$2.datePaiement!),
                '',
              ],
            ['', '', _t('TOTAL'), '', nombre(total), '', '', ''],
          ],
          columnWidths: {
            0: const pw.FixedColumnWidth(24),
            1: const pw.FlexColumnWidth(1.2),
            2: const pw.FlexColumnWidth(3),
            3: const pw.FlexColumnWidth(2),
            4: const pw.FlexColumnWidth(2),
            5: const pw.FlexColumnWidth(1.4),
            6: const pw.FlexColumnWidth(1.4),
            7: const pw.FlexColumnWidth(3),
          },
          cellAlignments: {4: pw.Alignment.centerRight},
          headerStyle: _gras(9),
          cellStyle: _norm(9.5),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          border: pw.TableBorder.all(color: PdfColors.grey600, width: .5),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 9),
        ),
        pw.SizedBox(height: 8),
        pw.Text(_t('Total à payer : ${_fcfaDoc(total)} (${montantEnLettres(total)})'), style: _gras(10)),
        pw.SizedBox(height: 14),
        _signatures([('Le comptable', ''), ('Le chef de gare', ''), ('Le responsable de la compagnie', id.representantNom)], hauteur: 40),
      ],
    ),
  );
  return doc.save();
}
