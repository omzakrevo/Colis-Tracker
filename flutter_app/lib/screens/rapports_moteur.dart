import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/format.dart';
import '../core/xlsx.dart';
import '../data/finance_models.dart';
import '../data/models.dart';
import 'receipt.dart' show pdfImage, pdfTexte;

/// Types de rapport proposés à l'administrateur.
enum TypeRapport {
  colis('Colis envoyés', 'Liste détaillée des colis, avec l\'agent qui les a enregistrés'),
  caisse('Caisse par personne (espèces / Orange Money)', 'Pour chaque personne : colis et billets vendus, encaissés en espèces ou par Orange Money, par jour, mois ou année'),
  agents('Activité par agent', 'Colis et billets enregistrés par chaque compte, avec les recettes'),
  gares('Recettes par gare', 'Colis, billets et recettes de chaque gare de départ'),
  billets('Billets vendus (liste)', 'Liste détaillée des billets, avec le vendeur'),
  ventesBillets('Ventes de billets par jour / mois', 'Nombre de billets et prix total vendus par jour, par mois ou par année'),
  billetsTrajet('Billets par trajet', 'Billets vendus et chiffre d\'affaires de chaque trajet (départ → arrivée)'),
  billetsHeure('Billets par heure de départ', 'Billets vendus par heure de départ et par trajet'),
  caGare('Chiffre d\'affaires par gare (jour / mois)', 'Chiffre d\'affaires (colis + billets) de chaque gare, jour par jour, mois par mois ou année par année'),
  nonRetires('Colis en attente de retrait', 'Colis arrivés et pas encore retirés, du plus ancien au plus récent'),
  synthese('Synthèse générale', 'Vue d\'ensemble : chiffres clés, jour par jour, statuts, agents et gares (tout en un)'),
  depenses('Dépenses', 'Dépenses par catégorie, par jour / mois / année, et détail de chaque dépense', compta: true),
  bilan('Bilan (entrées, sorties, résultat)', 'Entrées (colis, billets), sorties (dépenses, salaires) et résultat, par jour, mois ou année', compta: true),
  financier('Rapport financier complet', 'Tout ce qui s\'est passé : entrées, dépenses, salaires, résultat, gare par gare', compta: true);

  const TypeRapport(this.titre, this.description, {this.compta = false});
  final String titre, description;

  /// Rapport de comptabilité (réservé à l'administrateur et au comptable, module Comptabilité ouvert).
  final bool compta;
}

/// Un tableau du rapport. Les cellules sont des `String`, nombres, `DateTime` ou `null`.
class SectionRapport {
  SectionRapport(this.titre, this.entetes, this.lignes, {this.totaux, this.montants = const {}});
  final String titre;
  final List<String> entetes;
  final List<List<Object?>> lignes;

  /// Ligne de totaux (même nombre de colonnes que les en-têtes), facultative.
  final List<Object?>? totaux;

  /// Indices des colonnes en montant (affichage « 1 500 » avec séparateur de milliers).
  final Set<int> montants;

  /// Même tableau trié sur une colonne (la ligne de totaux reste en bas) : nombres, dates et textes.
  SectionRapport trie(int colonne, bool croissant) {
    int cmp(Object? a, Object? b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1; // les vides toujours en bas
      if (b == null) return -1;
      if (a is num && b is num) return a.compareTo(b);
      if (a is DateTime && b is DateTime) return a.compareTo(b);
      return '$a'.toLowerCase().compareTo('$b'.toLowerCase());
    }

    final l = [...lignes]
      ..sort((x, y) {
        final a = colonne < x.length ? x[colonne] : null;
        final b = colonne < y.length ? y[colonne] : null;
        if (a == null || b == null) return cmp(a, b);
        return croissant ? cmp(a, b) : -cmp(a, b);
      });
    return SectionRapport(titre, entetes, l, totaux: totaux, montants: montants);
  }
}

class Rapport {
  Rapport(this.type, this.sections, this.resume);
  final TypeRapport type;
  final List<SectionRapport> sections;

  /// Chiffres clés affichés en tête : libellé → valeur.
  final Map<String, String> resume;
}

/// Regroupement des chiffres dans le temps.
enum Granularite {
  jour('Par jour'),
  mois('Par mois'),
  annee('Par année');

  const Granularite(this.label);
  final String label;
}

class FiltresRapport {
  const FiltresRapport({
    this.debut,
    this.fin,
    this.agentId,
    this.agentNom,
    this.gareId,
    this.gareNom,
    this.statut,
    this.granularite = Granularite.jour,
    this.regroupe = false,
  });
  final Granularite granularite;

