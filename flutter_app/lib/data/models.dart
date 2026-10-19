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

  Map<String, dynamic> toJson() => {
    'id': id,
    'nom': nom,
    'ville': ville,
    'adresse': adresse,
    'responsable': responsable,
    'telephone': telephone,
  };

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

  /// Barragiste : ne peut que scanner (embarquement / déchargement).
  bool get isBarragiste => role == 'barragiste';

  /// Guichet : travaille dans une gare (colis) et vend les billets de cette gare.
  bool get isGuichet => role == 'guichet';

  /// Convoyeur : vend des billets à bord et scanne les colis ; aucun accès aux données des clients.
  bool get isConvoyeur => role == 'convoyeur';

  /// Ne fait que scanner (modes embarquement / déchargement, sans consultation).
  bool get scanRestreint => isBarragiste || isConvoyeur;

  /// Peut créer des billets de transport.
  bool get peutVendreBillets => isAdmin || isGuichet || isConvoyeur;

  /// Peut consulter la liste des billets (vendeurs, administrateur et chef de gare).
  bool get voitBillets => peutVendreBillets || role == 'chef_gare';

  /// Accède aux écrans de colis (liste, saisie, recherche, rapports).
  /// Vérifie les billets à l'embarquement (facultatif).
  bool get peutVerifierBillets => isAdmin || isGuichet || isConvoyeur || role == 'chef_gare' || role == 'agent';

  bool get voitColis => !isSuper && !scanRestreint;

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
    this.valeur,
    this.agentNom,
    this.retraitNom,
    this.retraitTelephone,
    this.retraitPieceIdentite,
    this.retraitSignature,
    this.retraitDate,
    this.photo,
    this.notes,
    this.enAttente = false,
    this.clientRef,
  });

  /// Créé ou modifié hors connexion, pas encore envoyé au serveur.
  final bool enAttente;

  /// Identifiant client d'un colis créé hors ligne (sert au numéro provisoire LOC-…).
  final String? clientRef;

  final int id, gareDepartId, gareArriveeId, nombre;
  final String numero, expediteurNom, expediteurTelephone;
  final String destinataireNom, destinataireTelephone, description, statut;
  final String? gareDepartNom, gareArriveeNom, agentNom;
  final String? retraitNom, retraitTelephone, retraitPieceIdentite;
  final String? retraitSignature, photo, notes;
  final double? poids;

  /// Valeur déclarée du colis (FCFA).
  final double? valeur;
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
    valeur: j['valeur'] == null ? null : _d(j['valeur']),
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
    enAttente: j['en_attente'] as bool? ?? false,
    clientRef: j['client_ref'] as String?,
  );

  /// Mêmes clés que la base : permet de mémoriser le colis sur l'appareil puis de le relire avec `fromJson`.
  /// `light` retire la photo et la signature (lourdes) pour les listes mises en cache.
  Map<String, dynamic> toJson({bool light = false}) => {
    'id': id,
    'numero': numero,
    'expediteur_nom': expediteurNom,
    'expediteur_telephone': expediteurTelephone,
    'destinataire_nom': destinataireNom,
    'destinataire_telephone': destinataireTelephone,
    'gare_depart_id': gareDepartId,
    'gare_arrivee_id': gareArriveeId,
    'gare_depart_nom': gareDepartNom,
    'gare_arrivee_nom': gareArriveeNom,
    'description': description,
    'nombre': nombre,
    'poids': poids,
    'valeur': valeur,
    'prix': prix,
    'statut': statut,
    'date_envoi': dateEnvoi.toIso8601String(),
    'agent_nom': agentNom,
    'retrait_nom': retraitNom,
    'retrait_telephone': retraitTelephone,
    'retrait_piece_identite': retraitPieceIdentite,
    'retrait_signature': light ? null : retraitSignature,
    'retrait_date': retraitDate?.toIso8601String(),
    'photo': light ? null : photo,
    'notes': notes,
    'created_at': createdAt.toIso8601String(),
    'en_attente': enAttente,
    'client_ref': clientRef,
  };

  Colis copyWith({
    String? statut,
    String? retraitNom,
    String? retraitTelephone,
    String? retraitPieceIdentite,
    String? retraitSignature,
    DateTime? retraitDate,
    bool? enAttente,
  }) => Colis(
    id: id,
    numero: numero,
    expediteurNom: expediteurNom,
    expediteurTelephone: expediteurTelephone,
    destinataireNom: destinataireNom,
    destinataireTelephone: destinataireTelephone,
    gareDepartId: gareDepartId,
    gareArriveeId: gareArriveeId,
    gareDepartNom: gareDepartNom,
    gareArriveeNom: gareArriveeNom,
    description: description,
    nombre: nombre,
    poids: poids,
    valeur: valeur,
    prix: prix,
    statut: statut ?? this.statut,
    dateEnvoi: dateEnvoi,
    agentNom: agentNom,
    retraitNom: retraitNom ?? this.retraitNom,
    retraitTelephone: retraitTelephone ?? this.retraitTelephone,
    retraitPieceIdentite: retraitPieceIdentite ?? this.retraitPieceIdentite,
    retraitSignature: retraitSignature ?? this.retraitSignature,
    retraitDate: retraitDate ?? this.retraitDate,
    photo: photo,
    notes: notes,
    createdAt: createdAt,
    enAttente: enAttente ?? this.enAttente,
    clientRef: clientRef,
  );
}

