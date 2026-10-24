import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/format.dart';
import '../core/imprimante.dart';
import '../core/theme.dart';
import '../core/ticket_texte.dart';
import '../data/journal.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../data/repo.dart';
import '../widgets/common.dart';
import 'receipt.dart' show pdfTexte;

/// Fin de journée : tout ce que la personne a vendu / enregistré / réceptionné, avec impression sur l'imprimante à tickets.
/// Chacun ne voit que son propre rapport ; l'administrateur peut choisir un employé.
class ClotureScreen extends ConsumerStatefulWidget {
  const ClotureScreen({super.key});

  @override
  ConsumerState<ClotureScreen> createState() => _ClotureState();
}

class _ClotureState extends ConsumerState<ClotureScreen> {
  DateTime _jour = DateTime.now();
  String? _agentId; // administrateur uniquement
  Future<List<JournalLigne>>? _futur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  void _charger() => setState(() => _futur = Repo.journalActivite(_jour, agentId: _agentId));

  bool _montants(Profil? me, CompanySettings? co) => (me?.isAdmin ?? false) || (co?.clotureMontants ?? false);

  String _nomPersonne(Profil? me, List<Profil> profils) {
    if (_agentId == null) return me?.nom ?? '';
    return profils.where((p) => p.id == _agentId).firstOrNull?.nom ?? '';
  }

