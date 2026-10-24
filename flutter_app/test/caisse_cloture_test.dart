import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:vip_colis/core/ticket_texte.dart';
import 'package:vip_colis/data/journal.dart';
import 'package:vip_colis/data/models.dart';
import 'package:vip_colis/screens/rapports_moteur.dart';

Colis _c(int i, String agent, double prix, String mode) => Colis(
  id: i, numero: 'COL-$i', expediteurNom: 'A', expediteurTelephone: '1', destinataireNom: 'B', destinataireTelephone: '2',
  gareDepartId: 1, gareArriveeId: 2, description: 'Sac', nombre: 1, prix: prix, statut: 'enregistre',
  dateEnvoi: DateTime(2026, 10, 10), createdAt: DateTime(2026, 10, 10), agentNom: agent, modePaiement: mode,
);

Ticket _t(int i, String vendeur, double prix, String mode) => Ticket(
  id: i, numero: 'TK-$i', clientNom: 'M', clientTelephone: '1', gareDepartId: 1, gareArriveeId: 2,
  dateVoyage: DateTime(2026, 10, 11), prix: prix, statut: 'emis', createdAt: DateTime(2026, 10, 10, 9), vendeurNom: vendeur, modePaiement: mode,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('fr_FR'));

  test('caisse : espèces et Orange Money par personne', () {
    final r = construireRapport(
      TypeRapport.caisse,
      [_c(1, 'Zoé', 1000, 'especes'), _c(2, 'Zoé', 2000, 'orange_money')],
      [_t(1, 'Zoé', 5000, 'orange_money'), _t(2, 'Paul', 4000, 'especes')],
    );
    final l = r.sections.first.lignes;
    expect(l.length, 2);
    // Zoé : colis 3 000 (1 000 esp. + 2 000 OM) + billet OM 5 000
    expect(l.first, ['Zoé', 2, 1000.0, 2000.0, 1, 0.0, 5000.0, 1000.0, 7000.0, 8000.0]);
    expect(r.sections.first.totaux!.last, 12000.0);
    expect(r.resume['Orange Money'], contains('7'));
  });

  test('modèle : le paiement par défaut est espèces et survit à la copie locale', () {
    final c = _c(1, 'Z', 100, 'orange_money');
    expect(Colis.fromJson(c.toJson()).modePaiement, 'orange_money');
    expect(Ticket.fromJson(_t(1, 'Z', 100, 'orange_money').toJson()).modePaiement, 'orange_money');
    expect(libelleModePaiement(null), 'Espèces');
  });

  test('rapport de fin de journée imprimable avec et sans montants', () async {
    final l = [
      JournalLigne(quand: DateTime(2026, 10, 10, 9, 5), type: 'billet', numero: 'TK-1', libelle: 'Ouaga > Bobo - Moussa', modePaiement: 'orange_money', montant: 5000),
      JournalLigne(quand: DateTime(2026, 10, 10, 10), type: 'colis_envoye', numero: 'COL-1', libelle: 'Bobo - Issa (2 colis)', modePaiement: 'especes', montant: 1500),
      JournalLigne(quand: DateTime(2026, 10, 10, 11), type: 'colis_recu', numero: 'COL-9', libelle: 'De Bobo - Awa'),
    ];
    final t = JournalTotaux(l);
    expect((t.billets, t.colisEnvoyes, t.colisRecus), (1, 1, 1));
    expect((t.especes, t.orangeMoney, t.total), (1500.0, 5000.0, 6500.0));

    final g = Generator(PaperSize.mm58, await CapabilityProfile.load());
    final co = CompanySettings.defaults;
    final avec = clotureTexte(g, 32, co, nom: 'Zoé', jour: DateTime(2026, 10, 10), lignes: l, montants: true);
    final sans = clotureTexte(g, 32, co, nom: 'Zoé', jour: DateTime(2026, 10, 10), lignes: l, montants: false);
    expect(avec.length, greaterThan(sans.length)); // les montants ajoutent des lignes
    String txt(List<int> b) => String.fromCharCodes(b.where((x) => x >= 32 && x < 127));
    expect(txt(avec), contains('ORANGE MONEY'));
    expect(txt(sans), isNot(contains('ORANGE MONEY')));
    expect(txt(sans), contains('BILLETS VENDUS'));
  });
}
