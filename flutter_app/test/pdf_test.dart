import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:vip_colis/data/models.dart';
import 'package:vip_colis/screens/rapport_pdf.dart';
import 'package:vip_colis/screens/receipt.dart';
import 'package:intl/date_symbol_data_local.dart';

Colis _c(int i, String statut) => Colis(
  id: i,
  numero: 'COL-2026-00000$i',
  expediteurNom: 'Awa Traoré',
  expediteurTelephone: '70000000',
  destinataireNom: 'Issa Ouédraogo',
  destinataireTelephone: '71000000',
  gareDepartId: 1,
  gareArriveeId: 2,
  gareDepartNom: 'Ouagadougou',
  gareArriveeNom: 'Bobo-Dioulasso',
  description: 'Sac de riz',
  nombre: 2,
  prix: 15000,
  statut: statut,
  dateEnvoi: DateTime(2026, 10, 10),
  createdAt: DateTime(2026, 10, 10),
  retraitNom: statut == 'retire' ? 'Moussa' : null,
  retraitTelephone: statut == 'retire' ? '72000000' : null,
  retraitDate: statut == 'retire' ? DateTime(2026, 10, 12) : null,
);

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  final co = CompanySettings.defaults;

  test('reçu : ticket 80 mm, A4 et A5 se génèrent', () async {
    for (final f in [PdfPageFormat.roll80, PdfPageFormat.a4, PdfPageFormat.a5]) {
      final bytes = await recuPdf(_c(1, 'enregistre'), co, f);
      expect(bytes.length, greaterThan(1000), reason: '$f');
    }
  });

  test('rapport PDF avec retraits sans signature', () async {
    final me = Profil(id: 'u', nom: 'Chef', username: 'chef', role: 'chef_gare', actif: true, gareId: 1);
    final bytes = await rapportPdf(
      co: co,
      me: me,
      perimetre: 'Ouagadougou',
      debut: DateTime(2026, 10, 1),
      fin: DateTime(2026, 10, 31),
      colis: [for (var i = 0; i < 60; i++) _c(i, i.isEven ? 'retire' : 'arrive')],
      gares: [LigneStat('Ouagadougou', 60, 900000)],
      agents: [LigneStat('Agent', 60, 900000)],
    );
    expect(bytes.length, greaterThan(2000));
  });
}
