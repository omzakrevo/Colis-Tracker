import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/format.dart';
import '../data/models.dart';
import 'receipt.dart' show pdfTexte;

// Pictogrammes du modèle de ticket (tracés vectoriels simples, noirs).
const _svgCalendrier =
    '<svg viewBox="0 0 24 24"><path fill-rule="evenodd" d="M7 2h2v2h6V2h2v2h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2V2zM5 9v11h14V9H5zm2 2h3v3H7v-3zm5 0h3v3h-3v-3z"/></svg>';
const _svgLieu =
    '<svg viewBox="0 0 24 24"><path fill-rule="evenodd" d="M12 2a7 7 0 0 0-7 7c0 5.25 7 13 7 13s7-7.75 7-13a7 7 0 0 0-7-7zm0 4.5a2.5 2.5 0 1 1 0 5 2.5 2.5 0 0 1 0-5z"/></svg>';
const _svgHorloge =
    '<svg viewBox="0 0 24 24"><path fill-rule="evenodd" d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm0 2.2a7.8 7.8 0 1 1 0 15.6 7.8 7.8 0 0 1 0-15.6zM11 7v5.4l4 2.4.9-1.5-3.2-1.9V7H11z"/></svg>';
const _svgSiege =
    '<svg viewBox="0 0 24 24"><path d="M5 2h4.2l1.2 9H18a2 2 0 0 1 2 2v4h-2.4v-3.4H9.3L8 4.4H5V2zM6 18h14v2.4H6V18z"/></svg>';
const _svgPersonne =
    '<svg viewBox="0 0 24 24"><path d="M12 12a5 5 0 1 0 0-10 5 5 0 0 0 0 10zm0 2.5c-3.6 0-10 1.8-10 5.5V22h20v-2c0-3.7-6.4-5.5-10-5.5z"/></svg>';
const _svgColis =
    '<svg viewBox="0 0 24 24"><path fill-rule="evenodd" d="M21 7.5l-9-5-9 5v9l9 5 9-5v-9zM12 4.8l5.6 3.1L12 11 6.4 7.9 12 4.8zM5 9.6l6 3.4v6.4l-6-3.4V9.6zm8 9.8V13l6-3.4V16l-6 3.4z"/></svg>';
const _svgBus =
    '<svg viewBox="0 0 64 64"><path fill-rule="evenodd" d="M12 2h40a6 6 0 0 1 6 6v40a6 6 0 0 1-3 5.2V60a2 2 0 0 1-2 2h-6a2 2 0 0 1-2-2v-5H19v5a2 2 0 0 1-2 2h-6a2 2 0 0 1-2-2v-6.8A6 6 0 0 1 6 48V8a6 6 0 0 1 6-6zM13 9v22h38V9H13zm4 33a4 4 0 1 0 0 8 4 4 0 0 0 0-8zm30 0a4 4 0 1 0 0 8 4 4 0 0 0 0-8z"/></svg>';

/// Pièces communes aux tickets (voyage, colis, étiquette) : même modèle visuel que le ticket de voyage de référence.
/// `k` agrandit toutes les tailles (largeur de référence : 210 unités) ; `kv` étire les espaces verticaux.
class _Modele {
  _Modele(this.k, {this.kv = 1});
  final double k, kv;

  double f(double s) => s * k;
  double v(double s) => s * k * kv;

  pw.Widget texte(
    String s,
    double taille, {
    bool gras = true,
    bool italique = false,
    pw.TextAlign align = pw.TextAlign.left,
    double? interligne,
  }) => pw.Text(
    pdfTexte(s),
    textAlign: align,
    style: pw.TextStyle(
      fontSize: f(taille),
      fontWeight: gras ? pw.FontWeight.bold : pw.FontWeight.normal,
      fontStyle: italique ? pw.FontStyle.italic : pw.FontStyle.normal,
      lineSpacing: interligne,
    ),
  );

  /// Texte centré sur une ligne, réduit si besoin pour tenir dans la largeur.
  pw.Widget centreAjuste(String s, double taille, {bool gras = true}) => pw.SizedBox(
    width: double.infinity,
    child: pw.FittedBox(
      fit: pw.BoxFit.scaleDown,
      child: texte(s, taille, gras: gras),
    ),
  );

  pw.Widget trait({double epaisseur = 1.4}) => pw.Padding(
    padding: pw.EdgeInsets.symmetric(vertical: v(4)),
    child: pw.Container(height: f(epaisseur), color: PdfColors.black),
  );

  pw.Widget pointilles() => pw.Padding(
    padding: pw.EdgeInsets.symmetric(vertical: v(4)),
    child: pw.Divider(
      height: f(1),
      thickness: f(1),
      color: PdfColors.black,
      borderStyle: pw.BorderStyle.dashed,
    ),
  );

