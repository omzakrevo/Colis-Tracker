import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../data/repo.dart';
import '../widgets/common.dart';

final _versionsProvider = FutureProvider<List<AppVersion>>(
  (ref) => Repo.versions(),
);

/// Console du super administrateur : versions de l'application proposées aux téléphones.
class MisesAJourScreen extends ConsumerWidget {
  const MisesAJourScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final versions = ref.watch(_versionsProvider);
    void refresh() => ref.invalidate(_versionsProvider);

    return RefreshIndicator(
      onRefresh: () async => refresh(),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          PageHeader(
            'Mises à jour',
            subtitle: 'Versions proposées aux téléphones Android',
            actions: [
              FilledButton.icon(
                onPressed: () => _publier(context, ref),
                icon: const Icon(Icons.upload_rounded),
                label: const Text('Publier'),
              ),
            ],
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Comment publier ?',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '1. Construisez l\'APK (GitHub → Actions → Application mobile). Il porte un numéro de build.\n'
                    '2. Mettez le fichier en ligne (stockage « app-releases » de votre serveur, ou n\'importe quel lien public).\n'
                    '3. Publiez ici le numéro de build et le lien : les téléphones ayant un numéro plus ancien '
                    'verront la proposition de mise à jour au prochain démarrage.\n'
                    'Le workflow GitHub peut faire les étapes 2 et 3 automatiquement (voir le README).',
                    style: TextStyle(
                      color: Brand.muted,
                      height: 1.45,
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
            ),
          ).reveal(),
          const SizedBox(height: 14),
          AsyncView<List<AppVersion>>(
            value: versions,
            onRetry: refresh,
            builder: (list) => list.isEmpty
                ? const EmptyState(
                    icon: Icons.system_update_alt_rounded,
                    text: 'Aucune version publiée',
                  )
                : Column(
                    children: [
                      for (var i = 0; i < list.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _VersionCard(
                            list[i],
                            onChanged: refresh,
                          ).reveal(i < 8 ? i : 8),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _publier(BuildContext context, WidgetRef ref) async {
    final nom = TextEditingController();
    final build = TextEditingController();
    final url = TextEditingController();
    final notes = TextEditingController();
    var obligatoire = false;
    final key = GlobalKey<FormState>();
    String? req(String? v) => (v ?? '').trim().isEmpty ? 'Requis' : null;

    // Pré-remplit le nom avec la version installée sur cet appareil.
    try {
      if (!kIsWeb) {
        final info = await PackageInfo.fromPlatform();
        nom.text = info.version;
      }
    } catch (_) {}
    if (!context.mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text(
            'Publier une version',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: SizedBox(
            width: 440,
            child: Form(
              key: key,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nom,
                      decoration: const InputDecoration(
                        labelText: 'Nom de la version *',
                        hintText: '1.2.0',
                      ),
                      validator: req,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: build,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Numéro de build *',
                        hintText: 'ex. 15',
                      ),
                      validator: (v) => (int.tryParse(v ?? '') ?? 0) < 1
                          ? 'Nombre ≥ 1'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: url,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'Lien de l\'APK *',
                        hintText: 'https://…/tchi-15.apk',
                      ),
                      validator: (v) => (v ?? '').trim().startsWith('http')
                          ? null
                          : 'Lien https requis',
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: notes,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Nouveautés (affichées aux utilisateurs)',
                      ),
                    ),
                    const SizedBox(height: 6),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: obligatoire,
                      activeThumbColor: Brand.orange,
                      onChanged: (v) => setS(() => obligatoire = v),
                      title: const Text(
                        'Mise à jour obligatoire',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'Bloque l\'application tant qu\'elle n\'est pas installée',
                      ),
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
              child: const Text('Publier'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await Repo.publierVersion(
        versionName: nom.text.trim(),
        buildNumber: int.parse(build.text),
        apkUrl: url.text.trim(),
        notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
        obligatoire: obligatoire,
      );
      ref.invalidate(_versionsProvider);
      if (context.mounted) toast(context, 'Version publiée');
    } catch (e) {
      if (context.mounted) {
        toast(
          context,
          e.toString().contains('duplicate')
              ? 'Ce numéro de build existe déjà.'
              : errMsg(e),
          error: true,
        );
      }
    }
  }
}

class _VersionCard extends StatelessWidget {
  const _VersionCard(this.v, {required this.onChanged});
  final AppVersion v;
  final VoidCallback onChanged;

  Future<void> _update(BuildContext context, Map<String, dynamic> data) async {
    try {
      await Repo.majVersion(v.id, data);
      onChanged();
    } catch (e) {
      if (context.mounted) toast(context, errMsg(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Opacity(
      opacity: v.actif ? 1 : .55,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Version ${v.versionName}  ·  build ${v.buildNumber}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15.5,
                    ),
                  ),
                ),
                if (v.obligatoire) _Tag('Obligatoire', const Color(0xFFDC2626)),
                const SizedBox(width: 6),
                _Tag(
                  v.actif ? 'Active' : 'Désactivée',
                  v.actif ? const Color(0xFF16A34A) : Brand.muted,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Publiée le ${dateHeureFr(v.createdAt)}',
              style: const TextStyle(color: Brand.muted, fontSize: 12.5),
            ),
            if (v.notes != null && v.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(v.notes!, style: const TextStyle(fontSize: 13.5)),
            ],
            const SizedBox(height: 8),
            Text(
              v.apkUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Brand.muted, fontSize: 12),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 0,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: v.apkUrl));
                    toast(context, 'Lien copié');
                  },
                  icon: const Icon(Icons.link_rounded, size: 18),
                  label: const Text('Copier le lien'),
                ),
                TextButton.icon(
                  onPressed: () => _update(context, {'actif': !v.actif}),
                  icon: Icon(
                    v.actif
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    size: 18,
                  ),
                  label: Text(v.actif ? 'Désactiver' : 'Activer'),
                ),
                TextButton.icon(
                  onPressed: () =>
                      _update(context, {'obligatoire': !v.obligatoire}),
                  icon: const Icon(Icons.priority_high_rounded, size: 18),
                  label: Text(
                    v.obligatoire ? 'Rendre facultative' : 'Rendre obligatoire',
                  ),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                  ),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Supprimer cette version ?'),
                        content: const Text(
                          'Elle ne sera plus proposée. Le fichier APK n\'est pas supprimé.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Annuler'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFDC2626),
                              minimumSize: const Size(0, 44),
                            ),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Supprimer'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      try {
                        await Repo.supprimerVersion(v.id);
                        onChanged();
                      } catch (e) {
                        if (context.mounted)
                          toast(context, errMsg(e), error: true);
                      }
                    }
                  },
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Supprimer'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: color,
        fontWeight: FontWeight.w800,
        fontSize: 11.5,
      ),
    ),
  );
}
