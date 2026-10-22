import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/format.dart';
import '../core/imprimante.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../data/repo.dart';
import '../widgets/client_fields.dart';
import '../widgets/common.dart';
import 'billet_pdf.dart';

/// Vente d'un billet de transport (guichet, administrateur, convoyeur).
class BilletFormScreen extends ConsumerStatefulWidget {
  const BilletFormScreen({super.key});

  @override
  ConsumerState<BilletFormScreen> createState() => _BilletFormScreenState();
}

class _BilletFormScreenState extends ConsumerState<BilletFormScreen> {
  final _form = GlobalKey<FormState>();
  final nom = TextEditingController();
  final tel = TextEditingController();
  final prix = TextEditingController();
  final heure = TextEditingController();
  final siege = TextEditingController();
  int? depart, arrivee;
  DateTime date = DateTime.now();
  bool _init = false, _saving = false;
  bool _prixManuel = false;

  /// Trajet fixé par l'administrateur pour le départ/arrivée choisis (prix et heures proposés).
  Trajet? get _trajet {
    final l = ref.read(trajetsProvider).value ?? const <Trajet>[];
    return l
        .where((t) => t.gareDepartId == depart && t.gareArriveeId == arrivee)
        .firstOrNull;
  }

  /// Applique le prix du trajet (sauf si l'agent l'a modifié à la main) et l'heure s'il n'y en a qu'une.
  void _appliquerTrajet() {
    final t = _trajet;
    if (t == null) return;
    if (!_prixManuel) prix.text = '${t.prix.round()}';
    if (t.horaires.length == 1 && heure.text.isEmpty)
      heure.text = t.horaires.first;
  }

