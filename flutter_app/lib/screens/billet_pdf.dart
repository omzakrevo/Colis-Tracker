import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/format.dart';
import '../core/imprimante.dart';
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
          width: f(84),
          child: pw.Text(
            pdfTexte(l),
            style: pw.TextStyle(fontSize: f(10.5), fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            pdfTexte(v),
            style: pw.TextStyle(
              fontSize: f(12.5),
              fontWeight: pw.FontWeight.bold,
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
        fontSize: f(size * 1.25),
        fontWeight: pw.FontWeight.bold,
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
            style: pw.TextStyle(fontSize: f(15), fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            pdfTexte(fcfa(t.prix)),
            style: pw.TextStyle(fontSize: f(18), fontWeight: pw.FontWeight.bold),
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
    // Feuille A4 / A5 : un exemplaire par page (client puis agence), centré et agrandi pour remplir la feuille.
    const marge = 28.0;
    final largeur = ((format.width - 2 * marge) * .8).clamp(200.0, 420.0);
    final hauteur = format.height - 2 * marge;
    // Le texte grossit tant que l'exemplaire tient dans la largeur ET la hauteur de la feuille.
    final kMax = hauteur / 485 * .97;
    final k = (largeur / 210 < kMax ? largeur / 210 : kMax).clamp(.7, 2.0);
    final kv = (1 + (hauteur - 485 * k) / (95 * k)).clamp(1.0, 4.0);
    for (final exemplaire in ['EXEMPLAIRE PASSAGER', 'EXEMPLAIRE AGENCE']) {
      doc.addPage(
        pw.Page(
          pageFormat: format.copyWith(
            marginLeft: marge,
            marginRight: marge,
            marginTop: marge,
            marginBottom: marge,
          ),
          build: (_) => pw.Align(
            alignment: pw.Alignment.topCenter,
            child: pw.SizedBox(
              width: largeur,
              child: _billet(t, co, logo, k, exemplaire: exemplaire, kv: kv),
            ),
          ),
        ),
      );
    }
  }
  return doc.save();
}

/// Imprime le billet. `ticket` : imprimante à tickets (58/80 mm), directement si une imprimante est réglée
/// sur cet appareil ; sinon feuille A4 (deux exemplaires) via la fenêtre d'impression.
Future<void> imprimerBillet(
  Ticket t,
  CompanySettings co, {
  bool ticket = false,
}) async {
  if (ticket &&
      await Imprimante.imprimerDirect(
        'Billet-${t.numero}',
        (format) => billetPdf(t, co, format),
      )) {
    return;
  }
  await Printing.layoutPdf(
    name: 'Billet-${t.numero}',
    format: ticket ? PdfPageFormat.roll80 : PdfPageFormat.a4,
    onLayout: (format) => billetPdf(t, co, format),
  );
}
