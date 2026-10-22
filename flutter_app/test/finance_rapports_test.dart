import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:vip_colis/data/finance_models.dart';
import 'package:vip_colis/data/models.dart';
import 'package:vip_colis/screens/rapports_moteur.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  test('bulletin proposé : indemnités et CNSS', () {
    final e = Employe(id: 4, nom: 'Awa', salaireBase: 100000, indemniteTransport: 10000);
    final b = Bulletin.pour(e, DateTime(2026, 10, 15), cnssTaux: 5.5);
    expect(b.mois, DateTime(2026, 10));
    expect(b.brut, 110000);
    expect(b.totalRetenues, 6050);
    expect(b.net, 103950);
    expect(Bulletin.pour(e, DateTime(2026, 10)).retenues, isEmpty);
  });

  test('rapports financiers : entrées, sorties, résultat', () {
    final depenses = [
      Depense(date: DateTime(2026, 10, 10), libelle: 'Gasoil', categorie: 'Carburant', montant: 30000),
      Depense(date: DateTime(2026, 10, 11), libelle: 'Loyer', categorie: 'Loyer', montant: 20000),
    ];
    final bulletins = [Bulletin(employeId: 4, mois: DateTime(2026, 10), salaireBase: 50000, statut: 'paye', datePaiement: DateTime(2026, 10, 12))];
    final r = construireRapport(TypeRapport.depenses, const [], const [], depenses: depenses);
    expect(r.sections.first.totaux!.last, 100);
    expect(r.resume['Montant total'], contains('50'));

    final b = construireRapport(TypeRapport.bilan, const [], const [], depenses: depenses, bulletins: bulletins, employes: {4: 'Awa'});
    expect(b.sections.last.totaux!.last, -100000.0); // 0 entrée - 50 000 dépenses - 50 000 salaires

    final f = construireRapport(TypeRapport.financier, const <Colis>[], const <Ticket>[],
        granularite: Granularite.mois, depenses: depenses, bulletins: bulletins, employes: {4: 'Awa'});
    expect(f.sections.length, greaterThan(4));
  });
}
