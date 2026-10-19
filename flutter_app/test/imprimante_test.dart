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
}
