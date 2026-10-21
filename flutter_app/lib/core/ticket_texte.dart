import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

import '../data/models.dart';
import 'format.dart';

/// Tickets en TEXTE ESC/POS : quelques centaines d'octets seulement, imprimés avec les polices et le QR code
/// de l'imprimante elle-même. C'est le mode le plus fiable sur les petites imprimantes Bluetooth, qui n'arrivent
/// pas à recevoir une image assez vite (bandes blanches, lignes coupées). Pas d'accents ni de pictogrammes.

/// Texte sans accents ni caractères spéciaux (les polices d'imprimante n'ont pas tous les accents).
String sansAccents(String s) {
  const de = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿÀÂÄÁÃÅÇÉÈÊËÍÌÎÏÑÓÒÔÖÕÚÙÛÜÝœŒ';
  const vers = 'aaaaaaceeeeiiiinooooouuuuyyAAAAAACEEEEIIIINOOOOOUUUUYoO';
  final b = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    final i = de.indexOf(c);
    if (i >= 0) {
      b.write(vers[i]);
    } else if (r == 0x2019 || r == 0x2018) {
      b.write("'");
    } else if (r == 0x2013 || r == 0x2014) {
      b.write('-');
    } else if (r == 0xA0 || r == 0x202F || r == 0x2009) {
      b.write(' ');
    } else if (r == 0xD7) {
      b.write('x');
    } else if (r == 0xB0) {
      b.write('o');
    } else if (r < 32 || r > 126) {
      b.write('');
    } else {
      b.write(c);
    }
  }
  return b.toString();
}

String _fcfa(double v) => sansAccents(fcfa(v)).replaceAll('FCFA', 'F CFA');

/// Coupe un texte en lignes de `largeur` caractères au plus (à l'espace si possible).
List<String> _lignes(String texte, int largeur) {
  final sortie = <String>[];
  for (final bloc in texte.split('\n')) {
    var reste = bloc.trim();
    if (reste.isEmpty) continue;
    while (reste.length > largeur) {
      var coupe = reste.lastIndexOf(' ', largeur);
      if (coupe <= 0) coupe = largeur;
      sortie.add(reste.substring(0, coupe).trimRight());
      reste = reste.substring(coupe).trimLeft();
    }
    sortie.add(reste);
  }
  return sortie;
}

class _Doc {
  _Doc(this.g, this.cols);
  final Generator g;
  final int cols;
  final List<int> octets = [];

  void ligne(
    String s, {
    bool gras = true,
    PosAlign align = PosAlign.left,
    PosTextSize taille = PosTextSize.size1,
  }) {
    // En double largeur, une ligne contient deux fois moins de caractères.
    final largeur = taille == PosTextSize.size1 ? cols : cols ~/ 2;
    for (final l in _lignes(sansAccents(s), largeur)) {
      octets.addAll(
        g.text(l, styles: PosStyles(bold: gras, align: align, width: taille, height: taille)),
      );
    }
  }

  void centre(String s, {bool gras = true, PosTextSize taille = PosTextSize.size1}) =>
      ligne(s, gras: gras, align: PosAlign.center, taille: taille);

  void trait() => octets.addAll(g.hr(ch: '-'));

  void vide([int n = 1]) => octets.addAll(g.emptyLines(n));

  /// « LIBELLE : valeur » ; la valeur passe à la ligne, légèrement décalée, si elle est trop longue.
  void champ(String libelle, String valeur) {
    final prefixe = '${sansAccents(libelle)} : ';
    final largeur = cols - prefixe.length;
    final l = _lignes(sansAccents(valeur), largeur < 8 ? cols : largeur);
    if (l.isEmpty) return;
    if (largeur < 8) {
      ligne(prefixe.trimRight());
      for (final x in l) {
        ligne('  $x');
      }
      return;
    }
    ligne('$prefixe${l.first}');
    for (final x in l.skip(1)) {
      ligne('${' ' * prefixe.length}$x');
    }
  }

  void entete(CompanySettings co, String activite) {
    final nom = sansAccents(co.nom).toUpperCase();
    // Nom de l'entreprise en grand s'il tient sur une ligne en double largeur.
    centre(nom, taille: nom.length <= cols ~/ 2 ? PosTextSize.size2 : PosTextSize.size1);
    centre(activite);
    if (co.slogan.isNotEmpty) centre(co.slogan, gras: false);
    if (co.telephone.isNotEmpty) centre('Tel : ${co.telephone}');
    trait();
  }

