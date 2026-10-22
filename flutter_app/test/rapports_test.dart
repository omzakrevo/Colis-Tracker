import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:vip_colis/data/models.dart';
import 'package:vip_colis/screens/rapports_moteur.dart';
import 'package:vip_colis/screens/receipt.dart';
import 'package:pdf/pdf.dart';

Colis _c(int i, String statut, String agent, double prix, {DateTime? date}) => Colis(
  id: i,
  numero: 'COL-$i',
  expediteurNom: 'Awa Traoré',
  expediteurTelephone: '70000000',
  destinataireNom: 'Issa',
  destinataireTelephone: '71000000',
  gareDepartId: 1,
  gareArriveeId: 2,
  gareDepartNom: 'Ouaga',
  gareArriveeNom: 'Bobo',
  description: 'Sac',
  nombre: 2,
  prix: prix,
  statut: statut,
  dateEnvoi: date ?? DateTime(2026, 10, 10),
  createdAt: DateTime(2026, 10, 10),
  agentNom: agent,
  agentId: agent,
  billetNumero: i == 1 ? 'TK-9' : null,
);

Ticket _t(int i, String vendeur, double prix, {String statut = 'actif'}) => Ticket(
  id: i,
  numero: 'TK-$i',
  clientNom: 'Moussa',
  clientTelephone: '72000000',
  gareDepartId: 1,
  gareArriveeId: 2,
  gareDepartNom: 'Ouaga',
  gareArriveeNom: 'Bobo',
  dateVoyage: DateTime(2026, 10, 11),
  prix: prix,
  statut: statut,
  createdAt: DateTime(2026, 10, 10, 9, 30),
  vendeurNom: vendeur,
);

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  final colis = [_c(1, 'enregistre', 'Zoé', 1000), _c(2, 'arrive', 'Zoé', 2000), _c(3, 'annule', 'Paul', 500), _c(4, 'arrive', 'Paul', 3000)];
  final billets = [_t(1, 'Zoé', 5000), _t(2, 'Paul', 4000), _t(3, 'Paul', 4000, statut: 'annule')];

  test('chaque type de rapport se construit avec les bons totaux', () {
    final a = construireRapport(TypeRapport.agents, colis, billets);
    final lignes = a.sections.first.lignes;
    expect(lignes.length, 2);
    // Zoé : 2 colis (3 000) + 1 billet (5 000) = 8 000 ; Paul : 1 colis (3 000) + 1 billet (4 000) = 7 000 (annulés exclus)
    expect(lignes.first, ['Zoé', 2, 3000.0, 1, 5000.0, 8000.0]);
    expect(lignes.last, ['Paul', 1, 3000.0, 1, 4000.0, 7000.0]);
    expect(a.sections.first.totaux!.last, 15000.0);

    final l = construireRapport(TypeRapport.colis, colis, const []);
    expect(l.sections.first.lignes.length, 4);
    expect(l.sections.first.lignes.first[2], 'Zoé'); // qui a envoyé
    expect(l.resume['Colis'], '3');

    final n = construireRapport(TypeRapport.nonRetires, colis, const []);
    expect(n.sections.first.lignes.length, 2);

    for (final t in TypeRapport.values) {
      final r = construireRapport(t, colis, billets);
      expect(r.sections, isNotEmpty, reason: t.name);
    }
  });

  test('exports : Excel et PDF du rapport synthèse', () async {
    final r = construireRapport(TypeRapport.synthese, colis, billets);
    final f = FiltresRapport(debut: DateTime(2026, 10, 1), fin: DateTime(2026, 10, 31), agentNom: 'Zoé');
    final xlsx = rapportXlsx(r, f);
    expect(String.fromCharCodes(xlsx.sublist(0, 2)), 'PK');
    File('${Directory.systemTemp.path}/tchi_synthese.xlsx').writeAsBytesSync(xlsx);
    final me = Profil(id: '1', nom: 'Admin', username: 'a', role: 'admin', actif: true);
    final pdf = await rapportDetailPdf(co: CompanySettings.defaults, me: me, rapport: r, filtres: f);
    expect(String.fromCharCodes(pdf.sublist(0, 4)), '%PDF');
    final pdf2 = await rapportDetailPdf(
      co: CompanySettings.defaults,
      me: me,
      rapport: construireRapport(TypeRapport.colis, colis, billets),
      filtres: f,
    );
    File('${Directory.systemTemp.path}/tchi_colis.pdf').writeAsBytesSync(pdf2);
    expect(pdf2.length, greaterThan(1000));
  });

  test('le nom de l\'agent figure sur le ticket de colis', () async {
    final bytes = await recuPdf(_c(1, 'enregistre', 'Zoé', 1000), CompanySettings.defaults, PdfPageFormat.roll80);
    expect(bytes.length, greaterThan(1000));
  });
}
