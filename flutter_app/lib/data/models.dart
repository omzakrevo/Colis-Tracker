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
  });

  final String id, nom, username, role;
  final int? gareId;
  final String? telephone;
  final bool actif;

  bool get isAdmin => role == 'admin';

  factory Profil.fromJson(Map<String, dynamic> j) => Profil(
        id: j['id'] as String,
        nom: j['nom'] as String,
        username: j['username'] as String,
        role: j['role'] as String,
        gareId: j['gare_id'] as int?,
        telephone: j['telephone'] as String?,
        actif: j['actif'] as bool? ?? true,
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
        nom: 'VIP Colis',
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