  void prix(double montant) {
    centre('PRIX PAYE');
    centre(_fcfa(montant), taille: PosTextSize.size2);
    trait();
  }

  void qr(String donnees, {QRSize taille = QRSize.size6}) {
    octets.addAll(g.qrcode(donnees, size: taille));
    centre(donnees, taille: PosTextSize.size1);
  }
}

List<int> _doc(Generator g, int cols, void Function(_Doc d) corps) {
  final d = _Doc(g, cols);
  corps(d);
  d.octets.addAll(g.feed(4));
  return d.octets;
}

/// Ticket de voyage.
List<int> ticketVoyageTexte(Generator g, int cols, Ticket t, CompanySettings co) => _doc(g, cols, (d) {
  d.entete(co, 'TRANSPORT DE VOYAGEURS');
  d.centre(t.annule ? 'TICKET ANNULE' : 'TICKET DE VOYAGE', taille: PosTextSize.size2);
  d.centre('N° ${t.numero}');
  d.trait();
  d.champ('DATE', dateFr(t.dateVoyage));
  d.champ('DEPART', t.gareDepartNom ?? '-');
  d.champ('ARRIVEE', t.gareArriveeNom ?? '-');
  if ((t.heureDepart ?? '').isNotEmpty) d.champ('HEURE', t.heureDepart!.replaceFirst(':', 'H'));
  if ((t.siege ?? '').isNotEmpty) d.champ('SIEGE', t.siege!);
  d.champ('PASSAGER', t.clientNom);
  d.trait();
  d.prix(t.prix);
  d.qr(t.numero);
  d.ligne('Scannez ce QR code pour verifier le ticket a l\'embarquement.', gras: false, align: PosAlign.center);
  d.trait();
  d.centre('MERCI ET BON VOYAGE !');
});

/// Ticket remis à l'expéditeur lors de l'enregistrement d'un colis.
List<int> ticketColisTexte(Generator g, int cols, Colis c, CompanySettings co) => _doc(g, cols, (d) {
  d.entete(co, 'TRANSPORT DE COLIS');
  d.centre('TICKET DE COLIS', taille: PosTextSize.size2);
  d.centre('N° ${c.numero}');
  d.trait();
  d.champ('DATE', dateFr(c.dateEnvoi));
  d.champ('DEPART', c.gareDepartNom ?? '-');
  d.champ('ARRIVEE', c.gareArriveeNom ?? '-');
  d.champ('EXPEDITEUR', '${c.expediteurNom}\n${c.expediteurTelephone}');
  d.champ('DESTINATAIRE', '${c.destinataireNom}\n${c.destinataireTelephone}');
  d.champ('COLIS', '${c.nombre} x ${c.description}${c.poids != null ? ' (${c.poids} kg)' : ''}');
  if (c.valeur != null) d.champ('VALEUR', _fcfa(c.valeur!));
  d.trait();
  d.prix(c.prix);
  d.qr(c.numero);
  d.ligne('Conservez ce ticket : il sera demande pour le retrait du colis.', gras: false, align: PosAlign.center);
  d.trait();
  d.centre('MERCI DE VOTRE CONFIANCE !');
});

/// Étiquette à coller sur le colis (sans prix) : destination en grand.
List<int> etiquetteTexte(Generator g, int cols, Colis c, CompanySettings co) => _doc(g, cols, (d) {
  d.centre(co.nom.toUpperCase());
  d.trait();
  d.centre('DESTINATION');
  d.centre(c.gareArriveeNom ?? '-', taille: PosTextSize.size2);
  d.centre('DE : ${c.gareDepartNom ?? '-'}');
  d.trait();
  d.champ('DESTINATAIRE', '${c.destinataireNom}\n${c.destinataireTelephone}');
  d.champ('EXPEDITEUR', '${c.expediteurNom}\n${c.expediteurTelephone}');
  d.champ('COLIS', '${c.nombre} x ${c.description}');
  d.champ('DATE', dateFr(c.dateEnvoi));
  d.trait();
  d.qr(c.numero);
});

/// Ticket d'essai.
List<int> testTexte(Generator g, int cols, CompanySettings co, String role, String imprimante) => _doc(g, cols, (d) {
  d.centre(co.nom.toUpperCase(), taille: co.nom.length <= cols ~/ 2 ? PosTextSize.size2 : PosTextSize.size1);
  d.centre('TEST - ${role.toUpperCase()}');
  d.trait();
  d.qr('TCHI-TEST');
  d.centre('Imprimante : $imprimante');
});
