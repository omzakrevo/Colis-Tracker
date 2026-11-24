import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pdf/pdf.dart';
import 'package:vip_colis/core/ticket_texte.dart';
import 'package:vip_colis/data/modele_ticket.dart';
import 'package:vip_colis/data/models.dart';
import 'package:vip_colis/screens/receipt.dart';

String _texte(List<int> b) =>
    String.fromCharCodes(b.where((x) => x >= 32 && x < 127));

CompanySettings _co(Map<String, dynamic>? modele) => CompanySettings(
  nom: 'Majestic Transport',
  slogan: '',
  telephone: '00 00 00 00',
  email: '',
  adresse: '',
  ville: '',
  pays: '',
  mentionTicket: 'Bagages sous la responsabilite du voyageur',
  modeleTickets: modele,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('fr_FR'));

  test('modèle : aller-retour JSON et blocs manquants ajoutés masqués', () {
    final m = ModeleTicket.defaut(SorteTicket.voyage).avec(
      echelle: 1.3,
      espacement: .5,
      masques: {'agent'},
      blocs: [
        const BlocTicket('titre', taille: 1.5, align: Alignement.gauche),
        const BlocTicket('nom'),
      ],
    );
    final tous = const ModelesTickets({}).avec(SorteTicket.voyage, m);
    final relu = ModelesTickets.fromJson(tous.toJson()).de(SorteTicket.voyage);
    expect(relu.echelle, 1.3);
    expect(relu.espacement, .5);
    expect(relu.masques, {'agent'});
    expect(relu.blocs.first.id, 'titre');
    expect(relu.blocs.first.align, Alignement.gauche);
    expect(relu.blocs.first.taille, 1.5);
    // Les autres blocs reviennent, mais masqués.
    expect(relu.bloc('qr')!.visible, isFalse);
    // Modèle absent ou illisible : modèle d'origine.
    expect(
      ModelesTickets.fromJson(null).de(SorteTicket.colis).blocs.length,
      ModeleTicket.defaut(SorteTicket.colis).blocs.length,
    );
    expect(
      ModelesTickets.fromJson('n importe quoi').de(SorteTicket.voyage).echelle,
      1,
    );
  });

  test(
    'ticket texte : informations masquées absentes, ordre respecté',
    () async {
      final g = Generator(PaperSize.mm58, await CapabilityProfile.load());
      final t = ticketExemple();
      final defaut = _texte(ticketVoyageTexte(g, 32, t, _co(null)));
      expect(defaut, contains('AGENT'));
      expect(defaut, contains('Bagages sous la responsabilite'));

      final m = ModeleTicket.defaut(SorteTicket.voyage);
      final sansAgent = _co({
        'voyage': m
            .avec(
              masques: {'agent'},
              blocs: [
                m.bloc('merci')!,
                ...m.blocs.where((b) => b.id != 'merci' && b.id != 'mention'),
              ],
            )
            .toJson(),
      });
      final texte = _texte(ticketVoyageTexte(g, 32, t, sansAgent));
      expect(texte, isNot(contains('AGENT')));
      expect(
        texte.indexOf('MERCI ET BON VOYAGE'),
        lessThan(texte.indexOf('DATE')),
      );
      // Mention retirée du modèle : remise masquée à la relecture, donc non imprimée.
      expect(texte, isNot(contains('Bagages sous la responsabilite')));
      expect(logoAffiche(_co(null), SorteTicket.voyage), isTrue);
      final sansLogo = _co({
        'voyage': m
            .avec(
              blocs: [
                for (final b in m.blocs)
                  b.id == 'logo' ? b.avec(visible: false) : b,
              ],
            )
            .toJson(),
      });
      expect(logoAffiche(sansLogo, SorteTicket.voyage), isFalse);
    },
  );

  test('aperçu PDF au format rouleau pour les trois sortes', () async {
    for (final s in SorteTicket.values) {
      final bytes = await apercuModelePdf(
        s,
        ModeleTicket.defaut(s).avec(echelle: 1.4, espacement: .4),
        _co(null),
        PdfPageFormat(58 * PdfPageFormat.mm, double.infinity),
      );
      expect(bytes.length, greaterThan(1000), reason: s.code);
    }
  });
}
