import '../core/format.dart';
import 'models.dart';

/// Modèle des tickets choisi par l'administrateur (écran « Modèle des tickets ») :
/// ordre des blocs, taille du texte, alignement, traits, lignes d'informations affichées.
/// Enregistré dans `company_settings.modele_tickets` (JSON) ; vide = modèle par défaut.

/// Les trois sortes de tickets imprimés.
enum SorteTicket {
  voyage('voyage', 'Ticket de voyage'),
  colis('colis', 'Ticket colis (client)'),
  etiquette('etiquette', 'Étiquette colis');

  const SorteTicket(this.code, this.libelle);
  final String code, libelle;
}

/// Alignement d'un bloc : gauche, centre, droite.
enum Alignement { gauche, centre, droite }

/// Un bloc du ticket (logo, nom, titre…).
class BlocTicket {
  const BlocTicket(
    this.id, {
    this.visible = true,
    this.taille = 1,
    this.align = Alignement.centre,
    this.traitApres = false,
  });

  final String id;
  final bool visible;

  /// Multiplicateur de taille (0,6 à 2).
  final double taille;
  final Alignement align;

  /// Trace un trait sous le bloc.
  final bool traitApres;

  BlocTicket avec({
    bool? visible,
    double? taille,
    Alignement? align,
    bool? traitApres,
  }) => BlocTicket(
    id,
    visible: visible ?? this.visible,
    taille: taille ?? this.taille,
    align: align ?? this.align,
    traitApres: traitApres ?? this.traitApres,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'visible': visible,
    'taille': taille,
    'align': align.name,
    'trait': traitApres,
  };

  static BlocTicket? fromJson(Object? o) {
    if (o is! Map) return null;
    final id = o['id'];
    if (id is! String) return null;
    return BlocTicket(
      id,
      visible: o['visible'] as bool? ?? true,
      taille: ((o['taille'] as num?)?.toDouble() ?? 1).clamp(.6, 2.0),
      align: Alignement.values.firstWhere(
        (a) => a.name == o['align'],
        orElse: () => Alignement.centre,
      ),
      traitApres: o['trait'] as bool? ?? false,
    );
  }
}

/// Nom affiché de chaque bloc dans l'écran de réglage.
const nomsBlocs = <String, String>{
  'logo': 'Logo',
  'nom': 'Nom de l\'entreprise',
  'activite': 'Activité et slogan',
  'telephone': 'Téléphone de l\'entreprise',
  'titre': 'Titre (TICKET DE VOYAGE…)',
  'numero': 'Numéro du ticket',
  'destination': 'Destination en grand',
  'infos': 'Informations (date, gares, passager…)',
  'prix': 'Prix payé',
  'qr': 'QR code',
  'qr_numero': 'Numéro sous le QR code',
  'consigne': 'Consigne (scannez ce QR code…)',
  'merci': 'Remerciement',
  'mention': 'Mention personnalisée',
};

/// Nom affiché de chaque ligne d'informations.
const nomsChamps = <String, String>{
  'date': 'Date',
  'depart': 'Départ',
  'arrivee': 'Arrivée',
  'heure': 'Heure',
  'siege': 'Siège',
  'passager': 'Passager',
  'expediteur': 'Expéditeur',
  'destinataire': 'Destinataire',
  'colis': 'Colis',
  'valeur': 'Valeur',
  'agent': 'Agent',
  'paiement': 'Paiement',
};

/// Modèle d'une sorte de ticket.
class ModeleTicket {
  const ModeleTicket({
    required this.blocs,
    this.masques = const {},
    this.echelle = 1,
    this.espacement = 1,
    this.icones = true,
  });

  /// Blocs dans l'ordre d'impression.
  final List<BlocTicket> blocs;

  /// Lignes d'informations masquées (ids de [nomsChamps]).
  final Set<String> masques;

  /// Taille générale du texte (0,8 à 1,5).
  final double echelle;

  /// Espace entre les lignes (0,3 = très serré … 1,6 = aéré).
  final double espacement;

  /// Pictogrammes devant les lignes d'informations.
  final bool icones;

