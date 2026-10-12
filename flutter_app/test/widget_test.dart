import 'package:flutter_test/flutter_test.dart';
import 'package:vip_colis/core/format.dart';
import 'package:vip_colis/data/repo.dart';

void main() {
  test('transitions de statut', () {
    expect(Statut.enregistre.suivants, [Statut.charge, Statut.annule]);
    expect(Statut.arrive.suivants, [Statut.annule]);
    expect(Statut.retire.suivants, isEmpty);
    expect(Statut.of('en_route'), Statut.enRoute);
  });

  test('filtre colis', () {
    const f = ColisFilter();
    final g = f.copyWith(statut: 'arrive', direction: 'envoi');
    expect(g.activeCount, 2);
    expect(g.copyWith(statut: null).statut, isNull);
    expect(g.copyWith(search: 'x').statut, 'arrive');
  });

  test('format FCFA', () {
    expect(fcfa(15000).replaceAll(RegExp(r'\s'), ''), '15000FCFA');
  });
}
