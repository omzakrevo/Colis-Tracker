import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:vip_colis/core/imprimante.dart';
import 'package:vip_colis/core/imprimante_ble.dart';

void main() {
  test('CRC8 et trame du protocole MXW01', () {
    // Table officielle : crc8([0]) = 0 ; crc8([1]) = 0x07 ; crc8([0x64]) = 0x3B
    expect(ImprimanteBle.crc8([0]), 0);
    expect(ImprimanteBle.crc8([1]), 0x07);
    expect(ImprimanteBle.crc8([0x64]), 0x3B);
    expect(ImprimanteBle.commande(0xA1, [0]), [0x22, 0x21, 0xA1, 0x00, 0x01, 0x00, 0x00, 0x00, 0xFF]);
    // Impression de 300 lignes en noir et blanc : 2C 01 30 00
    final c = ImprimanteBle.commande(0xA9, [300 & 0xFF, 300 >> 8, 0x30, 0]);
    expect(c.sublist(0, 6), [0x22, 0x21, 0xA9, 0x00, 0x04, 0x00]);
    expect(c.sublist(6, 10), [0x2C, 0x01, 0x30, 0x00]);
    expect(c.last, 0xFF);
  });

  test('image noir et blanc → lignes de 48 octets (bit faible = point de gauche, 1 = noir)', () {
    final image = img.Image(width: 384, height: 2, numChannels: 3);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    image.setPixel(0, 0, img.ColorRgb8(0, 0, 0)); // ligne 0, point 0
    image.setPixel(9, 0, img.ColorRgb8(0, 0, 0)); // ligne 0, point 9 → octet 1, bit 1
    image.setPixel(383, 1, img.ColorRgb8(0, 0, 0)); // ligne 1, dernier point → octet 47, bit 7
    final l = ImprimanteBle.lignes(image);
    expect(l.length, 2);
    expect(l[0].length, 48);
    expect(l[0][0], 0x01);
    expect(l[0][1], 0x02);
    expect(l[1][47], 0x80);
    expect(l[1].where((b) => b != 0).length, 1);
  });

  test('la configuration BLE est mémorisée avec son protocole et sa noirceur', () {
    const c = ImprimanteConfig(type: 'ble', nom: 'MXW01', adresse: '48:0F:57:4F:97:8D', protocole: 'chat', intensite: 60, vitesse: 0);
    final r = ImprimanteConfig.fromJson(c.toJson());
    expect((r.type, r.protocole, r.intensite, r.vitesse, r.configuree), ('ble', 'chat', 60, 0, true));
    expect(c.pour(type: 'bluetooth', nom: 'X', adresse: 'Y').intensite, 60);
  });
}
