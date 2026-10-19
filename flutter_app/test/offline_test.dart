import 'package:flutter_test/flutter_test.dart';
import 'package:vip_colis/data/models.dart';
import 'package:vip_colis/data/offline.dart';
import 'package:vip_colis/data/repo.dart';

Colis _colis(int id, String numero, String statut, {int dep = 1, int arr = 2, String exp = 'Awa', DateTime? date}) =>
    Colis(
      id: id,
      numero: numero,
      expediteurNom: exp,
      expediteurTelephone: '70000000',
      destinataireNom: 'Issa',
      destinataireTelephone: '71000000',
      gareDepartId: dep,
      gareArriveeId: arr,
      description: 'Sac',
      nombre: 1,
      prix: 1500,
      statut: statut,
      dateEnvoi: date ?? DateTime(2026, 10, 10),
      createdAt: date ?? DateTime(2026, 10, 10),
    );

Map<String, dynamic> _donnees(String ref) => {
      'expediteur_nom': 'Awa',
      'expediteur_telephone': '70000000',
      'destinataire_nom': 'Issa',
      'destinataire_telephone': '71000000',
      'gare_depart_id': 1,
      'gare_arrivee_id': 2,
      'description': 'Sac',
      'nombre': 1,
      'prix': 1500,
      'date_envoi': '2026-10-12',
      'client_ref': ref,
      'numero_provisoire': Outbox.provisoire(ref),
    };

OutboxOp _op(String type, Map<String, dynamic> p) =>
    OutboxOp(id: Outbox.nouvelleRef(), type: type, payload: p, createdAt: DateTime(2026, 10, 12, 9));

void main() {
  test('références : format, numéro provisoire, identifiant local négatif', () {
    final ref = Outbox.nouvelleRef();
    expect(ref, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(Outbox.provisoire(ref), matches(RegExp(r'^LOC-[0-9A-F]{8}$')));
    expect(Outbox.idLocal(ref), isNegative);
    expect(Outbox.idLocal(ref), Outbox.idLocal(ref));
  });

  test('colis créé hors ligne : visible en tête de liste, en attente', () {
    final ref = Outbox.nouvelleRef();
    final liste = Outbox.appliquer(
      [_colis(1, 'COL-2026-000001', 'enregistre')],
      [_op('creer', _donnees(ref))],
      garesNoms: {1: 'Ouaga', 2: 'Bobo'},
    );
    expect(liste.length, 2);
    expect(liste.first.numero, Outbox.provisoire(ref));
    expect(liste.first.enAttente, isTrue);
    expect(liste.first.statut, 'enregistre');
    expect(liste.first.gareArriveeNom, 'Bobo');
    expect(liste.first.id, Outbox.idLocal(ref));
  });

  test('statut et retrait en attente s\'appliquent au bon colis', () {
    final base = [_colis(1, 'COL-1', 'enregistre'), _colis(2, 'COL-2', 'arrive')];
    final liste = Outbox.appliquer(base, [
      _op('statut', {'id': 1, 'statut': 'charge'}),
      _op('retirer', {'id': 2, 'nom': 'Moussa', 'telephone': '7', 'piece': null, 'signature': null}),
    ]);
    expect(liste[0].statut, 'charge');
    expect(liste[0].enAttente, isTrue);
    expect(liste[1].statut, 'retire');
    expect(liste[1].retraitNom, 'Moussa');
    expect(base[0].statut, 'enregistre', reason: 'la liste d\'origine n\'est pas modifiée');
  });

  test('opération sur un colis créé hors ligne (visé par sa référence)', () {
    final ref = Outbox.nouvelleRef();
    final liste = Outbox.appliquer(const [], [
      _op('creer', _donnees(ref)),
      _op('statut', {'ref': ref, 'statut': 'charge'}),
    ]);
    expect(liste.single.statut, 'charge');
    final h = Outbox.historiqueLocal(liste.single, const [], [
      _op('creer', _donnees(ref)),
      _op('statut', {'ref': ref, 'statut': 'charge'}),
    ]);
    expect(h.map((e) => e.statut), ['enregistre', 'charge']);
  });

  test('scan par lot : embarquement et déchargement selon le statut', () {
    final base = [
      _colis(1, 'COL-1', 'enregistre'),
      _colis(2, 'COL-2', 'charge'),
      _colis(3, 'COL-3', 'en_route'),
    ];
    var l = Outbox.appliquer(base, [_op('scan', {'mode': 'embarquement', 'numeros': ['COL-1', 'COL-2']})]);
    expect(l.map((c) => c.statut), ['charge', 'charge', 'en_route']);
    l = Outbox.appliquer(base, [_op('scan', {'mode': 'dechargement', 'numeros': ['COL-2', 'COL-3', 'COL-1']})]);
    expect(l.map((c) => c.statut), ['enregistre', 'arrive', 'arrive']);
  });

  test('filtres locaux : recherche, statut, direction, dates, tri', () {
    final tous = [
      _colis(1, 'COL-1', 'enregistre', date: DateTime(2026, 10, 1)),
      _colis(2, 'COL-2', 'arrive', dep: 2, arr: 1, exp: 'Bintou', date: DateTime(2026, 10, 5)),
      _colis(3, 'COL-3', 'arrive', date: DateTime(2026, 10, 9)),
    ];
    expect(Outbox.filtrer(tous, const ColisFilter()).map((c) => c.id), [3, 2, 1]);
    expect(Outbox.filtrer(tous, const ColisFilter(ancienFirst: true)).map((c) => c.id), [1, 2, 3]);
    expect(Outbox.filtrer(tous, const ColisFilter(statut: 'arrive')).map((c) => c.id), [3, 2]);
    expect(Outbox.filtrer(tous, const ColisFilter(search: 'bint')).map((c) => c.id), [2]);
    expect(Outbox.filtrer(tous, const ColisFilter(direction: 'envoi'), maGareId: 1).map((c) => c.id), [3, 1]);
    expect(Outbox.filtrer(tous, const ColisFilter(direction: 'reception'), maGareId: 1).map((c) => c.id), [2]);
    expect(
      Outbox.filtrer(tous, ColisFilter(debut: DateTime(2026, 10, 2), fin: DateTime(2026, 10, 5))).map((c) => c.id),
      [2],
    );
  });

  test('colis : toJson puis fromJson conserve les données', () {
    final c = _colis(7, 'COL-7', 'charge');
    final r = Colis.fromJson(c.toJson());
    expect(r.numero, 'COL-7');
    expect(r.statut, 'charge');
    expect(r.dateEnvoi, c.dateEnvoi);
    expect(r.enAttente, isFalse);
  });

  test('opération : sérialisation', () {
    final o = _op('statut', {'id': 3, 'statut': 'charge'}).avecErreur('Refusé');
    final r = OutboxOp.fromJson(o.toJson());
    expect(r.type, 'statut');
    expect(r.erreur, 'Refusé');
    expect(r.payload['id'], 3);
  });
}
