import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pdf/pdf.dart';
import 'package:vip_colis/data/models.dart';
import 'package:vip_colis/data/offline.dart';
import 'package:vip_colis/screens/billet_pdf.dart';

Map<String, dynamic> _billet(String ref) => {
  'client_nom': 'Awa Traoré',
  'client_telephone': '70123456',
  'gare_depart_id': 1,
  'gare_arrivee_id': 2,
  'date_voyage': '2026-10-20',
  'heure_depart': '08:00',
  'siege': '12',
  'prix': 5000,
  'client_ref': ref,
  'numero_provisoire': Outbox.provisoire(ref),
};

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  test('un billet vendu hors ligne apparaît en tête de liste, une seule fois', () {
    final ref = Outbox.nouvelleRef();
    final op = OutboxOp(
      id: Outbox.nouvelleRef(),
      type: 'ticket',
      payload: {..._billet(ref), '_vendeur_nom': 'Bobo'},
      createdAt: DateTime(2026, 10, 19, 9),
    );
    final liste = Outbox.appliquerTickets(const [], [op], garesNoms: {1: 'Ouaga', 2: 'Bobo'});
    expect(liste, hasLength(1));
    expect(liste.first.enAttente, isTrue);
    expect(liste.first.numero, startsWith('LOC-'));
    expect(liste.first.gareArriveeNom, 'Bobo');
    expect(liste.first.id, lessThan(0));
    // Déjà reçu du serveur (même client_ref) : pas de doublon.
    expect(Outbox.appliquerTickets(liste, [op]), hasLength(1));
    expect(op.libelle, startsWith('Billet LOC-'));
  });

  test('Ticket et ClientSuggestion font l\'aller-retour JSON', () {
    final t = Outbox.ticketLocal(_billet(Outbox.nouvelleRef()), garesNoms: const {});
    final t2 = Ticket.fromJson(t.toJson());
    expect(t2.numero, t.numero);
    expect(t2.prix, 5000);
    final c = ClientSuggestion.fromJson({'nom': 'Awa', 'telephone': '70123456', 'nb_colis': 2, 'nb_tickets': 1});
    expect(c.telephoneAffiche, '70 12 34 56');
  });

  test('le billet PDF se génère sur rouleau et sur A4', () async {
    final t = Outbox.ticketLocal(_billet(Outbox.nouvelleRef()), garesNoms: {1: 'Ouaga', 2: 'Bobo'});
    final roll = await billetPdf(t, CompanySettings.defaults, PdfPageFormat.roll80);
    final a4 = await billetPdf(t, CompanySettings.defaults, PdfPageFormat.a4);
    expect(roll.length, greaterThan(1000));
    expect(a4.length, greaterThan(1000));
  });
}
