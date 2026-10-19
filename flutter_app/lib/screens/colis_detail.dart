import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:signature/signature.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../data/repo.dart';
import '../widgets/common.dart';
import 'receipt.dart';

class ColisDetailScreen extends ConsumerWidget {
  const ColisDetailScreen({super.key, required this.id});
  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colis = ref.watch(colisProvider(id));
    final histo = ref.watch(historiqueProvider(id));
    final company =
        ref.watch(settingsProvider).value ?? CompanySettings.defaults;

    return AsyncView<Colis>(
      value: colis,
      onRetry: () => ref.invalidate(colisProvider(id)),
      builder: (c) {
        final wide = MediaQuery.sizeOf(context).width >= 900;
        final suivants = Statut.of(c.statut).suivants;

        final info = [
          SectionCard(
            title: 'Expéditeur',
            icon: Icons.upload_rounded,
            child: Column(
              children: [
                InfoRow('Nom', c.expediteurNom, bold: true),
                InfoRow('Téléphone', c.expediteurTelephone),
              ],
            ),
          ),
          SectionCard(
            title: 'Destinataire',
            icon: Icons.download_rounded,
            accent: const Color(0xFF16A34A),
            child: Column(
              children: [
                InfoRow('Nom', c.destinataireNom, bold: true),
                InfoRow('Téléphone', c.destinataireTelephone),
              ],
            ),
          ),
          SectionCard(
            title: 'Trajet',
            icon: Icons.route_rounded,
            accent: const Color(0xFF2563EB),
            child: Column(
              children: [
                InfoRow('Départ', c.gareDepartNom ?? '—', bold: true),
                InfoRow('Arrivée', c.gareArriveeNom ?? '—', bold: true),
                InfoRow('Date d\'envoi', dateFr(c.dateEnvoi)),
                if (c.agentNom != null) InfoRow('Agent', c.agentNom!),
              ],
            ),
          ),
          SectionCard(
            title: 'Colis',
            icon: Icons.inventory_2_rounded,
            child: Column(
              children: [
                InfoRow('Description', c.description),
                InfoRow('Nombre', '${c.nombre}'),
                if (c.poids != null) InfoRow('Poids', '${c.poids} kg'),
                if (c.valeur != null) InfoRow('Valeur déclarée', fcfa(c.valeur!)),
                InfoRow('Prix', fcfa(c.prix), bold: true),
                if (c.notes != null) InfoRow('Notes', c.notes!),
              ],
            ),
          ),
        ];

        final extras = <Widget>[
          if (c.photo != null)
            SectionCard(
              title: 'Photo du colis',
              icon: Icons.photo_camera_rounded,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: _DataImage(c.photo!, height: 240, fit: BoxFit.cover),
              ),
            ),
          if (c.statut == 'retire' && c.retraitNom != null)
            SectionCard(
              title: 'Informations de retrait',
              icon: Icons.verified_rounded,
              accent: const Color(0xFF16A34A),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InfoRow('Retiré par', c.retraitNom!, bold: true),
                  InfoRow('Téléphone', c.retraitTelephone ?? '—'),
                  if (c.retraitPieceIdentite != null)
                    InfoRow('Pièce d\'identité', c.retraitPieceIdentite!),
                  if (c.retraitDate != null)
                    InfoRow('Date', dateHeureFr(c.retraitDate!)),
                  if (c.retraitSignature != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Brand.line),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _DataImage(c.retraitSignature!, height: 80),
                    ),
                  ],
                ],
              ),
            ),
          SectionCard(
            title: 'Historique',
            icon: Icons.history_rounded,
            accent: const Color(0xFF7C3AED),
            child: AsyncView<List<Historique>>(
              value: histo,
              loading: const SkeletonList(count: 3, height: 40),
              builder: (h) => h.isEmpty
                  ? const Text(
                      'Aucun historique.',
                      style: TextStyle(color: Brand.muted),
                    )
                  : _Timeline(h),
            ),
          ),
        ];

        return ListView(
          padding: const EdgeInsets.only(bottom: 110),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () =>
                      context.canPop() ? context.pop() : context.go('/colis'),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                Expanded(
                  child: Row(
                    children: [
                      Hero(
                        tag: 'colis-${c.id}',
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Statut.of(c.statut).color
                                .withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Statut.of(c.statut).icon,
                            color: Statut.of(c.statut).color,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onLongPress: () {
                                Clipboard.setData(
                                  ClipboardData(text: c.numero),
                                );
                                toast(context, 'Numéro copié');
                              },
                              child: Text(
                                c.numero,
                                style: const TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -.4,
                                ),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                StatutBadge(c.statut, large: true),
                                if (c.enAttente) const EnAttenteChip(),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ).reveal(),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                child: Column(
                  children: [
                    StatutProgress(c.statut),
                    if (c.statut == 'annule')
                      const Padding(
                        padding: EdgeInsets.only(top: 6, bottom: 6),
                        child: Text(
                          'Ce colis a été annulé.',
                          style: TextStyle(
                            color: Color(0xFFDC2626),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ).reveal(1),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (c.statut == 'arrive')
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                    ),
                    onPressed: () => _retrait(context, ref, c),
                    icon: const Icon(Icons.how_to_reg_rounded),
                    label: const Text('Enregistrer le retrait'),
                  ),
                if (suivants.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => _changerStatut(context, ref, c),
                    icon: const Icon(Icons.swap_horiz_rounded),
                    label: const Text('Changer le statut'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => avecMessage(context, () => imprimerRecu(c, company, ticket: true)),
                  icon: const Icon(Icons.receipt_long_rounded),
                  label: const Text('Ticket'),
                ),
                OutlinedButton.icon(
                  onPressed: () => avecMessage(context, () => imprimerRecu(c, company)),
                  icon: const Icon(Icons.print_rounded),
                  label: const Text('Reçu A4'),
                ),
              ],
            ).reveal(2),
            const SizedBox(height: 16),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        for (var i = 0; i < info.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: info[i].reveal(i + 2),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      children: [
                        _QrCard(c.numero).reveal(3),
                        const SizedBox(height: 14),
                        for (var i = 0; i < extras.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: extras[i].reveal(i + 4),
                          ),
                      ],
                    ),
                  ),
                ],
              )
            else
              Column(
                children: [
                  for (var i = 0; i < info.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: info[i].reveal(i + 2),
                    ),
                  _QrCard(c.numero).reveal(6),
                  const SizedBox(height: 12),
                  for (var i = 0; i < extras.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: extras[i].reveal(i + 7),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }

  Future<void> _changerStatut(
    BuildContext context,
    WidgetRef ref,
    Colis c,
  ) async {
    final notes = TextEditingController();
    final res = await showModalBottomSheet<Statut>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.viewInsetsOf(ctx).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Changer le statut',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: notes,
              maxLines: 2,
              decoration: const InputDecoration(hintText: 'Notes (optionnel)'),
            ),
            const SizedBox(height: 14),
            for (final s in Statut.of(c.statut).suivants)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.pop(ctx, s),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: s.color.withValues(alpha: .08),
                      border: Border.all(color: s.color.withValues(alpha: .35)),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Icon(s.icon, color: s.color),
                        const SizedBox(width: 12),
                        Text(
                          s.label,
                          style: TextStyle(
                            color: s.color,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const Spacer(),
                        Icon(Icons.chevron_right_rounded, color: s.color),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (res == null || !context.mounted) return;
    try {
      final envoye = await Repo.changerStatut(
        c.id,
        res.code,
        notes.text.trim().isEmpty ? null : notes.text.trim(),
      );
      ref.invalidate(colisProvider(c.id));
      ref.invalidate(historiqueProvider(c.id));
      ref.read(tickProvider.notifier).bump();
      HapticFeedback.mediumImpact();
      if (context.mounted) {
        toast(
          context,
          envoye
              ? 'Statut mis à jour : ${res.label}'
              : 'Statut « ${res.label} » enregistré — envoi dès le retour d\'internet',
        );
      }
    } catch (e) {
      if (context.mounted) toast(context, errMsg(e), error: true);
    }
  }

  Future<void> _retrait(BuildContext context, WidgetRef ref, Colis c) async {
    final envoye = await showDialog<bool>(
      context: context,
      builder: (_) => _RetraitDialog(c),
    );
    if (envoye != null) {
      ref.invalidate(colisProvider(c.id));
      ref.invalidate(historiqueProvider(c.id));
      ref.read(tickProvider.notifier).bump();
      if (context.mounted) {
        toast(
          context,
          envoye
              ? 'Retrait enregistré avec succès'
              : 'Retrait enregistré — envoi dès le retour d\'internet',
        );
      }
    }
  }
}

class _DataImage extends StatelessWidget {
  const _DataImage(this.data, {this.height, this.fit = BoxFit.contain});
  final String data;
  final double? height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    try {
      return Image.memory(
        base64Decode(data.split(',').last),
        height: height,
        width: double.infinity,
        fit: fit,
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }
}

class _QrCard extends StatelessWidget {
  const _QrCard(this.numero);
  final String numero;

  @override
  Widget build(BuildContext context) => SectionCard(
    title: 'QR de suivi',
    icon: Icons.qr_code_2_rounded,
    accent: Brand.emerald,
    child: Center(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Brand.line),
              borderRadius: BorderRadius.circular(16),
            ),
            child: QrImageView(data: numero, size: 150),
          ),
          const SizedBox(height: 8),
          Text(
            numero,
            style: const TextStyle(color: Brand.muted, fontSize: 12.5),
          ),
        ],
      ),
    ),
  );
}

