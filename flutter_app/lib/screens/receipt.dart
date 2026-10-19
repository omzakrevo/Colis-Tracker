import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/format.dart';
import '../data/models.dart';

/// Texte compatible avec la police PDF standard (les espaces insécables fines des montants ne s'y impriment pas).
String pdfTexte(String s) => s
    .replaceAll(' ', ' ')
    .replaceAll(' ', ' ')
    .replaceAll('—', '-')
    .replaceAll('–', '-')
    .replaceAll('…', '...')
    .replaceAll('’', "'")
    .replaceAll('→', '>');

pw.MemoryImage? pdfImage(String? dataUrl) {
  if (dataUrl == null || !dataUrl.contains(',')) return null;
  try {
    return pw.MemoryImage(base64Decode(dataUrl.split(',').last));
  } catch (_) {
    return null;
  }
}

/// Un exemplaire du reçu. `k` agrandit toutes les tailles pour remplir la largeur disponible.
pw.Widget _recu(
  Colis c,
  CompanySettings co,
  pw.MemoryImage? logo,
  double k, {
  String? exemplaire,
  double kv = 1,
}) {
  double f(double s) => s * k;
  double vs(double s) => s * k * kv; // espacements verticaux (étirés pour remplir une feuille)
  pw.Widget row(String l, String v, {bool bold = false}) => pw.Padding(
    padding: pw.EdgeInsets.symmetric(vertical: vs(2)),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: f(66),
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
    padding: pw.EdgeInsets.symmetric(vertical: vs(3)),
    child: pw.Divider(thickness: .6, color: PdfColors.grey600, height: 1),
  );
  pw.Widget centre(String t, double size, {bool bold = false}) => pw.Center(
    child: pw.Text(
      pdfTexte(t),
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
      if (logo != null) pw.Center(child: pw.Image(logo, height: f(44))),
      centre(co.nom.toUpperCase(), 15, bold: true),
      if (co.slogan.isNotEmpty) centre(co.slogan, 7.5),
      if (co.telephone.isNotEmpty) centre(co.telephone, 9),
      if (co.adresse.isNotEmpty || co.ville.isNotEmpty)
        centre('${co.adresse} ${co.ville}'.trim(), 9),
      divider(),
      centre('REÇU D\'EXPÉDITION', 10, bold: true),
      pw.SizedBox(height: vs(4)),
      centre(c.numero, 15, bold: true),
      if (c.numero.startsWith('LOC-'))
        centre('Numéro provisoire — le numéro définitif sera attribué à l\'envoi', 7),
      pw.SizedBox(height: vs(6)),
      pw.Center(
        child: pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(),
          data: c.numero,
          width: f(104),
          height: f(104),
        ),
      ),
      divider(),
      row('Date', dateFr(c.dateEnvoi)),
      row('Départ', c.gareDepartNom ?? '—', bold: true),
      row('Arrivée', c.gareArriveeNom ?? '—', bold: true),
      divider(),
      row('Expéditeur', c.expediteurNom, bold: true),
      row('Téléphone', c.expediteurTelephone),
      row('Destinataire', c.destinataireNom, bold: true),
      row('Téléphone', c.destinataireTelephone),
      divider(),
      row('Description', c.description),
      row('Nombre', '${c.nombre}'),
      if (c.poids != null) row('Poids', '${c.poids} kg'),
      if (c.valeur != null) row('Valeur', fcfa(c.valeur!)),
      divider(),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'TOTAL',
            style: pw.TextStyle(fontSize: f(12), fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            pdfTexte(fcfa(c.prix)),
            style: pw.TextStyle(fontSize: f(14), fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
      divider(),
      centre('Conservez ce reçu pour le retrait du colis.', 8),
      centre('Merci de votre confiance !', 8),
    ],
  );
}

Future<Uint8List> recuPdf(Colis c, CompanySettings co, PdfPageFormat format) {
  final doc = pw.Document();
  final logo = pdfImage(co.logo);

  if (format.width < 300) {
    // Imprimante à ticket (rouleau 58/80 mm) : le reçu occupe toute la largeur du papier.
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
        build: (_) => _recu(c, co, logo, k),
      ),
    );
  } else {
    // Feuille A4 / A5 : deux exemplaires côte à côte (client et agence) qui remplissent la page.
    const marge = 24.0, gap = 22.0;
    final colonne = (format.width - 2 * marge - gap) / 2;
    final k = (colonne / 210).clamp(.6, 1.6);
    // Étire les espacements pour que les exemplaires occupent aussi toute la hauteur de la feuille.
    final hauteur = format.height - 2 * marge - 30;
    final kv = (1 + (hauteur - 443 * k) / (105 * k)).clamp(1.0, 4.0);
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
              child: _recu(c, co, logo, k, exemplaire: 'EXEMPLAIRE CLIENT', kv: kv),
            ),
            pw.Container(
              width: gap,
              height: hauteur,
              alignment: pw.Alignment.center,
              child: pw.Container(width: .8, color: PdfColors.grey500),
            ),
            pw.SizedBox(
              width: colonne,
              child: _recu(c, co, logo, k, exemplaire: 'EXEMPLAIRE AGENCE', kv: kv),
            ),
          ],
        ),
      ),
    );
  }
  return doc.save();
}

/// Ouvre l'impression du reçu. `ticket` : imprimante à rouleau 80 mm ; sinon feuille A4 (deux exemplaires).
/// Le format réellement choisi dans la fenêtre d'impression est pris en compte.
Future<void> imprimerRecu(
  Colis c,
  CompanySettings co, {
  bool ticket = false,
}) => Printing.layoutPdf(
  name: 'Recu-${c.numero}',
  format: ticket ? PdfPageFormat.roll80 : PdfPageFormat.a4,
  onLayout: (format) => recuPdf(c, co, format),
);
