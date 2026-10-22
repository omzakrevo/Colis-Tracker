import 'package:flutter_test/flutter_test.dart';
import 'package:vip_colis/core/lettres.dart';

void main() {
  test('nombres en toutes lettres', () {
    const attendu = {
      0: 'zéro', 1: 'un', 16: 'seize', 17: 'dix-sept', 20: 'vingt', 21: 'vingt et un', 22: 'vingt-deux',
      70: 'soixante-dix', 71: 'soixante et onze', 72: 'soixante-douze', 80: 'quatre-vingts', 81: 'quatre-vingt-un',
      90: 'quatre-vingt-dix', 91: 'quatre-vingt-onze', 99: 'quatre-vingt-dix-neuf', 100: 'cent', 101: 'cent un',
      200: 'deux cents', 201: 'deux cent un', 280: 'deux cent quatre-vingts', 1000: 'mille', 1001: 'mille un',
      1100: 'mille cent', 2000: 'deux mille', 2080: 'deux mille quatre-vingts', 21000: 'vingt et un mille',
      80000: 'quatre-vingt mille', 100000: 'cent mille', 200000: 'deux cent mille', 1000000: 'un million',
      2000000: 'deux millions', 1999999: 'un million neuf cent quatre-vingt-dix-neuf mille neuf cent quatre-vingt-dix-neuf',
      350000: 'trois cent cinquante mille', 1500000: 'un million cinq cent mille', 2000000000: 'deux milliards',
    };
    attendu.forEach((n, t) => expect(enLettres(n), t, reason: '$n'));
  });

  test('montant en lettres', () {
    expect(montantEnLettres(150000), 'Cent cinquante mille francs CFA');
    expect(montantEnLettres(1), 'Un franc CFA');
    expect(montantEnLettres(75500.4), 'Soixante-quinze mille cinq cents francs CFA');
  });
}
