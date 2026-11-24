import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../core/imprimante.dart';
import '../data/modele_ticket.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../data/repo.dart';
import '../widgets/common.dart';
import 'receipt.dart';

/// Écran de l'administrateur : dessiner les tickets (ordre des éléments, taille du texte, alignement, traits,
/// lignes affichées), avec un aperçu en direct au format du rouleau.
class ModeleTicketsScreen extends ConsumerStatefulWidget {
  const ModeleTicketsScreen({super.key});

  @override
  ConsumerState<ModeleTicketsScreen> createState() =>
      _ModeleTicketsScreenState();
}

class _ModeleTicketsScreenState extends ConsumerState<ModeleTicketsScreen> {
  ModelesTickets? _modeles;
  String _initial = '';
  SorteTicket _sorte = SorteTicket.voyage;
  int _largeur = 58;
  bool _saving = false;
  Uint8List? _apercu;
  Timer? _attente;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    Imprimante.lire(RoleImprimante.client).then((c) {
      if (mounted) setState(() => _largeur = c.largeurMm >= 80 ? 80 : 58);
      _planifierApercu();
    });
  }

  @override
  void dispose() {
    _attente?.cancel();
    super.dispose();
  }

  ModeleTicket get _modele => _modeles!.de(_sorte);
  bool get _modifie => jsonEncode(_modeles!.toJson()) != _initial;

  void _changer(ModeleTicket m) {
    setState(() => _modeles = _modeles!.avec(_sorte, m));
    _planifierApercu();
  }

  void _changerBloc(int i, BlocTicket b) {
    final blocs = [..._modele.blocs];
    blocs[i] = b;
    _changer(_modele.avec(blocs: blocs));
  }

  void _deplacer(int i, int vers) {
    if (vers < 0 || vers >= _modele.blocs.length) return;
    final blocs = [..._modele.blocs];
    final b = blocs.removeAt(i);
    blocs.insert(vers, b);
    _changer(_modele.avec(blocs: blocs));
  }

  void _planifierApercu() {
    _attente?.cancel();
    _attente = Timer(const Duration(milliseconds: 350), _genererApercu);
  }

  Future<void> _genererApercu() async {
    final co = ref.read(settingsProvider).value;
    if (co == null || _modeles == null) return;
    final n = ++_generation;
    try {
      final pdf = await apercuModelePdf(
        _sorte,
        _modele,
        co,
        PdfPageFormat(_largeur * PdfPageFormat.mm, double.infinity),
      );
      Uint8List? png;
      await for (final page in Printing.raster(pdf, pages: [0], dpi: 200)) {
        png = await page.toPng();
        break;
      }
      if (mounted && n == _generation) setState(() => _apercu = png);
    } catch (_) {
      // L'aperçu n'est qu'une aide : une erreur ici ne bloque pas le réglage.
    }
  }

  Future<void> _enregistrer() async {
    setState(() => _saving = true);
    try {
      final cid = ref.read(profilProvider).value?.companyId;
      if (cid == null) throw 'Entreprise introuvable';
      await Repo.saveSettings(cid, {'modele_tickets': _modeles!.toJson()});
      _initial = jsonEncode(_modeles!.toJson());
      ref.invalidate(settingsProvider);
      if (mounted) toast(context, 'Modèle des tickets enregistré');
    } catch (e) {
      final s = '$e';
      if (mounted) {
        toast(
          context,
          s.contains('modele_tickets')
              ? 'Le serveur doit d\'abord être mis à jour (migration 33).'
              : errMsg(e),
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    return AsyncView<CompanySettings>(
      value: s,
      onRetry: () => ref.invalidate(settingsProvider),
      builder: (co) {
        if (_modeles == null) {
          _modeles = ModelesTickets.fromJson(co.modeleTickets);
          _initial = jsonEncode(_modeles!.toJson());
          _planifierApercu();
        }
        return LayoutBuilder(
          builder: (context, c) {
            final large = c.maxWidth >= 900;
            final reglages = _reglages(large);
            if (!large) return reglages;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: reglages),
                SizedBox(
                  width: 360,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(8, 16, 16, 40),
                    child: _carteApercu(),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _reglages(bool large) {
    final m = _modele;
    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        const PageHeader(
          'Modèle des tickets',
          subtitle: 'Choisissez l\'ordre, la taille et la place de chaque élément. L\'aperçu se met à jour tout seul.',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<SorteTicket>(
            segments: const [
              ButtonSegment(
                value: SorteTicket.voyage,
                label: Text('Voyage'),
                icon: Icon(Icons.directions_bus_rounded),
              ),
              ButtonSegment(
                value: SorteTicket.colis,
                label: Text('Colis'),
                icon: Icon(Icons.inventory_2_rounded),
              ),
              ButtonSegment(
                value: SorteTicket.etiquette,
                label: Text('Étiquette'),
                icon: Icon(Icons.sell_rounded),
              ),
            ],
            selected: {_sorte},
            onSelectionChanged: (v) {
              setState(() => _sorte = v.first);
              _planifierApercu();
            },
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'Ensemble du ticket',
          icon: Icons.tune_rounded,
          child: Column(
            children: [
              _curseur(
                'Taille du texte',
                m.echelle,
                .8,
                1.5,
                (v) => _changer(m.avec(echelle: v)),
              ),
              _curseur(
                'Espace entre les lignes',
                m.espacement,
                .3,
                1.6,
                (v) => _changer(m.avec(espacement: v)),
                gauche: 'Serré (ticket court)',
                droite: 'Aéré',
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Petits dessins devant les informations'),
                value: m.icones,
                onChanged: (v) => _changer(m.avec(icones: v)),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Aperçu sur papier de '),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 58, label: Text('58 mm')),
                      ButtonSegment(value: 80, label: Text('80 mm')),
                    ],
                    selected: {_largeur},
                    onSelectionChanged: (v) {
                      setState(() => _largeur = v.first);
                      _planifierApercu();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        if (!large) ...[const SizedBox(height: 14), _carteApercu()],
        const SizedBox(height: 14),
        SectionCard(
          title: 'Informations affichées',
          icon: Icons.list_alt_rounded,
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final id in _champsDe(_sorte))
                FilterChip(
                  label: Text(nomsChamps[id] ?? id),
                  selected: !m.masques.contains(id),
                  onSelected: (v) => _changer(
                    m.avec(
                      masques: v
                          ? (m.masques.toSet()..remove(id))
                          : (m.masques.toSet()..add(id)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'Éléments du ticket (de haut en bas)',
          icon: Icons.view_agenda_rounded,
          child: Column(
            children: [
              for (var i = 0; i < m.blocs.length; i++)
                _carteBloc(i, m.blocs[i]),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _saving || !_modifie ? null : _enregistrer,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_rounded),
                label: const Text('Enregistrer'),
              ),
              OutlinedButton.icon(
                onPressed: () => _changer(ModeleTicket.defaut(_sorte)),
                icon: const Icon(Icons.restart_alt_rounded),
                label: Text('Modèle d\'origine (${_sorte.libelle})'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<String> _champsDe(SorteTicket s) => switch (s) {
    SorteTicket.voyage => const [
      'date',
      'depart',
      'arrivee',
      'heure',
      'siege',
      'passager',
      'agent',
      'paiement',
    ],
    SorteTicket.colis => const [
      'date',
      'depart',
      'arrivee',
      'expediteur',
      'destinataire',
      'colis',
      'valeur',
      'agent',
      'paiement',
    ],
    SorteTicket.etiquette => const [
      'destinataire',
      'expediteur',
      'colis',
      'date',
    ],
  };

  Widget _curseur(
    String titre,
    double valeur,
    double min,
    double max,
    ValueChanged<double> change, {
    String? gauche,
    String? droite,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$titre : ${(valeur * 100).round()} %'),
      Slider(
        value: valeur.clamp(min, max),
        min: min,
        max: max,
        divisions: ((max - min) * 20).round(),
        onChanged: change,
      ),
      if (gauche != null || droite != null)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(gauche ?? '', style: const TextStyle(fontSize: 12)),
            Text(droite ?? '', style: const TextStyle(fontSize: 12)),
          ],
        ),
    ],
  );

  Widget _carteBloc(int i, BlocTicket b) {
    final n = _modele.blocs.length;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Monter',
                  onPressed: i == 0 ? null : () => _deplacer(i, i - 1),
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
                IconButton(
                  tooltip: 'Descendre',
                  onPressed: i == n - 1 ? null : () => _deplacer(i, i + 1),
                  icon: const Icon(Icons.arrow_downward_rounded),
                ),
                Expanded(
                  child: Text(
                    nomsBlocs[b.id] ?? b.id,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Switch(
                  value: b.visible,
                  onChanged: (v) => _changerBloc(i, b.avec(visible: v)),
                ),
              ],
            ),
            if (b.visible) ...[
              _curseur(
                'Taille',
                b.taille,
                .6,
                2,
                (v) => _changerBloc(i, b.avec(taille: v)),
              ),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (b.id != 'infos')
                    SegmentedButton<Alignement>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: Alignement.gauche,
                          icon: Icon(Icons.format_align_left_rounded),
                          tooltip: 'À gauche',
                        ),
                        ButtonSegment(
                          value: Alignement.centre,
                          icon: Icon(Icons.format_align_center_rounded),
                          tooltip: 'Au centre',
                        ),
                        ButtonSegment(
                          value: Alignement.droite,
                          icon: Icon(Icons.format_align_right_rounded),
                          tooltip: 'À droite',
                        ),
                      ],
                      selected: {b.align},
                      onSelectionChanged: (v) =>
                          _changerBloc(i, b.avec(align: v.first)),
                    ),
                  FilterChip(
                    label: const Text('Trait en dessous'),
                    selected: b.traitApres,
                    onSelected: (v) => _changerBloc(i, b.avec(traitApres: v)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _carteApercu() => SectionCard(
    title: 'Aperçu',
    icon: Icons.visibility_rounded,
    child: Center(
      child: _apercu == null
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            )
          : Container(
              constraints: const BoxConstraints(maxWidth: 300),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.black12),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 6),
                ],
              ),
              child: Image.memory(
                _apercu!,
                fit: BoxFit.fitWidth,
                gaplessPlayback: true,
              ),
            ),
    ),
  );
}
