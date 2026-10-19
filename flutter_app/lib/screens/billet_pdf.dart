import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/format.dart';
import '../data/models.dart';
import 'receipt.dart' show pdfImage, pdfTexte;

/// Un exemplaire du billet de transport. `k` agrandit toutes les tailles pour remplir la largeur disponible.
pw.Widget _billet(
  Ticket t,
  CompanySettings co,
  pw.MemoryImage? logo,
  double k, {
  String? exemplaire,
  double kv = 1,
}) {
  double f(double s) => s * k;
  double vs(double s) => s * k * kv;
  pw.Widget row(String l, String v, {bool bold = false}) => pw.Padding(
    padding: pw.EdgeInsets.symmetric(vertical: vs(2)),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: f(58),
          child: pw.Text(
            pdfTexte(l),
            style: pw.TextStyle(fontSize: f(8.5), color: PdfColors.grey700),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            pdfTexte(v),
            style: pw.TextStyle(
              fontSize: f(10),
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ),
      ],
    ),
  );
  pw.Widget divider() => pw.Padding(
    padding: pw.EdgeInsets.symmetric(vertical: vs(5)),
    child: pw.Divider(height: 1, color: PdfColors.grey500, thickness: .6),
  );
  pw.Widget centre(String s, double size, {bool bold = false}) => pw.Center(
    child: pw.Text(
      pdfTexte(s),
      textAlign: pw.TextAlign.center,
      style: pw.TextStyle(
        fontSize: f(size),
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      if (exemplaire != null) ...[
        pw.Container(
          padding: pw.EdgeInsets.symmetric(vertical: f(3)),
          color: PdfColors.grey200,
          child: centre(exemplaire, 8, bold: true),
        ),
        pw.SizedBox(height: vs(6)),
      ],
      if (logo != null) pw.Center(child: pw.Image(logo, height: f(40))),
      centre(co.nom.toUpperCase(), 15, bold: true),
      if (co.telephone.isNotEmpty) centre(co.telephone, 9),
      if (co.adresse.isNotEmpty || co.ville.isNotEmpty)
        centre('${co.adresse} ${co.ville}'.trim(), 9),
      divider(),
      centre('BILLET DE TRANSPORT', 10, bold: true),
      pw.SizedBox(height: vs(4)),
      centre(t.numero, 15, bold: true),
      if (t.numero.startsWith('LOC-'))
        centre('Numéro provisoire — le numéro définitif sera attribué à l\'envoi', 7),
      if (t.annule) centre('BILLET ANNULÉ', 12, bold: true),
      pw.SizedBox(height: vs(6)),
      pw.Center(
        child: pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(),
          data: t.numero,
          width: f(92),
          height: f(92),
        ),
      ),
      divider(),
      row('Passager', t.clientNom, bold: true),
      row('Téléphone', t.clientTelephone),
      divider(),
      row('Départ', t.gareDepartNom ?? '—', bold: true),
      row('Arrivée', t.gareArriveeNom ?? '—', bold: true),
      row('Date', dateFr(t.dateVoyage)),
      if ((t.heureDepart ?? '').isNotEmpty) row('Heure', t.heureDepart!),
      if ((t.siege ?? '').isNotEmpty) row('Place', t.siege!, bold: true),
      divider(),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'TOTAL',
            style: pw.TextStyle(fontSize: f(12), fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            pdfTexte(fcfa(t.prix)),
            style: pw.TextStyle(fontSize: f(14), fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
      divider(),
      centre('Présentez ce billet à l\'embarquement.', 8),
      centre('Bon voyage !', 8),
    ],
  );
}

Future<Uint8List> billetPdf(Ticket t, CompanySettings co, PdfPageFormat format) {
  final doc = pw.Document();
  final logo = pdfImage(co.logo);

  if (format.width < 300) {
    // Imprimante à ticket (rouleau 58/80 mm) : le billet occupe toute la largeur du papier.
    const marge = 7.0;
    final k = (format.width - 2 * marge) / 210;
    doc.addPage(
      pw.Page(
        pageFormat: format.copyWith(
          marginLeft: marge,
          marginRight: marge,
          marginTop: 10,
          marginBottom: 10,
        ),
        build: (_) => _billet(t, co, logo, k),
      ),
    );
  } else {
    // Feuille A4 / A5 : deux exemplaires côte à côte (passager et agence).
    const marge = 24.0, gap = 22.0;
    final colonne = (format.width - 2 * marge - gap) / 2;
    final k = (colonne / 210).clamp(.6, 1.6);
    final hauteur = format.height - 2 * marge - 30;
    final kv = (1 + (hauteur - 400 * k) / (95 * k)).clamp(1.0, 4.0);
    doc.addPage(
      pw.Page(
        pageFormat: format.copyWith(
          marginLeft: marge,
          marginRight: marge,
          marginTop: marge,
          marginBottom: marge,
        ),
        build: (_) => pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: colonne,
              child: _billet(t, co, logo, k, exemplaire: 'EXEMPLAIRE PASSAGER', kv: kv),
            ),
            pw.Container(
              width: gap,
              height: hauteur,
              alignment: pw.Alignment.center,
              child: pw.Container(width: .8, color: PdfColors.grey500),
            ),
            pw.SizedBox(
              width: colonne,
              child: _billet(t, co, logo, k, exemplaire: 'EXEMPLAIRE AGENCE', kv: kv),
            ),
          ],
        ),
      ),
    );
  }
  return doc.save();
}

/// Ouvre l'impression du billet. `ticket` : imprimante à rouleau 80 mm ; sinon feuille A4 (deux exemplaires).
Future<void> imprimerBillet(
  Ticket t,
  CompanySettings co, {
  bool ticket = false,
}) => Printing.layoutPdf(
  name: 'Billet-${t.numero}',
  format: ticket ? PdfPageFormat.roll80 : PdfPageFormat.a4,
  onLayout: (format) => billetPdf(t, co, format),
);
