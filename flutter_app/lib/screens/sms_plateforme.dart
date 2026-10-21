import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../data/repo.dart';
import '../widgets/common.dart';

/// Superadmin : compte SMSBUS de la plateforme (utilisé par défaut par toutes les entreprises)
/// et réglage des SMS entreprise par entreprise.
class SmsPlateformeScreen extends ConsumerStatefulWidget {
  const SmsPlateformeScreen({super.key});

  @override
  ConsumerState<SmsPlateformeScreen> createState() => _SmsPlateformeState();
}

class _SmsPlateformeState extends ConsumerState<SmsPlateformeScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _sender = TextEditingController();
  final _port = TextEditingController(text: '7170');
  final _indicatif = TextEditingController(text: '226');
  final _terminal = TextEditingController();
  final _test = TextEditingController();
  bool _actif = true, _loaded = false, _saving = false, _soldeEnCours = false;
  String? _solde;
  DateTime? _soldeLe;

  @override
  void dispose() {
    for (final c in [_user, _pass, _sender, _port, _indicatif, _terminal, _test]) {
      c.dispose();
    }
    super.dispose();
  }

  void _load(SmsGlobal g) {
    if (_loaded) return;
    _loaded = true;
    _actif = g.actif;
    _user.text = g.username;
    _sender.text = g.sender;
    _port.text = '${g.port}';
    _indicatif.text = g.indicatif;
    _terminal.text = g.terminalId;
    _solde = g.soldeTexte;
    _soldeLe = g.soldeLe;
  }

  Map<String, dynamic> _data() => {
    'actif': _actif,
    'username': _user.text.trim(),
    if (_pass.text.isNotEmpty) 'password': _pass.text,
    'sender': _sender.text.trim(),
    'port': int.tryParse(_port.text.trim()) ?? 7170,
    'indicatif': _indicatif.text.trim(),
    'terminal_id': _terminal.text.trim(),
  };

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await Repo.enregistrerSmsGlobal(_data());
      _pass.clear();
      ref.invalidate(smsGlobalProvider);
      if (mounted) toast(context, 'Compte SMS de la plateforme enregistré');
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _actualiserSolde() async {
    setState(() => _soldeEnCours = true);
    try {
      await Repo.enregistrerSmsGlobal({'terminal_id': _terminal.text.trim(), 'port': int.tryParse(_port.text.trim()) ?? 7170});
      final r = await Repo.soldeSmsGlobal();
      if (mounted) {
        setState(() {
          _solde = r.solde;
          _soldeLe = r.le;
        });
      }
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    } finally {
      if (mounted) setState(() => _soldeEnCours = false);
    }
  }

  Future<void> _tester() async {
    final tel = _test.text.trim();
    if (tel.isEmpty) {
      toast(context, 'Saisissez un numéro pour le test', error: true);
      return;
    }
    try {
      await Repo.enregistrerSmsGlobal(_data());
      await Repo.testerSmsGlobal(tel);
      if (mounted) toast(context, 'SMS de test envoyé');
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  Future<void> _regler(SmsEntreprise e, {bool? bloque, String? source}) async {
    try {
      await Repo.reglerSmsEntreprise(e.companyId, bloque: bloque, source: source);
      ref.invalidate(smsEntreprisesProvider);
    } catch (err) {
      if (mounted) toast(context, errMsg(err), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = ref.watch(smsGlobalProvider);
    final ent = ref.watch(smsEntreprisesProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const PageHeader(
          'SMS de la plateforme',
          subtitle: 'Un seul compte SMSBUS pour toutes les entreprises ; chacune peut choisir le sien.',
        ),
        g.when(
          loading: () => const SizedBox(height: 60),
          error: (e, _) => SectionCard(
            title: 'SMS indisponibles',
            icon: Icons.sms_failed_rounded,
            child: Text(
              '${errMsg(e)}\n\nExécutez supabase/rattrapage.sql dans Supabase (SQL Editor), puis rouvrez cette page.',
            ),
          ),
          data: (cfg) {
            _load(cfg);
            return SectionCard(
              title: 'Compte SMSBUS de la plateforme',
              icon: Icons.sms_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _actif,
                    onChanged: (v) => setState(() => _actif = v),
                    title: const Text('SMS de la plateforme actifs'),
                    subtitle: const Text('Désactivé : aucune entreprise utilisant ce compte n\'envoie de SMS'),
                  ),
                  TextField(controller: _user, decoration: const InputDecoration(labelText: 'Identifiant (username)')),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pass,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Mot de passe / clé API SMSBUS',
                      helperText: cfg.motDePasseDefini ? 'Laissez vide pour conserver le mot de passe actuel' : null,
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
                          decoration: const InputDecoration(labelText: 'Nom d\'expéditeur (Sender ID)', counterText: ''),
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
                  const SizedBox(height: 12),
                  TextField(
                    controller: _terminal,
                    decoration: const InputDecoration(
                      labelText: 'Identifiant Terminal Web / Compte API WEB (pour le solde)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _solde ?? 'Solde inconnu',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _soldeEnCours ? null : _actualiserSolde,
                        icon: _soldeEnCours
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
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
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _test,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(labelText: 'Numéro pour un SMS de test'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: _tester,
                        icon: const Icon(Icons.send_rounded),
                        label: const Text('Tester'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('Enregistrer'),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'Entreprises',
          icon: Icons.business_rounded,
          child: ent.when(
            loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
            error: (e, _) => Text(errMsg(e)),
            data: (l) => Column(
              children: [
                for (final e in l)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(e.nom, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      '${e.source == 'propre' ? 'Compte propre' : 'Compte de la plateforme'} · '
                      '${e.envoyes} envoyé(s) · ${e.echecs} échec(s)'
                      '${e.actif ? '' : ' · désactivé par l\'entreprise'}',
                    ),
                    trailing: Wrap(
                      spacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (e.source == 'propre')
                          TextButton(
                            onPressed: () => _regler(e, source: 'global'),
                            child: const Text('Imposer la plateforme'),
                          ),
                        Switch(
                          value: !e.bloque,
                          onChanged: (v) => _regler(e, bloque: !v),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