  BlocTicket? bloc(String id) {
    for (final b in blocs) {
      if (b.id == id) return b;
    }
    return null;
  }

  ModeleTicket avec({
    List<BlocTicket>? blocs,
    Set<String>? masques,
    double? echelle,
    double? espacement,
    bool? icones,
  }) => ModeleTicket(
    blocs: blocs ?? this.blocs,
    masques: masques ?? this.masques,
    echelle: echelle ?? this.echelle,
    espacement: espacement ?? this.espacement,
    icones: icones ?? this.icones,
  );

  Map<String, dynamic> toJson() => {
    'blocs': [for (final b in blocs) b.toJson()],
    'masques': masques.toList(),
    'echelle': echelle,
    'espacement': espacement,
    'icones': icones,
  };

  /// Lit un modèle enregistré ; les blocs inconnus sont ignorés, les blocs manquants ajoutés (masqués s'ils
  /// sont nouveaux, pour ne rien changer à un modèle déjà réglé).
  static ModeleTicket fromJson(SorteTicket sorte, Object? o) {
    final defaut = ModeleTicket.defaut(sorte);
    if (o is! Map) return defaut;
    final ids = defaut.blocs.map((b) => b.id).toSet();
    final lus = <BlocTicket>[];
    final vus = <String>{};
    for (final x in (o['blocs'] as List?) ?? const []) {
      final b = BlocTicket.fromJson(x);
      if (b != null && ids.contains(b.id) && vus.add(b.id)) lus.add(b);
    }
    if (lus.isEmpty) {
      lus.addAll(defaut.blocs);
    } else {
      for (final b in defaut.blocs) {
        if (!vus.contains(b.id)) lus.add(b.avec(visible: false));
      }
    }
    return ModeleTicket(
      blocs: lus,
      masques: {
        for (final m in (o['masques'] as List?) ?? const [])
          if (m is String) m,
      },
      echelle: ((o['echelle'] as num?)?.toDouble() ?? 1).clamp(.8, 1.5),
      espacement: ((o['espacement'] as num?)?.toDouble() ?? 1).clamp(.3, 1.6),
      icones: o['icones'] as bool? ?? true,
    );
  }

  /// Modèle d'origine (celui du ticket de référence).
  factory ModeleTicket.defaut(SorteTicket sorte) => switch (sorte) {
    SorteTicket.voyage || SorteTicket.colis => const ModeleTicket(
      blocs: [
        BlocTicket('logo'),
        BlocTicket('nom'),
        BlocTicket('activite'),
        BlocTicket('telephone', traitApres: true),
        BlocTicket('titre'),
        BlocTicket('numero', traitApres: true),
        BlocTicket('infos', align: Alignement.gauche, traitApres: true),
        BlocTicket('prix', align: Alignement.gauche, traitApres: true),
        BlocTicket('qr'),
        BlocTicket('qr_numero'),
        BlocTicket('consigne', traitApres: true),
        BlocTicket('merci'),
        BlocTicket('mention'),
      ],
    ),
    SorteTicket.etiquette => const ModeleTicket(
      blocs: [
        BlocTicket('logo'),
        BlocTicket('nom', traitApres: true),
        BlocTicket('destination', traitApres: true),
        BlocTicket('infos', align: Alignement.gauche, traitApres: true),
        BlocTicket('qr'),
        BlocTicket('qr_numero'),
        BlocTicket('activite', visible: false),
        BlocTicket('telephone', visible: false),
      ],
    ),
  };
}

/// Les modèles des trois sortes de tickets d'une entreprise.
class ModelesTickets {
  const ModelesTickets(this._modeles);
  final Map<SorteTicket, ModeleTicket> _modeles;

  ModeleTicket de(SorteTicket s) => _modeles[s] ?? ModeleTicket.defaut(s);

  ModelesTickets avec(SorteTicket s, ModeleTicket m) =>
      ModelesTickets({..._modeles, s: m});

  Map<String, dynamic> toJson() => {
    for (final e in _modeles.entries) e.key.code: e.value.toJson(),
  };

