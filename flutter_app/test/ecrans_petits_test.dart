import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:vip_colis/core/theme.dart';
import 'package:vip_colis/data/models.dart';
import 'package:vip_colis/data/providers.dart';
import 'package:vip_colis/screens/billet_form.dart';
import 'package:vip_colis/screens/colis_form.dart';

final _profil = Profil(id: 'u1', nom: 'Zoé', username: 'zoe', role: 'admin', actif: true, gareId: 1);
final _gares = [
  Gare(id: 1, nom: 'Ouaga', ville: 'Ouaga', adresse: 'a'),
  Gare(id: 2, nom: 'Bobo', ville: 'Bobo', adresse: 'b'),
];

Future<void> _ouvre(WidgetTester t, Widget ecran, {required Size taille, double clavier = 0}) async {
  t.view.devicePixelRatio = 2;
  t.view.physicalSize = Size(taille.width * 2, taille.height * 2);
  t.view.viewInsets = FakeViewPadding(bottom: clavier * 2);
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        profilProvider.overrideWithValue(AsyncData(_profil)),
        garesProvider.overrideWith((ref) async => _gares),
        trajetsProvider.overrideWith((ref) async => <Trajet>[]),
      ],
      child: MaterialApp(theme: Brand.theme(), home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: ecran))),
    ),
  );
  await t.pump(const Duration(milliseconds: 600));
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  // Écrans de terminaux POS / petits téléphones, avec et sans clavier.
  const tailles = [Size(320, 568), Size(360, 480)];
  for (final taille in tailles) {
    for (final clavier in [0.0, 260.0]) {
      testWidgets('formulaire colis sans débordement ${taille.width.toInt()}x${taille.height.toInt()} clavier=${clavier.toInt()}', (t) async {
        await _ouvre(t, const ColisFormScreen(), taille: taille, clavier: clavier);
        expect(t.takeException(), isNull);
        // Un champ est saisissable et le bouton « Continuer » reste affiché.
        expect(find.text('Continuer'), findsOneWidget);
        final champs = find.byType(TextFormField);
        expect(champs, findsWidgets);
        await t.enterText(champs.first, 'Awa');
        await t.pump();
        expect(t.takeException(), isNull);
      });

      testWidgets('formulaire billet sans débordement ${taille.width.toInt()}x${taille.height.toInt()} clavier=${clavier.toInt()}', (t) async {
        await _ouvre(t, const BilletFormScreen(), taille: taille, clavier: clavier);
        expect(t.takeException(), isNull);
        expect(find.byType(TextFormField), findsWidgets);
      });
    }
  }
}
