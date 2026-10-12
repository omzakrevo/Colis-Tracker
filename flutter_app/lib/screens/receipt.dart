import 'dart:convert';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/format.dart';
import '../data/models.dart';

/// Génère le reçu (format ticket 80 mm) avec QR code de suivi.
Future<void> imprimerRecu(Colis c, CompanySettings co) async {
  final doc = pw.Document();
  pw.MemoryImage? logo;
  if (co.logo != null && co.logo!.contains(',')) {
    try {
      logo = pw.MemoryImage(base64Decode(co.logo!.split(',').last));
    } catch (_) {}
  }
  pw.Widget row(String l, String v, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(width: 62, child: pw.Text(l, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700))),
          pw.Expanded(
              child: pw.Text(v,
                  style: pw.TextStyle(fontSize: 9, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal))),
        ]),
      );
  final divider = pw.Divider(thickness: .5, color: PdfColors.grey500);

  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.roll80.copyWith(marginLeft: 12, marginRight: 12, marginTop: 14, marginBottom: 14),
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      if (logo != null) pw.Center(child: pw.Image(logo, height: 40)),
      pw.Center(child: pw.Text(co.nom.toUpperCase(), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold))),
      pw.Center(child: pw.Text(co.slogan, style: const pw.TextStyle(fontSize: 7), textAlign: pw.TextAlign.center)),
      if (co.telephone.isNotEmpty) pw.Center(child: pw.Text(co.telephone, style: const pw.TextStyle(fontSize: 8))),
      if (co.adresse.isNotEmpty || co.ville.isNotEmpty)
        pw.Center(child: pw.Text('${co.adresse} ${co.ville}'.trim(), style: const pw.TextStyle(fontSize: 8))),
      divider,
      pw.Center(child: pw.Text('REÇU D\'EXPÉDITION', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
      pw.SizedBox(height: 4),
      pw.Center(child: pw.Text(c.numero, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold))),
      pw.SizedBox(height: 6),
      pw.Center(
        child: pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(), data: c.numero, width: 90, height: 90),
      ),
      divider,
      row('Date', dateFr(c.dateEnvoi)),
      row('Départ', c.gareDepartNom ?? '—', bold: true),
      row('Arrivée', c.gareArriveeNom ?? '—', bold: true),
      divider,
      row('Expéditeur', c.expediteurNom, bold: true),
      row('Téléphone', c.expediteurTelephone),
      row('Destinataire', c.destinataireNom, bold: true),
      row('Téléphone', c.destinataireTelephone),
      divider,
      row('Description', c.description),
      row('Nombre', '${c.nombre}'),
      if (c.poids != null) row('Poids', '${c.poids} kg'),
      divider,
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('TOTAL', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.Text(fcfa(c.prix), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
      ]),
      divider,
      pw.Center(child: pw.Text('Conservez ce reçu pour le retrait du colis.', style: const pw.TextStyle(fontSize: 7))),
      pw.Center(child: pw.Text('Merci de votre confiance !', style: const pw.TextStyle(fontSize: 7))),
    ]),
  ));

  await Printing.layoutPdf(name: 'Recu-${c.numero}', onLayout: (_) => doc.save());
}
