import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/config.dart';
import '../core/identifiant.dart';
import '../core/theme.dart';
import '../data/providers.dart';
import '../data/repo.dart';
import '../widgets/app_shell.dart';
import '../widgets/common.dart';

/// Une entreprise crée son compte (et son compte administrateur) toute seule.
/// Elle reste « en attente » jusqu'à validation par l'administrateur de la plateforme.
class InscriptionScreen extends ConsumerStatefulWidget {
  const InscriptionScreen({super.key});

  @override
  ConsumerState<InscriptionScreen> createState() => _InscriptionScreenState();
}

class _InscriptionScreenState extends ConsumerState<InscriptionScreen> {
  final _form = GlobalKey<FormState>();
  final _entreprise = TextEditingController(), _ville = TextEditingController();
  final _nom = TextEditingController(), _tel = TextEditingController();
  final _pass = TextEditingController(), _pass2 = TextEditingController();
  bool _saving = false, _hide = true;

  @override
  void dispose() {
    for (final c in [_entreprise, _ville, _nom, _tel, _pass, _pass2]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await Repo.inscrireEntreprise(
        entreprise: _entreprise.text.trim(),
        ville: _ville.text.trim(),
        nomAdmin: _nom.text.trim(),
        telephone: _tel.text.trim(),
        password: _pass.text,
      );
      // Connexion automatique : l'écran « en attente de validation » s'affiche ensuite.
      await ref.read(authProvider.notifier).login(_tel.text, _pass.text);
    } catch (e) {
      if (mounted)
        toast(
          context,
          estErreurReseau(e) ? 'Pas de connexion internet.' : errMsg(e),
          error: true,
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _req(String? v) => (v ?? '').trim().isEmpty ? 'Champ requis' : null;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => context.go('/login'),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const Logo(size: 34),
                      const SizedBox(width: 10),
                      Text(
                        AppConfig.appName.toUpperCase(),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          letterSpacing: .6,
                        ),
                      ),
                    ],
                  ).reveal(),
                  const SizedBox(height: 18),
                  const Text(
                    'Créer mon entreprise',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.6,
                    ),
                  ).reveal(1),
                  const SizedBox(height: 6),
                  const Text(
                    'Votre demande sera validée par l\'administrateur de la plateforme. '
                    'Vous pourrez ensuite créer les comptes de vos utilisateurs.',
                    style: TextStyle(color: Brand.muted, height: 1.4),
                  ).reveal(2),
                  const SizedBox(height: 22),
                  SectionCard(
                    title: 'Entreprise',
                    icon: Icons.business_rounded,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _entreprise,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Nom de l\'entreprise *',
                          ),
                          validator: _req,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _ville,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(labelText: 'Ville'),
                        ),
                      ],
                    ),
                  ).reveal(3),
                  const SizedBox(height: 14),
                  SectionCard(
                    title: 'Administrateur',
                    icon: Icons.admin_panel_settings_rounded,
                    accent: const Color(0xFF2563EB),
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _nom,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Votre nom complet *',
                          ),
                          validator: _req,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _tel,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Numéro de téléphone *',
                            hintText: '+226 70 11 22 33',
                            helperText:
                                'Il servira d\'identifiant de connexion.',
                          ),
                          validator: (v) => estTelephone(v ?? '')
                              ? null
                              : 'Numéro invalide (8 à 15 chiffres)',
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _pass,
                          obscureText: _hide,
                          decoration: InputDecoration(
                            labelText: 'Mot de passe *',
                            suffixIcon: IconButton(
                              icon: Icon(
                                _hide
                                    ? Icons.visibility_rounded
                                    : Icons.visibility_off_rounded,
                              ),
                              onPressed: () => setState(() => _hide = !_hide),
                            ),
                          ),
                          validator: (v) => (v ?? '').length < 6
                              ? '6 caractères minimum'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _pass2,
                          obscureText: _hide,
                          decoration: const InputDecoration(
                            labelText: 'Confirmer le mot de passe *',
                          ),
                          validator: (v) => v != _pass.text
                              ? 'Les mots de passe diffèrent'
                              : null,
                        ),
                      ],
                    ),
                  ).reveal(4),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving ? null : _submit,
                      child: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Envoyer ma demande'),
                    ),
                  ).reveal(5),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
