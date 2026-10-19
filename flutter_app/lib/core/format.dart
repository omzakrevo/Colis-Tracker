import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final _num = NumberFormat.decimalPattern('fr_FR');
final _date = DateFormat('dd/MM/yyyy', 'fr_FR');
final _dateTime = DateFormat('dd/MM/yyyy HH:mm', 'fr_FR');

String fcfa(num v) => '${_num.format(v.round())} FCFA';
String nombre(num v) => _num.format(v.round());
String dateFr(DateTime d) => _date.format(d.toLocal());
String dateHeureFr(DateTime d) => _dateTime.format(d.toLocal());
String dateIso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// Statuts d'un colis, avec libellé, couleur et icône.
enum Statut {
  enregistre(
    'enregistre',
    'Enregistré',
    Color(0xFF2563EB),
    Icons.edit_note_rounded,
  ),
  charge('charge', 'Chargé', Color(0xFFEA580C), Icons.inventory_2_rounded),
  enRoute(
    'en_route',
    'En route',
    Color(0xFFCA8A04),
    Icons.local_shipping_rounded,
  ),
  arrive('arrive', 'Arrivé', Color(0xFF16A34A), Icons.where_to_vote_rounded),
  retire('retire', 'Retiré', Color(0xFF475569), Icons.verified_rounded),
  annule('annule', 'Annulé', Color(0xFFDC2626), Icons.cancel_rounded);

  const Statut(this.code, this.label, this.color, this.icon);
  final String code;
  final String label;
  final Color color;
  final IconData icon;

  static Statut of(String code) =>
      Statut.values.firstWhere((s) => s.code == code, orElse: () => enregistre);

  /// Statuts accessibles depuis celui-ci.
  List<Statut> get suivants => switch (this) {
    enregistre => [charge, annule],
    charge => [enRoute, annule],
    enRoute => [arrive, annule],
    arrive => [annule],
    _ => const [],
  };
}

String roleLabel(String role) => switch (role) {
  'superadmin' => 'Super administrateur',
  'admin' => 'Administrateur',
  'chef_gare' => 'Chef de gare',
  'barragiste' => 'Barragiste',
  'guichet' => 'Guichet',
  'convoyeur' => 'Convoyeur',
  _ => 'Agent',
};
