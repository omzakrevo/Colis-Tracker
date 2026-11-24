import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vip_colis/core/theme.dart';
import 'package:vip_colis/data/models.dart';
import 'package:vip_colis/data/providers.dart';
import 'package:vip_colis/screens/modele_tickets.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  for (final taille in const [Size(360, 640), Size(1280, 800)]) {
    testWidgets(
      'écran Modèle des tickets sans débordement ${taille.width.toInt()} px',
      (t) async {
        SharedPreferences.setMockInitialValues({});
        t.view.devicePixelRatio = 2;
        t.view.physicalSize = Size(taille.width * 2, taille.height * 2);
        addTearDown(t.view.reset);
        await t.pumpWidget(
          ProviderScope(
            overrides: [
              settingsProvider.overrideWith(
                (ref) async => CompanySettings.defaults,
              ),
            ],
            child: MaterialApp(
              theme: Brand.theme(),
              home: const Scaffold(body: ModeleTicketsScreen()),
            ),
          ),
        );
        await t.pump(const Duration(milliseconds: 600));
        expect(find.text('Modèle des tickets'), findsOneWidget);
        // Changer de sorte de ticket : les éléments de l'étiquette apparaissent.
        await t.tap(find.text('Étiquette'));
        await t.pump(const Duration(milliseconds: 600));
        await t.scrollUntilVisible(
          find.text('Destination en grand'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Destination en grand'), findsOneWidget);
        // Masquer un élément active le bouton Enregistrer.
        final enregistrer = find.widgetWithText(FilledButton, 'Enregistrer');
        await t.scrollUntilVisible(
          enregistrer,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(t.widget<FilledButton>(enregistrer).onPressed, isNull);
        await t.tap(find.byType(Switch).last);
        await t.pump(const Duration(milliseconds: 600));
        expect(t.widget<FilledButton>(enregistrer).onPressed, isNotNull);
        expect(t.takeException(), isNull);
      },
    );
  }
}