  pw.Widget bande(String s) => pw.Container(
    padding: pw.EdgeInsets.symmetric(vertical: f(3)),
    color: PdfColors.grey300,
    child: pw.Center(child: texte(s, 9)),
  );

  /// En-tête : logo (ou pictogramme) à gauche, nom de l'entreprise en grand, activité, slogan, téléphone.
  pw.Widget entete(CompanySettings co, pw.MemoryImage? logo, String activite, {String svg = _svgBus}) {
    final icone = logo != null
        ? pw.Image(logo, width: f(58), height: f(58), fit: pw.BoxFit.contain)
        : pw.SvgImage(svg: svg, width: f(58), height: f(58));
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        icone,
        pw.SizedBox(width: f(8)),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: double.infinity,
                child: pw.FittedBox(
                  fit: pw.BoxFit.scaleDown,
                  alignment: pw.Alignment.centerLeft,
                  child: texte(co.nom.toUpperCase(), 36),
                ),
              ),
              texte(activite, 9.5),
              if (co.slogan.isNotEmpty) texte(co.slogan, 8.5, italique: true),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget telephone(CompanySettings co) => co.telephone.isEmpty
      ? pw.SizedBox()
      : pw.Padding(
          padding: pw.EdgeInsets.only(top: v(2)),
          child: pw.Center(child: texte('Tél. : ${co.telephone}', 9)),
        );

  pw.Widget titre(String s, String numero, {String? note}) => pw.Column(
    children: [
      centreAjuste(s, 25),
      pw.SizedBox(height: v(2)),
      centreAjuste('N° : $numero', 14),
      if (note != null) texte(note, 6.5, gras: false, align: pw.TextAlign.center),
    ],
  );

  /// Une ligne « pictogramme  LIBELLÉ : valeur ».
  pw.Widget ligne(String svg, String libelle, String valeur, {double taille = 11}) => pw.Padding(
    padding: pw.EdgeInsets.symmetric(vertical: v(2.2)),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(width: f(15), child: pw.SvgImage(svg: svg, width: f(13), height: f(13))),
        pw.SizedBox(width: f(5)),
        // Libellé long (DESTINATAIRE…) : police réduite pour tenir sur une ligne, sans changer l'alignement.
        pw.SizedBox(width: f(76), child: texte(libelle, libelle.length >= 11 ? taille * .8 : taille)),
        pw.SizedBox(width: f(6), child: texte(':', taille)),
        pw.Expanded(child: texte(valeur, taille)),
      ],
    ),
  );

  pw.Widget prix(double montant) => pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      texte('PRIX PAYÉ :', 14),
      texte(fcfa(montant).replaceAll('FCFA', 'F CFA'), 18),
    ],
  );

  pw.Widget qr(String donnees, {double taille = 96}) => pw.Center(
    child: pw.BarcodeWidget(
      barcode: pw.Barcode.qrCode(),
      data: donnees,
      width: f(taille),
      height: f(taille),
    ),
  );

  pw.Widget pied(String message, {String? consigne}) => pw.Column(
    children: [
      if (consigne != null) texte(consigne, 8.5, gras: true, align: pw.TextAlign.center),
      trait(),
      centreAjuste(message, 15),
    ],
  );
}

/// Ticket de voyage (billet de transport).
pw.Widget ticketVoyage(
  Ticket t,
  CompanySettings co,
  pw.MemoryImage? logo,
  double k, {
  double kv = 1,
  String? bande,
}) {
  final m = _Modele(k, kv: kv);
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      if (bande != null) ...[m.bande(bande), pw.SizedBox(height: m.v(4))],
      m.entete(co, logo, 'TRANSPORT DE VOYAGEURS'),
      m.telephone(co),
      m.trait(),
      m.titre(
        t.annule ? 'TICKET ANNULÉ' : 'TICKET DE VOYAGE',
        t.numero,
        note: t.numero.startsWith('LOC-')
            ? 'Numéro provisoire : le numéro définitif sera attribué à l\'envoi'
            : null,
      ),
      m.trait(epaisseur: 1),
      m.ligne(_svgCalendrier, 'DATE', dateFr(t.dateVoyage)),
      m.ligne(_svgLieu, 'DÉPART', (t.gareDepartNom ?? '—').toUpperCase()),
      m.ligne(_svgLieu, 'ARRIVÉE', (t.gareArriveeNom ?? '—').toUpperCase()),
      if ((t.heureDepart ?? '').isNotEmpty)
        m.ligne(_svgHorloge, 'HEURE', t.heureDepart!.replaceFirst(':', 'H')),
      if ((t.siege ?? '').isNotEmpty) m.ligne(_svgSiege, 'SIÈGE', t.siege!),
      m.ligne(_svgPersonne, 'PASSAGER', t.clientNom.toUpperCase()),
      m.pointilles(),
      m.prix(t.prix),
      m.pointilles(),
      m.qr(t.numero),
      pw.SizedBox(height: m.v(2)),
      m.centreAjuste(t.numero, 14),
      pw.SizedBox(height: m.v(2)),
      m.texte(
        'Scannez ce QR code pour vérifier le ticket au contrôle ou à l\'embarquement.',
        8.5,
        gras: true,
        align: pw.TextAlign.center,
      ),
      m.pied('MERCI ET BON VOYAGE !'),
    ],
  );
}

