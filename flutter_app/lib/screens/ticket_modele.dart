import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/format.dart';
import '../data/modele_ticket.dart';
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

String _svg(Picto p) => switch (p) {
  Picto.calendrier => _svgCalendrier,
  Picto.lieu => _svgLieu,
  Picto.horloge => _svgHorloge,
  Picto.siege => _svgSiege,
  Picto.personne => _svgPersonne,
  Picto.colis => _svgColis,
};

pw.TextAlign _texteAlign(Alignement a) => switch (a) {
  Alignement.gauche => pw.TextAlign.left,
  Alignement.centre => pw.TextAlign.center,
  Alignement.droite => pw.TextAlign.right,
};

pw.Alignment _boite(Alignement a) => switch (a) {
  Alignement.gauche => pw.Alignment.centerLeft,
  Alignement.centre => pw.Alignment.center,
  Alignement.droite => pw.Alignment.centerRight,
};

/// Pièces du ticket. `k` agrandit toutes les tailles (largeur de référence : 210 unités) ;
/// `kv` étire les espaces verticaux (feuille A4) ; `e` = espacement choisi dans le modèle.
class _Modele {
  _Modele(this.k, {this.kv = 1, this.e = 1});
  final double k, kv, e;

  double f(double s) => s * k;
  double v(double s) => s * k * kv * e;

  pw.Widget texte(
    String s,
    double taille, {
    bool gras = true,
    bool italique = false,
    pw.TextAlign align = pw.TextAlign.left,
  }) => pw.Text(
    pdfTexte(s),
    textAlign: align,
    style: pw.TextStyle(
      fontSize: f(taille),
      fontWeight: gras ? pw.FontWeight.bold : pw.FontWeight.normal,
      fontStyle: italique ? pw.FontStyle.italic : pw.FontStyle.normal,
    ),
  );

  /// Texte sur une ligne, réduit si besoin pour tenir dans la largeur.
  pw.Widget ajuste(
    String s,
    double taille, {
    bool gras = true,
    Alignement align = Alignement.centre,
  }) => pw.SizedBox(
    width: double.infinity,
    child: pw.FittedBox(
      fit: pw.BoxFit.scaleDown,
      alignment: _boite(align),
      child: texte(s, taille, gras: gras),
    ),
  );

  pw.Widget trait({double epaisseur = 1.4, bool pointilles = false}) =>
      pw.Padding(
        padding: pw.EdgeInsets.symmetric(vertical: v(4)),
        child: pointilles
            ? pw.Divider(
                height: f(1),
                thickness: f(1),
                color: PdfColors.black,
                borderStyle: pw.BorderStyle.dashed,
              )
            : pw.Container(height: f(epaisseur), color: PdfColors.black),
      );

  pw.Widget bande(String s) => pw.Container(
    padding: pw.EdgeInsets.symmetric(vertical: f(3)),
    color: PdfColors.grey300,
    child: pw.Center(child: texte(s, 9)),
  );

  /// Nom coupé en deux lignes équilibrées s'il est long, pour pouvoir l'agrandir.
  List<String> lignesNom(String nom) {
    final n = nom.toUpperCase().trim();
    if (n.length <= 14 || !n.contains(' ')) return [n];
    var meilleur = -1;
    for (var i = 0; i < n.length; i++) {
      if (n[i] == ' ' &&
          (meilleur < 0 ||
              (i - n.length / 2).abs() < (meilleur - n.length / 2).abs())) {
        meilleur = i;
      }
    }
    return [n.substring(0, meilleur).trim(), n.substring(meilleur + 1).trim()];
  }

