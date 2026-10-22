import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:vip_colis/data/finance_models.dart';
import 'package:vip_colis/data/models.dart';
import 'package:vip_colis/screens/finance_pdf.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  final co = CompanySettings(
    nom: 'Tchi Transport', slogan: 'Voyagez avec confiance', telephone: '+226 70 00 00 00', email: 'contact@tchi.bf',
    adresse: 'Avenue Kwame N\'Krumah', ville: 'Ouagadougou', pays: 'Burkina Faso',
  );
  const id = IdentiteLegale(ifu: '00012345 K', rccm: 'BF OUA 2024 B 1234', regimeFiscal: 'RSI', compteBancaire: 'BF42 0000 1234', numeroCnss: '98765', representantNom: 'Ali Ouédraogo', tvaTaux: 18);
  final dir = Directory.systemTemp.path;

  test('décharge, facture, reçu, contrat', () async {
    final dec = FinanceDoc(type: TypeDoc.decharge, numero: 'DEC-2026-0001', date: DateTime(2026, 10, 22), montant: 125000, data: {
      'beneficiaire': 'Issa Traoré', 'piece': 'CNIB B1234567', 'telephone': '70112233', 'motif': 'Avance sur salaire d\'octobre',
      'mode': 'Espèces', 'lieu': 'Ouagadougou', 'comptable': 'Zoé Compaoré', 'chef_gare': 'Paul Sawadogo', 'responsable': 'Ali Ouédraogo',
    });
    final b1 = await dechargePdf(dec, co, id);
    File('$dir/tchi_decharge.pdf').writeAsBytesSync(b1);

    final fac = FinanceDoc(type: TypeDoc.facture, numero: 'FAC-2026-0001', date: DateTime(2026, 10, 22), statut: 'payee', data: {
      'client_nom': 'Société Faso Négoce', 'client_adresse': 'Zone industrielle, Bobo-Dioulasso', 'client_tel': '76000000', 'client_ifu': '00099887 B',
      'lignes': [
        LigneFacture('Transport de 40 colis Ouaga - Bobo', 1, 200000).toJson(),
        LigneFacture('Manutention', 40, 500).toJson(),
      ],
      'tva_taux': 18, 'remise': 5000, 'mode_paiement': 'Virement', 'conditions': 'Paiement à 30 jours', 'responsable': 'Ali Ouédraogo',
    });
    final t = totauxFacture(fac);
    expect(t.ht, 220000);
    expect(t.tva, 38700); // (220 000 - 5 000) x 18 %
    expect(t.ttc, 253700);
    File('$dir/tchi_facture.pdf').writeAsBytesSync(await facturePdf(fac, co, id));

    final rec = FinanceDoc(type: TypeDoc.recu, numero: 'REC-2026-0001', date: DateTime(2026, 10, 22), montant: 253700, data: {
      'payeur': 'Société Faso Négoce', 'objet': 'Règlement facture FAC-2026-0001', 'mode': 'Virement', 'facture': 'FAC-2026-0001', 'comptable': 'Zoé Compaoré',
    });
    expect((await recuPaiementPdf(rec, co, id)).length, greaterThan(1000));

    final ctr = FinanceDoc(type: TypeDoc.contrat, numero: 'CTR-2026-0001', date: DateTime(2026, 10, 22), data: {
      'employe_nom': 'Issa Traoré', 'naissance': '12/03/1990', 'adresse': 'Secteur 15, Ouagadougou', 'piece': 'CNIB B1234567', 'telephone': '70112233',
      'poste': 'Chauffeur', 'lieu': 'Gare de Ouagadougou', 'type': 'CDD', 'date_debut': '01/11/2026', 'date_fin': '31/10/2027', 'essai_mois': '3',
      'salaire': '150000', 'avantages': 'Indemnité de transport 15 000 F', 'heures': '40', 'conges': '2,5', 'preavis': '1 mois', 'mode_paiement': 'Espèces',
    });
    final bc = await contratPdf(ctr, co, id);
    expect(bc.length, greaterThan(2000));
    File('$dir/tchi_contrat.pdf').writeAsBytesSync(bc);
  });

  test('bulletin de salaire et émargement', () async {
    final e = Employe(id: 1, matricule: 'E-001', nom: 'Issa Traoré', poste: 'Chauffeur', dateEmbauche: DateTime(2024, 3, 1), salaireBase: 150000, indemniteTransport: 15000, numeroCnss: '55512');
    final b = Bulletin.pour(e, DateTime(2026, 10, 15), cnssTaux: 5.5).copyWith(statut: 'paye', datePaiement: DateTime(2026, 10, 31));
    expect(b.brut, 165000);
    expect(b.totalRetenues, 9075);
    expect(b.net, 155925);
    File('$dir/tchi_bulletin.pdf').writeAsBytesSync(await bulletinPdf(b, e, co, id));
    final e2 = Employe(id: 2, matricule: 'E-002', nom: 'Awa Sanou', poste: 'Guichetière', salaireBase: 90000);
    final em = await emargementPdf([(e, b), (e2, Bulletin.pour(e2, DateTime(2026, 10, 1)))], DateTime(2026, 10), co, id);
    File('$dir/tchi_emargement.pdf').writeAsBytesSync(em);
    expect(em.length, greaterThan(1000));
  });
}
