import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:intl/date_symbol_data_local.dart';
import 'package:vip_colis/core/imprimante.dart';
import 'package:vip_colis/core/ticket_texte.dart';
import 'package:vip_colis/data/models.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  TestWidgetsFlutterBinding.ensureInitialized();

  test('la configuration de l\'imprimante fait l\'aller-retour', () {
    const c = ImprimanteConfig(type: 'bluetooth', nom: 'MS-B58A', adresse: '66:02:BD:06:18:7B');
    final c2 = ImprimanteConfig.fromJson(c.toJson());
    expect(c2.configuree, isTrue);
    expect(c2.largeurMm, 58);
    expect(const ImprimanteConfig().configuree, isFalse);
  });

  test('une image de 384 points se convertit en ESC/POS', () async {
    final gen = Generator(PaperSize.mm58, await CapabilityProfile.load());
    final image = img.grayscale(img.Image(width: 384, height: 160, backgroundColor: img.ColorRgb8(255, 255, 255)));
    final octets = gen.imageRaster(image, align: PosAlign.left);
    expect(octets.length, greaterThan(384 ~/ 8 * 160));
  });

  test('page rendue à fond transparent : sortie blanche (et non noire), texte noir conservé', () {
    // Fond entièrement transparent (cas du rendu PDF) : tout doit rester blanc.
    final vide = img.Image(width: 40, height: 20, numChannels: 4);
    img.fill(vide, color: img.ColorRgba8(0, 0, 0, 0));
    final blanc = versNoirEtBlanc(vide);
    expect(blanc.getPixel(5, 5).r, 255);
    expect(blanc.getPixel(39, 19).r, 255);

    // Un trait noir opaque sur fond transparent : seul le trait sort noir.
    final page = img.Image(width: 40, height: 20, numChannels: 4);
    img.fill(page, color: img.ColorRgba8(0, 0, 0, 0));
    img.fillRect(page, x1: 10, y1: 5, x2: 20, y2: 8, color: img.ColorRgba8(0, 0, 0, 255));
    final r = versNoirEtBlanc(page);
    expect(r.getPixel(12, 6).r, 0);
    expect(r.getPixel(30, 15).r, 255);

    // Fond blanc opaque : blanc.
    final opaque = img.Image(width: 10, height: 10, numChannels: 4);
    img.fill(opaque, color: img.ColorRgba8(255, 255, 255, 255));
    expect(versNoirEtBlanc(opaque).getPixel(3, 3).r, 255);
  });

  test('mode colonnes : une ligne de 24 points = une commande ESC * de 1152 octets + saut de ligne', () async {
    final gen = Generator(PaperSize.mm58, await CapabilityProfile.load());
    final image = versNoirEtBlanc(img.Image(width: 384, height: 24, numChannels: 3, backgroundColor: img.ColorRgb8(255, 255, 255)));
    final octets = gen.image(image, align: PosAlign.left);
    // ESC * 33 nL nH … (déclenche l'impression de colonnes en double densité 24 points)
    final i = octets.indexOf(0x2A); // '*'
    expect(octets[i - 1], 0x1B);
    expect(octets[i + 1], 33);
    expect(octets.length, greaterThan(1152));
    expect(const ImprimanteConfig().mode, 2); // texte par défaut
    expect(ImprimanteConfig.fromJson(const ImprimanteConfig().avec(vitesse: 2).toJson()).vitesse, 2);
  });

  test('mode texte : peu d\'octets, QR natif, sans accents', () async {
    final g = Generator(PaperSize.mm58, await CapabilityProfile.load());
    final co = CompanySettings(
      nom: 'Tchi Ténéré', slogan: '', telephone: '0102', email: '', adresse: '', ville: '', pays: '',
    );
    final t = Ticket(
      id: 1, numero: 'TK-1', clientNom: 'Aïssata Koné', clientTelephone: '0707',
      gareDepartId: 1, gareArriveeId: 2, dateVoyage: DateTime(2026, 10, 21), prix: 5000,
      statut: 'actif', createdAt: DateTime(2026, 10, 21), gareDepartNom: 'Abidjan', gareArriveeNom: 'Bouaké',
    );
    final b = ticketVoyageTexte(g, 32, t, co);
    expect(b.length, lessThan(2000));
    expect(b.every((x) => x >= 0 && x <= 255), isTrue);
    // GS ( k : commande QR code
    var qr = false;
    for (var i = 0; i < b.length - 2; i++) {
      if (b[i] == 0x1D && b[i + 1] == 0x28 && b[i + 2] == 0x6B) qr = true;
    }
    expect(qr, isTrue);
    expect(sansAccents('Aïssata Koné'), 'Aissata Kone');
    expect(ImprimanteConfig.fromJson(const ImprimanteConfig().toJson()).mode, 2);
  });
}