  /// Une ligne « pictogramme  LIBELLÉ : valeur » (téléphone en grand dessous s'il y en a un).
  pw.Widget ligne(ChampTicket c, double s, bool icones) {
    final taille = 11 * s;
    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(vertical: v(2.2)),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (icones) ...[
            pw.SizedBox(
              width: f(15 * s),
              child: pw.SvgImage(
                svg: _svg(c.picto),
                width: f(13 * s),
                height: f(13 * s),
              ),
            ),
            pw.SizedBox(width: f(5)),
          ],
          // Libellé long (DESTINATAIRE…) : police réduite pour tenir sur une ligne.
          // Colonne des libellés plafonnée : en grande taille, la valeur garde assez de place.
          pw.SizedBox(
            width: f((76 * s).clamp(0, 84)),
            child: pw.FittedBox(
              fit: pw.BoxFit.scaleDown,
              alignment: pw.Alignment.centerLeft,
              child: texte(
                c.libelle,
                c.libelle.length >= 11 ? taille * .8 : taille,
              ),
            ),
          ),
          pw.SizedBox(width: f(6 * s), child: texte(':', taille)),
          pw.Expanded(
            child: (c.tel ?? '').isEmpty
                ? texte(c.valeur, taille)
                : pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [texte(c.valeur, taille), texte(c.tel!, 17 * s)],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Ticket dessiné selon le modèle de l'administrateur.
pw.Widget ticketSelonModele(
  ContenuTicket c,
  ModeleTicket modele,
  CompanySettings co,
  pw.MemoryImage? logo,
  double k, {
  double kv = 1,
  String? bande,
}) {
  final m = _Modele(k, kv: kv, e: modele.espacement);
  final enfants = <pw.Widget>[
    if (bande != null) ...[m.bande(bande), pw.SizedBox(height: m.v(4))],
  ];

  pw.Widget? bloc(BlocTicket b) {
    final s = b.taille * modele.echelle;
    final ta = _texteAlign(b.align);
    switch (b.id) {
      case 'logo':
        final icone = logo != null
            ? pw.Image(logo, height: m.f(76 * s), fit: pw.BoxFit.contain)
            : pw.SvgImage(
                svg: c.sorte == SorteTicket.voyage ? _svgBus : _svgColis,
                width: m.f(62 * s),
                height: m.f(62 * s),
              );
        return pw.Align(alignment: _boite(b.align), child: icone);
      case 'nom':
        final noms = m.lignesNom(co.nom);
        return pw.Column(
          children: [
            // Aussi grand que la largeur le permet, sans réserver de hauteur vide quand le nom est long.
            for (final n in noms)
              pw.Align(
                alignment: _boite(b.align),
                child: pw.ConstrainedBox(
                  constraints: pw.BoxConstraints(
                    maxWidth: m.f(210),
                    maxHeight: m.f((noms.length > 1 ? 40 : 50) * s),
                  ),
                  child: pw.FittedBox(
                    fit: pw.BoxFit.contain,
                    child: m.texte(n, 44),
                  ),
                ),
              ),
          ],
        );
      case 'activite':
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            m.texte(c.activite, 9.5 * s, align: ta),
            if (co.slogan.isNotEmpty)
              m.texte(co.slogan, 8.5 * s, italique: true, align: ta),
          ],
        );
      case 'telephone':
        if (co.telephone.isEmpty) return null;
        return m.texte('Tél. : ${co.telephone}', 15 * s, align: ta);
      case 'titre':
        return m.ajuste(c.titre, 25 * s, align: b.align);
      case 'numero':
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            m.ajuste('N° : ${c.numero}', 14 * s, align: b.align),
            if (c.note != null)
              m.texte(c.note!, 6.5 * s, gras: false, align: ta),
          ],
        );
      case 'destination':
        if (c.destination == null) return null;
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            m.texte('DESTINATION', 9 * s, align: ta),
            m.ajuste(c.destination!, 30 * s, align: b.align),
            if (c.provenance != null) m.texte(c.provenance!, 10 * s, align: ta),
          ],
        );
      case 'infos':
        final champs = [
          for (final x in c.champs)
            if (!modele.masques.contains(x.id)) x,
        ];
        if (champs.isEmpty) return null;
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [for (final x in champs) m.ligne(x, s, modele.icones)],
        );
      case 'prix':
        if (c.prix == null) return null;
        if (c.gratuit) {
          return m.ajuste(
            'VOYAGE GRATUIT — MERCI DE VOTRE FIDÉLITÉ',
            14 * s,
            align: b.align,
          );
        }
        final montant = fcfa(c.prix!).replaceAll('FCFA', 'F CFA');
        if (b.align == Alignement.centre) {
          return pw.Column(
            children: [m.texte('PRIX PAYÉ', 12 * s), m.ajuste(montant, 22 * s)],
          );
        }
        return pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            m.texte('PRIX PAYÉ :', 14 * s),
            pw.SizedBox(width: m.f(6)),
            // Montant réduit si besoin pour ne jamais déborder du ticket.
            pw.Expanded(
              child: m.ajuste(montant, 18 * s, align: Alignement.droite),
            ),
          ],
        );
      case 'qr':
        return pw.Align(
          alignment: _boite(b.align),
          child: pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(),
            data: c.numero,
            width: m.f(96 * s),
            height: m.f(96 * s),
          ),
        );
      case 'qr_numero':
        return m.ajuste(c.numero, 14 * s, align: b.align);
      case 'consigne':
        if (c.consigne.isEmpty) return null;
        return m.texte(c.consigne, 8.5 * s, align: ta);
      case 'merci':
        if (c.merci.isEmpty) return null;
        return m.ajuste(c.merci, 15 * s, align: b.align);
      case 'mention':
        if (co.mentionTicket.trim().isEmpty) return null;
        return m.texte(co.mentionTicket.trim(), 11 * s, align: ta);
    }
    return null;
  }

  var premier = true;
  for (final b in modele.blocs) {
    if (!b.visible) continue;
    final w = bloc(b);
    if (w == null) continue;
    if (!premier) enfants.add(pw.SizedBox(height: m.v(2)));
    premier = false;
    enfants.add(w);
    if (b.traitApres) {
      enfants.add(
        m.trait(
          epaisseur: b.id == 'telephone' || b.id == 'nom' ? 1.4 : 1,
          pointilles: b.id == 'infos' || b.id == 'prix',
        ),
      );
    }
  }
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    mainAxisSize: pw.MainAxisSize.min,
    children: enfants,
  );
}

