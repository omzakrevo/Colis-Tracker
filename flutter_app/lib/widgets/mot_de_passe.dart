import 'package:flutter/material.dart';

import '../data/providers.dart';
import '../data/repo.dart';
import 'common.dart';

/// Fenêtre « Changer mon mot de passe » : chacun peut remplacer le mot de passe provisoire donné par l'administrateur.
/// Renvoie `true` si le mot de passe a été changé (l'appelant déconnecte alors l'utilisateur).
Future<bool> changerMotDePasseDialog(BuildContext context) async {
  final nouveau = TextEditingController();
  final confirme = TextEditingController();
  final cle = GlobalKey<FormState>();
  var cache = true;
  var envoi = false;
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('Changer mon mot de passe'),
        content: Form(
          key: cle,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nouveau,
                obscureText: cache,
                decoration: InputDecoration(
                  labelText: 'Nouveau mot de passe',
                  helperText: '6 caractères minimum',
                  suffixIcon: IconButton(
                    icon: Icon(cache ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                    onPressed: () => setS(() => cache = !cache),
                  ),
                ),
                validator: (v) {
                  final t = v ?? '';
                  if (t.length < 6) return 'Au moins 6 caractères';
                  if (t == '123456') return 'Choisissez un autre mot de passe que le mot de passe provisoire';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: confirme,
                obscureText: cache,
                decoration: const InputDecoration(labelText: 'Confirmer le mot de passe'),
                validator: (v) => v != nouveau.text ? 'Les deux mots de passe sont différents' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: envoi ? null : () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            onPressed: envoi
                ? null
                : () async {
                    if (!cle.currentState!.validate()) return;
                    setS(() => envoi = true);
                    try {
                      await Repo.changerMonMotDePasse(nouveau.text);
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } catch (e) {
                      setS(() => envoi = false);
                      if (ctx.mounted) toast(ctx, errMsg(e), error: true);
                    }
                  },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    ),
  );
  nouveau.dispose();
  confirme.dispose();
  return ok ?? false;
}
