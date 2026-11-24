import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../core/imprimante.dart';
import '../core/ticket_texte.dart';
import '../data/modele_ticket.dart';
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
        texte: (g, cols) => ticketVoyageTexte(g, cols, t, co),
        logo: logoAffiche(co, SorteTicket.voyage) ? co.logo : null,
      )) {
    return;
  }
  if (ticket) {
    // Toujours au format du rouleau (58/80 mm), même si la fenêtre d'impression propose A4.
    final rouleau = await formatRouleau(RoleImprimante.client);
    await Printing.layoutPdf(
      name: 'Billet-${t.numero}',
      format: rouleau,
      onLayout: (_) => billetPdf(t, co, rouleau),
    );
    return;
  }
  await Printing.layoutPdf(
    name: 'Billet-${t.numero}',
    format: PdfPageFormat.a4,
    onLayout: (format) => billetPdf(t, co, format),
  );
}
