import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../core/imprimante.dart';
import '../data/models.dart';
import 'receipt.dart';

export 'receipt.dart' show billetPdf;

/// Imprime le billet : directement sur l'imprimante « clients » si elle est réglée, sinon fenêtre d'impression.
/// `ticket: false` = feuille A4 (un seul billet).
Future<void> imprimerBillet(
  Ticket t,
  CompanySettings co, {
  bool ticket = false,
}) async {
  if (ticket &&
      await Imprimante.imprimerDirect(
        RoleImprimante.client,
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