/// Billet de transport vendu à un passager.
class Ticket {
  Ticket({
    required this.id,
    required this.numero,
    required this.clientNom,
    required this.clientTelephone,
    required this.gareDepartId,
    required this.gareArriveeId,
    required this.dateVoyage,
    required this.prix,
    required this.statut,
    required this.createdAt,
    this.gareDepartNom,
    this.gareArriveeNom,
    this.heureDepart,
    this.siege,
    this.vendeurNom,
    this.notes,
    this.clientRef,
    this.enAttente = false,
  });

  final int id, gareDepartId, gareArriveeId;
  final String numero, clientNom, clientTelephone, statut;
  final String? gareDepartNom, gareArriveeNom, heureDepart, siege, vendeurNom, notes;
  final DateTime dateVoyage, createdAt;
  final double prix;

  /// Identifiant client d'un billet créé hors ligne (numéro provisoire LOC-…).
  final String? clientRef;

  /// Créé hors connexion, pas encore envoyé au serveur.
  final bool enAttente;

  bool get annule => statut == 'annule';

  factory Ticket.fromJson(Map<String, dynamic> j) => Ticket(
    id: j['id'] as int,
    numero: j['numero'] as String,
    clientNom: j['client_nom'] as String,
    clientTelephone: j['client_telephone'] as String,
    gareDepartId: j['gare_depart_id'] as int,
    gareArriveeId: j['gare_arrivee_id'] as int,
    gareDepartNom: j['gare_depart_nom'] as String?,
    gareArriveeNom: j['gare_arrivee_nom'] as String?,
    dateVoyage: DateTime.parse(j['date_voyage'] as String),
    heureDepart: j['heure_depart'] as String?,
    siege: j['siege'] as String?,
    prix: _d(j['prix']),
    statut: (j['statut'] as String?) ?? 'emis',
    vendeurNom: j['vendeur_nom'] as String?,
    notes: j['notes'] as String?,
    createdAt: DateTime.parse(j['created_at'] as String),
    clientRef: j['client_ref'] as String?,
    enAttente: j['en_attente'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'numero': numero,
    'client_nom': clientNom,
    'client_telephone': clientTelephone,
    'gare_depart_id': gareDepartId,
    'gare_arrivee_id': gareArriveeId,
    'gare_depart_nom': gareDepartNom,
    'gare_arrivee_nom': gareArriveeNom,
    'date_voyage': dateVoyage.toIso8601String(),
    'heure_depart': heureDepart,
    'siege': siege,
    'prix': prix,
    'statut': statut,
    'vendeur_nom': vendeurNom,
    'notes': notes,
    'created_at': createdAt.toIso8601String(),
    'client_ref': clientRef,
    'en_attente': enAttente,
  };

  Ticket copyWith({String? statut, bool? enAttente}) => Ticket(
    id: id,
    numero: numero,
    clientNom: clientNom,
    clientTelephone: clientTelephone,
    gareDepartId: gareDepartId,
    gareArriveeId: gareArriveeId,
    gareDepartNom: gareDepartNom,
    gareArriveeNom: gareArriveeNom,
    dateVoyage: dateVoyage,
    heureDepart: heureDepart,
    siege: siege,
    prix: prix,
    statut: statut ?? this.statut,
    vendeurNom: vendeurNom,
    notes: notes,
    createdAt: createdAt,
    clientRef: clientRef,
    enAttente: enAttente ?? this.enAttente,
  );
}

/// Client déjà connu (retrouvé par téléphone ou par nom pendant la saisie).
class ClientSuggestion {
  ClientSuggestion({
    required this.nom,
    required this.telephone,
    this.nbColis = 0,
    this.nbTickets = 0,
    this.dernierDepartId,
    this.dernierArriveeId,
  });