  static ModelesTickets fromJson(Object? o) => ModelesTickets({
    if (o is Map)
      for (final s in SorteTicket.values)
        if (o[s.code] != null) s: ModeleTicket.fromJson(s, o[s.code]),
  });
}

// ── Contenu d'un ticket (commun à l'impression image et à l'impression texte) ──

/// Pictogramme d'une ligne d'informations.
enum Picto { calendrier, lieu, horloge, siege, personne, colis }

/// Une ligne « LIBELLÉ : valeur » (avec téléphone en grand éventuel).
class ChampTicket {
  const ChampTicket(this.id, this.libelle, this.valeur, this.picto, {this.tel});
  final String id, libelle, valeur;
  final Picto picto;
  final String? tel;
}

/// Tout ce qu'un ticket peut afficher ; le modèle choisit quoi, où et en quelle taille.
class ContenuTicket {
  const ContenuTicket({
    required this.sorte,
    required this.activite,
    required this.titre,
    required this.numero,
    required this.champs,
    this.note,
    this.prix,
    this.gratuit = false,
    this.consigne = '',
    this.merci = '',
    this.destination,
    this.provenance,
  });

  final SorteTicket sorte;
  final String activite, titre, numero, consigne, merci;
  final String? note, destination, provenance;
  final List<ChampTicket> champs;

  /// Prix payé ; `null` = pas de prix sur ce ticket (étiquette).
  final double? prix;
  final bool gratuit;
}

String? _noteProvisoire(String numero) => numero.startsWith('LOC-')
    ? 'Numéro provisoire : le numéro définitif sera attribué à l\'envoi'
    : null;

ContenuTicket contenuVoyage(Ticket t) => ContenuTicket(
  sorte: SorteTicket.voyage,
  activite: 'TRANSPORT DE VOYAGEURS',
  titre: t.annule ? 'TICKET ANNULÉ' : 'TICKET DE VOYAGE',
  numero: t.numero,
  note: _noteProvisoire(t.numero),
  champs: [
    ChampTicket('date', 'DATE', dateFr(t.dateVoyage), Picto.calendrier),
    ChampTicket(
      'depart',
      'DÉPART',
      (t.gareDepartNom ?? '—').toUpperCase(),
      Picto.lieu,
    ),
    ChampTicket(
      'arrivee',
      'ARRIVÉE',
      (t.gareArriveeNom ?? '—').toUpperCase(),
      Picto.lieu,
    ),
    if ((t.heureDepart ?? '').isNotEmpty)
      ChampTicket(
        'heure',
        'HEURE',
        t.heureDepart!.replaceFirst(':', 'H'),
        Picto.horloge,
      ),
    if ((t.siege ?? '').isNotEmpty)
      ChampTicket('siege', 'SIÈGE', t.siege!, Picto.siege),
    ChampTicket(
      'passager',
      'PASSAGER',
      t.clientNom.toUpperCase(),
      Picto.personne,
    ),
    if ((t.vendeurNom ?? '').isNotEmpty)
      ChampTicket(
        'agent',
        'AGENT',
        t.vendeurNom!.toUpperCase(),
        Picto.personne,
      ),
    ChampTicket(
      'paiement',
      'PAIEMENT',
      t.gratuit
          ? 'GRATUIT (FIDÉLITÉ)'
          : libelleModePaiement(t.modePaiement).toUpperCase(),
      Picto.personne,
    ),
  ],
  prix: t.prix,
  gratuit: t.gratuit,
  consigne: 'Scannez ce QR code pour vérifier le ticket au contrôle ou à l\'embarquement.',
  merci: 'MERCI ET BON VOYAGE !',
);

