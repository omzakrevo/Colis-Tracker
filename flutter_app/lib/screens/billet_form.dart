import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/format.dart';
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
        'date_voyage': '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
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
      await _proposerImpression(t);
      if (mounted) context.go('/billets/${t.id}');
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
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
        content: Text('Billet ${t.numero} enregistré. Imprimez-le maintenant pour le client.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'non'),
            child: const Text('Plus tard'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(ctx, 'a4'),
            icon: const Icon(Icons.print_rounded),
            label: const Text('Billet A4'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, 'ticket'),
            icon: const Icon(Icons.receipt_long_rounded),
            label: const Text('Ticket 80 mm'),
          ),
        ],
      ),
    );
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
    final gares = ref.watch(garesProvider).value ?? const <Gare>[];
    final me = ref.watch(profilProvider).value;
    if (!_init && me != null) {
      depart = me.isGuichet ? me.gareId : null;
      _init = true;
    }
    final lockDepart = me != null && me.isGuichet && me.gareId != null;

    return SingleChildScrollView(
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
                      if (!lockDepart && depart == null) depart = c.dernierDepartId;
                      arrivee ??= c.dernierArriveeId;
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
                        decoration: const InputDecoration(labelText: 'Gare de départ *'),
                        items: [
                          for (final g in gares)
                            if (!lockDepart || g.id == me.gareId)
                              DropdownMenuItem(value: g.id, child: Text(g.nom)),
                        ],
                        onChanged: lockDepart ? null : (v) => setState(() => depart = v),
                        validator: (v) => v == null ? 'Choisissez une gare' : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        key: ValueKey('a$arrivee'),
                        initialValue: arrivee,
                        decoration: const InputDecoration(labelText: 'Gare d\'arrivée *'),
                        items: [
                          for (final g in gares)
                            DropdownMenuItem(value: g.id, child: Text(g.nom)),
                        ],
                        onChanged: (v) => setState(() => arrivee = v),
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
                            firstDate: DateTime.now().subtract(const Duration(days: 1)),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
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
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
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
                              controller: siege,
                              decoration: const InputDecoration(labelText: 'Place'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: prix,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                        decoration: const InputDecoration(labelText: 'Prix (FCFA) *'),
                        validator: (v) {
                          final n = double.tryParse((v ?? '').replaceAll(',', '.'));
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
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
