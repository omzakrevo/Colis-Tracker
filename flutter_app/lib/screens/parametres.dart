import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../data/models.dart';
import '../data/providers.dart';
import '../data/repo.dart';
import '../widgets/app_shell.dart';
import '../widgets/common.dart';
import 'identite_legale.dart';
import 'reinitialisation.dart';
import 'sms_section.dart';

class ParametresScreen extends ConsumerStatefulWidget {
  const ParametresScreen({super.key});

  @override
  ConsumerState<ParametresScreen> createState() => _ParametresScreenState();
}

class _ParametresScreenState extends ConsumerState<ParametresScreen> {
  final _c = <String, TextEditingController>{
    for (final k in [
      'nom',
      'slogan',
      'telephone',
      'email',
      'adresse',
      'ville',
      'pays',
    ])
      k: TextEditingController(),
  };
  String? _logo;
  bool _loaded = false, _saving = false;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _load(CompanySettings s) {
    if (_loaded) return;
    _loaded = true;
    _c['nom']!.text = s.nom;
    _c['slogan']!.text = s.slogan;
    _c['telephone']!.text = s.telephone;
    _c['email']!.text = s.email;
    _c['adresse']!.text = s.adresse;
    _c['ville']!.text = s.ville;
    _c['pays']!.text = s.pays;
    _logo = s.logo;
  }

  Future<void> _pickLogo() async {
    final f = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 400,
      maxHeight: 400,
      imageQuality: 85,
    );
    if (f == null) return;
    final bytes = await f.readAsBytes();
    setState(() => _logo = 'data:image/png;base64,${base64Encode(bytes)}');
  }

  Future<void> _save() async {
    if (_c['nom']!.text.trim().isEmpty) {
      toast(context, 'Le nom de la société est requis', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final cid = ref.read(profilProvider).value?.companyId;
      if (cid == null) throw 'Entreprise introuvable';
      await Repo.saveSettings(cid, {
        for (final e in _c.entries) e.key: e.value.text.trim(),
        'logo': _logo,
      });
      ref.invalidate(settingsProvider);
      if (mounted) toast(context, 'Paramètres enregistrés');
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
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
      builder: (settings) {
        _load(settings);
        return ListView(
          padding: const EdgeInsets.only(bottom: 100),
          children: [
            const PageHeader(
              'Paramètres',
              subtitle: 'Identité de la société, utilisée sur les reçus.',
            ),
            SectionCard(
              title: 'Logo',
              icon: Icons.image_rounded,
              child: Row(
                children: [
                  Logo(size: 72, data: _logo),
                  const SizedBox(width: 16),
                  Wrap(
                    spacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _pickLogo,
                        icon: const Icon(Icons.upload_rounded),
                        label: const Text('Choisir'),
                      ),
                      if (_logo != null)
                        TextButton(
                          onPressed: () => setState(() => _logo = null),
                          child: const Text('Retirer'),
                        ),
                    ],
                  ),
                ],
              ),
            ).reveal(),
            const SizedBox(height: 14),
            SectionCard(
              title: 'Société',
              icon: Icons.business_rounded,
              child: Column(
                children: [
                  TextField(
                    controller: _c['nom'],
                    decoration: const InputDecoration(labelText: 'Nom *'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _c['slogan'],
                    decoration: const InputDecoration(labelText: 'Slogan'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _c['telephone'],
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Téléphone'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _c['email'],
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'E-mail'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _c['adresse'],
                    decoration: const InputDecoration(labelText: 'Adresse'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _c['ville'],
                          decoration: const InputDecoration(labelText: 'Ville'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _c['pays'],
                          decoration: const InputDecoration(labelText: 'Pays'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ).reveal(1),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
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
            ).reveal(2),
            const SizedBox(height: 28),
            if (ref.watch(authProvider).value?.company?.moduleFinance ?? false) ...[
              const IdentiteLegaleCard(),
              const SizedBox(height: 28),
            ],
            const SmsSection(),
            const SizedBox(height: 28),
            const ReinitialisationCard(),
          ],
        );
      },
    );
  }
}
