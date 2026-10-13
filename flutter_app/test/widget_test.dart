import 'package:flutter_test/flutter_test.dart';
import 'package:vip_colis/core/format.dart';
import 'package:vip_colis/core/identifiant.dart';
import 'package:vip_colis/data/repo.dart';

void main() {
  testsIdentifiant();
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

void testsIdentifiant() {
  test('identifiant : téléphone ou nom', () {
    expect(normaliserIdentifiant('+226 70 11-22.33'), '22670112233');
    expect(normaliserIdentifiant('  Admin '), 'admin');
    expect(emailDepuisIdentifiant('+226 70 11 22 33'), '22670112233@vipcolis.app');
    expect(estTelephone('70112233'), isTrue);
    expect(estTelephone('12'), isFalse);
    expect(estErreurReseau(Exception('Failed host lookup: x')), isTrue);
    expect(estErreurReseau(Exception('autre')), isFalse);
  });
}
