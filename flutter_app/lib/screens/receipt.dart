import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/imprimante.dart';
import '../data/models.dart';
import 'ticket_modele.dart';

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

/// Met en page un document sur la largeur d'un rouleau (58/80 mm) ou, sur feuille A4/A5, une page par exemplaire.
Future<Uint8List> _document(
  PdfPageFormat format,
  pw.Widget Function(double k, double kv, String? bande) construire, {
  List<String?> exemplaires = const [null],
  double hauteurRef = 560,
}) {
  final doc = pw.Document();
  if (format.width < 300) {
    // Imprimante à tickets (rouleau 58/80 mm) : le ticket occupe toute la largeur du papier.
    const marge = 7.0;
    final k = (format.width - 2 * marge) / 210;
    doc.addPage(
      pw.Page(
        pageFormat: format.copyWith(
          marginLeft: marge,
          marginRight: marge,
          marginTop: 10,
          marginBottom: 14,
        ),
        build: (_) => construire(k, 1, null),
      ),
    );
  } else {
    // Feuille A4 / A5 : un exemplaire par page, centré et agrandi pour remplir la feuille.
    const marge = 28.0;
    final largeur = ((format.width - 2 * marge) * .8).clamp(200.0, 420.0);
    final hauteur = format.height - 2 * marge;
    final kMax = hauteur / hauteurRef * .97;
    final k = (largeur / 210 < kMax ? largeur / 210 : kMax).clamp(.7, 2.0);
    final kv = (1 + (hauteur - hauteurRef * k) / (110 * k)).clamp(1.0, 1.8);
    for (final bande in exemplaires) {
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
            child: pw.SizedBox(width: largeur, child: construire(k, kv, bande)),
          ),
        ),
      );
    }
  }
  return doc.save();
}

/// Ticket remis au client à l'enregistrement du colis (rouleau) ou reçu A4 (exemplaire client puis agence).
Future<Uint8List> recuPdf(Colis c, CompanySettings co, PdfPageFormat format) {
  final logo = pdfImage(co.logo);
  return _document(
    format,
    (k, kv, bande) => ticketColisClient(c, co, logo, k, kv: kv, bande: bande),
    exemplaires: const ['EXEMPLAIRE CLIENT', 'EXEMPLAIRE AGENCE'],
  );
}

/// Étiquette autocollante à coller sur le colis.
Future<Uint8List> etiquettePdf(Colis c, CompanySettings co, PdfPageFormat format) {
  final logo = pdfImage(co.logo);
  return _document(
    format,
    (k, kv, bande) => etiquetteColis(c, co, logo, k, kv: kv, bande: bande),
    hauteurRef: 430,
  );
}

/// Ticket de voyage : un seul ticket, y compris sur feuille A4.
Future<Uint8List> billetPdf(Ticket t, CompanySettings co, PdfPageFormat format) {
  final logo = pdfImage(co.logo);
  return _document(format, (k, kv, bande) => ticketVoyage(t, co, logo, k, kv: kv));
}

/// Imprime le ticket client du colis : directement sur l'imprimante « clients » si elle est réglée
/// (écran Imprimante), sinon fenêtre d'impression. `ticket: false` = feuille A4.
Future<void> imprimerRecu(
  Colis c,
  CompanySettings co, {
  bool ticket = false,
}) async {
  if (ticket &&
      await Imprimante.imprimerDirect(
        RoleImprimante.client,
        'Ticket-${c.numero}',
        (format) => recuPdf(c, co, format),
      )) {
    return;
  }
  await Printing.layoutPdf(
    name: 'Ticket-${c.numero}',
    format: ticket ? PdfPageFormat.roll80 : PdfPageFormat.a4,
    onLayout: (format) => recuPdf(c, co, format),
  );
}

/// Imprime l'étiquette à coller sur le colis (imprimante « étiquettes » si elle est réglée).
Future<void> imprimerEtiquette(Colis c, CompanySettings co) async {
  if (await Imprimante.imprimerDirect(
    RoleImprimante.colis,
    'Etiquette-${c.numero}',
    (format) => etiquettePdf(c, co, format),
  )) {
    return;
  }
  await Printing.layoutPdf(
    name: 'Etiquette-${c.numero}',
    format: PdfPageFormat.roll80,
    onLayout: (format) => etiquettePdf(c, co, format),
  );
}
