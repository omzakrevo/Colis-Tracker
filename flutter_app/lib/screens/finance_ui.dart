
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/finance_models.dart';
import '../data/finance_repo.dart';
import '../data/providers.dart';
import '../widgets/common.dart';

// Éléments communs aux écrans de la comptabilité.

final identiteProvider = FutureProvider.autoDispose<IdentiteLegale>((ref) => FinanceRepo.identite());
final employesProvider = FutureProvider.autoDispose<List<Employe>>((ref) => FinanceRepo.employes());

/// Le module Comptabilité est-il ouvert pour l'entreprise de l'utilisateur connecté ?
bool moduleFinanceOuvert(WidgetRef ref) {
  final auth = ref.watch(authProvider).value;
  final p = auth?.profil;
  return p != null && (p.isAdmin || p.isComptable) && (auth?.company?.moduleFinance ?? false);
}

/// Ouvre la boîte d'impression, ou enregistre / partage le PDF.
Future<void> imprimerPdf(BuildContext context, Future<Uint8List> Function() construire, String nom) async {
  try {
    final bytes = await construire();
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: nom);
  } catch (e) {
    if (context.mounted) toast(context, errMsg(e), error: true);
  }
}

Future<void> partagerPdf(BuildContext context, Future<Uint8List> Function() construire, String nom) async {
  try {
    final bytes = await construire();
    await Printing.sharePdf(bytes: bytes, filename: '$nom.pdf');
  } catch (e) {
    if (context.mounted) toast(context, errMsg(e), error: true);
  }
}

/// Boutons « Imprimer » et « PDF » d'un document.
class BoutonsPdf extends StatelessWidget {
  const BoutonsPdf({super.key, required this.construire, required this.nom});
  final Future<Uint8List> Function() construire;
  final String nom;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      OutlinedButton.icon(
        onPressed: () => imprimerPdf(context, construire, nom),
        icon: const Icon(Icons.print_rounded, size: 18),
        label: const Text('Imprimer'),
      ),
      OutlinedButton.icon(
        onPressed: () => partagerPdf(context, construire, nom),
        icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
        label: const Text('PDF'),
      ),
    ],
  );
}

/// Champ date (sélecteur de calendrier).
class ChampDate extends StatelessWidget {
  const ChampDate({super.key, required this.libelle, required this.valeur, required this.onChanged, this.facultatif = false});
  final String libelle;
  final DateTime? valeur;
  final ValueChanged<DateTime?> onChanged;
  final bool facultatif;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(14),
    onTap: () async {
      final d = await showDatePicker(
        context: context,
        initialDate: valeur ?? DateTime.now(),
        firstDate: DateTime(1940),
        lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
      );
      if (d != null) onChanged(d);
    },
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: libelle,
        suffixIcon: facultatif && valeur != null
            ? IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => onChanged(null))
            : const Icon(Icons.event_rounded),
      ),
      child: Text(valeur == null ? '—' : dateFr(valeur!)),
    ),
  );
}

/// Champ texte avec un libellé (raccourci).
Widget champTexte(TextEditingController c, String libelle, {bool requis = false, TextInputType? clavier, int lignes = 1, String? aide, List<TextInputFormatter>? formats, ValueChanged<String>? onChanged}) =>
    TextFormField(
      controller: c,
      keyboardType: clavier,
      maxLines: lignes,
      inputFormatters: formats,
      onChanged: onChanged,
      textInputAction: lignes > 1 ? null : TextInputAction.next,
      decoration: InputDecoration(labelText: requis ? '$libelle *' : libelle, helperText: aide),
      validator: requis ? (v) => (v ?? '').trim().isEmpty ? 'Champ obligatoire' : null : null,
    );

Widget champMontant(TextEditingController c, String libelle, {bool requis = false, ValueChanged<String>? onChanged}) => TextFormField(
  controller: c,
  keyboardType: const TextInputType.numberWithOptions(decimal: true),
  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
  onChanged: onChanged,
  textInputAction: TextInputAction.next,
  decoration: InputDecoration(labelText: requis ? '$libelle *' : libelle, suffixText: 'F CFA'),
  validator: requis
      ? (v) {
          final n = double.tryParse((v ?? '').replaceAll(',', '.'));
          return n == null || n <= 0 ? 'Montant invalide' : null;
        }
      : null,
);

double lireMontant(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '.').replaceAll(' ', '')) ?? 0;

/// Fenêtre de saisie : plein écran sur téléphone, boîte centrée sur ordinateur. Renvoie `true` si enregistré.
Future<T?> ouvrirEditeur<T>(BuildContext context, {required String titre, required Widget Function(BuildContext) contenu, List<Widget> actions = const []}) {
  final large = MediaQuery.sizeOf(context).width >= 760;
  return showDialog<T>(
    context: context,
    useSafeArea: true,
    builder: (ctx) => Dialog(
      insetPadding: large ? const EdgeInsets.symmetric(horizontal: 80, vertical: 30) : EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(large ? 20 : 0)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 720, maxHeight: large ? 780 : double.infinity),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: Text(titre, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            actions: [...actions, IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded))],
          ),
          body: contenu(ctx),
        ),
      ),
    ),
  );
}

/// Période (début, fin) avec raccourcis, pour les listes comptables.
class SelecteurPeriode extends StatelessWidget {
  const SelecteurPeriode({super.key, required this.debut, required this.fin, required this.onChanged});
  final DateTime debut, fin;
  final void Function(DateTime debut, DateTime fin) onChanged;

  @override
  Widget build(BuildContext context) {
    Future<void> choisir(bool d) async {
      final x = await showDatePicker(context: context, initialDate: d ? debut : fin, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)));
      if (x != null) onChanged(d ? x : debut, d ? fin : x);
    }

    final auj = DateTime.now();
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(onPressed: () => choisir(true), icon: const Icon(Icons.event_rounded, size: 18), label: Text('Du ${dateFr(debut)}')),
        OutlinedButton.icon(onPressed: () => choisir(false), icon: const Icon(Icons.event_rounded, size: 18), label: Text('Au ${dateFr(fin)}')),
        ActionChip(label: const Text('Aujourd\'hui'), onPressed: () => onChanged(DateTime(auj.year, auj.month, auj.day), auj)),
        ActionChip(label: const Text('Ce mois'), onPressed: () => onChanged(DateTime(auj.year, auj.month), auj)),
        ActionChip(label: const Text('Mois dernier'), onPressed: () => onChanged(DateTime(auj.year, auj.month - 1), DateTime(auj.year, auj.month, 0))),
        ActionChip(label: const Text('Cette année'), onPressed: () => onChanged(DateTime(auj.year), auj)),
      ],
    );
  }
}

/// Tuile d'accueil d'une rubrique.
class TuileFinance extends StatelessWidget {
  const TuileFinance({super.key, required this.icone, required this.titre, required this.detail, required this.onTap, this.couleur = Brand.orange});
  final IconData icone;
  final String titre, detail;
  final VoidCallback onTap;
  final Color couleur;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 300,
    child: Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(color: couleur.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)),
                child: Icon(icone, color: couleur),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titre, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                    const SizedBox(height: 2),
                    Text(detail, style: const TextStyle(color: Brand.muted, fontSize: 12.5)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Brand.muted),
            ],
          ),
        ),
      ),
    ),
  );
}
