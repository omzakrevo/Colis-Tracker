import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../data/models.dart';

int _derniereProposee = 0;

/// Propose l'installation d'une nouvelle version (une seule fois par lancement, sauf mise à jour obligatoire).
Future<void> proposerMiseAJour(BuildContext context, AppVersion v) async {
  // Une fois par version et par lancement, sauf mise à jour obligatoire.
  if (_derniereProposee >= v.buildNumber && !v.obligatoire) return;
  _derniereProposee = v.buildNumber;
  await showDialog<void>(
    context: context,
    barrierDismissible: !v.obligatoire,
    builder: (_) => PopScope(canPop: !v.obligatoire, child: _UpdateDialog(v)),
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog(this.v);
  final AppVersion v;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  StreamSubscription<OtaEvent>? _sub;
  bool _enCours = false;
  int _pct = 0;
  String? _message;

  AppVersion get v => widget.v;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// Télécharge l'APK dans l'application puis ouvre l'installation (Android demande une confirmation).
  void _installer() {
    setState(() {
      _enCours = true;
      _pct = 0;
      _message = null;
    });
    try {
      _sub = OtaUpdate()
          .execute(v.apkUrl, destinationFilename: 'tchi-${v.buildNumber}.apk')
          .listen(
            (e) {
              if (!mounted) return;
              switch (e.status) {
                case OtaStatus.DOWNLOADING:
                  setState(() => _pct = int.tryParse(e.value ?? '') ?? _pct);
                case OtaStatus.INSTALLING:
                  setState(() {
                    _enCours = false;
                    _message =
                        'Téléchargé. Appuyez sur « Installer » dans la fenêtre Android qui s\'ouvre.';
                  });
                case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
                  setState(() {
                    _enCours = false;
                    _message =
                        'Autorisez Tchi à installer des applications (Paramètres Android), puis réessayez.';
                  });
                case OtaStatus.INSTALLATION_ERROR:
                  setState(() {
                    _enCours = false;
                    _message =
                        'Installation refusée : l\'ancienne version a été installée avec une autre signature. '
                        'Désinstallez Tchi une fois (envoyez d\'abord les opérations en attente), puis installez cette version : '
                        'les mises à jour suivantes seront automatiques.';
                  });
                case OtaStatus.INSTALLATION_DONE:
                  break;
                default:
                  _echec('${e.status.name}${e.value == null ? '' : ' : ${e.value}'}');
              }
            },
            onError: (Object err) => _echec('$err'),
          );
    } catch (err) {
      _echec('$err');
    }
  }

  /// Dernier recours : ouvre le lien dans le navigateur.
  Future<void> _echec(String detail) async {
    if (!mounted) return;
    setState(() {
      _enCours = false;
      _message = 'Téléchargement impossible ($detail). Ouverture du lien dans le navigateur…';
    });
    await launchUrl(Uri.parse(v.apkUrl), mode: LaunchMode.externalApplication);
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
        if (_enCours) ...[
          const SizedBox(height: 14),
          LinearProgressIndicator(value: _pct > 0 ? _pct / 100 : null),
          const SizedBox(height: 6),
          Text(_pct > 0 ? 'Téléchargement… $_pct %' : 'Téléchargement…', style: const TextStyle(fontSize: 13)),
        ],
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(_message!, style: const TextStyle(fontSize: 13, height: 1.4)),
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
          onPressed: _enCours ? null : () => Navigator.pop(context),
          child: const Text('Plus tard'),
        ),
      FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
        onPressed: _enCours ? null : _installer,
        icon: const Icon(Icons.download_rounded),
        label: Text(_enCours ? 'Téléchargement…' : 'Mettre à jour'),
      ),
    ],
  );
}