ContenuTicket contenuColis(Colis c) => ContenuTicket(
  sorte: SorteTicket.colis,
  activite: 'TRANSPORT DE COLIS',
  titre: 'TICKET DE COLIS',
  numero: c.numero,
  note: _noteProvisoire(c.numero),
  champs: [
    ChampTicket('date', 'DATE', dateFr(c.dateEnvoi), Picto.calendrier),
    ChampTicket(
      'depart',
      'DÉPART',
      (c.gareDepartNom ?? '—').toUpperCase(),
      Picto.lieu,
    ),
    ChampTicket(
      'arrivee',
      'ARRIVÉE',
      (c.gareArriveeNom ?? '—').toUpperCase(),
      Picto.lieu,
    ),
    ChampTicket(
      'expediteur',
      'EXPÉDITEUR',
      c.expediteurNom.toUpperCase(),
      Picto.personne,
      tel: c.expediteurTelephone,
    ),
    ChampTicket(
      'destinataire',
      'DESTINATAIRE',
      c.destinataireNom.toUpperCase(),
      Picto.personne,
      tel: c.destinataireTelephone,
    ),
    ChampTicket(
      'colis',
      'COLIS',
      '${c.nombre} × ${c.description}${c.poids != null ? ' (${c.poids} kg)' : ''}',
      Picto.colis,
    ),
    if (c.valeur != null)
      ChampTicket(
        'valeur',
        'VALEUR',
        fcfa(c.valeur!).replaceAll('FCFA', 'F CFA'),
        Picto.colis,
      ),
    if ((c.agentNom ?? '').isNotEmpty)
      ChampTicket('agent', 'AGENT', c.agentNom!.toUpperCase(), Picto.personne),
    ChampTicket(
      'paiement',
      'PAIEMENT',
      libelleModePaiement(c.modePaiement).toUpperCase(),
      Picto.personne,
    ),
  ],
  prix: c.prix,
  consigne: 'Conservez ce ticket : il vous sera demandé pour le retrait du colis. Suivi par QR code.',
  merci: 'MERCI DE VOTRE CONFIANCE !',
);

ContenuTicket contenuEtiquette(Colis c) => ContenuTicket(
  sorte: SorteTicket.etiquette,
  activite: 'COLIS',
  titre: 'COLIS',
  numero: c.numero,
  destination: (c.gareArriveeNom ?? '—').toUpperCase(),
  provenance: 'DE : ${(c.gareDepartNom ?? '—').toUpperCase()}',
  champs: [
    ChampTicket(
      'destinataire',
      'DESTINATAIRE',
      c.destinataireNom.toUpperCase(),
      Picto.personne,
      tel: c.destinataireTelephone,
    ),
    ChampTicket(
      'expediteur',
      'EXPÉDITEUR',
      c.expediteurNom.toUpperCase(),
      Picto.personne,
      tel: c.expediteurTelephone,
    ),
    ChampTicket(
      'colis',
      'COLIS',
      '${c.nombre} × ${c.description}',
      Picto.colis,
    ),
    ChampTicket('date', 'DATE', dateFr(c.dateEnvoi), Picto.calendrier),
  ],
);

/// Données d'exemple pour l'aperçu de l'écran de réglage.
Ticket ticketExemple() => Ticket(
  id: 0,
  numero: 'BIL-2026-0001',
  clientNom: 'Ouattara Issa',
  clientTelephone: '70000000',
  gareDepartId: 1,
  gareArriveeId: 2,
  gareDepartNom: 'Gare Ouagadougou',
  gareArriveeNom: 'Gare Bobo-Dioulasso',
  dateVoyage: DateTime.now(),
  heureDepart: '07:30',
  siege: '12',
  prix: 4000,
  statut: 'emis',
  vendeurNom: 'Administrateur',
  createdAt: DateTime.now(),
);

Colis colisExemple() => Colis(
  id: 0,
  numero: 'COL-2026-0001',
  expediteurNom: 'Awa Traoré',
  expediteurTelephone: '70 12 34 56',
  destinataireNom: 'Issa Ouédraogo',
  destinataireTelephone: '76 54 32 10',
  gareDepartId: 1,
  gareArriveeId: 2,
  gareDepartNom: 'Gare Ouagadougou',
  gareArriveeNom: 'Gare Bobo-Dioulasso',
  description: 'Sac de riz',
  nombre: 2,
  prix: 3000,
  statut: 'enregistre',
  dateEnvoi: DateTime.now(),
  createdAt: DateTime.now(),
);
