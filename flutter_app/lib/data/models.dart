double _d(dynamic v) => v == null ? 0 : (v as num).toDouble();

class Gare {
  Gare({
    required this.id,
    required this.nom,
    required this.ville,
    required this.adresse,
    this.responsable,
    this.telephone,
  });

  final int id;
  final String nom, ville, adresse;
  final String? responsable, telephone;

  factory Gare.fromJson(Map<String, dynamic> j) => Gare(
    id: j['id'] as int,
    nom: j['nom'] as String,
    ville: j['ville'] as String,
    adresse: j['adresse'] as String,
    responsable: j['responsable'] as String?,
    telephone: j['telephone'] as String?,
  );
}

class Profil {
  Profil({
    required this.id,
    required this.nom,
    required this.username,
    required this.role,
    required this.actif,
    this.gareId,
    this.telephone,
    this.companyId,
  });

  final String id, nom, username, role;
  final int? gareId, companyId;
  final String? telephone;
  final bool actif;

  /// Administrateur d'une entreprise.
  bool get isAdmin => role == 'admin';

  /// Super administrateur de la plateforme.
  bool get isSuper => role == 'superadmin';

  Map<String, dynamic> toJson() => {
    'id': id,
    'nom': nom,
    'username': username,
    'role': role,
    'gare_id': gareId,
    'telephone': telephone,
    'actif': actif,
    'company_id': companyId,
  };

  factory Profil.fromJson(Map<String, dynamic> j) => Profil(
    id: j['id'] as String,
    nom: (j['nom'] as String?) ?? '',
    username: (j['username'] as String?) ?? '',
    role: (j['role'] as String?) ?? 'agent',
    gareId: j['gare_id'] as int?,
    companyId: j['company_id'] as int?,
    telephone: j['telephone'] as String?,
    actif: j['actif'] as bool? ?? true,
  );
}

/// Entreprise cliente (SaaS) et son abonnement.
class Company {
  Company({
    required this.id,
    required this.nom,
    required this.statut,
    required this.plan,
    required this.maxUtilisateurs,
    required this.createdAt,
    this.telephone,
    this.ville,
    this.pays,
    this.abonnementFin,
    this.nbUtilisateurs,
    this.adminNom,
    this.adminIdentifiant,
    this.statutEffectif,
  });

  final int id, maxUtilisateurs;
  final String nom, statut, plan;
  final String? telephone,
      ville,
      pays,
      adminNom,
      adminIdentifiant,
      statutEffectif;
  final DateTime? abonnementFin;
  final DateTime createdAt;
  final int? nbUtilisateurs;

  /// Statut réel tenant compte de la date de fin (actif / expire / en_attente / suspendu).
  String get statutReel => statutEffectif ?? statut;

  Map<String, dynamic> toJson() => {
    'id': id,
    'nom': nom,
    'statut': statut,
    'plan': plan,
    'max_utilisateurs': maxUtilisateurs,
    'created_at': createdAt.toIso8601String(),
    'telephone': telephone,
    'ville': ville,
    'pays': pays,
    'abonnement_fin': abonnementFin == null
        ? null
        : '${abonnementFin!.year.toString().padLeft(4, '0')}-${abonnementFin!.month.toString().padLeft(2, '0')}-${abonnementFin!.day.toString().padLeft(2, '0')}',
  };

  factory Company.fromJson(Map<String, dynamic> j) => Company(
    id: j['id'] as int,
    nom: j['nom'] as String,
    statut: j['statut'] as String,
    plan: (j['plan'] as String?) ?? 'standard',
    maxUtilisateurs: (j['max_utilisateurs'] as num?)?.toInt() ?? 5,
    createdAt: DateTime.parse(j['created_at'] as String),
    telephone: j['telephone'] as String?,
    ville: j['ville'] as String?,
    pays: j['pays'] as String?,
    abonnementFin: j['abonnement_fin'] == null
        ? null
        : DateTime.parse(j['abonnement_fin'] as String),
    nbUtilisateurs: (j['nb_utilisateurs'] as num?)?.toInt(),
    adminNom: j['admin_nom'] as String?,
    adminIdentifiant: j['admin_identifiant'] as String?,
    statutEffectif: j['statut_effectif'] as String?,
  );
}

/// Réponse de la fonction SQL `ma_session` : le compte et l'abonnement sont-ils valides ?
class SessionCheck {
  SessionCheck({required this.valide, this.motif, this.profil, this.company});
  final bool valide;
  final String? motif;
  final Profil? profil;
  final Company? company;

  factory SessionCheck.fromJson(Map<String, dynamic> j) => SessionCheck(
    valide: j['valide'] as bool? ?? false,
    motif: j['motif'] as String?,
    profil: j['profil'] == null
        ? null
        : Profil.fromJson(Map<String, dynamic>.from(j['profil'] as Map)),
    company: j['entreprise'] == null
        ? null
        : Company.fromJson(Map<String, dynamic>.from(j['entreprise'] as Map)),
  );
}

