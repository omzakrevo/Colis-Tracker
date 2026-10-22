import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vip_colis/core/xlsx.dart';

void main() {
  test('classeur xlsx : feuilles, nombres, dates, caractères spéciaux', () {
    final b = classeurXlsx([
      FeuilleXlsx('Colis', ['N°', 'Date', 'Prix', 'Nom'], [
        ['COL-1', DateTime(2026, 10, 21, 14, 30), 1500.5, 'A & B <x> "é"'],
        ['COL-2', DateTime(2026, 10, 22), 2000, null],
      ]),
      FeuilleXlsx('Colis', ['Agent'], [
        ['Zoé'],
      ]),
    ]);
    expect(b.length, greaterThan(500));
    expect(String.fromCharCodes(b.sublist(0, 2)), 'PK');
    File('${Directory.systemTemp.path}/tchi_test.xlsx').writeAsBytesSync(b);
  });
}