/// Ticket remis à l'expéditeur lors de l'enregistrement d'un colis (même modèle).
pw.Widget ticketColisClient(
  Colis c,
  CompanySettings co,
  pw.MemoryImage? logo,
  double k, {
  double kv = 1,
  String? bande,
}) {
  final m = _Modele(k, kv: kv);
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      if (bande != null) ...[m.bande(bande), pw.SizedBox(height: m.v(4))],
      m.entete(co, logo, 'TRANSPORT DE COLIS', svg: _svgColis),
      m.telephone(co),
      m.trait(),
      m.titre(
        'TICKET DE COLIS',
        c.numero,
        note: c.numero.startsWith('LOC-')
            ? 'Numéro provisoire : le numéro définitif sera attribué à l\'envoi'
            : null,
      ),
      m.trait(epaisseur: 1),
      m.ligne(_svgCalendrier, 'DATE', dateFr(c.dateEnvoi)),
      m.ligne(_svgLieu, 'DÉPART', (c.gareDepartNom ?? '—').toUpperCase()),
      m.ligne(_svgLieu, 'ARRIVÉE', (c.gareArriveeNom ?? '—').toUpperCase()),
      m.ligne(_svgPersonne, 'EXPÉDITEUR', '${c.expediteurNom.toUpperCase()}\n${c.expediteurTelephone}'),
      m.ligne(_svgPersonne, 'DESTINATAIRE', '${c.destinataireNom.toUpperCase()}\n${c.destinataireTelephone}'),
      m.ligne(_svgColis, 'COLIS', '${c.nombre} × ${c.description}${c.poids != null ? ' (${c.poids} kg)' : ''}'),
      if (c.valeur != null) m.ligne(_svgColis, 'VALEUR', fcfa(c.valeur!).replaceAll('FCFA', 'F CFA')),
      m.pointilles(),
      m.prix(c.prix),
      m.pointilles(),
      m.qr(c.numero),
      pw.SizedBox(height: m.v(2)),
      m.centreAjuste(c.numero, 14),
      pw.SizedBox(height: m.v(2)),
      m.texte(
        'Conservez ce ticket : il vous sera demandé pour le retrait du colis. Suivi par QR code.',
        8.5,
        gras: true,
        align: pw.TextAlign.center,
      ),
      m.pied('MERCI DE VOTRE CONFIANCE !'),
    ],
  );
}

/// Étiquette autocollante à coller sur le colis : destination en grand, destinataire, QR code (sans prix).
pw.Widget etiquetteColis(
  Colis c,
  CompanySettings co,
  pw.MemoryImage? logo,
  double k, {
  double kv = 1,
  String? bande,
}) {
  final m = _Modele(k, kv: kv);
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      if (bande != null) ...[m.bande(bande), pw.SizedBox(height: m.v(4))],
      m.entete(co, logo, 'COLIS', svg: _svgColis),
      m.trait(),
      m.texte('DESTINATION', 9, align: pw.TextAlign.center),
      m.centreAjuste((c.gareArriveeNom ?? '—').toUpperCase(), 30),
      m.texte('DE : ${(c.gareDepartNom ?? '—').toUpperCase()}', 10, align: pw.TextAlign.center),
      m.trait(epaisseur: 1),
      m.ligne(_svgPersonne, 'DESTINATAIRE', '${c.destinataireNom.toUpperCase()}\n${c.destinataireTelephone}'),
      m.ligne(_svgPersonne, 'EXPÉDITEUR', '${c.expediteurNom.toUpperCase()}\n${c.expediteurTelephone}'),
      m.ligne(_svgColis, 'COLIS', '${c.nombre} × ${c.description}'),
      m.ligne(_svgCalendrier, 'DATE', dateFr(c.dateEnvoi)),
      m.pointilles(),
      m.qr(c.numero),
      pw.SizedBox(height: m.v(2)),
      m.centreAjuste(c.numero, 15),
    ],
  );
}
