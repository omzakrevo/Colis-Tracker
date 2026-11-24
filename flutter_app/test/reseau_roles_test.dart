import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vip_colis/data/reseau.dart';
import 'package:vip_colis/screens/rapports_moteur.dart';

void main() {
  test('hors ligne : les appels échouent tout de suite au lieu d\'attendre le délai', () async {
    Reseau.echec();
    expect(Reseau.horsLigne, isTrue);
    final t = Stopwatch()..start();
    await expectLater(
      Future<void>.delayed(const Duration(seconds: 30))
          .reseau(const Duration(seconds: 8)),
      throwsA(isA<TimeoutException>()),
    );
    expect(t.elapsedMilliseconds, lessThan(200));
    Reseau.succes();
    expect(Reseau.horsLigne, isFalse);
  });

  test('un appel trop lent met l\'application hors ligne, un appel réussi la remet en ligne', () async {
    await expectLater(
      Future<void>.delayed(const Duration(seconds: 5))
          .reseau(const Duration(milliseconds: 50)),
      throwsA(isA<TimeoutException>()),
    );
    expect(Reseau.horsLigne, isTrue);
    Reseau.succes();
    expect(await Future.value(7).reseau(const Duration(seconds: 1)), 7);
    expect(Reseau.horsLigne, isFalse);
  });

  test('chaque rôle ne voit que les rapports qui le concernent', () {
    final admin = typesPour('admin', finance: true);
    expect(admin, contains(TypeRapport.caisse));
    expect(admin, contains(TypeRapport.bilan));
    final compta = typesPour('comptable', finance: true);
    expect(compta, isNot(contains(TypeRapport.caisse)));
    expect(compta, contains(TypeRapport.financier));
    expect(
      typesPour('comptable', finance: false),
      isNot(contains(TypeRapport.financier)),
    );
    final chef = typesPour('chef_gare', finance: true);
    expect(chef, isNot(contains(TypeRapport.caisse)));
    expect(chef, isNot(contains(TypeRapport.bilan)));
    expect(chef, isNot(contains(TypeRapport.gares)));
    expect(typesPour('guichet', finance: true), [
      TypeRapport.colis,
      TypeRapport.billets,
      TypeRapport.ventesBillets,
    ]);
    expect(typesPour('agent', finance: true), [TypeRapport.colis]);
    expect(typesPour('barragiste', finance: true), isEmpty);
  });
}