  Future<void> _imprimer(List<JournalLigne> l, Profil? me, CompanySettings co, bool montants, List<Profil> profils) async {
    final nom = _nomPersonne(me, profils);
    try {
      final ok = await Imprimante.imprimerDirect(
        RoleImprimante.client,
        'Fin-de-journee',
        (format) => _pdf(l, co, nom, montants, format),
        texte: (g, cols) => clotureTexte(g, cols, co, nom: nom, jour: _jour, lignes: l, montants: montants),
      );
      if (!ok) {
        await Printing.layoutPdf(
          name: 'Fin-de-journee',
          format: PdfPageFormat.roll80,
          onLayout: (format) => _pdf(l, co, nom, montants, format),
        );
      }
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  Future<Uint8List> _pdf(List<JournalLigne> l, CompanySettings co, String nom, bool montants, PdfPageFormat format) async {
    final t = JournalTotaux(l);
    final doc = pw.Document();
    pw.Widget ligne(String a, String b, {bool gras = false}) => pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(pdfTexte(a), style: pw.TextStyle(fontSize: 9, fontWeight: gras ? pw.FontWeight.bold : pw.FontWeight.normal)),
        pw.Text(pdfTexte(b), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      ],
    );
    doc.addPage(
      pw.MultiPage(
        pageFormat: format.width > 300 ? format : format.copyWith(marginLeft: 6, marginRight: 6, marginTop: 8, marginBottom: 8),
        build: (c) => [
          pw.Center(child: pw.Text(pdfTexte(co.nom.toUpperCase()), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold))),
          pw.Center(child: pw.Text('RAPPORT DE FIN DE JOURNEE', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
          pw.SizedBox(height: 6),
          ligne('Agent', nom),
          ligne('Date', dateFr(_jour)),
          pw.Divider(),
          if (l.isEmpty) pw.Center(child: pw.Text('Aucune operation ce jour', style: const pw.TextStyle(fontSize: 9))),
          for (final x in l) ...[
            ligne('${_h(x.quand)}  ${x.typeLibelle} ${x.numero}', montants && x.encaisse ? fcfa(x.montant!) : ''),
            pw.Text(
              pdfTexte('   ${x.libelle}${montants && x.encaisse ? ' - ${libelleModePaiement(x.modePaiement)}' : ''}'),
              style: const pw.TextStyle(fontSize: 8),
            ),
            pw.SizedBox(height: 2),
          ],
          pw.Divider(),
          ligne('Billets vendus', '${t.billets}', gras: true),
          ligne('Colis envoyes', '${t.colisEnvoyes}', gras: true),
          ligne('Colis recus', '${t.colisRecus}', gras: true),
          if (montants) ...[
            pw.Divider(),
            ligne('Billets', fcfa(t.montantBillets)),
            ligne('Colis', fcfa(t.montantColis)),
            ligne('Especes', fcfa(t.especes)),
            ligne('Orange Money', fcfa(t.orangeMoney)),
            ligne('TOTAL', fcfa(t.total), gras: true),
          ],
          pw.SizedBox(height: 18),
          pw.Text('Signature :', style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    );
    return doc.save();
  }

  static String _h(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(profilProvider).value;
    final co = ref.watch(settingsProvider).value;
    final profils = ref.watch(profilsProvider).value ?? const <Profil>[];
    final montants = _montants(me, co);
    final employes = profils.where((p) => !p.isSuper && !p.isComptable).toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        PageHeader(
          'Fin de journée',
          subtitle: 'Tout ce que vous avez vendu, enregistré et réceptionné. Imprimez ce rapport avant de quitter votre poste.',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.event_rounded),
                label: Text(dateFr(_jour)),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _jour,
                    firstDate: DateTime(2024),
                    lastDate: DateTime.now(),
                  );
                  if (d != null) {
                    _jour = d;
                    _charger();
                  }
                },
              ),
              if (me?.isAdmin ?? false)
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _agentId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Employé', isDense: true),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Moi')),
                      for (final p in employes.where((p) => p.id != me?.id)) DropdownMenuItem(value: p.id, child: Text(p.nom)),
                    ],
                    onChanged: (v) {
                      _agentId = v;
                      _charger();
                    },
                  ),
                ),
              IconButton(tooltip: 'Actualiser', onPressed: _charger, icon: const Icon(Icons.refresh_rounded)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<JournalLigne>>(
          future: _futur,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
            }
            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Impossible de charger le rapport (internet requis, et mise à jour du serveur faite ?)\n${errMsg(snap.error!)}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              );
            }
            final l = snap.data!;
            final t = JournalTotaux(l);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _Chiffre('Billets vendus', '${t.billets}', Icons.confirmation_number_rounded, Brand.orange),
                    _Chiffre('Colis envoyés', '${t.colisEnvoyes}', Icons.outbox_rounded, const Color(0xFF2563EB)),
                    _Chiffre('Colis reçus', '${t.colisRecus}', Icons.move_to_inbox_rounded, const Color(0xFF16A34A)),
                    if (montants) ...[
                      _Chiffre('Espèces', fcfa(t.especes), Icons.payments_rounded, const Color(0xFF16A34A)),
                      _Chiffre('Orange Money', fcfa(t.orangeMoney), Icons.phone_android_rounded, const Color(0xFFEA580C)),
                      _Chiffre('Total encaissé', fcfa(t.total), Icons.account_balance_wallet_rounded, const Color(0xFF7C3AED)),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: const Icon(Icons.print_rounded),
                  label: const Text('Imprimer le rapport'),
                  onPressed: co == null ? null : () => _imprimer(l, me, co, montants, profils),
                ),
                const SizedBox(height: 16),
                SectionCard(
                  title: 'Détail de la journée (${l.length})',
                  icon: Icons.list_alt_rounded,
                  child: l.isEmpty
                      ? const Padding(padding: EdgeInsets.all(12), child: Text('Aucune opération à cette date.'))
                      : Column(
                          children: [
                            for (final x in l)
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  radius: 16,
                                  backgroundColor: switch (x.type) {
                                    'billet' => Brand.orange.withValues(alpha: .15),
                                    'colis_envoye' => const Color(0xFF2563EB).withValues(alpha: .15),
                                    _ => const Color(0xFF16A34A).withValues(alpha: .15),
                                  },
                                  child: Icon(
                                    switch (x.type) {
                                      'billet' => Icons.confirmation_number_rounded,
                                      'colis_envoye' => Icons.outbox_rounded,
                                      _ => Icons.move_to_inbox_rounded,
                                    },
                                    size: 16,
                                  ),
                                ),
                                title: Text('${_h(x.quand)} · ${x.typeLibelle} ${x.numero}', style: const TextStyle(fontWeight: FontWeight.w700)),
                                subtitle: Text(x.libelle, maxLines: 2, overflow: TextOverflow.ellipsis),
                                trailing: montants && x.encaisse
                                    ? Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(fcfa(x.montant!), style: const TextStyle(fontWeight: FontWeight.w800)),
                                          Text(libelleModePaiement(x.modePaiement), style: Theme.of(context).textTheme.labelSmall),
                                        ],
                                      )
                                    : null,
                              ),
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Chiffre extends StatelessWidget {
  const _Chiffre(this.titre, this.valeur, this.icone, this.couleur);
  final String titre, valeur;
  final IconData icone;
  final Color couleur;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 170,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icone, color: couleur),
            const SizedBox(height: 8),
            FittedBox(fit: BoxFit.scaleDown, child: Text(valeur, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
            Text(titre, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ),
  );
}
