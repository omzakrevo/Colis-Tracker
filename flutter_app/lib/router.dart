import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data/providers.dart';
import 'screens/attente.dart';
import 'screens/billet_detail.dart';
import 'screens/billet_form.dart';
import 'screens/billet_verif.dart';
import 'screens/billets_list.dart';
import 'screens/colis_detail.dart';
import 'screens/colis_form.dart';
import 'screens/colis_list.dart';
import 'screens/dashboard.dart';
import 'screens/entreprises.dart';
import 'screens/gares.dart';
import 'screens/imprimante.dart';
import 'screens/inscription.dart';
import 'screens/login.dart';
import 'screens/mises_a_jour.dart';
import 'screens/parametres.dart';
import 'screens/rapports.dart';
import 'screens/recherche.dart';
import 'screens/scanner.dart';
import 'screens/trajets.dart';
import 'screens/utilisateurs.dart';
import 'widgets/app_shell.dart';

CustomTransitionPage<void> _page(GoRouterState s, Widget child) =>
    CustomTransitionPage<void>(
      key: s.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 320),
      transitionsBuilder: (context, anim, _, c) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, .03),
              end: Offset.zero,
            ).animate(curved),
            child: c,
          ),
        );
      },
    );

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      if (auth.isLoading) return null;
      final d = auth.value ?? const AuthData();
      final loc = state.matchedLocation;
      const publiques = ['/login', '/inscription'];
      final p = d.profil;
      if (p == null) return publiques.contains(loc) ? null : '/login';
      if (p.isSuper)
        return (loc == '/entreprises' || loc == '/mises-a-jour')
            ? null
            : '/entreprises';
      if (d.bloque) return loc == '/attente' ? null : '/attente';
      // Le barragiste n'a accès qu'au scanner.
      if (p.isBarragiste) return loc == '/scanner' ? null : '/scanner';
      // Le convoyeur vend des billets et scanne, rien d'autre.
      if (p.isConvoyeur) {
        return (loc.startsWith('/billets') ||
                loc == '/scanner' ||
                loc == '/imprimante')
            ? null
            : '/billets';
      }
      if (publiques.contains(loc) ||
          loc == '/attente' ||
          loc == '/mises-a-jour' ||
          loc.startsWith('/entreprises'))
        return '/';
      const adminOnly = ['/gares', '/utilisateurs', '/parametres', '/trajets'];
      if (!p.isAdmin && adminOnly.any(loc.startsWith)) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        pageBuilder: (c, s) => _page(s, const LoginScreen()),
      ),
      GoRoute(
        path: '/inscription',
        pageBuilder: (c, s) => _page(s, const InscriptionScreen()),
      ),
      GoRoute(
        path: '/attente',
        pageBuilder: (c, s) => _page(s, const AttenteScreen()),
      ),
      ShellRoute(
        builder: (c, s, child) =>
            AppShell(location: s.matchedLocation, child: child),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (c, s) => _page(s, const DashboardScreen()),
          ),
          GoRoute(
            path: '/mises-a-jour',
            pageBuilder: (c, s) => _page(s, const MisesAJourScreen()),
          ),
          GoRoute(
            path: '/entreprises',
            pageBuilder: (c, s) => _page(s, const EntreprisesScreen()),
          ),
          GoRoute(
            path: '/colis',
            pageBuilder: (c, s) => _page(s, const ColisListScreen()),
          ),
          GoRoute(
            path: '/colis/nouveau',
            pageBuilder: (c, s) => _page(s, const ColisFormScreen()),
          ),
          GoRoute(
            path: '/colis/:id',
            pageBuilder: (c, s) => _page(
              s,
              ColisDetailScreen(id: int.parse(s.pathParameters['id']!)),
            ),
          ),
          GoRoute(
            path: '/billets',
            pageBuilder: (c, s) => _page(s, const BilletsListScreen()),
          ),
          GoRoute(
            path: '/billets/nouveau',
            pageBuilder: (c, s) => _page(s, const BilletFormScreen()),
          ),
          GoRoute(
            path: '/imprimante',
            pageBuilder: (c, s) => _page(s, const ImprimanteScreen()),
          ),
          GoRoute(
            path: '/billets/verifier',
            pageBuilder: (c, s) => _page(s, const BilletVerifScreen()),
          ),
          GoRoute(
            path: '/trajets',
            pageBuilder: (c, s) => _page(s, const TrajetsScreen()),
          ),
          GoRoute(
            path: '/billets/:id',
            pageBuilder: (c, s) => _page(
              s,
              BilletDetailScreen(id: int.parse(s.pathParameters['id']!)),
            ),
          ),
          GoRoute(
            path: '/scanner',
            pageBuilder: (c, s) => _page(s, const ScannerScreen()),
          ),
          GoRoute(
            path: '/recherche',
            pageBuilder: (c, s) => _page(s, const RechercheScreen()),
          ),
          GoRoute(
            path: '/rapports',
            pageBuilder: (c, s) => _page(s, const RapportsScreen()),
          ),
          GoRoute(
            path: '/gares',
            pageBuilder: (c, s) => _page(s, const GaresScreen()),
          ),
          GoRoute(
            path: '/utilisateurs',
            pageBuilder: (c, s) => _page(s, const UtilisateursScreen()),
          ),
          GoRoute(
            path: '/parametres',
            pageBuilder: (c, s) => _page(s, const ParametresScreen()),
          ),
        ],
      ),
    ],
  );
});
