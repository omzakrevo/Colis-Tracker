import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../data/providers.dart';

/// Bandeaux d'état en haut de l'écran : hors connexion, envoi en cours, opérations refusées.
class SyncBanner extends ConsumerWidget {
  const SyncBanner({super.key, required this.offline});
  final bool offline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncProvider);
    final n = sync.pending;
    final enAttente = n == 0
        ? ''
        : ' · $n opération${n > 1 ? 's' : ''} en attente d\'envoi';
    return Column(
      children: [
        if (offline)
          _Bandeau(
            icone: Icons.cloud_off_rounded,
            fond: const Color(0xFFFEF3C7),
            encre: const Color(0xFF92400E),
            texte:
                'Hors connexion — vos actions sont gardées sur l\'appareil$enAttente.',
          )
        else if (n > 0)
          _Bandeau(
            icone: Icons.cloud_sync_rounded,
            fond: const Color(0xFFDBEAFE),
            encre: const Color(0xFF1E40AF),
            texte: sync.syncing
                ? 'Envoi de $n opération${n > 1 ? 's' : ''}…'
                : '$n opération${n > 1 ? 's' : ''} en attente d\'envoi — nouvelle tentative automatique.',
          ),
        if (sync.rejected.isNotEmpty)
          _Bandeau(
            icone: Icons.error_outline_rounded,
            fond: const Color(0xFFFEE2E2),
            encre: const Color(0xFF991B1B),
            texte:
                '${sync.rejected.length} opération${sync.rejected.length > 1 ? 's' : ''} refusée${sync.rejected.length > 1 ? 's' : ''} par le serveur — touchez pour voir.',
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => const _RejetsDialog(),
            ),
          ),
      ],
    );
  }
}

class _Bandeau extends StatelessWidget {
  const _Bandeau({
    required this.icone,
    required this.fond,
    required this.encre,
    required this.texte,
    this.onTap,
  });
  final IconData icone;
  final Color fond, encre;
  final String texte;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: fond,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            children: [
              Icon(icone, size: 18, color: encre),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  texte,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: encre,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  ).animate().fadeIn().slideY(begin: -.4, end: 0);
}

class _RejetsDialog extends ConsumerWidget {
  const _RejetsDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rejets = ref.watch(syncProvider).rejected;
    return AlertDialog(
      title: const Text(
        'Opérations refusées',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      content: SizedBox(
        width: 440,
        child: rejets.isEmpty
            ? const Text('Aucune.')
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ces actions faites hors ligne n\'ont pas pu être appliquées (par exemple parce que le colis a changé entre-temps). Vérifiez le colis concerné et refaites l\'action si nécessaire.',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    for (final o in rejets)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          o.libelle,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          '${dateHeureFr(o.createdAt)}\n${o.erreur ?? ''}',
                        ),
                        isThreeLine: true,
                        trailing: IconButton(
                          tooltip: 'Supprimer',
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () =>
                              ref.read(syncProvider.notifier).oublier(o.id),
                        ),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}
