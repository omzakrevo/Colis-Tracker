import 'package:flutter_test/flutter_test.dart';
import 'package:vip_colis/core/format.dart';
import 'package:vip_colis/data/models.dart';

void main() {
  test('places : numérotation automatique, plein à la capacité', () {
    final p = PlacesVoyage(5, {1, 2, 4});
    expect(p.libres, 2);
    expect(p.suivante, 3); // plus petit numéro libre
    expect(p.plein, isFalse);
    final plein = PlacesVoyage(3, {1, 2, 3});
    expect(plein.plein, isTrue);
    expect(plein.suivante, isNull);
    expect(PlacesVoyage(50, {}).suivante, 1);
    expect(PlacesVoyage(50, {for (var i = 1; i <= 50; i++) i}).plein, isTrue);
  });

  test('trajet : capacité de 50 places par défaut', () {
    final t = Trajet.fromJson({'id': 1, 'gare_depart_id': 1, 'gare_arrivee_id': 2, 'prix': 5000, 'horaires': ['06:30']});
    expect(t.capacite, 50);
    expect(Trajet.fromJson({...t.toJson(), 'capacite': 70}).capacite, 70);
  });

  test('comptable : voit tout le financier, ne vend ni ne scanne', () {
    final c = Profil(id: '1', nom: 'Compta', username: 'c', role: 'comptable', actif: true);
    expect(c.isComptable, isTrue);
    expect(c.voitToutLeReseau, isTrue);
    expect(c.peutVendreBillets, isFalse);
    expect(c.peutVerifierBillets, isFalse);
    expect(c.voitColis, isFalse);
    expect(roleLabel('comptable'), contains('Comptable'));
  });
}
