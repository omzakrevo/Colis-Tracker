import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:vip_colis/core/imprimante.dart';

void main() {
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
}