  @override
  void dispose() {
    for (final c in [nom, tel, prix, heure, siege]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _req(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Champ obligatoire' : null;

  Future<void> _enregistrer() async {
    if (!_form.currentState!.validate()) return;
    final me = ref.read(profilProvider).value;
    setState(() => _saving = true);
    try {
      final t = await Repo.creerTicket({
        'client_nom': nom.text.trim(),
        'client_telephone': tel.text.trim(),
        'gare_depart_id': depart,
        'gare_arrivee_id': arrivee,
        'date_voyage':
            '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        'heure_depart': heure.text.trim().isEmpty ? null : heure.text.trim(),
        'siege': siege.text.trim().isEmpty ? null : siege.text.trim(),
        'prix': double.parse(prix.text.replaceAll(',', '.')),
      }, vendeurNom: me?.nom);
      ref.read(tickProvider.notifier).bump();
      if (!mounted) return;
      toast(
        context,
        t.enAttente
            ? 'Billet ${t.numero} enregistré hors ligne — il sera envoyé dès le retour d\'internet'
            : 'Billet ${t.numero} enregistré !',
      );
      await _imprimerApresCreation(t);
      // On reste sur la vente : même trajet, nouveau client, pour enchaîner les billets.
      if (mounted) {
        nom.clear();
        tel.clear();
        siege.clear();
        final p = prix.text, h = heure.text;
        _form.currentState?.reset(); // efface aussi les messages d'erreur
        prix.text = p;
        heure.text = h;
        _prixManuel = false;
        setState(() {});
      }
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Le ticket sort tout de suite sur l'imprimante « clients » si elle est réglée ; sinon on propose la fenêtre.
  Future<void> _imprimerApresCreation(Ticket t) async {
    final client = await Imprimante.lire(RoleImprimante.client);
    if (!client.configuree) {
      await _proposerImpression(t);
      return;
    }
    if (!client.auto) return;
    try {
      final co = await ref.read(settingsProvider.future);
      await imprimerBillet(t, co, ticket: true);
    } catch (e) {
      if (mounted) {
        toast(
          context,
          'Impression : ${errMsg(e)}\nVous pourrez réimprimer depuis la fiche du billet.',
          error: true,
        );
      }
    }
  }

  Future<void> _proposerImpression(Ticket t) async {
    final choix = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Imprimer le billet ?',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Billet ${t.numero} enregistré. Imprimez-le maintenant pour le client.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'non'),
            child: const Text('Plus tard'),
          ),
          TextButton.icon(
            onPressed: () => Navigator.pop(ctx, 'config'),
            icon: const Icon(Icons.settings_bluetooth_rounded),
            label: const Text('Imprimante'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(ctx, 'a4'),
            icon: const Icon(Icons.print_rounded),
            label: const Text('Billet A4'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, 'ticket'),
            icon: const Icon(Icons.receipt_long_rounded),
            label: const Text('Ticket'),
          ),
        ],
      ),
    );
    if (choix == 'config') {
      // Réglage de l'imprimante (Bluetooth…), puis on repropose l'impression.
      if (!mounted) return;
      await context.push('/imprimante');
      if (mounted) await _proposerImpression(t);
      return;
    }
    if (choix == null || choix == 'non') return;
    try {
      final co = await ref.read(settingsProvider.future);
      await imprimerBillet(t, co, ticket: choix == 'ticket');
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(trajetsProvider);
    final gares = ref.watch(garesProvider).value ?? const <Gare>[];
    final me = ref.watch(profilProvider).value;
    if (!_init && me != null) {
      depart = me.isGuichet ? me.gareId : null;
      _init = true;
    }
    final lockDepart = me != null && me.isGuichet && me.gareId != null;

    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const PageHeader('Vendre un billet'),
                SectionCard(
                  title: 'Passager',
                  icon: Icons.person_rounded,
                  child: ClientFields(
                    nom: nom,
                    telephone: tel,
                    validator: _req,
                    onPick: (c) => setState(() {
                      if (!lockDepart && depart == null)
                        depart = c.dernierDepartId;
                      arrivee ??= c.dernierArriveeId;
                      _appliquerTrajet();
                    }),
                  ),
                ),
                const SizedBox(height: 14),
                SectionCard(
                  title: 'Voyage',
                  icon: Icons.directions_bus_rounded,
                  child: Column(
                    children: [
                      DropdownButtonFormField<int>(
                        key: ValueKey('d$depart'),
                        initialValue: depart,
                        decoration: const InputDecoration(
                          labelText: 'Gare de départ *',
                        ),
                        items: [
                          for (final g in gares)
                            if (!lockDepart || g.id == me.gareId)
                              DropdownMenuItem(value: g.id, child: Text(g.nom)),
                        ],
                        onChanged: lockDepart
                            ? null
                            : (v) => setState(() {
                                depart = v;
                                _appliquerTrajet();
                              }),
                        validator: (v) =>
                            v == null ? 'Choisissez une gare' : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        key: ValueKey('a$arrivee'),
                        initialValue: arrivee,
                        decoration: const InputDecoration(
                          labelText: 'Gare d\'arrivée *',
                        ),
                        items: [
                          for (final g in gares)
                            DropdownMenuItem(value: g.id, child: Text(g.nom)),
                        ],
                        onChanged: (v) => setState(() {
                          arrivee = v;
                          _appliquerTrajet();
                        }),
                        validator: (v) => v == null
                            ? 'Choisissez une gare'
                            : (v == depart ? 'Doit différer du départ' : null),
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: date,
                            firstDate: DateTime.now().subtract(
                              const Duration(days: 1),
                            ),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                          );
                          if (d != null) setState(() => date = d);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Date du voyage',
                            suffixIcon: Icon(Icons.event_rounded),
                          ),
                          child: Text(dateFr(date)),
                        ),
                      ),
                      if ((_trajet?.horaires ?? const <String>[])
                          .isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              for (final h in _trajet!.horaires)
                                ChoiceChip(
                                  label: Text(h),
                                  selected: heure.text == h,
                                  onSelected: (_) =>
                                      setState(() => heure.text = h),
                                ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
 textInputAction: TextInputAction.next,
                              controller: heure,
                              decoration: const InputDecoration(
                                labelText: 'Heure',
                                hintText: '08:00',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
 textInputAction: TextInputAction.next,
                              controller: siege,
                              decoration: const InputDecoration(
                                labelText: 'Place',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
 textInputAction: TextInputAction.next,
                        controller: prix,
                        onChanged: (_) => _prixManuel = true,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        decoration: InputDecoration(
                          labelText: 'Prix (FCFA) *',
                          helperText: _trajet == null
                              ? null
                              : 'Prix du trajet : ${fcfa(_trajet!.prix)}',
                        ),
                        validator: (v) {
                          final n = double.tryParse(
                            (v ?? '').replaceAll(',', '.'),
                          );
                          return n == null || n < 0 ? 'Prix invalide' : null;
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _saving ? null : _enregistrer,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_rounded),
                  label: const Text('Enregistrer le billet'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
