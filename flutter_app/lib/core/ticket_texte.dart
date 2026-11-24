import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

import '../data/journal.dart';
import '../data/modele_ticket.dart';
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
    // En double (triple…) largeur, une ligne contient deux (trois…) fois moins de caractères.
    final largeur = cols ~/ taille.value;
    for (final l in _lignes(sansAccents(s), largeur)) {
      octets.addAll(
        g.text(
          l,
          styles: PosStyles(
            bold: gras,
            align: align,
            width: taille,
            height: taille,
          ),
        ),
      );
    }
  }

  void centre(
    String s, {
    bool gras = true,
    PosTextSize taille = PosTextSize.size1,
  }) => ligne(s, gras: gras, align: PosAlign.center, taille: taille);

  void trait() => octets.addAll(g.hr(ch: '-'));

  void vide([int n = 1]) => octets.addAll(g.emptyLines(n));

  /// « LIBELLE : valeur » ; la valeur passe à la ligne, légèrement décalée, si elle est trop longue.
  void champ(
    String libelle,
    String valeur, {
    PosTextSize taille = PosTextSize.size1,
  }) {
    // En double taille, une ligne contient deux fois moins de caractères.
    final c = cols ~/ taille.value;
    final prefixe = '${sansAccents(libelle)} : ';
    final largeur = c - prefixe.length;
    final l = _lignes(sansAccents(valeur), largeur < 8 ? c : largeur);
    if (l.isEmpty) return;
    if (largeur < 8) {
      ligne(prefixe.trimRight(), taille: taille);
      for (final x in l) {
        ligne('  $x', taille: taille);
      }
      return;
    }
    ligne('$prefixe${l.first}', taille: taille);
    for (final x in l.skip(1)) {
      ligne('${' ' * prefixe.length}$x', taille: taille);
    }
  }

  /// Nom de l'entreprise le plus grand possible : triple taille s'il est court, sinon double taille
  /// sur plusieurs lignes (un mot par ligne si besoin) plutôt que petit sur une seule.
  /// `s` < 0,8 : nom en taille normale ; `s` ≥ 1,25 : triple taille dès que possible.
  void nomGrand(String nom, {double s = 1, PosAlign align = PosAlign.center}) {
    final n = sansAccents(nom).toUpperCase().trim();
    if (n.isEmpty) return;
    if (s < .8) {
      ligne(n, align: align);
      return;
    }
    if (n.length <= cols ~/ 3) {
      ligne(n, align: align, taille: PosTextSize.size3);
      return;
    }
    if (s >= 1.25) {
      final mots = _lignes(n, cols ~/ 3);
      if (mots.every((l) => l.length <= cols ~/ 3)) {
        for (final l in mots) {
          ligne(l, align: align, taille: PosTextSize.size3);
        }
        return;
      }
    }
    for (final l in _lignes(n, cols ~/ 2)) {
      ligne(
        l,
        align: align,
        taille: l.length <= cols ~/ 2 ? PosTextSize.size2 : PosTextSize.size1,
      );
    }
  }

  /// Numéro de téléphone en double taille (lisible), précédé d'un libellé s'il tient sur la ligne.
  void telGrand(String tel, {String libelle = ''}) {
    final t = sansAccents(tel).trim();
    if (t.isEmpty) return;
    final avec = libelle.isEmpty ? t : '$libelle $t';
    ligne(avec.length <= cols ~/ 2 ? avec : t, taille: PosTextSize.size2);
  }

  /// Mention personnalisée de l'entreprise, en bas du ticket.
  void mention(CompanySettings co) {
    if (co.mentionTicket.trim().isEmpty) return;
    centre(co.mentionTicket.trim());
  }

  void entete(CompanySettings co, String activite) {
    nomGrand(co.nom);
    centre(activite);
    if (co.slogan.isNotEmpty) centre(co.slogan, gras: false);
    if (co.telephone.isNotEmpty) {
      final t = sansAccents(co.telephone).trim();
      centre(
        ('Tel : $t').length <= cols ~/ 2 ? 'Tel : $t' : t,
        taille: PosTextSize.size2,
      );
    }
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

/// Taille de police d'imprimante (1 à 3 fois) pour une taille de base et le multiplicateur du modèle.
PosTextSize _taille(int base, double s) {
  final n = (base * s).round().clamp(1, 3);
  return n == 1
      ? PosTextSize.size1
      : n == 2
      ? PosTextSize.size2
      : PosTextSize.size3;
}

PosAlign _align(Alignement a) => switch (a) {
  Alignement.gauche => PosAlign.left,
  Alignement.centre => PosAlign.center,
  Alignement.droite => PosAlign.right,
};

/// Ticket texte selon le modèle de l'administrateur (même ordre, tailles et alignements que le ticket image ;
/// le logo, s'il est affiché, est imprimé en tête par l'imprimante elle-même).
void _selonModele(_Doc d, ContenuTicket c, ModeleTicket m, CompanySettings co) {
  var premier = true;
  for (final b in m.blocs) {
    if (!b.visible || b.id == 'logo') continue;
    final s = b.taille * m.echelle;
    final al = _align(b.align);
    final avant = d.octets.length;
    if (!premier && m.espacement >= 1.3) d.vide();
    final debut = d.octets.length;
    switch (b.id) {
      case 'nom':
        d.nomGrand(co.nom, s: s, align: al);
      case 'activite':
        d.ligne(c.activite, align: al, taille: _taille(1, s));
        if (co.slogan.isNotEmpty) d.ligne(co.slogan, gras: false, align: al);
      case 'telephone':
        if (co.telephone.isNotEmpty) {
          final t = sansAccents(co.telephone).trim();
          final tt = _taille(2, s);
          d.ligne(
            ('Tel : $t').length <= d.cols ~/ tt.value ? 'Tel : $t' : t,
            align: al,
            taille: tt,
          );
        }
      case 'titre':
        d.ligne(c.titre, align: al, taille: _taille(2, s));
      case 'numero':
        d.ligne('N° ${c.numero}', align: al, taille: _taille(1, s));
      case 'destination':
        if (c.destination != null) {
          d.ligne('DESTINATION', align: al);
          d.ligne(c.destination!, align: al, taille: _taille(2, s));
          if (c.provenance != null) d.ligne(c.provenance!, align: al);
        }
      case 'infos':
        for (final x in c.champs) {
          if (m.masques.contains(x.id)) continue;
          d.champ(x.libelle, x.valeur, taille: _taille(1, s));
          if ((x.tel ?? '').isNotEmpty) d.telGrand(x.tel!);
        }
      case 'prix':
        if (c.prix != null) {
          // « À gauche » = libellé et montant sur une ligne en image ; en texte, montant centré en grand.
          final al = b.align == Alignement.gauche
              ? PosAlign.center
              : _align(b.align);
          if (c.gratuit) {
            d.ligne('VOYAGE GRATUIT', align: al, taille: _taille(2, s));
            d.ligne('Merci pour votre fidelite !', align: al);
          } else {
            d.ligne('PRIX PAYE', align: al, taille: _taille(1, s));
            d.ligne(_fcfa(c.prix!), align: al, taille: _taille(2, s));
          }
        }
      case 'qr':
        final n = (6 * s).round().clamp(3, 8);
        final taille = switch (n) {
          3 => QRSize.size3,
          4 => QRSize.size4,
          5 => QRSize.size5,
          6 => QRSize.size6,
          7 => QRSize.size7,
          _ => QRSize.size8,
        };
        d.octets.addAll(d.g.qrcode(c.numero, size: taille, align: al));
      case 'qr_numero':
        d.ligne(c.numero, align: al, taille: _taille(1, s));
      case 'consigne':
        if (c.consigne.isNotEmpty) {
          d.ligne(c.consigne, gras: false, align: al, taille: _taille(1, s));
        }
      case 'merci':
        if (c.merci.isNotEmpty) {
          d.ligne(c.merci, align: al, taille: _taille(1, s));
        }
      case 'mention':
        if (co.mentionTicket.trim().isNotEmpty) {
          d.ligne(co.mentionTicket.trim(), align: al, taille: _taille(1, s));
        }
    }
    if (d.octets.length == debut) {
      // Rien d'imprimé pour ce bloc : on retire l'éventuelle ligne vide ajoutée avant.
      d.octets.removeRange(avant, d.octets.length);
      continue;
    }
    premier = false;
    if (b.traitApres) d.trait();
  }
}

ModeleTicket _modeleDe(CompanySettings co, SorteTicket s) =>
    ModelesTickets.fromJson(co.modeleTickets).de(s);

/// Le logo est-il affiché sur ce ticket (le mode texte l'imprime en tête) ?
bool logoAffiche(CompanySettings co, SorteTicket s) =>
    _modeleDe(co, s).bloc('logo')?.visible ?? true;

/// Ticket de voyage.
List<int> ticketVoyageTexte(
  Generator g,
  int cols,
  Ticket t,
  CompanySettings co,
) => _doc(
  g,
  cols,
  (d) =>
      _selonModele(d, contenuVoyage(t), _modeleDe(co, SorteTicket.voyage), co),
);

/// Ticket remis à l'expéditeur lors de l'enregistrement d'un colis.
List<int> ticketColisTexte(
  Generator g,
  int cols,
  Colis c,
  CompanySettings co,
) => _doc(
  g,
  cols,
  (d) => _selonModele(d, contenuColis(c), _modeleDe(co, SorteTicket.colis), co),
);

/// Étiquette à coller sur le colis (sans prix) : destination en grand.
List<int> etiquetteTexte(Generator g, int cols, Colis c, CompanySettings co) =>
    _doc(
      g,
      cols,
      (d) => _selonModele(
        d,
        contenuEtiquette(c),
        _modeleDe(co, SorteTicket.etiquette),
        co,
      ),
    );

/// Ticket d'essai.
List<int> testTexte(
  Generator g,
  int cols,
  CompanySettings co,
  String role,
  String imprimante,
) => _doc(g, cols, (d) {
  d.nomGrand(co.nom);
  d.centre('TEST - ${role.toUpperCase()}');
  d.trait();
  d.qr('TCHI-TEST');
  d.centre('Imprimante : $imprimante');
});

/// Rapport de fin de journée d'une personne (billets vendus, colis enregistrés, colis réceptionnés).
/// `montants` : affiche les prix et les totaux par mode de paiement (choix de l'administrateur).
List<int> clotureTexte(
  Generator g,
  int cols,
  CompanySettings co, {
  required String nom,
  required DateTime jour,
  required List<JournalLigne> lignes,
  required bool montants,
}) => _doc(g, cols, (d) {
  final t = JournalTotaux(lignes);
  d.entete(co, 'RAPPORT DE FIN DE JOURNEE');
  d.champ('AGENT', nom);
  d.champ('DATE', dateFr(jour));
  d.trait();
  if (lignes.isEmpty) d.centre('Aucune operation ce jour');
  for (final l in lignes) {
    final h =
        '${l.quand.hour.toString().padLeft(2, '0')}:${l.quand.minute.toString().padLeft(2, '0')}';
    final genre = switch (l.type) {
      'billet' => 'BILLET',
      'colis_envoye' => 'COLIS ENVOYE',
      _ => 'COLIS RECU',
    };
    d.ligne('$h $genre ${l.numero}');
    d.ligne('  ${l.libelle}', gras: false);
    if (montants && l.encaisse)
      d.ligne(
        '  ${_fcfa(l.montant!)} - ${libelleModePaiement(l.modePaiement)}',
        gras: false,
      );
  }
  d.trait();
  d.champ('BILLETS VENDUS', '${t.billets}');
  d.champ('COLIS ENVOYES', '${t.colisEnvoyes}');
  d.champ('COLIS RECUS', '${t.colisRecus}');
  if (montants) {
    d.trait();
    d.champ('BILLETS', _fcfa(t.montantBillets));
    d.champ('COLIS', _fcfa(t.montantColis));
    d.champ('ESPECES', _fcfa(t.especes));
    d.champ('ORANGE MONEY', _fcfa(t.orangeMoney));
    d.centre('TOTAL');
    d.centre(_fcfa(t.total), taille: PosTextSize.size2);
  }
  d.trait();
  d.vide(2);
  d.ligne('Signature :');
  d.vide(2);
});
