import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../data/repo.dart';
import '../widgets/common.dart';

/// Réglages des SMS automatiques (passerelle SMSBUS) : identifiants, événements, modèles de messages, journal.
class SmsSection extends ConsumerStatefulWidget {
  const SmsSection({super.key});

  @override
  ConsumerState<SmsSection> createState() => _SmsSectionState();
}

class _SmsSectionState extends ConsumerState<SmsSection> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _sender = TextEditingController();
  final _port = TextEditingController(text: '7170');
  final _terminal = TextEditingController();
  String? _solde;
  DateTime? _soldeLe;
  bool _soldeEnCours = false;
  final _indicatif = TextEditingController(text: '226');
  final _tests = TextEditingController();
  final _tpl = <String, TextEditingController>{
    for (final k in ['envoi_exp', 'envoi_dest', 'arrive', 'retire', 'billet'])
      k: TextEditingController(),
  };
  String _source = 'global';
  bool _actif = false, _envoi = true, _arrive = true, _retire = true, _billet = true;
  bool _loaded = false, _saving = false;

  @override
  void dispose() {
    for (final c in [_user, _pass, _sender, _port, _terminal, _indicatif, _tests, ..._tpl.values]) {
      c.dispose();
    }
    super.dispose();
  }

  void _load(SmsConfig? c) {
    if (_loaded) return;
    _loaded = true;
    if (c == null) return;
    _actif = c.actif;
    _source = c.source;
    _envoi = c.colisEnvoi;
    _arrive = c.colisArrive;
    _retire = c.colisRetire;
    _billet = c.billet;
    _user.text = c.username;
    _terminal.text = c.terminalId;
    _solde = c.soldeTexte;
    _soldeLe = c.soldeLe;
    _sender.text = c.sender;
    _port.text = '${c.port}';
    _indicatif.text = c.indicatif;
    _tpl['envoi_exp']!.text = c.tplEnvoiExp;
    _tpl['envoi_dest']!.text = c.tplEnvoiDest;
    _tpl['arrive']!.text = c.tplArrive;
    _tpl['retire']!.text = c.tplRetire;
    _tpl['billet']!.text = c.tplBillet;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await Repo.enregistrerSms({
        'actif': _actif,
        'source': _source,
        'username': _user.text.trim(),
        'terminal_id': _terminal.text.trim(),
        if (_pass.text.isNotEmpty) 'password': _pass.text,
        'sender': _sender.text.trim(),
        'port': int.tryParse(_port.text.trim()) ?? 7170,
        'indicatif': _indicatif.text.trim(),
        'sms_colis_envoi': _envoi,
        'sms_colis_arrive': _arrive,
        'sms_colis_retire': _retire,
        'sms_billet': _billet,
        'tpl_envoi_exp': _tpl['envoi_exp']!.text.trim(),
        'tpl_envoi_dest': _tpl['envoi_dest']!.text.trim(),
        'tpl_arrive': _tpl['arrive']!.text.trim(),
        'tpl_retire': _tpl['retire']!.text.trim(),
        'tpl_billet': _tpl['billet']!.text.trim(),
      });
      _pass.clear();
      ref.invalidate(smsConfigProvider);
      if (mounted) toast(context, 'Réglages SMS enregistrés');
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _actualiserSolde() async {
    setState(() => _soldeEnCours = true);
    try {
      // Enregistre d'abord l'identifiant Terminal Web saisi.
      await Repo.enregistrerSms({'terminal_id': _terminal.text.trim()});
      final r = await Repo.soldeSms();
      if (mounted) setState(() {
        _solde = r.solde;
        _soldeLe = r.le;
      });
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    } finally {
      if (mounted) setState(() => _soldeEnCours = false);
    }
  }

  Future<void> _tester() async {
    final tel = _tests.text.trim();
    if (tel.isEmpty) {
      toast(context, 'Saisissez un numéro pour le test', error: true);
      return;
    }
    try {
      await Repo.testerSms(tel);
      if (mounted) toast(context, 'SMS de test envoyé — voyez le journal');
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(smsConfigProvider);
    return cfg.when(
      loading: () => const SizedBox(height: 60),
      error: (e, _) => SectionCard(
        title: 'SMS indisponibles',
        icon: Icons.sms_failed_rounded,
        child: Text(
          'Impossible de charger les réglages SMS : ${errMsg(e)}\n\n'
          'Si le message parle d\'une table ou d\'une fonction introuvable, exécutez le script '
          'supabase/rattrapage.sql dans Supabase (SQL Editor), puis rouvrez cette page.',
        ),
      ),
      data: (c) {
        _load(c);
        Widget tpl(String key, String label) => Padding(
          padding: const EdgeInsets.only(top: 12),
          child: TextField(
            controller: _tpl[key],
            maxLines: 3,
            minLines: 2,
            decoration: InputDecoration(labelText: label),
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PageHeader(
              'SMS automatiques',
              subtitle: 'Passerelle SMSBUS : prévenez expéditeurs, destinataires et passagers.',
            ),
            if (c?.bloque ?? false)
              SectionCard(
                title: 'SMS désactivés',
                icon: Icons.block_rounded,
                child: const Text(
                  'L\'administrateur de la plateforme a désactivé les SMS pour votre entreprise. '
                  'Contactez-le pour les réactiver.',
                ),
              ),
            if (c?.bloque ?? false) const SizedBox(height: 14),
            SectionCard(
              title: 'Compte SMSBUS',
              icon: Icons.sms_rounded,
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _actif,
                    onChanged: (c?.bloque ?? false) ? null : (v) => setState(() => _actif = v),
                    title: const Text('Envoyer les SMS automatiquement'),
                  ),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'global', label: Text('Compte de la plateforme')),
                      ButtonSegment(value: 'propre', label: Text('Mon compte SMSBUS')),
                    ],
                    selected: {_source},
                    onSelectionChanged: (v) => setState(() => _source = v.first),
                  ),
                  const SizedBox(height: 8),
                  if (_source == 'global')
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Les SMS partent avec le compte SMSBUS de la plateforme : rien à configurer. '
                        'Choisissez « Mon compte SMSBUS » pour utiliser vos propres identifiants.',
                        style: TextStyle(color: Brand.muted, fontSize: 12.5),
                      ),
                    ),
                  if (_source == 'propre') ...[
                  TextField(
                    controller: _user,
                    decoration: const InputDecoration(labelText: 'Identifiant (username)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pass,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Mot de passe / clé API SMSBUS',
                      helperText: (c?.username ?? '').isEmpty
                          ? null
                          : 'Laissez vide pour conserver le mot de passe actuel',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _sender,
                          maxLength: 18,
                          decoration: const InputDecoration(
                            labelText: 'Nom d\'expéditeur (Sender ID)',
                            counterText: '',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _indicatif,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Indicatif pays'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _port,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Port'),
                        ),
                      ),
                    ],
                  ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_source == 'propre')
            SectionCard(
              title: 'Solde SMS',
              icon: Icons.account_balance_wallet_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _terminal,
                    decoration: const InputDecoration(
                      labelText: 'Identifiant Terminal Web SMSBUS',
                      helperText: 'Indiqué dans votre compte SMSBUS (« Terminal Web »)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _solde == null ? 'Solde inconnu' : _solde!,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _soldeEnCours ? null : _actualiserSolde,
                        icon: _soldeEnCours
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh_rounded),
                        label: const Text('Actualiser le solde'),
                      ),
                    ],
                  ),
                  if (_soldeLe != null)
                    Text(
                      'Mis à jour le ${dateHeureFr(_soldeLe!)}',
                      style: const TextStyle(color: Brand.muted, fontSize: 12.5),
                    ),
                ],
              ),
            ),
            if (_source == 'propre') const SizedBox(height: 14),
            SectionCard(
              title: 'Quand envoyer un SMS ?',
              icon: Icons.notifications_active_rounded,
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _envoi,
                    onChanged: (v) => setState(() => _envoi = v),
                    title: const Text('Envoi d\'un colis'),
                    subtitle: const Text('Expéditeur et destinataire sont prévenus'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _arrive,
                    onChanged: (v) => setState(() => _arrive = v),
                    title: const Text('Arrivée du colis'),
                    subtitle: const Text('Le destinataire est prévenu qu\'il peut le retirer'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _retire,
                    onChanged: (v) => setState(() => _retire = v),
                    title: const Text('Retrait du colis'),
                    subtitle: const Text('L\'expéditeur est prévenu que le colis a été remis'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _billet,
                    onChanged: (v) => setState(() => _billet = v),
                    title: const Text('Vente d\'un billet'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: 'Modèles de messages',
              icon: Icons.edit_note_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Mots remplacés automatiquement : {entreprise} {numero} {expediteur} {destinataire} {depart} {arrivee} {retrait} {prix}. '
                    'Pour un billet : {nom} {date} {siege}. Les accents sont retirés à l\'envoi pour tenir dans un seul SMS.',
                    style: TextStyle(color: Brand.muted, fontSize: 12.5),
                  ),
                  tpl('envoi_exp', 'Envoi — message à l\'expéditeur'),
                  tpl('envoi_dest', 'Envoi — message au destinataire'),
                  tpl('arrive', 'Arrivée — message au destinataire'),
                  tpl('retire', 'Retrait — message à l\'expéditeur'),
                  tpl('billet', 'Billet — message au passager'),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Enregistrer les SMS'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const _JournalSms(),
                  ),
                  icon: const Icon(Icons.history_rounded),
                  label: const Text('Journal'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tests,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Numéro pour un SMS de test'),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(onPressed: _tester, child: const Text('Envoyer un test')),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _JournalSms extends StatefulWidget {
  const _JournalSms();

  @override
  State<_JournalSms> createState() => _JournalSmsState();
}

class _JournalSmsState extends State<_JournalSms> {
  late Future<List<SmsLigne>> _f = Repo.smsJournal();

  void _recharger() => setState(() => _f = Repo.smsJournal());

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Journal des SMS', style: TextStyle(fontWeight: FontWeight.w800)),
    content: SizedBox(
      width: 520,
      height: 440,
      child: FutureBuilder<List<SmsLigne>>(
        future: _f,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return Text(errMsg(snap.error!));
          final l = snap.data!;
          if (l.isEmpty) return const Center(child: Text('Aucun SMS pour le moment.'));
          return ListView.separated(
            itemCount: l.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final s = l[i];
              final (icone, couleur) = switch (s.statut) {
                'envoye' => (Icons.check_circle_rounded, const Color(0xFF16A34A)),
                'echec' => (Icons.error_rounded, Colors.red),
                _ => (Icons.schedule_rounded, const Color(0xFFB45309)),
              };
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(icone, color: couleur),
                title: Text('${s.typeLabel} · ${s.telephone}'),
                subtitle: Text(
                  '${dateHeureFr(s.createdAt)}\n${s.message}'
                  '${s.statut == 'echec' && s.reponse != null ? '\n${s.reponse}' : ''}',
                ),
                isThreeLine: true,
                trailing: s.statut == 'echec'
                    ? IconButton(
                        tooltip: 'Renvoyer',
                        icon: const Icon(Icons.refresh_rounded),
                        onPressed: () async {
                          await Repo.renvoyerSms(s.id);
                          _recharger();
                        },
                      )
                    : null,
              );
            },
          );
        },
      ),
    ),
    actions: [
      TextButton(onPressed: _recharger, child: const Text('Actualiser')),
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer')),
    ],
  );
}