ModeleTicket _modele(CompanySettings co, SorteTicket s) =>
    ModelesTickets.fromJson(co.modeleTickets).de(s);

/// Ticket de voyage (billet de transport).
pw.Widget ticketVoyage(
  Ticket t,
  CompanySettings co,
  pw.MemoryImage? logo,
  double k, {
  double kv = 1,
  String? bande,
}) => ticketSelonModele(
  contenuVoyage(t),
  _modele(co, SorteTicket.voyage),
  co,
  logo,
  k,
  kv: kv,
  bande: bande,
);

/// Ticket remis à l'expéditeur lors de l'enregistrement d'un colis.
pw.Widget ticketColisClient(
  Colis c,
  CompanySettings co,
  pw.MemoryImage? logo,
  double k, {
  double kv = 1,
  String? bande,
}) => ticketSelonModele(
  contenuColis(c),
  _modele(co, SorteTicket.colis),
  co,
  logo,
  k,
  kv: kv,
  bande: bande,
);

/// Étiquette autocollante à coller sur le colis : destination en grand, destinataire, QR code (sans prix).
pw.Widget etiquetteColis(
  Colis c,
  CompanySettings co,
  pw.MemoryImage? logo,
  double k, {
  double kv = 1,
  String? bande,
}) => ticketSelonModele(
  contenuEtiquette(c),
  _modele(co, SorteTicket.etiquette),
  co,
  logo,
  k,
  kv: kv,
  bande: bande,
);