  /// Vrai pour les rapports qui regroupent par période (le libellé du filtre n'a de sens que pour eux).
  final bool regroupe;
  final DateTime? debut, fin;
  final String? agentId, agentNom, gareNom, statut;
  final int? gareId;

  String get periode => '${debut == null ? '...' : dateFr(debut!)} au ${fin == null ? '...' : dateFr(fin!)}';

  String get description => [
    'Période : $periode',
    if (agentNom != null) 'Agent : $agentNom',
    if (gareNom != null) 'Gare de départ : $gareNom',
    if (statut != null) 'Statut : ${Statut.of(statut!).label}',
    if (regroupe) 'Regroupement : ${granularite.label.toLowerCase()}',
  ].join('  ·  ');
}

DateTime _jour(DateTime d) => DateTime(d.year, d.month, d.day);

/// Construit les tableaux d'un rapport à partir des colis et billets déjà filtrés.
Rapport construireRapport(
  TypeRapport type,
  List<Colis> colisBruts,
  List<Ticket> billetsBruts, {
  Granularite granularite = Granularite.jour,
  List<Depense> depenses = const [],
  List<Bulletin> bulletins = const [],
  Map<int, String> employes = const {},
}) {
  final actifs = colisBruts.where((c) => c.statut != 'annule').toList();
  final billetsActifs = billetsBruts.where((t) => !t.annule).toList();
  final recetteColis = actifs.fold<double>(0, (a, c) => a + c.prix);
  final recetteBillets = billetsActifs.fold<double>(0, (a, t) => a + t.prix);

  SectionRapport colisListe(List<Colis> l, {String titre = 'Colis envoyés'}) => SectionRapport(
    titre,
    [
      'Date', 'N°', 'Agent (envoyé par)', 'Expéditeur', 'Tél. exp.', 'Destinataire', 'Tél. dest.', 'Départ', 'Arrivée',
      'Description', 'Nb', 'Poids (kg)', 'Valeur', 'Prix', 'Statut', 'Billet lié', 'Paiement',
    ],
    [
      for (final c in l)
        [
          _jour(c.dateEnvoi), c.numero, c.agentNom ?? '—', c.expediteurNom, c.expediteurTelephone, c.destinataireNom,
          c.destinataireTelephone, c.gareDepartNom ?? '', c.gareArriveeNom ?? '', c.description, c.nombre, c.poids, c.valeur,
          c.prix, Statut.of(c.statut).label, c.billetNumero ?? '', libelleModePaiement(c.modePaiement),
        ],
    ],
    montants: {12, 13},
    totaux: [
      'TOTAL', '${l.length} colis', '', '', '', '', '', '', '', '', l.fold<int>(0, (a, c) => a + c.nombre), null, null,
      l.where((c) => c.statut != 'annule').fold<double>(0, (a, c) => a + c.prix), '', '', '',
    ],
  );

  SectionRapport billetsListe(List<Ticket> l) => SectionRapport(
    'Billets vendus',
    ['Date de vente', 'N°', 'Vendu par', 'Passager', 'Téléphone', 'Départ', 'Arrivée', 'Date voyage', 'Heure', 'Siège', 'Prix', 'Statut', 'Paiement'],
    [
      for (final t in l)
        [
          t.createdAt.toLocal(), t.numero, t.vendeurNom ?? '—', t.clientNom, t.clientTelephone, t.gareDepartNom ?? '',
          t.gareArriveeNom ?? '', _jour(t.dateVoyage), t.heureDepart ?? '', t.siege ?? '', t.prix, t.annule ? 'Annulé' : 'Valide', libelleModePaiement(t.modePaiement),
        ],
    ],
    montants: {10},
    totaux: ['TOTAL', '${l.length} billets', '', '', '', '', '', '', '', '', l.where((t) => !t.annule).fold<double>(0, (a, t) => a + t.prix), '', ''],
  );


  SectionRapport caisseParPersonne() {
    // personne -> [nbColis, colisEsp, colisOM, nbBillets, billetsEsp, billetsOM]
    final m = <String, List<double>>{};
    List<double> v(String k) => m.putIfAbsent(k, () => List.filled(6, 0));
    for (final c in actifs) {
      final x = v(c.agentNom ?? '—');
      x[0]++;
      x[c.modePaiement == 'orange_money' ? 2 : 1] += c.prix;
    }
    for (final t in billetsActifs) {
      final x = v(t.vendeurNom ?? '—');
      x[3]++;
      x[t.modePaiement == 'orange_money' ? 5 : 4] += t.prix;
    }
    final noms = m.keys.toList()..sort((a, b) => (m[b]!.sublist(1, 3).fold(0.0, (p, e) => p + e) + m[b]!.sublist(4).fold(0.0, (p, e) => p + e)).compareTo(m[a]!.sublist(1, 3).fold(0.0, (p, e) => p + e) + m[a]!.sublist(4).fold(0.0, (p, e) => p + e)));
    final lignes = [
      for (final n in noms)
        [
          n, m[n]![0].toInt(), m[n]![1], m[n]![2], m[n]![3].toInt(), m[n]![4], m[n]![5],
          m[n]![1] + m[n]![4], m[n]![2] + m[n]![5], m[n]![1] + m[n]![2] + m[n]![4] + m[n]![5],
        ],
    ];
    double somme(int i) => lignes.fold<double>(0, (a, l) => a + (l[i] as num));
    return SectionRapport(
      'Caisse par personne',
      ['Personne', 'Colis', 'Colis espèces', 'Colis Orange Money', 'Billets', 'Billets espèces', 'Billets Orange Money', 'Total espèces', 'Total Orange Money', 'Total'],
      lignes,
      montants: {2, 3, 5, 6, 7, 8, 9},
      totaux: ['TOTAL', somme(1).toInt(), somme(2), somme(3), somme(4).toInt(), somme(5), somme(6), somme(7), somme(8), somme(9)],
    );
  }

  SectionRapport parAgent() {
    final m = <String, ({int c, double rc, int b, double rb})>{};
    for (final c in actifs) {
      final k = c.agentNom ?? '—';
      final v = m[k] ?? (c: 0, rc: 0, b: 0, rb: 0);
      m[k] = (c: v.c + 1, rc: v.rc + c.prix, b: v.b, rb: v.rb);
    }
    for (final t in billetsActifs) {
      final k = t.vendeurNom ?? '—';
      final v = m[k] ?? (c: 0, rc: 0, b: 0, rb: 0);
      m[k] = (c: v.c, rc: v.rc, b: v.b + 1, rb: v.rb + t.prix);
    }
    final noms = m.keys.toList()..sort((a, b) => (m[b]!.rc + m[b]!.rb).compareTo(m[a]!.rc + m[a]!.rb));
    return SectionRapport(
      'Activité par agent',
      ['Agent', 'Colis', 'Recette colis', 'Billets', 'Recette billets', 'Total'],
      [for (final n in noms) [n, m[n]!.c, m[n]!.rc, m[n]!.b, m[n]!.rb, m[n]!.rc + m[n]!.rb]],
      montants: {2, 4, 5},
      totaux: ['TOTAL', actifs.length, recetteColis, billetsActifs.length, recetteBillets, recetteColis + recetteBillets],
    );
  }

  SectionRapport parGare() {
    final m = <String, ({int c, double rc, int b, double rb})>{};
    for (final c in actifs) {
      final k = c.gareDepartNom ?? '—';
      final v = m[k] ?? (c: 0, rc: 0, b: 0, rb: 0);
      m[k] = (c: v.c + 1, rc: v.rc + c.prix, b: v.b, rb: v.rb);
    }
    for (final t in billetsActifs) {
      final k = t.gareDepartNom ?? '—';
      final v = m[k] ?? (c: 0, rc: 0, b: 0, rb: 0);
      m[k] = (c: v.c, rc: v.rc, b: v.b + 1, rb: v.rb + t.prix);
    }
    final noms = m.keys.toList()..sort((a, b) => (m[b]!.rc + m[b]!.rb).compareTo(m[a]!.rc + m[a]!.rb));
    return SectionRapport(
      'Recettes par gare de départ',
      ['Gare', 'Colis', 'Recette colis', 'Billets', 'Recette billets', 'Total'],
      [for (final n in noms) [n, m[n]!.c, m[n]!.rc, m[n]!.b, m[n]!.rb, m[n]!.rc + m[n]!.rb]],
      montants: {2, 4, 5},
      totaux: ['TOTAL', actifs.length, recetteColis, billetsActifs.length, recetteBillets, recetteColis + recetteBillets],
    );
  }

  SectionRapport parJour() {
    final m = <DateTime, ({int c, double rc, int b, double rb})>{};
    for (final c in actifs) {
      final k = _jour(c.dateEnvoi);
      final v = m[k] ?? (c: 0, rc: 0, b: 0, rb: 0);
      m[k] = (c: v.c + 1, rc: v.rc + c.prix, b: v.b, rb: v.rb);
    }
    for (final t in billetsActifs) {
      final k = _jour(t.createdAt.toLocal());
      final v = m[k] ?? (c: 0, rc: 0, b: 0, rb: 0);
      m[k] = (c: v.c, rc: v.rc, b: v.b + 1, rb: v.rb + t.prix);
    }
    final jours = m.keys.toList()..sort();
    return SectionRapport(
      'Activité jour par jour',
      ['Date', 'Colis', 'Recette colis', 'Billets', 'Recette billets', 'Total'],
      [for (final j in jours) [j, m[j]!.c, m[j]!.rc, m[j]!.b, m[j]!.rb, m[j]!.rc + m[j]!.rb]],
      montants: {2, 4, 5},
    );
  }

  SectionRapport parStatut() {
    final m = <String, int>{};
    for (final c in colisBruts) {
      m[c.statut] = (m[c.statut] ?? 0) + 1;
    }
    return SectionRapport(
      'Colis par statut',
      ['Statut', 'Colis'],
      [for (final s in Statut.values) if ((m[s.code] ?? 0) > 0) [s.label, m[s.code]]],
      totaux: ['TOTAL', colisBruts.length],
    );
  }


  /// Début de la période contenant `d` selon le regroupement choisi.
  DateTime cle(DateTime d) => switch (granularite) {
    Granularite.jour => DateTime(d.year, d.month, d.day),
    Granularite.mois => DateTime(d.year, d.month),
    Granularite.annee => DateTime(d.year),
  };
  String libelle(DateTime k) => switch (granularite) {
    Granularite.jour => dateFr(k),
    Granularite.mois => '${k.month.toString().padLeft(2, '0')}/${k.year}',
    Granularite.annee => '${k.year}',
  };
  String periodeNom() => switch (granularite) {
    Granularite.jour => 'Date',
    Granularite.mois => 'Mois',
    Granularite.annee => 'Année',
  };

  SectionRapport ventesBilletsPeriode() {
    final m = <DateTime, ({int n, double ca, int ann})>{};
    for (final t in billetsBruts) {
      final k = cle(t.createdAt.toLocal());
      final v = m[k] ?? (n: 0, ca: 0, ann: 0);
      m[k] = t.annule ? (n: v.n, ca: v.ca, ann: v.ann + 1) : (n: v.n + 1, ca: v.ca + t.prix, ann: v.ann);
    }
    final ks = m.keys.toList()..sort();
    return SectionRapport(
      'Ventes de billets (${granularite.label.toLowerCase()})',
      [periodeNom(), 'Billets vendus', 'Prix total', 'Prix moyen', 'Billets annulés'],
      [for (final k in ks) [libelle(k), m[k]!.n, m[k]!.ca, m[k]!.n == 0 ? 0.0 : m[k]!.ca / m[k]!.n, m[k]!.ann]],
      montants: {2, 3},
      totaux: [
        'TOTAL',
        billetsActifs.length,
        recetteBillets,
        billetsActifs.isEmpty ? 0.0 : recetteBillets / billetsActifs.length,
        billetsBruts.length - billetsActifs.length,
      ],
    );
  }

  String trajetNom(Ticket t) => '${t.gareDepartNom ?? '—'} → ${t.gareArriveeNom ?? '—'}';

  SectionRapport billetsParTrajet() {
    final m = <String, ({int n, double ca})>{};
    for (final t in billetsActifs) {
      final k = trajetNom(t);
      final v = m[k] ?? (n: 0, ca: 0);
      m[k] = (n: v.n + 1, ca: v.ca + t.prix);
    }
    final noms = m.keys.toList()..sort((a, b) => m[b]!.ca.compareTo(m[a]!.ca));
    return SectionRapport(
      'Billets par trajet',
      ['Trajet', 'Billets vendus', 'Prix total', 'Prix moyen', 'Part du total (%)'],
      [
        for (final n in noms)
          [n, m[n]!.n, m[n]!.ca, m[n]!.ca / m[n]!.n, recetteBillets == 0 ? 0.0 : (m[n]!.ca * 1000 / recetteBillets).round() / 10],
      ],
      montants: {2, 3},
      totaux: ['TOTAL', billetsActifs.length, recetteBillets, billetsActifs.isEmpty ? 0.0 : recetteBillets / billetsActifs.length, 100],
    );
  }

  SectionRapport billetsParHeure() {
    final m = <String, ({int n, double ca})>{};
    for (final t in billetsActifs) {
      final h = (t.heureDepart ?? '').trim().isEmpty ? 'Sans horaire' : t.heureDepart!.trim();
      final k = '$h|${trajetNom(t)}';
      final v = m[k] ?? (n: 0, ca: 0);
      m[k] = (n: v.n + 1, ca: v.ca + t.prix);
    }
    final ks = m.keys.toList()..sort();
    return SectionRapport(
      'Billets par heure de départ',
      ['Heure de départ', 'Trajet', 'Billets vendus', 'Prix total'],
      [
        for (final k in ks) [k.split('|').first, k.split('|').last, m[k]!.n, m[k]!.ca],
      ],
      montants: {3},
      totaux: ['TOTAL', '', billetsActifs.length, recetteBillets],
    );
  }

  SectionRapport caParGare() {
    final m = <String, ({int c, double rc, int b, double rb})>{};
    final periodes = <String, DateTime>{};
    String k(String gare, DateTime p) => '$gare|${p.toIso8601String()}';
    void add(String gare, DateTime d, {double rc = 0, int c = 0, double rb = 0, int b = 0}) {
      final p = cle(d);
      final key = k(gare, p);
      periodes[key] = p;
      final v = m[key] ?? (c: 0, rc: 0, b: 0, rb: 0);
      m[key] = (c: v.c + c, rc: v.rc + rc, b: v.b + b, rb: v.rb + rb);
    }

    for (final c in actifs) {
      add(c.gareDepartNom ?? '—', c.dateEnvoi, c: 1, rc: c.prix);
    }
    for (final t in billetsActifs) {
      add(t.gareDepartNom ?? '—', t.createdAt.toLocal(), b: 1, rb: t.prix);
    }
    final ks = m.keys.toList()
      ..sort((a, b) {
        final ga = a.split('|').first, gb = b.split('|').first;
        final c = ga.compareTo(gb);
        return c != 0 ? c : periodes[a]!.compareTo(periodes[b]!);
      });
    return SectionRapport(
      'Chiffre d\'affaires par gare (${granularite.label.toLowerCase()})',
      ['Gare', periodeNom(), 'Colis', 'CA colis', 'Billets', 'CA billets', 'CA total'],
      [
        for (final key in ks)
          [key.split('|').first, libelle(periodes[key]!), m[key]!.c, m[key]!.rc, m[key]!.b, m[key]!.rb, m[key]!.rc + m[key]!.rb],
      ],
      montants: {3, 5, 6},
      totaux: ['TOTAL', '', actifs.length, recetteColis, billetsActifs.length, recetteBillets, recetteColis + recetteBillets],
    );
  }

  final totalDepenses = depenses.fold<double>(0, (a, d) => a + d.montant);
  final totalSalaires = bulletins.fold<double>(0, (a, b) => a + b.net);
  final entrees = recetteColis + recetteBillets;
  final sorties = totalDepenses + totalSalaires;
  final resultat = entrees - sorties;

  SectionRapport caisseParPeriode() {
    final m = <DateTime, ({double e, double o})>{};
    void ajoute(DateTime d, double prix, bool om) {
      final k = cle(d);
      final x = m[k] ?? (e: 0, o: 0);
      m[k] = om ? (e: x.e, o: x.o + prix) : (e: x.e + prix, o: x.o);
    }

    for (final c in actifs) {
      ajoute(c.dateEnvoi, c.prix, c.modePaiement == 'orange_money');
    }
    for (final t in billetsActifs) {
      ajoute(t.createdAt.toLocal(), t.prix, t.modePaiement == 'orange_money');
    }
    final ks = m.keys.toList()..sort();
    final e = m.values.fold<double>(0, (a, x) => a + x.e);
    final o = m.values.fold<double>(0, (a, x) => a + x.o);
    return SectionRapport(
      'Encaissements (${granularite.label.toLowerCase()})',
      [periodeNom(), 'Espèces', 'Orange Money', 'Total'],
      [for (final k in ks) [libelle(k), m[k]!.e, m[k]!.o, m[k]!.e + m[k]!.o]],
      montants: {1, 2, 3},
      totaux: ['TOTAL', e, o, e + o],
    );
  }

  SectionRapport depensesParCategorie() {
    final m = <String, ({int n, double s})>{};
    for (final d in depenses) {
      final v = m[d.categorie] ?? (n: 0, s: 0);
      m[d.categorie] = (n: v.n + 1, s: v.s + d.montant);
    }
    final ks = m.keys.toList()..sort((a, b) => m[b]!.s.compareTo(m[a]!.s));
    return SectionRapport(
      'Dépenses par catégorie',
      ['Catégorie', 'Nombre', 'Montant', 'Part du total (%)'],
      [for (final k in ks) [k, m[k]!.n, m[k]!.s, totalDepenses == 0 ? 0.0 : (m[k]!.s * 1000 / totalDepenses).round() / 10]],
      montants: {2},
      totaux: ['TOTAL', depenses.length, totalDepenses, 100],
    );
  }

  SectionRapport depensesParPeriode() {
    final m = <DateTime, ({int n, double s})>{};
    for (final d in depenses) {
      final k = cle(d.date);
      final v = m[k] ?? (n: 0, s: 0);
      m[k] = (n: v.n + 1, s: v.s + d.montant);
    }
    final ks = m.keys.toList()..sort();
    return SectionRapport(
      'Dépenses (${granularite.label.toLowerCase()})',
      [periodeNom(), 'Nombre', 'Montant'],
      [for (final k in ks) [libelle(k), m[k]!.n, m[k]!.s]],
      montants: {2},
      totaux: ['TOTAL', depenses.length, totalDepenses],
    );
  }

  SectionRapport depensesDetail() => SectionRapport(
    'Détail des dépenses',
    ['Date', 'Libellé', 'Catégorie', 'Bénéficiaire', 'Mode', 'Référence', 'Montant'],
    [for (final d in depenses) [_jour(d.date), d.libelle, d.categorie, d.beneficiaire, d.modePaiement, d.reference, d.montant]],
    montants: {6},
    totaux: ['TOTAL', '${depenses.length} dépenses', '', '', '', '', totalDepenses],
  );

  SectionRapport salairesPayes() => SectionRapport(
    'Salaires payés',
    ['Employé', 'Mois', 'Date de paiement', 'Brut', 'Retenues', 'Net payé'],
    [
      for (final b in bulletins)
        [employes[b.employeId] ?? 'Employé n° ${b.employeId}', '${b.mois.month.toString().padLeft(2, '0')}/${b.mois.year}', b.datePaiement == null ? null : _jour(b.datePaiement!), b.brut, b.totalRetenues, b.net],
    ],
    montants: {3, 4, 5},
    totaux: ['TOTAL', '', null, bulletins.fold<double>(0, (a, b) => a + b.brut), bulletins.fold<double>(0, (a, b) => a + b.totalRetenues), totalSalaires],
  );

  SectionRapport bilanParPeriode() {
    final m = <DateTime, ({double c, double b, double d, double s})>{};
    void ajoute(DateTime d, {double c = 0, double b = 0, double dep = 0, double sal = 0}) {
      final k = cle(d);
      final v = m[k] ?? (c: 0, b: 0, d: 0, s: 0);
      m[k] = (c: v.c + c, b: v.b + b, d: v.d + dep, s: v.s + sal);
    }

    for (final c in actifs) {
      ajoute(c.dateEnvoi, c: c.prix);
    }
    for (final t in billetsActifs) {
      ajoute(t.createdAt.toLocal(), b: t.prix);
    }
    for (final d in depenses) {
      ajoute(d.date, dep: d.montant);
    }
    for (final b in bulletins) {
      ajoute(b.datePaiement ?? b.mois, sal: b.net);
    }
    final ks = m.keys.toList()..sort();
    return SectionRapport(
      'Bilan (${granularite.label.toLowerCase()})',
      [periodeNom(), 'Entrées colis', 'Entrées billets', 'Total entrées', 'Dépenses', 'Salaires', 'Total sorties', 'Résultat'],
      [
        for (final k in ks)
          [libelle(k), m[k]!.c, m[k]!.b, m[k]!.c + m[k]!.b, m[k]!.d, m[k]!.s, m[k]!.d + m[k]!.s, m[k]!.c + m[k]!.b - m[k]!.d - m[k]!.s],
      ],
      montants: {1, 2, 3, 4, 5, 6, 7},
      totaux: ['TOTAL', recetteColis, recetteBillets, entrees, totalDepenses, totalSalaires, sorties, resultat],
    );
  }

  SectionRapport chiffresFinanciers() => SectionRapport(
    'Résumé financier',
    ['Poste', 'Montant'],
    [
      ['Entrées : colis', recetteColis],
      ['Entrées : billets de voyage', recetteBillets],
      ['TOTAL DES ENTRÉES', entrees],
      ['Sorties : dépenses', totalDepenses],
      ['Sorties : salaires payés', totalSalaires],
      ['TOTAL DES SORTIES', sorties],
      ['RÉSULTAT (entrées - sorties)', resultat],
    ],
    montants: {1},
  );

  final resumeFinancier = <String, String>{
    'Entrées': fcfa(entrees),
    'Dépenses': fcfa(totalDepenses),
    'Salaires': fcfa(totalSalaires),
    'Résultat': fcfa(resultat),
  };

  final resume = <String, String>{
    'Colis': '${actifs.length}',
    'Recette colis': fcfa(recetteColis),
    'Billets': '${billetsActifs.length}',
    'Recette billets': fcfa(recetteBillets),
    'Recette totale': fcfa(recetteColis + recetteBillets),
  };

  switch (type) {
    case TypeRapport.colis:
      return Rapport(type, [colisListe(colisBruts)], {
        'Colis': '${actifs.length}',
        'Recette': fcfa(recetteColis),
        'Annulés': '${colisBruts.length - actifs.length}',
      });
    case TypeRapport.caisse:
      return Rapport(type, [caisseParPersonne(), caisseParPeriode()], {
        'Colis': '${actifs.length}',
        'Billets': '${billetsActifs.length}',
        'Espèces': fcfa(actifs.where((c) => c.modePaiement != 'orange_money').fold<double>(0, (a, c) => a + c.prix) + billetsActifs.where((t) => t.modePaiement != 'orange_money').fold<double>(0, (a, t) => a + t.prix)),
        'Orange Money': fcfa(actifs.where((c) => c.modePaiement == 'orange_money').fold<double>(0, (a, c) => a + c.prix) + billetsActifs.where((t) => t.modePaiement == 'orange_money').fold<double>(0, (a, t) => a + t.prix)),
        'Total': fcfa(recetteColis + recetteBillets),
      });
    case TypeRapport.billets:
      return Rapport(type, [billetsListe(billetsBruts)], {
        'Billets': '${billetsActifs.length}',
        'Recette': fcfa(recetteBillets),
        'Annulés': '${billetsBruts.length - billetsActifs.length}',
      });
    case TypeRapport.depenses:
      return Rapport(type, [depensesParCategorie(), depensesParPeriode(), depensesDetail()], {
        'Dépenses': '${depenses.length}',
        'Montant total': fcfa(totalDepenses),
      });
    case TypeRapport.bilan:
      return Rapport(type, [chiffresFinanciers(), bilanParPeriode()], resumeFinancier);
    case TypeRapport.financier:
      return Rapport(type, [chiffresFinanciers(), bilanParPeriode(), parGare(), depensesParCategorie(), salairesPayes(), depensesDetail()], resumeFinancier);
    case TypeRapport.ventesBillets:
      return Rapport(type, [ventesBilletsPeriode()], {
        'Billets': '${billetsActifs.length}',
        'Prix total': fcfa(recetteBillets),
        'Prix moyen': fcfa(billetsActifs.isEmpty ? 0 : recetteBillets / billetsActifs.length),
      });
    case TypeRapport.billetsTrajet:
      return Rapport(type, [billetsParTrajet()], {'Billets': '${billetsActifs.length}', 'Prix total': fcfa(recetteBillets)});
    case TypeRapport.billetsHeure:
      return Rapport(type, [billetsParHeure()], {'Billets': '${billetsActifs.length}', 'Prix total': fcfa(recetteBillets)});
    case TypeRapport.caGare:
      return Rapport(type, [caParGare()], resume);
    case TypeRapport.agents:
      return Rapport(type, [parAgent()], resume);
    case TypeRapport.gares:
      return Rapport(type, [parGare()], resume);
    case TypeRapport.nonRetires:
      final l = colisBruts.where((c) => c.statut == 'arrive').toList()..sort((a, b) => a.dateEnvoi.compareTo(b.dateEnvoi));
      final auj = _jour(DateTime.now());
      return Rapport(
        type,
        [
          SectionRapport(
            'Colis arrivés, pas encore retirés',
            ['Date d\'envoi', 'N°', 'Destinataire', 'Téléphone', 'Départ', 'Arrivée', 'Description', 'Prix', 'Jours d\'attente', 'Agent'],
            [
              for (final c in l)
                [
                  _jour(c.dateEnvoi), c.numero, c.destinataireNom, c.destinataireTelephone, c.gareDepartNom ?? '',
                  c.gareArriveeNom ?? '', c.description, c.prix, auj.difference(_jour(c.dateEnvoi)).inDays, c.agentNom ?? '—',
                ],
            ],
            montants: {7},
            totaux: ['TOTAL', '${l.length} colis', '', '', '', '', '', l.fold<double>(0, (a, c) => a + c.prix), null, ''],
          ),
        ],
        {'Colis en attente': '${l.length}', 'Valeur à encaisser/livrer': fcfa(l.fold<double>(0, (a, c) => a + c.prix))},
      );
    case TypeRapport.synthese:
      return Rapport(type, [
        SectionRapport('Chiffres clés', ['Indicateur', 'Valeur'], [
          ['Colis enregistrés (hors annulés)', actifs.length],
          ['Colis annulés', colisBruts.length - actifs.length],
          ['Recette colis', recetteColis],
          ['Billets vendus (hors annulés)', billetsActifs.length],
          ['Billets annulés', billetsBruts.length - billetsActifs.length],
          ['Recette billets', recetteBillets],
          ['Recette totale', recetteColis + recetteBillets],
        ], montants: {1}),
        parJour(),
        parStatut(),
        parAgent(),
        parGare(),
      ], resume);
  }
}