class _Timeline extends StatelessWidget {
  const _Timeline(this.items);
  final List<Historique> items;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < items.length; i++)
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 26,
                child: Column(
                  children: [
                    Container(
                          margin: const EdgeInsets.only(top: 3),
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: Statut.of(items[i].statut).color,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                            boxShadow: [
                              BoxShadow(
                                color: Statut.of(items[i].statut).color
                                    .withValues(alpha: .4),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        )
                        .animate(delay: (140 * i).ms)
                        .scale(duration: 350.ms, curve: Curves.easeOutBack),
                    if (i < items.length - 1)
                      Expanded(
                        child: Container(width: 2, color: Brand.line)
                            .animate(delay: (140 * i).ms)
                            .scaleY(
                              begin: 0,
                              end: 1,
                              alignment: Alignment.topCenter,
                              duration: 350.ms,
                            ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child:
                      Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                children: [
                                  StatutBadge(items[i].statut),
                                  Text(
                                    dateHeureFr(items[i].date),
                                    style: const TextStyle(
                                      color: Brand.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              if (items[i].agentNom != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Text(
                                    'par ${items[i].agentNom}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Brand.muted,
                                    ),
                                  ),
                                ),
                              if (items[i].notes != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Text(
                                    items[i].notes!,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                            ],
                          )
                          .animate(delay: (140 * i).ms)
                          .fadeIn()
                          .slideX(begin: .08, end: 0),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

class _RetraitDialog extends StatefulWidget {
  const _RetraitDialog(this.colis);
  final Colis colis;

  @override
  State<_RetraitDialog> createState() => _RetraitDialogState();
}

class _RetraitDialogState extends State<_RetraitDialog> {
  late final nom = TextEditingController(text: widget.colis.destinataireNom);
  late final tel = TextEditingController(
    text: widget.colis.destinataireTelephone,
  );
  final piece = TextEditingController();
  final sig = SignatureController(
    penStrokeWidth: 3,
    penColor: Brand.ink,
    exportBackgroundColor: Colors.white,
  );
  bool _saving = false;

  @override
  void dispose() {
    nom.dispose();
    tel.dispose();
    piece.dispose();
    sig.dispose();
    super.dispose();
  }

  Future<void> _ok() async {
    if (nom.text.trim().isEmpty || tel.text.trim().isEmpty || sig.isEmpty) {
      toast(context, 'Nom, téléphone et signature sont requis', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final Uint8List? png = await sig.toPngBytes(height: 200);
      final envoye = await Repo.retirer(
        widget.colis.id,
        nom: nom.text.trim(),
        telephone: tel.text.trim(),
        piece: piece.text.trim().isEmpty ? null : piece.text.trim(),
        signature: png == null
            ? null
            : 'data:image/png;base64,${base64Encode(png)}',
      );
      if (mounted) Navigator.pop(context, envoye);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        toast(context, errMsg(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text(
      'Enregistrer le retrait',
      style: TextStyle(fontWeight: FontWeight.w800),
    ),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nom,
              decoration: const InputDecoration(
                labelText: 'Nom du retrayant *',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: tel,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Téléphone *'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: piece,
              decoration: const InputDecoration(
                labelText: 'Pièce d\'identité',
                hintText: 'CNI, passeport, permis…',
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Text(
                  'Signature *',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                TextButton(onPressed: sig.clear, child: const Text('Effacer')),
              ],
            ),
            Container(
              height: 150,
              decoration: BoxDecoration(
                border: Border.all(color: Brand.line, width: 1.5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Signature(
                  controller: sig,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
        onPressed: _saving ? null : _ok,
        child: _saving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : const Text('Confirmer le retrait'),
      ),
    ],
  );
}
