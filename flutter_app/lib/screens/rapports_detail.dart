import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../data/repo.dart';
import '../widgets/common.dart';
import 'rapports_moteur.dart';

/// Rapports détaillés : choix du type, filtres (période, agent, gare, statut), aperçu, export PDF / Excel / impression.
class RapportsDetailScreen extends ConsumerStatefulWidget {
  const RapportsDetailScreen({super.key});

  @override
  ConsumerState<RapportsDetailScreen> createState() => _RapportsDetailState();
}

class _RapportsDetailState extends ConsumerState<RapportsDetailScreen> {
  TypeRapport _type = TypeRapport.colis;
  late DateTime _debut = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _fin = DateTime.now();
  String? _agentId;
  int? _gareId;
  String? _statut;
  bool _charge = false;
  Rapport? _rapport;
  FiltresRapport? _filtres;
  String? _erreur;

  bool get _besoinColis => _type != TypeRapport.billets;
  bool get _besoinBillets =>
      _type == TypeRapport.billets || _type == TypeRapport.agents || _type == TypeRapport.gares || _type == TypeRapport.synthese;

  Future<void> _choisirDate(bool debut) async {
    final d = await showDatePicker(
      context: context,
      initialDate: debut ? _debut : _fin,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => debut ? _debut = d : _fin = d);
  }

  void _raccourci(int jours) => setState(() {
    final auj = DateTime.now();
    _fin = auj;
    _debut = DateTime(auj.year, auj.month, auj.day).subtract(Duration(days: jours));
  });

  Future<void> _generer() async {
    final profils = ref.read(profilsProvider).value ?? const <Profil>[];
    final gares = ref.read(garesProvider).value ?? const <Gare>[];
    final agent = profils.where((p) => p.id == _agentId).firstOrNull;
    final gare = gares.where((g) => g.id == _gareId).firstOrNull;
    final f = FiltresRapport(
      debut: _debut,
      fin: _fin,
      agentId: _agentId,
      agentNom: agent?.nom,
      gareId: _gareId,
      gareNom: gare?.nom,
      statut: _type == TypeRapport.colis ? _statut : null,
    );
    setState(() {
      _charge = true;
      _erreur = null;
    });
    try {
      final colis = _besoinColis
          ? await Repo.rapportColis(
              debut: f.debut,
              fin: f.fin,
              agentId: f.agentId,
              gareDepartId: f.gareId,
              statut: f.statut,
            )
          : <Colis>[];
      final billets = _besoinBillets
          ? await Repo.rapportBillets(debut: f.debut, fin: f.fin, vendeurId: f.agentId, gareDepartId: f.gareId)
          : <Ticket>[];
      if (!mounted) return;
      setState(() {
        _rapport = construireRapport(_type, colis, billets);
        _filtres = f;
      });
    } catch (e) {
      if (mounted) setState(() => _erreur = errMsg(e));
    } finally {
      if (mounted) setState(() => _charge = false);
    }
  }

  String get _nomFichier {
    final base = 'rapport-${_type.name}-${dateIso(_debut)}_${dateIso(_fin)}';
    return base;
  }

