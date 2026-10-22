import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/format.dart';
import '../data/models.dart';
import 'receipt.dart' show pdfImage, pdfTexte;

/// Construit le rapport d'activité (PDF A4) : synthèse, recettes, liste des colis et signatures des retraits.
Future<Uint8List> rapportPdf({
  required CompanySettings co,
  required Profil me,
  required String perimetre,
  required DateTime? debut,
  required DateTime? fin,
  required List<Colis> colis,
  required List<LigneStat> gares,
  required List<LigneStat> agents,
}) {
  final doc = pw.Document();
  final logo = pdfImage(co.logo);
  String t(String s) => pdfTexte(s);

  // Les recettes sont encaissées au départ : un agent ne compte que les colis partis de sa gare.
  final comptes = me.voitToutLeReseau
      ? colis.where((c) => c.statut != 'annule')
      : colis.where((c) => c.statut != 'annule' && c.gareDepartId == me.gareId);
  final recette = comptes.fold<double>(0, (a, c) => a + c.prix);
  final parStatut = <String, int>{};
  for (final c in colis) {
    parStatut[c.statut] = (parStatut[c.statut] ?? 0) + 1;
  }
  final retires = colis.where((c) => c.statut == 'retire').toList();

  pw.Widget titre(String s) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
    child: pw.Text(
      t(s),
      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
    ),
  );
  pw.Widget tableau(List<String> entetes, List<List<String>> lignes, {Map<int, pw.TableColumnWidth>? largeurs}) =>
      pw.TableHelper.fromTextArray(
        headers: entetes.map(t).toList(),
        data: [for (final l in lignes) l.map(t).toList()],
        columnWidths: largeurs,
        headerStyle: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
        cellStyle: const pw.TextStyle(fontSize: 8.5),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        border: pw.TableBorder.all(color: PdfColors.grey400, width: .4),
      );

  final periode = '${debut == null ? '...' : dateFr(debut)} au ${fin == null ? '...' : dateFr(fin)}';

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Page ${ctx.pageNumber} / ${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ),
      build: (_) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (logo != null) ...[pw.Image(logo, height: 42), pw.SizedBox(width: 12)],
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(t(co.nom.toUpperCase()), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                  pw.Text(t('Rapport d\'activité'), style: const pw.TextStyle(fontSize: 11)),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(t('Période : $periode'), style: const pw.TextStyle(fontSize: 9)),
                pw.Text(t('Périmètre : $perimetre'), style: const pw.TextStyle(fontSize: 9)),
                pw.Text(t('Édité le ${dateHeureFr(DateTime.now())} par ${me.nom}'), style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
              ],
            ),
          ],
        ),
        pw.Divider(thickness: .8),
        titre('Synthèse'),
        tableau(
          ['Colis', 'Recette (au départ)', ...parStatut.keys.map((s) => Statut.of(s).label)],
          [
            ['${colis.length}', fcfa(recette), ...parStatut.values.map((v) => '$v')],
          ],
        ),
        if (gares.isNotEmpty) ...[
          titre('Recettes par gare'),
          tableau(
            ['Gare', 'Colis', 'Recette'],
            [for (final g in gares) [g.nom, '${g.total}', fcfa(g.recette)]],
          ),
        ],
        if (agents.isNotEmpty) ...[
          titre('Recettes par agent'),
          tableau(
            ['Agent', 'Colis', 'Recette'],
            [for (final a in agents) [a.nom, '${a.total}', fcfa(a.recette)]],
          ),
        ],
        titre('Liste des colis (${colis.length})'),
        tableau(
          ['N°', 'Date', 'Expéditeur', 'Destinataire', 'Trajet', 'Statut', 'Prix'],
          [
            for (final c in colis)
              [
                c.numero,
                dateFr(c.dateEnvoi),
                c.expediteurNom,
                c.destinataireNom,
                '${c.gareDepartNom ?? '-'} > ${c.gareArriveeNom ?? '-'}',
                Statut.of(c.statut).label,
                fcfa(c.prix),
              ],
          ],
          largeurs: {
            0: const pw.FlexColumnWidth(2.2),
            1: const pw.FlexColumnWidth(1.5),
            2: const pw.FlexColumnWidth(2),
            3: const pw.FlexColumnWidth(2),
            4: const pw.FlexColumnWidth(2.6),
            5: const pw.FlexColumnWidth(1.4),
            6: const pw.FlexColumnWidth(1.6),
          },
        ),
        titre('Retraits et signatures (${retires.length})'),
        if (retires.isEmpty)
          pw.Text('Aucun retrait sur la période.', style: const pw.TextStyle(fontSize: 9))
        else
          pw.Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final c in retires)
                pw.Container(
                  width: 250,
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey500, width: .5),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(t(c.numero), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      pw.Text(t('Retiré par : ${c.retraitNom ?? '-'}'), style: const pw.TextStyle(fontSize: 8.5)),
                      pw.Text(t('Téléphone : ${c.retraitTelephone ?? '-'}'), style: const pw.TextStyle(fontSize: 8.5)),
                      if ((c.retraitPieceIdentite ?? '').isNotEmpty)
                        pw.Text(t('Pièce : ${c.retraitPieceIdentite}'), style: const pw.TextStyle(fontSize: 8.5)),
                      if (c.retraitDate != null)
                        pw.Text(t('Le ${dateHeureFr(c.retraitDate!)}'), style: const pw.TextStyle(fontSize: 8.5)),
                      pw.SizedBox(height: 4),
                      pw.Container(
                        height: 52,
                        width: double.infinity,
                        alignment: pw.Alignment.center,
                        decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400, width: .4)),
                        child: pdfImage(c.retraitSignature) == null
                            ? pw.Text('Signature non disponible', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600))
                            : pw.Image(pdfImage(c.retraitSignature)!, fit: pw.BoxFit.contain),
                      ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    ),
  );
  return doc.save();
}

/// Télécharge (web) ou partage (mobile) le rapport PDF.
Future<void> telechargerRapport(Uint8List pdf, {DateTime? debut, DateTime? fin}) {
  String j(DateTime? d) => d == null ? 'debut' : dateIso(d);
  return Printing.sharePdf(bytes: pdf, filename: 'rapport-${j(debut)}_${fin == null ? 'fin' : dateIso(fin)}.pdf');
}
