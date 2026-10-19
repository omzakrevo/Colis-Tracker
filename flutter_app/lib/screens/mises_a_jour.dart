import 'package:file_picker/file_picker.dart';
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
                    '2. Cliquez sur « Publier », choisissez le fichier APK : il est téléversé sur votre serveur (ou saisissez un lien public).\n'
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
    PlatformFile? fichier;
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
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      onPressed: () async {
                        try {
                          final f = await FilePicker.pickFile(
                            type: FileType.custom,
                            allowedExtensions: const ['apk'],
                            dialogTitle: 'Choisir l\'APK à publier',
                          );
                          if (f == null) return;
                          // Un nom comme « tchi-12.apk » renseigne le numéro de build.
                          final n = RegExp(r'(\d+)\.apk$', caseSensitive: false).firstMatch(f.name);
                          setS(() {
                            fichier = f;
                            if (n != null && build.text.isEmpty) build.text = n.group(1)!;
                          });
                        } catch (e) {
                          if (ctx.mounted) {
                            toast(ctx, 'Impossible d\'ouvrir le fichier : ${errMsg(e)}', error: true);
                          }
                        }
                      },
                      icon: const Icon(Icons.attach_file_rounded),
                      label: Text(
                        fichier == null
                            ? 'Choisir le fichier APK (téléversement)'
                            : '${fichier!.name}  ·  ${((fichier!.lengthSync() ?? 0) / 1048576).toStringAsFixed(1)} Mo',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: url,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        labelText: fichier == null
                            ? 'ou lien de l\'APK *'
                            : 'Lien de l\'APK (inutile : le fichier sera téléversé)',
                        hintText: 'https://…/tchi-15.apk',
                      ),
                      validator: (v) =>
                          fichier != null || (v ?? '').trim().startsWith('http')
                          ? null
                          : 'Choisissez un fichier ou saisissez un lien https',
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
    var enCours = false;
    try {
      var lien = url.text.trim();
      if (fichier != null) {
        // Téléversement de l'APK sur le serveur (plusieurs dizaines de Mo : on affiche une attente).
        enCours = true;
        if (context.mounted) {
          showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (_) => const AlertDialog(
              content: Row(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 18),
                  Expanded(child: Text('Téléversement de l\'APK…')),
                ],
              ),
            ),
          );
        }
        final octets = await fichier!.readAsBytes();
        lien = await Repo.televerserApk(octets, int.parse(build.text));
        if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
        enCours = false;
      }
      await Repo.publierVersion(
        versionName: nom.text.trim(),
        buildNumber: int.parse(build.text),
        apkUrl: lien,
        notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
        obligatoire: obligatoire,
      );
      ref.invalidate(_versionsProvider);
      if (context.mounted) toast(context, 'Version publiée');
    } catch (e) {
      final pendantEnvoi = enCours;
      if (enCours && context.mounted) Navigator.of(context, rootNavigator: true).pop();
      if (pendantEnvoi && context.mounted) {
        // Un échec pendant l'envoi du fichier n'est pas forcément « pas d'internet » : on montre la vraie cause.
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Téléversement impossible', style: TextStyle(fontWeight: FontWeight.w800)),
            content: SingleChildScrollView(
              child: SelectableText(
                'La connexion à votre serveur fonctionne (vous êtes connecté), mais l\'envoi du fichier a échoué.\n\n'
                'Causes fréquentes : le serveur ou son reverse-proxy (nginx, Caddy…) refuse les gros fichiers '
                '(limite « client_max_body_size » / « FILE_SIZE_LIMIT » du service Storage), ou le script '
                'rattrapage.sql n\'a pas été exécuté (règle d\'écriture du super administrateur).\n\n'
                'Solution de repli : GitHub → Actions → Application mobile (Android) → Run workflow, en cochant « Publier ».\n\n'
                'Détail technique : ${e.runtimeType} — $e',
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer'))],
          ),
        );
        return;
      }
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