// ─────────────────────────────── Excel ───────────────────────────────

/// Fichier Excel du rapport : une feuille par tableau (le tableau complet, sans limite de colonnes).
Uint8List rapportXlsx(Rapport r, FiltresRapport f) => classeurXlsx([
  for (final s in r.sections)
    FeuilleXlsx(s.titre, s.entetes, [
      ...s.lignes,
      if (s.totaux != null) s.totaux!,
    ]),
]);

// ───────────────────────────────── PDF ─────────────────────────────────

String _cellule(Object? v, bool montant) {
  if (v == null) return '';
  if (v is DateTime) return (v.hour != 0 || v.minute != 0) ? dateHeureFr(v) : dateFr(v);
  if (v is num) return (montant || v is double) ? nombre(v) : '$v';
  return '$v';
}

/// PDF du rapport (A4 paysage pour les tableaux larges).
Future<Uint8List> rapportDetailPdf({
  required CompanySettings co,
  required Profil me,
  required Rapport rapport,
  required FiltresRapport filtres,
}) async {
  final doc = pw.Document();
  final logo = pdfImage(co.logo);
  String t(String s) => pdfTexte(s);
  final large = rapport.sections.any((s) => s.entetes.length > 8);
  final format = large ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;

  doc.addPage(
    pw.MultiPage(
      pageFormat: format,
      margin: const pw.EdgeInsets.all(24),
      footer: (ctx) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(t('${co.nom} · édité par ${me.nom} le ${dateHeureFr(DateTime.now())}'), style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
          pw.Text('Page ${ctx.pageNumber} / ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
        ],
      ),
      build: (_) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (logo != null) ...[pw.Image(logo, height: 40), pw.SizedBox(width: 12)],
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(t(co.nom.toUpperCase()), style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
                  pw.Text(t(rapport.type.titre), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                  pw.Text(t(filtres.description), style: const pw.TextStyle(fontSize: 8.5)),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Wrap(
          spacing: 18,
          runSpacing: 4,
          children: [
            for (final e in rapport.resume.entries)
              pw.RichText(
                text: pw.TextSpan(
                  children: [
                    pw.TextSpan(text: t('${e.key} : '), style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                    pw.TextSpan(text: t(e.value), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ),
          ],
        ),
        for (final s in rapport.sections) ...[
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 14, bottom: 5),
            child: pw.Text(t(s.titre), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          ),
          if (s.lignes.isEmpty)
            pw.Text(t('Aucune donnée sur cette période.'), style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700))
          else
            pw.TableHelper.fromTextArray(
              headers: s.entetes.map(t).toList(),
              data: [
                for (final l in s.lignes) [for (var i = 0; i < s.entetes.length; i++) t(_cellule(i < l.length ? l[i] : null, s.montants.contains(i)))],
                if (s.totaux != null)
                  [for (var i = 0; i < s.entetes.length; i++) t(_cellule(i < s.totaux!.length ? s.totaux![i] : null, s.montants.contains(i)))],
              ],
              headerStyle: pw.TextStyle(fontSize: s.entetes.length > 12 ? 6.5 : 8, fontWeight: pw.FontWeight.bold),
              cellStyle: pw.TextStyle(fontSize: s.entetes.length > 12 ? 6.5 : 8),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2.5),
              border: pw.TableBorder.all(color: PdfColors.grey400, width: .4),
              cellAlignments: {
                for (final i in s.montants) i: pw.Alignment.centerRight,
              },
              oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
              rowDecoration: null,
            ),
        ],
      ],
    ),
  );
  return doc.save();
}
