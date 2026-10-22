// Modèles du module Comptabilité (employés, dépenses, bulletins de salaire, documents).

double _n(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
DateTime? _d(Object? v) => v == null ? null : DateTime.parse('$v');
String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

const categoriesDepenses = [
  'Carburant',
  'Entretien et réparations',
  'Salaires et avances',
  'Loyer et charges',
  'Électricité, eau, internet',
  'Fournitures de bureau',
  'Péages et taxes',
  'Assurance',
  'Frais de mission',
  'Communication',
  'Impôts et taxes',
  'Autres',
];
const modesPaiement = ['Espèces', 'Virement', 'Chèque', 'Mobile money'];
const typesContrat = ['CDI', 'CDD', 'Stage', 'Journalier / saisonnier'];

class LigneMontant {
  LigneMontant(this.libelle, this.montant);
  final String libelle;
  final double montant;

  factory LigneMontant.fromJson(Map<String, dynamic> j) => LigneMontant('${j['libelle'] ?? ''}', _n(j['montant']));
  Map<String, dynamic> toJson() => {'libelle': libelle, 'montant': montant};
}

class Employe {
  Employe({
    this.id,
    this.matricule = '',
    required this.nom,
    this.poste = '',
    this.telephone = '',
    this.adresse = '',
    this.dateNaissance,
    this.pieceIdentite = '',
    this.dateEmbauche,
    this.typeContrat = 'CDI',
    this.dateFinContrat,
    this.salaireBase = 0,
    this.indemniteTransport = 0,
    this.indemniteLogement = 0,
    this.numeroCnss = '',
    this.compteBancaire = '',
    this.gareId,
    this.actif = true,
    this.notes = '',
  });

  final int? id, gareId;
  final String matricule, nom, poste, telephone, adresse, pieceIdentite, typeContrat, numeroCnss, compteBancaire, notes;
  final DateTime? dateNaissance, dateEmbauche, dateFinContrat;
  final double salaireBase, indemniteTransport, indemniteLogement;
  final bool actif;

  factory Employe.fromJson(Map<String, dynamic> j) => Employe(
    id: (j['id'] as num?)?.toInt(),
    matricule: '${j['matricule'] ?? ''}',
    nom: '${j['nom'] ?? ''}',
    poste: '${j['poste'] ?? ''}',
    telephone: '${j['telephone'] ?? ''}',
    adresse: '${j['adresse'] ?? ''}',
    dateNaissance: _d(j['date_naissance']),
    pieceIdentite: '${j['piece_identite'] ?? ''}',
    dateEmbauche: _d(j['date_embauche']),
    typeContrat: '${j['type_contrat'] ?? 'CDI'}',
    dateFinContrat: _d(j['date_fin_contrat']),
    salaireBase: _n(j['salaire_base']),
    indemniteTransport: _n(j['indemnite_transport']),
    indemniteLogement: _n(j['indemnite_logement']),
    numeroCnss: '${j['numero_cnss'] ?? ''}',
    compteBancaire: '${j['compte_bancaire'] ?? ''}',
    gareId: (j['gare_id'] as num?)?.toInt(),
    actif: j['actif'] as bool? ?? true,
    notes: '${j['notes'] ?? ''}',
  );

  Map<String, dynamic> toJson() => {
    'matricule': matricule,
    'nom': nom,
    'poste': poste,
    'telephone': telephone,
    'adresse': adresse,
    'date_naissance': dateNaissance == null ? null : _iso(dateNaissance!),
    'piece_identite': pieceIdentite,
    'date_embauche': dateEmbauche == null ? null : _iso(dateEmbauche!),
    'type_contrat': typeContrat,
    'date_fin_contrat': dateFinContrat == null ? null : _iso(dateFinContrat!),
    'salaire_base': salaireBase,
    'indemnite_transport': indemniteTransport,
    'indemnite_logement': indemniteLogement,
    'numero_cnss': numeroCnss,
    'compte_bancaire': compteBancaire,
    'gare_id': gareId,
    'actif': actif,
    'notes': notes,
  };
}

class Depense {
  Depense({
    this.id,
    required this.date,
    this.categorie = 'Autres',
    required this.libelle,
    this.beneficiaire = '',
    required this.montant,
    this.modePaiement = 'Espèces',
    this.reference = '',
    this.gareId,
    this.gareNom,
    this.notes = '',
  });

  final int? id, gareId;
  final DateTime date;
  final String categorie, libelle, beneficiaire, modePaiement, reference, notes;
  final String? gareNom;
  final double montant;

  factory Depense.fromJson(Map<String, dynamic> j) => Depense(
    id: (j['id'] as num?)?.toInt(),
    date: DateTime.parse('${j['date_depense']}'),
    categorie: '${j['categorie'] ?? 'Autres'}',
    libelle: '${j['libelle'] ?? ''}',
    beneficiaire: '${j['beneficiaire'] ?? ''}',
    montant: _n(j['montant']),
    modePaiement: '${j['mode_paiement'] ?? 'Espèces'}',
    reference: '${j['reference'] ?? ''}',
    gareId: (j['gare_id'] as num?)?.toInt(),
    notes: '${j['notes'] ?? ''}',
  );

  Map<String, dynamic> toJson() => {
    'date_depense': _iso(date),
    'categorie': categorie,
    'libelle': libelle,
    'beneficiaire': beneficiaire,
    'montant': montant,
    'mode_paiement': modePaiement,
    'reference': reference,
    'gare_id': gareId,
    'notes': notes,
  };
}

class Bulletin {
  Bulletin({
    this.id,
    required this.employeId,
    required this.mois,
    required this.salaireBase,
    this.primes = const [],
    this.retenues = const [],
    this.statut = 'brouillon',
    this.datePaiement,
    this.modePaiement = 'Espèces',
    this.notes = '',
  });

  final int? id;
  final int employeId;
  final DateTime mois; // 1er jour du mois
  final double salaireBase;
  final List<LigneMontant> primes, retenues;
  final String statut, modePaiement, notes;
  final DateTime? datePaiement;

  bool get paye => statut == 'paye';
  double get totalPrimes => primes.fold(0.0, (a, l) => a + l.montant);
  double get brut => salaireBase + totalPrimes;
  double get totalRetenues => retenues.fold(0.0, (a, l) => a + l.montant);
  double get net => (brut - totalRetenues) < 0 ? 0 : brut - totalRetenues;

  factory Bulletin.fromJson(Map<String, dynamic> j) => Bulletin(
    id: (j['id'] as num?)?.toInt(),
    employeId: (j['employe_id'] as num).toInt(),
    mois: DateTime.parse('${j['mois']}'),
    salaireBase: _n(j['salaire_base']),
    primes: [for (final l in (j['primes'] as List? ?? const [])) LigneMontant.fromJson(Map<String, dynamic>.from(l as Map))],
    retenues: [for (final l in (j['retenues'] as List? ?? const [])) LigneMontant.fromJson(Map<String, dynamic>.from(l as Map))],
    statut: '${j['statut'] ?? 'brouillon'}',
    datePaiement: _d(j['date_paiement']),
    modePaiement: '${j['mode_paiement'] ?? 'Espèces'}',
    notes: '${j['notes'] ?? ''}',
  );

  Map<String, dynamic> toJson() => {
    'employe_id': employeId,
    'mois': _iso(mois),
    'salaire_base': salaireBase,
    'primes': [for (final l in primes) l.toJson()],
    'retenues': [for (final l in retenues) l.toJson()],
    'brut': brut,
    'total_retenues': totalRetenues,
    'net': net,
    'statut': statut,
    'date_paiement': datePaiement == null ? null : _iso(datePaiement!),
    'mode_paiement': modePaiement,
    'notes': notes,
  };

  Bulletin copyWith({
    double? salaireBase,
    List<LigneMontant>? primes,
    List<LigneMontant>? retenues,
    String? statut,
    DateTime? datePaiement,
    String? modePaiement,
    String? notes,
  }) => Bulletin(
    id: id,
    employeId: employeId,
    mois: mois,
    salaireBase: salaireBase ?? this.salaireBase,
    primes: primes ?? this.primes,
    retenues: retenues ?? this.retenues,
    statut: statut ?? this.statut,
    datePaiement: datePaiement ?? this.datePaiement,
    modePaiement: modePaiement ?? this.modePaiement,
    notes: notes ?? this.notes,
  );

  /// Bulletin proposé pour un employé : salaire de base, indemnités fixes et cotisation CNSS salariale (si un taux est réglé).
  static Bulletin pour(Employe e, DateTime mois, {double cnssTaux = 0}) {
    final primes = [
      if (e.indemniteTransport > 0) LigneMontant('Indemnité de transport', e.indemniteTransport),
      if (e.indemniteLogement > 0) LigneMontant('Indemnité de logement', e.indemniteLogement),
    ];
    final brut = e.salaireBase + primes.fold(0.0, (a, l) => a + l.montant);
    final cnss = (brut * cnssTaux / 100).roundToDouble();
    return Bulletin(
      employeId: e.id!,
      mois: DateTime(mois.year, mois.month),
      salaireBase: e.salaireBase,
      primes: primes,
      retenues: [if (cnss > 0) LigneMontant('Cotisation CNSS (${cnssTaux.toString().replaceAll(RegExp(r'\.0$'), '')} %)', cnss)],
    );
  }
}

enum TypeDoc {
  decharge('decharge', 'Décharge', 'Décharges'),
  facture('facture', 'Facture', 'Factures'),
  recu('recu', 'Reçu de paiement', 'Reçus'),
  contrat('contrat', 'Contrat de travail', 'Contrats');

  const TypeDoc(this.code, this.libelle, this.pluriel);
  final String code, libelle, pluriel;

  static TypeDoc of(String c) => values.firstWhere((t) => t.code == c, orElse: () => decharge);
}

/// Document comptable enregistré ; `data` contient tous ses champs (modifiables).
class FinanceDoc {
  FinanceDoc({
    this.id,
    required this.type,
    this.numero = '',
    required this.date,
    this.titre = '',
    this.montant = 0,
    this.statut = 'emis',
    this.data = const {},
    this.employeId,
  });

  final int? id, employeId;
  final TypeDoc type;
  final String numero, titre, statut;
  final DateTime date;
  final double montant;
  final Map<String, dynamic> data;

  factory FinanceDoc.fromJson(Map<String, dynamic> j) => FinanceDoc(
    id: (j['id'] as num?)?.toInt(),
    type: TypeDoc.of('${j['type']}'),
    numero: '${j['numero'] ?? ''}',
    date: DateTime.parse('${j['date_doc']}'),
    titre: '${j['titre'] ?? ''}',
    montant: _n(j['montant']),
    statut: '${j['statut'] ?? 'emis'}',
    data: Map<String, dynamic>.from((j['data'] as Map?) ?? const {}),
    employeId: (j['employe_id'] as num?)?.toInt(),
  );

  Map<String, dynamic> toJson() => {
    'type': type.code,
    'date_doc': _iso(date),
    'titre': titre,
    'montant': montant,
    'statut': statut,
    'data': data,
    'employe_id': employeId,
  };

  String s(String cle) => '${data[cle] ?? ''}';
}

/// Une ligne de facture.
class LigneFacture {
  LigneFacture(this.designation, this.quantite, this.prixUnitaire);
  final String designation;
  final double quantite, prixUnitaire;
  double get total => quantite * prixUnitaire;

  factory LigneFacture.fromJson(Map<String, dynamic> j) => LigneFacture('${j['designation'] ?? ''}', _n(j['quantite']), _n(j['prix_unitaire']));
  Map<String, dynamic> toJson() => {'designation': designation, 'quantite': quantite, 'prix_unitaire': prixUnitaire};
}

/// Identité légale utilisée sur les documents officiels (issue des paramètres de l'entreprise).
class IdentiteLegale {
  const IdentiteLegale({
    this.ifu = '',
    this.rccm = '',
    this.regimeFiscal = '',
    this.compteBancaire = '',
    this.numeroCnss = '',
    this.representantNom = '',
    this.representantFonction = 'Directeur général',
    this.tvaTaux = 0,
    this.cnssTaux = 5.5,
  });

  final String ifu, rccm, regimeFiscal, compteBancaire, numeroCnss, representantNom, representantFonction;
  final double tvaTaux, cnssTaux;

  factory IdentiteLegale.fromJson(Map<String, dynamic> j) => IdentiteLegale(
    ifu: '${j['ifu'] ?? ''}',
    rccm: '${j['rccm'] ?? ''}',
    regimeFiscal: '${j['regime_fiscal'] ?? ''}',
    compteBancaire: '${j['compte_bancaire'] ?? ''}',
    numeroCnss: '${j['numero_cnss'] ?? ''}',
    representantNom: '${j['representant_nom'] ?? ''}',
    representantFonction: '${j['representant_fonction'] ?? 'Directeur général'}',
    tvaTaux: _n(j['tva_taux']),
    cnssTaux: j['cnss_taux'] == null ? 5.5 : _n(j['cnss_taux']),
  );
}
