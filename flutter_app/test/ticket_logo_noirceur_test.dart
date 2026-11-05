import 'dart:convert';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:image/image.dart' as img;
import 'package:vip_colis/core/imprimante.dart';
import 'package:vip_colis/core/ticket_texte.dart';
import 'package:vip_colis/data/models.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  TestWidgetsFlutterBinding.ensureInitialized();

  test('qualité d\'impression : très noire par défaut, enregistrée, seuils croissants', () {
    const c = ImprimanteConfig();
    expect(c.noirceur, 2);
    expect(ImprimanteConfig.fromJson(c.avec(noirceur: 0).toJson()).noirceur, 0);
    expect(const ImprimanteConfig(noirceur: 0).seuil, lessThan(const ImprimanteConfig(noirceur: 2).seuil));
    expect(const ImprimanteConfig(noirceur: 0).intensiteChat, lessThan(const ImprimanteConfig(noirceur: 2).intensiteChat));
    expect(c.pour(type: 'ble', nom: 'x', adresse: 'y').noirceur, 2);
  });

  test('le logo est mis en noir et blanc à la largeur du papier', () {
    final logo = img.Image(width: 200, height: 100, numChannels: 3, backgroundColor: img.ColorRgb8(255, 255, 255));
    img.fillRect(logo, x1: 50, y1: 20, x2: 150, y2: 80, color: img.ColorRgb8(200, 0, 0));
    final url = 'data:image/png;base64,${base64Encode(img.encodePng(logo))}';
    final r = logoVersImage(url, 384, 168)!;
    expect(r.width, 288); // 75 % du papier
    expect(r.getPixel(r.width ~/ 2, r.height ~/ 2).r, 0); // rouge → noir
    expect(logoVersImage(null, 384, 168), isNull);
    expect(logoVersImage('data:image/png;base64,AAAA', 384, 168), isNull);
  });

  test('nom de l\'entreprise en grand sur le ticket texte, sur plusieurs lignes si long', () async {
    final g = Generator(PaperSize.mm58, await CapabilityProfile.load());
    final co = CompanySettings(nom: 'MyEasyTransport MyEgala', slogan: '', telephone: '', email: '', adresse: '', ville: '', pays: '');
    final b = etiquetteTexte(
      g, 32,
      Colis(
        id: 1, numero: 'C-1', expediteurNom: 'A', expediteurTelephone: '1', destinataireNom: 'B', destinataireTelephone: '2',
        gareDepartId: 1, gareArriveeId: 2, description: 'x', nombre: 1, prix: 1000, statut: 'enregistre',
        dateEnvoi: DateTime(2026, 11, 5), createdAt: DateTime(2026, 11, 5),
      ),
      co,
    );
    // GS ! 0x11 = double largeur et hauteur : le nom (coupé en deux lignes) s'imprime en grand.
    var doubles = 0;
    for (var i = 0; i < b.length - 2; i++) {
      if (b[i] == 0x1D && b[i + 1] == 0x21 && b[i + 2] == 0x11) doubles++;
    }
    expect(doubles, greaterThanOrEqualTo(2));
  });
}