  final String nom, telephone;
  final int nbColis, nbTickets;
  final int? dernierDepartId, dernierArriveeId;

  factory ClientSuggestion.fromJson(Map<String, dynamic> j) => ClientSuggestion(
    nom: j['nom'] as String,
    telephone: j['telephone'] as String,
    nbColis: (j['nb_colis'] as num?)?.toInt() ?? 0,
    nbTickets: (j['nb_tickets'] as num?)?.toInt() ?? 0,
    dernierDepartId: (j['dernier_depart_id'] as num?)?.toInt(),
    dernierArriveeId: (j['dernier_arrivee_id'] as num?)?.toInt(),
  );

  Map<String, dynamic> toJson() => {
    'nom': nom,
    'telephone': telephone,
    'nb_colis': nbColis,
    'nb_tickets': nbTickets,
    'dernier_depart_id': dernierDepartId,
    'dernier_arrivee_id': dernierArriveeId,
  };

  /// « 70 12 34 56 » (groupes de 2 chiffres).
  String get telephoneAffiche {
    final d = telephone;
    final reste = d.length.isOdd ? d.substring(0, 1) : '';
    final pairs = RegExp(r'..').allMatches(d.substring(reste.length)).map((m) => m.group(0)!).toList();
    return [if (reste.isNotEmpty) reste, ...pairs].join(' ');
  }
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'statut': statut,
    'date_changement': date.toIso8601String(),
    'notes': notes,
    'agent_nom': agentNom,
  };

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

  Map<String, dynamic> toJson() => {
    'nom': nom,
    'slogan': slogan,
    'telephone': telephone,
    'email': email,
    'adresse': adresse,
    'ville': ville,
    'pays': pays,
    'logo': logo,
  };

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

/// Version de l'application publiée par le super administrateur (mise à jour intégrée).
class AppVersion {
  AppVersion({
    required this.id,
    required this.versionName,
    required this.buildNumber,
    required this.apkUrl,
    required this.obligatoire,
    required this.actif,
    required this.createdAt,
    this.notes,
  });

  final int id, buildNumber;
  final String versionName, apkUrl;
  final String? notes;
  final bool obligatoire, actif;
  final DateTime createdAt;

  factory AppVersion.fromJson(Map<String, dynamic> j) => AppVersion(
    id: j['id'] as int,
    versionName: j['version_name'] as String,
    buildNumber: (j['build_number'] as num).toInt(),
    apkUrl: j['apk_url'] as String,
    notes: j['notes'] as String?,
    obligatoire: j['obligatoire'] as bool? ?? false,
    actif: j['actif'] as bool? ?? true,
    createdAt: DateTime.parse(j['created_at'] as String),
  );
}

/// Configuration SMS SMSBUS de l'entreprise (le mot de passe n'est jamais renvoyé par le serveur).
class SmsConfig {
  SmsConfig({
    this.actif = false,
    this.username = '',
    this.sender = '',
    this.port = 7170,
    this.indicatif = '226',
    this.colisEnvoi = true,
    this.colisArrive = true,
    this.colisRetire = true,
    this.billet = true,
    this.tplEnvoiExp = '',
    this.tplEnvoiDest = '',
    this.tplArrive = '',
    this.tplRetire = '',
    this.tplBillet = '',
  });

  final bool actif, colisEnvoi, colisArrive, colisRetire, billet;
  final String username, sender, indicatif;
  final int port;
  final String tplEnvoiExp, tplEnvoiDest, tplArrive, tplRetire, tplBillet;

  factory SmsConfig.fromJson(Map<String, dynamic> j) => SmsConfig(
    actif: j['actif'] as bool? ?? false,
    username: j['username'] as String? ?? '',
    sender: j['sender'] as String? ?? '',
    port: (j['port'] as num?)?.toInt() ?? 7170,
    indicatif: j['indicatif'] as String? ?? '226',
    colisEnvoi: j['sms_colis_envoi'] as bool? ?? true,
    colisArrive: j['sms_colis_arrive'] as bool? ?? true,
    colisRetire: j['sms_colis_retire'] as bool? ?? true,
    billet: j['sms_billet'] as bool? ?? true,
    tplEnvoiExp: j['tpl_envoi_exp'] as String? ?? '',
    tplEnvoiDest: j['tpl_envoi_dest'] as String? ?? '',
    tplArrive: j['tpl_arrive'] as String? ?? '',
    tplRetire: j['tpl_retire'] as String? ?? '',
    tplBillet: j['tpl_billet'] as String? ?? '',
  );
}

/// Une ligne du journal des SMS envoyés.
class SmsLigne {
  SmsLigne({
    required this.id,
    required this.type,
    required this.telephone,
    required this.message,
    required this.statut,
    required this.createdAt,
    this.reponse,
  });

