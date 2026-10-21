import 'dart:convert';

import 'package:flutter/material.dart';

import '../widgets/scan_numero.dart';

import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../core/format.dart';
import '../core/imprimante.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../data/repo.dart';
import '../widgets/client_fields.dart';
import '../widgets/common.dart';
import 'receipt.dart';

class ColisFormScreen extends ConsumerStatefulWidget {
  const ColisFormScreen({super.key});

  @override
  ConsumerState<ColisFormScreen> createState() => _ColisFormScreenState();
}

class _ColisFormScreenState extends ConsumerState<ColisFormScreen> {
  final _keys = [
    GlobalKey<FormState>(),
    GlobalKey<FormState>(),
    GlobalKey<FormState>(),
  ];
  int _step = 0;
  bool _saving = false;

  final expNom = TextEditingController(), expTel = TextEditingController();
  final destNom = TextEditingController(), destTel = TextEditingController();
  final description = TextEditingController(),
      nb = TextEditingController(text: '1');
  final poids = TextEditingController(), prix = TextEditingController();
  final valeur = TextEditingController();
  final billet = TextEditingController();
  final notes = TextEditingController();
  int? depart, arrivee;
  DateTime date = DateTime.now();
  String? photo;
  bool _init = false;

  @override
  void dispose() {
    for (final c in [
      expNom,
      expTel,
      destNom,
      destTel,
      description,
      nb,
      poids,
      prix,
      valeur,
      billet,
      notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _photo(ImageSource src) async {
    try {
      final f = await ImagePicker().pickImage(
        source: src,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 70,
      );
      if (f == null) return;
      final bytes = await f.readAsBytes();
      setState(() => photo = 'data:image/jpeg;base64,${base64Encode(bytes)}');
    } catch (e) {
      if (mounted)
        toast(context, 'Impossible d\'accéder à la photo', error: true);
    }
  }

  void _next() {
    if (!_keys[_step].currentState!.validate()) return;
    if (_step < 2) {
      setState(() => _step++);
    } else {
      _submit();
    }
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      final c = await Repo.creerColis({
        'expediteur_nom': expNom.text.trim(),
        'expediteur_telephone': expTel.text.trim(),
        'destinataire_nom': destNom.text.trim(),
        'destinataire_telephone': destTel.text.trim(),
        'gare_depart_id': depart,
        'gare_arrivee_id': arrivee,
        'description': description.text.trim(),
        'nombre': int.parse(nb.text),
        'poids': poids.text.trim().isEmpty
            ? null
            : double.parse(poids.text.replaceAll(',', '.')),
        'valeur': valeur.text.trim().isEmpty
            ? null
            : double.parse(valeur.text.replaceAll(',', '.')),
        // N'est envoyé que s'il est renseigné : le serveur sans la migration 24 ne connaît pas cette colonne.
        if (billet.text.trim().isNotEmpty) 'billet_numero': billet.text.trim().toUpperCase(),
        'prix': double.parse(prix.text.replaceAll(',', '.')),
        'date_envoi': dateIso(date),
        'photo': photo,
        'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
      }, agentNom: ref.read(profilProvider).value?.nom);
      ref.read(tickProvider.notifier).bump();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      toast(
        context,
        c.enAttente
            ? 'Colis ${c.numero} enregistré hors ligne — il sera envoyé dès le retour d\'internet'
            : 'Colis ${c.numero} enregistré !',
      );
      await _imprimerApresCreation(c);
      if (mounted) context.go('/colis/${c.id}');
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Juste après l'enregistrement : le ticket client sort tout de suite sur l'imprimante « clients » et l'étiquette
  /// sur l'imprimante « colis » (chacune selon son réglage). Une imprimante absente n'empêche pas l'autre : on
  /// pourra la relancer depuis la fiche du colis. Sans aucune imprimante réglée, on propose la fenêtre d'impression.
  Future<void> _imprimerApresCreation(Colis c) async {
    final client = await Imprimante.lire(RoleImprimante.client);
    final etiquette = await Imprimante.lire(RoleImprimante.colis);
    if (!client.configuree && !etiquette.configuree) {
      await _proposerImpression(c);
      return;
    }
    final co = await ref.read(settingsProvider.future);
    final erreurs = <String>[];
    if (client.configuree && client.auto) {
      try {
        await imprimerRecu(c, co, ticket: true);
      } catch (e) {
        erreurs.add('Ticket client : ${errMsg(e)}');
      }
    }
    if (etiquette.configuree && etiquette.auto) {
      try {
        await imprimerEtiquette(c, co);
      } catch (e) {
        erreurs.add('Étiquette colis : ${errMsg(e)}');
      }
    }
    if (erreurs.isNotEmpty && mounted) {
      toast(
        context,
        '${erreurs.join('\n')}\nVous pourrez réimprimer depuis la fiche du colis.',
        error: true,
      );
    }
  }

  /// Fenêtre « Imprimer ? » (aucune imprimante réglée).
  Future<void> _proposerImpression(Colis c) async {
    final choix = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Imprimer le ticket ?',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Colis ${c.numero} enregistré. Imprimez maintenant le reçu à remettre au client.',
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
            label: const Text('Reçu A4'),
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
      if (mounted) await _proposerImpression(c);
      return;
    }
    if (choix == null || choix == 'non') return;
    try {
      final co = await ref.read(settingsProvider.future);
      await imprimerRecu(c, co, ticket: choix == 'ticket');
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gares = ref.watch(garesProvider);
    final me = ref.watch(profilProvider).value;
    if (!_init && me != null) {
      depart = me.gareId;
      _init = true;
    }
    final lockDepart = me != null && !me.isAdmin && me.gareId != null;
    // Clavier ouvert sur un petit écran : on masque l'en-tête et les étapes pour laisser la place aux champs.
    final clavier = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!clavier) ...[
              Row(
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const Expanded(
                    child: PageHeader(
                      'Nouveau colis',
                      subtitle: 'Enregistrement d\'une expédition',
                    ),
                  ),
                ],
              ),
              _Steps(_step),
              const SizedBox(height: 18),
            ],
            Expanded(
              child: gares.when(
                loading: () => const SkeletonList(count: 3, height: 120),
                error: (e, _) => Center(child: Text(errMsg(e))),
                data: (gl) => SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.only(bottom: 24),
                  child: AnimatedSwitcher(
                    duration: 350.ms,
                    switchInCurve: Curves.easeOutCubic,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween(
                          begin: const Offset(.06, 0),
                          end: Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(
                      key: ValueKey(_step),
                      child: _stepBody(gl, lockDepart),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  if (_step > 0) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() => _step--),
                        child: const Text('Retour'),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _saving ? null : _next,
                      child: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _step < 2 ? 'Continuer' : 'Enregistrer le colis',
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _req(String? v) => (v ?? '').trim().isEmpty ? 'Champ requis' : null;

  Widget _stepBody(List<Gare> gares, bool lockDepart) {
    switch (_step) {
      case 0:
        return Form(
          key: _keys[0],
          child: Column(
            children: [
              SectionCard(
                title: 'Expéditeur',
                icon: Icons.upload_rounded,
                child: Column(
                  children: [
                    ClientFields(
                      nom: expNom,
                      telephone: expTel,
                      validator: _req,
                      onPick: (c) {
                        if (arrivee == null && c.dernierArriveeId != null) {
                          setState(() => arrivee = c.dernierArriveeId);
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SectionCard(
                title: 'Destinataire',
                icon: Icons.download_rounded,
                accent: const Color(0xFF16A34A),
                child: Column(
                  children: [
                    ClientFields(
                      nom: destNom,
                      telephone: destTel,
                      validator: _req,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      case 1:
        return Form(
          key: _keys[1],
          child: Column(
            children: [
              SectionCard(
                title: 'Trajet',
                icon: Icons.route_rounded,
                accent: const Color(0xFF2563EB),
                child: Column(
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: depart,
                      decoration: const InputDecoration(
                        labelText: 'Gare de départ *',
                      ),
                      items: [
                        for (final g in gares)
                          DropdownMenuItem(value: g.id, child: Text(g.nom)),
                      ],
                      onChanged: lockDepart
                          ? null
                          : (v) => setState(() => depart = v),
                      validator: (v) =>
                          v == null ? 'Choisissez une gare' : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      key: ValueKey(arrivee),
                      initialValue: arrivee,
                      decoration: const InputDecoration(
                        labelText: 'Gare d\'arrivée *',
                      ),
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
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (d != null) setState(() => date = d);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Date d\'envoi',
                          suffixIcon: Icon(Icons.event_rounded),
                        ),
                        child: Text(dateFr(date)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SectionCard(
                title: 'Contenu',
                icon: Icons.inventory_2_rounded,
                child: Column(
                  children: [
                    TextFormField(
                      controller: description,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Description *',
                        hintText: 'Carton de vêtements…',
                      ),
                      validator: _req,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: nb,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Nombre *',
                            ),
                            validator: (v) =>
                                (int.tryParse(v ?? '') ?? 0) < 1 ? '≥ 1' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: poids,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Poids (kg)',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      default:
        return Form(
          key: _keys[2],
          child: Column(
            children: [
              SectionCard(
                title: 'Tarif',
                icon: Icons.payments_rounded,
                accent: const Color(0xFF16A34A),
                child: TextFormField(
                  controller: prix,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Prix (FCFA) *',
                    suffixText: 'FCFA',
                  ),
                  validator: (v) =>
                      (double.tryParse((v ?? '').replaceAll(',', '.')) ?? 0) <=
                          0
                      ? 'Le prix doit être supérieur à 0'
                      : null,
                ),
              ),
              const SizedBox(height: 14),
              SectionCard(
                title: 'Valeur du colis',
                icon: Icons.diamond_rounded,
                accent: const Color(0xFF7C3AED),
                child: TextFormField(
                  controller: valeur,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Valeur déclarée (FCFA)',
                    helperText:
                        'Facultatif — valeur des marchandises transportées',
                    suffixText: 'FCFA',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    final n = double.tryParse(v.replaceAll(',', '.'));
                    return n == null || n < 0 ? 'Valeur invalide' : null;
                  },
                ),
              ),
              const SizedBox(height: 14),
              SectionCard(
                title: 'Billet de voyage (facultatif)',
                icon: Icons.confirmation_number_rounded,
                accent: const Color(0xFF0EA5E9),
                child: TextFormField(
                  controller: billet,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'Numéro du billet lié au colis',
                    helperText: 'Scannez le QR code du billet du voyageur, ou saisissez son numéro',
                    suffixIcon: IconButton(
                      tooltip: 'Scanner le billet',
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      onPressed: () async {
                        final n = await scannerNumero(
                          context,
                          titre: 'Scanner le billet',
                        );
                        if (n != null && mounted)
                          setState(() => billet.text = n);
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SectionCard(
                title: 'Photo du colis',
                icon: Icons.photo_camera_rounded,
                child: Column(
                  children: [
                    if (photo != null)
                      Stack(
                        alignment: Alignment.topRight,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.memory(
                              base64Decode(photo!.split(',').last),
                              height: 190,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ).animate().fadeIn().scale(
                            begin: const Offset(.95, .95),
                          ),
                          IconButton.filled(
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black54,
                            ),
                            onPressed: () => setState(() => photo = null),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _photo(ImageSource.camera),
                              icon: const Icon(Icons.photo_camera_rounded),
                              label: const Text('Prendre'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _photo(ImageSource.gallery),
                              icon: const Icon(Icons.image_rounded),
                              label: const Text('Galerie'),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SectionCard(
                title: 'Notes',
                icon: Icons.sticky_note_2_rounded,
                accent: Brand.muted,
                child: TextFormField(
                  controller: notes,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Informations complémentaires (optionnel)',
                  ),
                ),
              ),
            ],
          ),
        );
    }
  }
}

class _Steps extends StatelessWidget {
  const _Steps(this.step);
  final int step;
  static const labels = ['Contacts', 'Trajet', 'Tarif'];

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < 3; i++) ...[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: i <= step ? 1 : 0),
                duration: 450.ms,
                curve: Curves.easeOut,
                builder: (_, v, _) => ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: LinearProgressIndicator(
                    value: v,
                    minHeight: 5,
                    backgroundColor: Brand.line,
                    color: Brand.orange,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${i + 1}. ${labels[i]}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: i == step ? FontWeight.w800 : FontWeight.w500,
                  color: i <= step ? Brand.ink : Brand.muted,
                ),
              ),
            ],
          ),
        ),
        if (i < 2) const SizedBox(width: 8),
      ],
    ],
  );
}