class Colis {
  Colis({
    required this.id,
    required this.numero,
    required this.expediteurNom,
    required this.expediteurTelephone,
    required this.destinataireNom,
    required this.destinataireTelephone,
    required this.gareDepartId,
    required this.gareArriveeId,
    required this.description,
    required this.nombre,
    required this.prix,
    required this.statut,
    required this.dateEnvoi,
    required this.createdAt,
    this.gareDepartNom,
    this.gareArriveeNom,
    this.poids,
    this.agentNom,
    this.retraitNom,
    this.retraitTelephone,
    this.retraitPieceIdentite,
    this.retraitSignature,
    this.retraitDate,
    this.photo,
    this.notes,
  });

  final int id, gareDepartId, gareArriveeId, nombre;
  final String numero, expediteurNom, expediteurTelephone;
  final String destinataireNom, destinataireTelephone, description, statut;
  final String? gareDepartNom, gareArriveeNom, agentNom;
  final String? retraitNom, retraitTelephone, retraitPieceIdentite;
  final String? retraitSignature, photo, notes;
  final double? poids;
  final double prix;
  final DateTime dateEnvoi, createdAt;
  final DateTime? retraitDate;

  factory Colis.fromJson(Map<String, dynamic> j) => Colis(
    id: j['id'] as int,
    numero: j['numero'] as String,
    expediteurNom: j['expediteur_nom'] as String,
    expediteurTelephone: j['expediteur_telephone'] as String,
    destinataireNom: j['destinataire_nom'] as String,
    destinataireTelephone: j['destinataire_telephone'] as String,
    gareDepartId: j['gare_depart_id'] as int,
    gareArriveeId: j['gare_arrivee_id'] as int,
    gareDepartNom: j['gare_depart_nom'] as String?,
    gareArriveeNom: j['gare_arrivee_nom'] as String?,
    description: j['description'] as String,
    nombre: j['nombre'] as int,
    poids: j['poids'] == null ? null : _d(j['poids']),
    prix: _d(j['prix']),
    statut: j['statut'] as String,
    dateEnvoi: DateTime.parse(j['date_envoi'] as String),
    agentNom: j['agent_nom'] as String?,
    retraitNom: j['retrait_nom'] as String?,
    retraitTelephone: j['retrait_telephone'] as String?,
    retraitPieceIdentite: j['retrait_piece_identite'] as String?,
    retraitSignature: j['retrait_signature'] as String?,
    retraitDate: j['retrait_date'] == null
        ? null
        : DateTime.parse(j['retrait_date'] as String),
    photo: j['photo'] as String?,
    notes: j['notes'] as String?,
    createdAt: DateTime.parse(j['created_at'] as String),
  );
}

class Historique {
  Historique({
    required this.id,
    required this.statut,
    required this.date,
    this.notes,
    this.agentNom,
  });

  final int id;
  final String statut;
  final DateTime date;
  final String? notes, agentNom;

  factory Historique.fromJson(Map<String, dynamic> j) => Historique(
    id: j['id'] as int,
    statut: j['statut'] as String,
    date: DateTime.parse(j['date_changement'] as String),
    notes: j['notes'] as String?,
    agentNom: j['agent_nom'] as String?,
  );
}

class CompanySettings {
  CompanySettings({
    required this.nom,
    required this.slogan,
    required this.telephone,
    required this.email,
    required this.adresse,
    required this.ville,
    required this.pays,
    this.logo,
  });

  final String nom, slogan, telephone, email, adresse, ville, pays;
  final String? logo;

  factory CompanySettings.fromJson(Map<String, dynamic> j) => CompanySettings(
    nom: j['nom'] as String,
    slogan: j['slogan'] as String,
    telephone: j['telephone'] as String,
    email: j['email'] as String,
    adresse: j['adresse'] as String,
    ville: j['ville'] as String,
    pays: j['pays'] as String,
    logo: j['logo'] as String?,
  );

  static CompanySettings get defaults => CompanySettings(
    nom: 'Mon entreprise',
    slogan: 'Réseau de transport express — Burkina Faso',
    telephone: '',
    email: '',
    adresse: '',
    ville: '',
    pays: 'Burkina Faso',
  );
}

class DashboardStats {
  DashboardStats(this.m);
  final Map<String, dynamic> m;
  double v(String k) => _d(m[k]);
}

class JourStat {
  JourStat(this.date, this.total, this.recette);
  final DateTime date;
  final int total;
  final double recette;
}

class LigneStat {
  LigneStat(this.nom, this.total, this.recette);
  final String nom;
  final int total;
  final double recette;
}
