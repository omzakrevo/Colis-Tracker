import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/providers.dart';

/// Apparition en cascade : fondu + glissement vers le haut.
extension Reveal on Widget {
  Widget reveal([int index = 0]) => animate()
      .fadeIn(duration: 420.ms, delay: (60 * index).ms, curve: Curves.easeOut)
      .slideY(
        begin: 0.12,
        end: 0,
        duration: 480.ms,
        delay: (60 * index).ms,
        curve: Curves.easeOutCubic,
      );
}

/// Nombre qui « compte » jusqu'à sa valeur.
class CountUp extends StatelessWidget {
  const CountUp(this.value, {super.key, this.format, this.style});
  final num value;
  final String Function(num)? format;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: value.toDouble()),
    duration: const Duration(milliseconds: 1100),
    curve: Curves.easeOutCubic,
    builder: (_, v, _) => Text((format ?? nombre)(v), style: style),
  );
}

/// Pastille « en attente d'envoi » d'un colis créé ou modifié hors ligne.
class EnAttenteChip extends StatelessWidget {
  const EnAttenteChip({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0xFFFEF3C7),
      borderRadius: BorderRadius.circular(99),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.cloud_upload_outlined, size: 13, color: Color(0xFFB45309)),
        SizedBox(width: 4),
        Text(
          'En attente d\'envoi',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF92400E),
          ),
        ),
      ],
    ),
  );
}

class StatutBadge extends StatelessWidget {
  const StatutBadge(this.code, {super.key, this.large = false});
  final String code;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final s = Statut.of(code);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: EdgeInsets.symmetric(
        horizontal: large ? 14 : 10,
        vertical: large ? 7 : 4,
      ),
      decoration: BoxDecoration(
        color: s.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(s.icon, size: large ? 16 : 13, color: s.color),
          const SizedBox(width: 5),
          Text(
            s.label,
            style: TextStyle(
              color: s.color,
              fontWeight: FontWeight.w700,
              fontSize: large ? 13 : 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    this.icon,
    required this.child,
    this.accent,
  });
  final String title;
  final IconData? icon;
  final Widget child;
  final Color? accent;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: (accent ?? Brand.orange).withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 16, color: accent ?? Brand.orange),
                ),
                const SizedBox(width: 10),
              ],
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    ),
  );
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.bold = false});
  final String label, value;
  final bool bold;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(color: Brand.muted, fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );
}

class PageHeader extends StatelessWidget {
  const PageHeader(
    this.title, {
    super.key,
    this.subtitle,
    this.actions = const [],
  });
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.5,
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    subtitle!,
                    style: const TextStyle(color: Brand.muted, fontSize: 14),
                  ),
                ),
            ],
          ),
        ),
        ...actions,
      ],
    ),
  ).animate().fadeIn(duration: 350.ms).slideX(begin: -.03, end: 0);
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 54, color: Brand.line)
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .moveY(
                begin: -4,
                end: 4,
                duration: 1600.ms,
                curve: Curves.easeInOut,
              ),
          const SizedBox(height: 12),
          Text(text, style: const TextStyle(color: Brand.muted)),
        ],
      ),
    ),
  );
}

class Skeleton extends StatelessWidget {
  const Skeleton({super.key, this.height = 72, this.radius = 18});
  final double height, radius;

  @override
  Widget build(BuildContext context) =>
      Container(
            height: height,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(radius),
            ),
          )
          .animate(onPlay: (c) => c.repeat())
          .shimmer(duration: 1300.ms, color: Brand.line.withValues(alpha: .7));
}

class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 5, this.height = 72});
  final int count;
  final double height;

  @override
  // Défilement désactivé mais présent : sur un petit écran le squelette est rogné au lieu de déborder.
  Widget build(BuildContext context) => SingleChildScrollView(
    physics: const NeverScrollableScrollPhysics(),
    child: Column(
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Skeleton(height: height),
          ),
      ],
    ),
  );
}

/// Affiche chargement (squelette), erreur (avec réessayer) ou contenu.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.builder,
    this.loading,
    this.onRetry,
  });
  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final Widget? loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => value.when(
    skipLoadingOnReload: true,
    data: builder,
    loading: () => loading ?? const SkeletonList(),
    error: (e, _) => Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 44, color: Brand.muted),
            const SizedBox(height: 10),
            Text(errMsg(e), textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('Réessayer'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

void toast(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? const Color(0xFFDC2626) : Brand.emerald,
      ),
    );
}

/// Champ de formulaire étiqueté.
class Labeled extends StatelessWidget {
  const Labeled(this.label, this.child, {super.key});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 2),
        child: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12.5,
            color: Brand.muted,
          ),
        ),
      ),
      child,
    ],
  );
}

/// Barre de progression du colis : un camion avance le long des étapes.
class StatutProgress extends StatelessWidget {
  const StatutProgress(this.code, {super.key});
  final String code;

  static const _steps = [
    Statut.enregistre,
    Statut.charge,
    Statut.enRoute,
    Statut.arrive,
    Statut.retire,
  ];

  @override
  Widget build(BuildContext context) {
    final cancelled = code == 'annule';
    final idx = cancelled
        ? 0
        : _steps.indexWhere((s) => s.code == code).clamp(0, 4);
    final color = cancelled ? Statut.annule.color : Statut.of(code).color;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        return SizedBox(
          height: 74,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 14,
                right: 14,
                top: 22,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: Brand.line,
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
              ),
              Positioned(
                left: 14,
                top: 22,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: (w - 28) * (idx / 4)),
                  duration: const Duration(milliseconds: 1000),
                  curve: Curves.easeInOutCubic,
                  builder: (_, v, _) => Container(
                    height: 4,
                    width: v,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                ),
              ),
              for (var i = 0; i < _steps.length; i++)
                Positioned(
                  left: 14 + (w - 28) * (i / 4) - 14,
                  top: 10,
                  child: SizedBox(
                    width: 28,
                    child: Column(
                      children: [
                        AnimatedContainer(
                              duration: 400.ms,
                              curve: Curves.easeOut,
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i <= idx ? color : Colors.white,
                                border: Border.all(
                                  color: i <= idx ? color : Brand.line,
                                  width: 2,
                                ),
                              ),
                              child: Icon(
                                i <= idx ? Icons.check_rounded : _steps[i].icon,
                                size: 15,
                                color: i <= idx ? Colors.white : Brand.muted,
                              ),
                            )
                            .animate(delay: (140 * i).ms)
                            .scale(
                              begin: const Offset(.4, .4),
                              duration: 380.ms,
                              curve: Curves.easeOutBack,
                            ),
                      ],
                    ),
                  ),
                ),
              for (var i = 0; i < _steps.length; i++)
                Positioned(
                  left: 14 + (w - 28) * (i / 4) - 36,
                  top: 44,
                  child: SizedBox(
                    width: 72,
                    child: Text(
                      _steps[i].label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: i == idx
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: i <= idx ? Brand.ink : Brand.muted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Lance une action (impression…) et affiche l'erreur éventuelle au lieu de la laisser passer en silence.
Future<void> avecMessage(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) toast(context, errMsg(e), error: true);
  }
}