  Future<void> _pdf({required bool imprimer}) async {
    final r = _rapport, f = _filtres, me = ref.read(profilProvider).value;
    if (r == null || f == null || me == null) return;
    try {
      final co = await ref.read(settingsProvider.future);
      final bytes = await rapportDetailPdf(co: co, me: me, rapport: r, filtres: f);
      if (imprimer) {
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: _nomFichier);
      } else {
        await Printing.sharePdf(bytes: bytes, filename: '$_nomFichier.pdf');
      }
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  Future<void> _excel() async {
    final r = _rapport, f = _filtres;
    if (r == null || f == null) return;
    try {
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Enregistrer le fichier Excel',
        fileName: '$_nomFichier.xlsx',
        bytes: rapportXlsx(r, f),
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
      );
      if (saved != null && mounted) toast(context, 'Fichier Excel enregistré');
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(profilProvider).value;
    final profils = ref.watch(profilsProvider).value ?? const <Profil>[];
    final gares = ref.watch(garesProvider).value ?? const <Gare>[];
    final agents = profils.where((p) => p.role != 'superadmin').toList();
    final peutFiltrerAgent = me != null && (me.isAdmin || me.role == 'chef_gare') && agents.length > 1;

    final filtres = SectionCard(
      title: 'Choisir le rapport',
      icon: Icons.tune_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<TypeRapport>(
            initialValue: _type,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Type de rapport'),
            items: [for (final t in TypeRapport.values) DropdownMenuItem(value: t, child: Text(t.titre))],
            onChanged: (v) => setState(() {
              _type = v ?? _type;
              _rapport = null;
            }),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 12),
            child: Text(_type.description, style: const TextStyle(color: Brand.muted, fontSize: 12.5)),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: () => _choisirDate(true),
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text('Du ${dateFr(_debut)}'),
              ),
              OutlinedButton.icon(
                onPressed: () => _choisirDate(false),
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text('Au ${dateFr(_fin)}'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ActionChip(label: const Text('Aujourd\'hui'), onPressed: () => _raccourci(0)),
              ActionChip(label: const Text('7 jours'), onPressed: () => _raccourci(6)),
              ActionChip(label: const Text('30 jours'), onPressed: () => _raccourci(29)),
              ActionChip(
                label: const Text('Ce mois'),
                onPressed: () => setState(() {
                  final a = DateTime.now();
                  _debut = DateTime(a.year, a.month, 1);
                  _fin = a;
                }),
              ),
            ],
          ),
          if (_type != TypeRapport.nonRetires) ...[
            if (peutFiltrerAgent) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _agentId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Agent (qui a enregistré)'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Tous les agents')),
                  for (final a in agents) DropdownMenuItem<String?>(value: a.id, child: Text('${a.nom} · ${roleLabel(a.role)}')),
                ],
                onChanged: (v) => setState(() => _agentId = v),
              ),
            ],
            if (gares.length > 1) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: _gareId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Gare de départ'),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('Toutes les gares')),
                  for (final g in gares) DropdownMenuItem<int?>(value: g.id, child: Text(g.nom)),
                ],
                onChanged: (v) => setState(() => _gareId = v),
              ),
            ],
            if (_type == TypeRapport.colis) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _statut,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Statut du colis'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Tous les statuts')),
                  for (final s in Statut.values) DropdownMenuItem<String?>(value: s.code, child: Text(s.label)),
                ],
                onChanged: (v) => setState(() => _statut = v),
              ),
            ],
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _charge ? null : _generer,
            icon: _charge
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Icon(Icons.analytics_rounded),
            label: Text(_charge ? 'Calcul en cours…' : 'Générer le rapport'),
          ),
        ],
      ),
    );

    final r = _rapport;
    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        Row(
          children: [
            IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.arrow_back_rounded)),
            const Expanded(
              child: PageHeader('Rapports détaillés', subtitle: 'Plusieurs types de rapports, en PDF et en Excel.'),
            ),
          ],
        ),
        filtres,
        if (_erreur != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_erreur!, style: const TextStyle(color: Colors.red)),
          ),
        if (r != null) ...[
          const SizedBox(height: 14),
          SectionCard(
            title: r.type.titre,
            icon: Icons.assessment_rounded,
            accent: const Color(0xFF16A34A),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_filtres!.description, style: const TextStyle(color: Brand.muted, fontSize: 12.5)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 24,
                  runSpacing: 8,
                  children: [
                    for (final e in r.resume.entries)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.key, style: const TextStyle(color: Brand.muted, fontSize: 12)),
                          Text(e.value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _pdf(imprimer: false),
                      icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                      label: const Text('PDF'),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
                      onPressed: _excel,
                      icon: const Icon(Icons.table_chart_rounded, size: 18),
                      label: const Text('Excel'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _pdf(imprimer: true),
                      icon: const Icon(Icons.print_rounded, size: 18),
                      label: const Text('Imprimer'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          for (final s in r.sections) ...[const SizedBox(height: 14), _Apercu(s)],
        ],
      ],
    );
  }
}

class _Apercu extends StatelessWidget {
  const _Apercu(this.s);
  final SectionRapport s;

  String _c(Object? v, int i) {
    if (v == null) return '';
    if (v is DateTime) return (v.hour != 0 || v.minute != 0) ? dateHeureFr(v) : dateFr(v);
    if (v is num) return (s.montants.contains(i) || v is double) ? nombre(v) : '$v';
    return '$v';
  }

  @override
  Widget build(BuildContext context) {
    const max = 30;
    final lignes = s.lignes.take(max).toList();
    return SectionCard(
      title: '${s.titre} (${s.lignes.length})',
      icon: Icons.table_rows_rounded,
      accent: const Color(0xFF2563EB),
      child: s.lignes.isEmpty
          ? const Text('Aucune donnée sur cette période.', style: TextStyle(color: Brand.muted))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowHeight: 38,
                    dataRowMinHeight: 32,
                    dataRowMaxHeight: 40,
                    columnSpacing: 18,
                    columns: [for (final e in s.entetes) DataColumn(label: Text(e, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)))],
                    rows: [
                      for (final l in lignes)
                        DataRow(cells: [for (var i = 0; i < s.entetes.length; i++) DataCell(Text(_c(i < l.length ? l[i] : null, i), style: const TextStyle(fontSize: 12)))]),
                      if (s.totaux != null)
                        DataRow(
                          color: WidgetStatePropertyAll(Brand.orangeSoft),
                          cells: [
                            for (var i = 0; i < s.entetes.length; i++)
                              DataCell(Text(_c(i < s.totaux!.length ? s.totaux![i] : null, i), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800))),
                          ],
                        ),
                    ],
                  ),
                ),
                if (s.lignes.length > max)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Aperçu limité à $max lignes : le PDF et le fichier Excel contiennent les ${s.lignes.length} lignes.',
                      style: const TextStyle(color: Brand.muted, fontSize: 12.5),
                    ),
                  ),
              ],
            ),
    );
  }
}
