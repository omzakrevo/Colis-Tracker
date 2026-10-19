import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import 'common.dart';

class ColisTile extends StatelessWidget {
  const ColisTile(this.c, {super.key});
  final Colis c;

  @override
  Widget build(BuildContext context) {
    final s = Statut.of(c.statut);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/colis/${c.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Hero(
                tag: 'colis-${c.id}',
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: s.color.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(s.icon, color: s.color, size: 22),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          c.numero,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14.5,
                          ),
                        ),
                        StatutBadge(c.statut),
                        if (c.enAttente) const EnAttenteChip(),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${c.expediteurNom}  →  ${c.destinataireNom}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${c.gareDepartNom ?? '—'} → ${c.gareArriveeNom ?? '—'}  ·  ${dateFr(c.dateEnvoi)}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Brand.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                fcfa(c.prix),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