  final int id;
  final String type, telephone, message, statut;
  final String? reponse;
  final DateTime createdAt;

  factory SmsLigne.fromJson(Map<String, dynamic> j) => SmsLigne(
    id: j['id'] as int,
    type: j['type'] as String,
    telephone: j['telephone'] as String,
    message: j['message'] as String,
    statut: j['statut'] as String,
    reponse: j['reponse'] as String?,
    createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
  );

  String get typeLabel => switch (type) {
    'envoi_exp' => 'Envoi (expéditeur)',
    'envoi_dest' => 'Envoi (destinataire)',
    'arrive' => 'Arrivée',
    'retire' => 'Retrait',
    'billet' => 'Billet',
    _ => 'Test',
  };
}

/// Trajet : prix et heures de départ fixés par l'administrateur entre deux gares.
class Trajet {
  Trajet({
    required this.id,
    required this.gareDepartId,
    required this.gareArriveeId,
    required this.prix,
    this.horaires = const [],
  });

  final int id, gareDepartId, gareArriveeId;
  final double prix;
  final List<String> horaires;

  factory Trajet.fromJson(Map<String, dynamic> j) => Trajet(
    id: j['id'] as int,
    gareDepartId: j['gare_depart_id'] as int,
    gareArriveeId: j['gare_arrivee_id'] as int,
    prix: _d(j['prix']),
    horaires: [for (final h in (j['horaires'] as List? ?? const [])) '$h'],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'gare_depart_id': gareDepartId,
    'gare_arrivee_id': gareArriveeId,
    'prix': prix,
    'horaires': horaires,
  };
}

/// Billet vu par la vérification (copie gardée sur le téléphone pour fonctionner sans internet).
class BilletVerif {
  BilletVerif({
    required this.id,
    required this.numero,
    required this.clientNom,
    required this.clientTelephone,
    required this.dateVoyage,
    required this.statut,
    this.gareDepartNom,
    this.gareArriveeNom,
    this.heureDepart,
    this.siege,
    this.nbVerifications = 0,
  });

  final int id, nbVerifications;
  final String numero, clientNom, clientTelephone, statut;
  final String? gareDepartNom, gareArriveeNom, heureDepart, siege;
  final DateTime dateVoyage;

  bool get annule => statut == 'annule';

  /// Le billet est-il pour un autre jour que `jour` ?
  bool autreJour(DateTime jour) =>
      DateTime(dateVoyage.year, dateVoyage.month, dateVoyage.day) !=
      DateTime(jour.year, jour.month, jour.day);

  BilletVerif avecVerifications(int n) => BilletVerif(
    id: id,
    numero: numero,
    clientNom: clientNom,
    clientTelephone: clientTelephone,
    dateVoyage: dateVoyage,
    statut: statut,
    gareDepartNom: gareDepartNom,
    gareArriveeNom: gareArriveeNom,
    heureDepart: heureDepart,
    siege: siege,
    nbVerifications: n,
  );

  factory BilletVerif.fromJson(Map<String, dynamic> j) => BilletVerif(
    id: (j['id'] as num).toInt(),
    numero: j['numero'] as String,
    clientNom: j['client_nom'] as String,
    clientTelephone: j['client_telephone'] as String,
    gareDepartNom: j['gare_depart_nom'] as String?,
    gareArriveeNom: j['gare_arrivee_nom'] as String?,
    dateVoyage: DateTime.parse(j['date_voyage'] as String),
    heureDepart: j['heure_depart'] as String?,
    siege: j['siege'] as String?,
    statut: (j['statut'] as String?) ?? 'emis',
    nbVerifications: (j['nb_verifications'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'numero': numero,
    'client_nom': clientNom,
    'client_telephone': clientTelephone,
    'gare_depart_nom': gareDepartNom,
    'gare_arrivee_nom': gareArriveeNom,
    'date_voyage': dateVoyage.toIso8601String(),
    'heure_depart': heureDepart,
    'siege': siege,
    'statut': statut,
    'nb_verifications': nbVerifications,
  };
}

/// Résultat d'une vérification de billet.
class VerifResultat {
  VerifResultat({this.billet, this.horsLigne = false, this.message});
  final BilletVerif? billet;

  /// Vérifié sans internet : sera enregistré au retour du réseau.
  final bool horsLigne;
  final String? message;
}
