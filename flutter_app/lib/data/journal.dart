/// Une ligne du rapport de fin de journée : un billet vendu, un colis enregistré ou un colis réceptionné.
class JournalLigne {
  JournalLigne({
    required this.quand,
    required this.type,
    required this.numero,
    required this.libelle,
    this.modePaiement,
    this.montant,
  });

  final DateTime quand;

  /// 'billet', 'colis_envoye' ou 'colis_recu'.
  final String type;
  final String numero, libelle;
  final String? modePaiement;
  final double? montant;

  factory JournalLigne.fromJson(Map<String, dynamic> j) => JournalLigne(
    quand: DateTime.parse('${j['quand']}').toLocal(),
    type: '${j['type']}',
    numero: '${j['numero']}',
    libelle: '${j['libelle'] ?? ''}',
    modePaiement: j['mode_paiement'] as String?,
    montant: (j['montant'] as num?)?.toDouble(),
  );

  String get typeLibelle => switch (type) {
    'billet' => 'Billet vendu',
    'colis_envoye' => 'Colis envoyé',
    _ => 'Colis reçu',
  };
  bool get encaisse => montant != null;
}

/// Totaux d'un rapport de fin de journée.
class JournalTotaux {
  JournalTotaux(List<JournalLigne> l)
    : billets = l.where((x) => x.type == 'billet').length,
      colisEnvoyes = l.where((x) => x.type == 'colis_envoye').length,
      colisRecus = l.where((x) => x.type == 'colis_recu').length,
      especes = l.where((x) => x.encaisse && x.modePaiement != 'orange_money').fold(0.0, (a, x) => a + x.montant!),
      orangeMoney = l.where((x) => x.encaisse && x.modePaiement == 'orange_money').fold(0.0, (a, x) => a + x.montant!),
      montantBillets = l.where((x) => x.type == 'billet').fold(0.0, (a, x) => a + (x.montant ?? 0)),
      montantColis = l.where((x) => x.type == 'colis_envoye').fold(0.0, (a, x) => a + (x.montant ?? 0));

  final int billets, colisEnvoyes, colisRecus;
  final double especes, orangeMoney, montantBillets, montantColis;
  double get total => especes + orangeMoney;
}
