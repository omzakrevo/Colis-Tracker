import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../data/models.dart';
import 'common.dart';

bool _dejaMontree = false;

/// Propose l'installation d'une nouvelle version (une seule fois par lancement, sauf mise à jour obligatoire).
Future<void> proposerMiseAJour(BuildContext context, AppVersion v) async {
  if (_dejaMontree && !v.obligatoire) return;
  _dejaMontree = true;
  await showDialog<void>(
    context: context,
    barrierDismissible: !v.obligatoire,
    builder: (_) => PopScope(canPop: !v.obligatoire, child: _UpdateDialog(v)),
  );
}

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog(this.v);
  final AppVersion v;

  Future<void> _installer(BuildContext context) async {
    final ok = await launchUrl(
      Uri.parse(v.apkUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!context.mounted) return;
    toast(
      context,
      ok
          ? 'Téléchargement lancé : ouvrez le fichier puis appuyez sur « Installer ».'
          : 'Impossible d\'ouvrir le lien de téléchargement.',
      error: !ok,
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: Brand.orangeSoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.system_update_rounded, color: Brand.orange),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            v.obligatoire
                ? 'Mise à jour obligatoire'
                : 'Nouvelle version disponible',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
        ),
      ],
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${AppConfig.appName} ${v.versionName}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        if (v.notes != null && v.notes!.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(v.notes!, style: const TextStyle(height: 1.4)),
        ],
        const SizedBox(height: 12),
        Text(
          v.obligatoire
              ? 'Cette version est nécessaire pour continuer à utiliser l\'application.'
              : 'Vos données sont conservées. L\'installation prend quelques secondes.',
          style: const TextStyle(color: Brand.muted, fontSize: 13),
        ),
      ],
    ),
    actions: [
      if (!v.obligatoire)
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Plus tard'),
        ),
      FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
        onPressed: () => _installer(context),
        icon: const Icon(Icons.download_rounded),
        label: const Text('Mettre à jour'),
      ),
    ],
  );
}
