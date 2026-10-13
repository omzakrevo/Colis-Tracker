import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/providers.dart';
import '../widgets/common.dart';

/// Affiché quand l'entreprise n'est pas (ou plus) autorisée : en attente de validation, suspendue, abonnement expiré.
class AttenteScreen extends ConsumerStatefulWidget {
  const AttenteScreen({super.key});

  @override
  ConsumerState<AttenteScreen> createState() => _AttenteScreenState();
}

class _AttenteScreenState extends ConsumerState<AttenteScreen> {
  bool _checking = false;

  Future<void> _verifier() async {
    setState(() => _checking = true);
    await ref.read(authProvider.notifier).revalider();
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider);
    final motif = s.motif;
    final attente = motif == 'en_attente';
    final color = attente ? const Color(0xFFCA8A04) : const Color(0xFFDC2626);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: .12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          attente
                              ? Icons.hourglass_top_rounded
                              : Icons.lock_clock_rounded,
                          size: 46,
                          color: color,
                        ),
                      )
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .scale(
                        begin: const Offset(.94, .94),
                        end: const Offset(1.04, 1.04),
                        duration: 1400.ms,
                        curve: Curves.easeInOut,
                      ),
                  const SizedBox(height: 24),
                  Text(
                    attente
                        ? 'Demande envoyée'
                        : (motif == 'abonnement_expire'
                              ? 'Abonnement expiré'
                              : 'Accès suspendu'),
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.5,
                    ),
                  ).reveal(),
                  if (s.company != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      s.company!.nom,
                      style: const TextStyle(
                        color: Brand.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ).reveal(1),
                  ],
                  const SizedBox(height: 14),
                  Text(
                    messageMotif(motif),
                    textAlign: TextAlign.center,
                    style: const TextStyle(height: 1.45),
                  ).reveal(2),
                  if (motif == 'abonnement_expire' &&
                      s.company?.abonnementFin != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Expiré le ${dateFr(s.company!.abonnementFin!)}',
                      style: const TextStyle(color: Brand.muted),
                    ),
                  ],
                  if (s.offline) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Hors connexion : la vérification se fera dès le retour d\'internet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Brand.muted, fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _checking ? null : _verifier,
                      icon: _checking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.refresh_rounded),
                      label: const Text('Vérifier à nouveau'),
                    ),
                  ).reveal(3),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => ref.read(authProvider.notifier).logout(),
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Se déconnecter'),
                    ),
                  ).reveal(4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
