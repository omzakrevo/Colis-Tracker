import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/identifiant.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../data/repo.dart';
import '../widgets/common.dart';

class UtilisateursScreen extends ConsumerWidget {
  const UtilisateursScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(profilsProvider);
    final gares = ref.watch(garesProvider).value ?? const <Gare>[];
    final me = ref.watch(profilProvider).value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          'Utilisateurs',
          subtitle: ref.watch(sessionProvider).company == null
              ? 'Comptes et rôles'
              : 'Comptes et rôles · ${users.value?.where((u) => u.actif).length ?? '…'} / ${ref.watch(sessionProvider).company!.maxUtilisateurs} utilisateurs actifs',
          actions: [
            FilledButton.icon(
              onPressed: () => _edit(context, ref, null, gares),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Ajouter'),
            ),
          ],
        ),
        Expanded(
          child: AsyncView<List<Profil>>(
            value: users,
            onRetry: () => ref.invalidate(profilsProvider),
            builder: (list) => ListView.separated(
              padding: const EdgeInsets.only(bottom: 100),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final u = list[i];
                final gare = gares.where((g) => g.id == u.gareId).firstOrNull;
                final color = u.role == 'admin'
                    ? Brand.orange
                    : (u.role == 'chef_gare'
                          ? const Color(0xFF2563EB)
                          : (u.role == 'barragiste' || u.role == 'convoyeur' || u.role == 'comptable'
                                ? const Color(0xFF7C3AED)
                                : const Color(0xFF16A34A)));
                return Card(
                  child: Opacity(
                    opacity: u.actif ? 1 : .5,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: color.withValues(alpha: .14),
                            child: Text(
                              u.nom.isEmpty ? '?' : u.nom[0].toUpperCase(),
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  u.nom,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  '${u.username} · ${roleLabel(u.role)}${gare != null ? ' · ${gare.nom}' : ''}',
                                  style: const TextStyle(
                                    color: Brand.muted,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (u.id != me?.id)
                            Switch(
                              value: u.actif,
                              activeThumbColor: Brand.orange,
                              onChanged: (v) async {
                                try {
                                  await Repo.majProfil(u.id, {'actif': v});
                                  ref.invalidate(profilsProvider);
                                } catch (e) {
                                  if (context.mounted)
                                    toast(context, errMsg(e), error: true);
                                }
                              },
                            ),
                          IconButton(
                            onPressed: () => _edit(context, ref, u, gares),
                            icon: const Icon(Icons.edit_rounded, size: 20),
                          ),
                        ],
                      ),
                    ),
                  ),
                ).reveal(i < 10 ? i : 10);
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    Profil? u,
    List<Gare> gares,
  ) async {
    final nom = TextEditingController(text: u?.nom);
    final username = TextEditingController(text: u?.username);
    final pass = TextEditingController();
    var role = u?.role ?? 'agent';
    int? gareId = u?.gareId;
    final key = GlobalKey<FormState>();
    String? req(String? v) => (v ?? '').trim().isEmpty ? 'Requis' : null;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(
            u == null ? 'Nouvel utilisateur' : 'Modifier',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          content: SizedBox(
            width: 420,
            child: Form(
              key: key,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nom,
                      decoration: const InputDecoration(
                        labelText: 'Nom complet *',
                      ),
                      validator: req,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: username,
                      enabled: u == null,
                      autocorrect: false,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Téléphone (identifiant de connexion) *',
                        hintText: '+226 70 11 22 33',
                      ),
                      validator: (v) =>
                          normaliserIdentifiant(v ?? '').length < 3
                          ? 'Numéro de téléphone requis'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: pass,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: u == null
                            ? 'Mot de passe *'
                            : 'Nouveau mot de passe (laisser vide = inchangé)',
                      ),
                      validator: (v) => u == null && (v ?? '').length < 6
                          ? '6 caractères minimum'
                          : ((v ?? '').isNotEmpty && v!.length < 6
                                ? '6 caractères minimum'
                                : null),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: role,
                      decoration: const InputDecoration(labelText: 'Rôle'),
                      items: [
                        for (final r in ['admin', 'chef_gare', 'agent', 'guichet', 'convoyeur', 'barragiste', 'comptable'])
                          DropdownMenuItem(value: r, child: Text(roleLabel(r))),
                      ],
                      onChanged: (v) => setS(() => role = v!),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int?>(
                      initialValue: gareId,
                      decoration: const InputDecoration(labelText: 'Gare'),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('— Aucune —'),
                        ),
                        for (final g in gares)
                          DropdownMenuItem<int?>(
                            value: g.id,
                            child: Text(g.nom),
                          ),
                      ],
                      onChanged: (v) => setS(() => gareId = v),
                      validator: (v) =>
                          !['admin', 'barragiste', 'convoyeur', 'comptable'].contains(role) && v == null
                          ? 'Gare requise pour ce rôle'
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () {
                if (key.currentState!.validate()) Navigator.pop(ctx, true);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    const String? phone = null;
    try {
      if (u == null) {
        await Repo.creerUtilisateur(
          username: username.text.trim(),
          password: pass.text,
          nom: nom.text.trim(),
          role: role,
          gareId: gareId,
          telephone: phone,
        );
      } else {
        await Repo.majProfil(u.id, {
          'nom': nom.text.trim(),
          'role': role,
          'gare_id': gareId,
        });
        if (pass.text.isNotEmpty) await Repo.changerMotDePasse(u.id, pass.text);
      }
      ref.invalidate(profilsProvider);
      if (context.mounted) toast(context, 'Utilisateur enregistré');
    } catch (e) {
      if (context.mounted) toast(context, errMsg(e), error: true);
    }
  }
}
