import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data/providers.dart';
import 'screens/colis_detail.dart';
import 'screens/colis_form.dart';
import 'screens/colis_list.dart';
import 'screens/dashboard.dart';
import 'screens/gares.dart';
import 'screens/login.dart';
import 'screens/parametres.dart';
import 'screens/rapports.dart';
import 'screens/recherche.dart';
import 'screens/scanner.dart';
import 'screens/utilisateurs.dart';
import 'widgets/app_shell.dart';

CustomTransitionPage<void> _page(GoRouterState s, Widget child) =>
    CustomTransitionPage<void>(
      key: s.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 320),
      transitionsBuilder: (context, anim, _, c) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, .03), end: Offset.zero).animate(curved),
            child: c,
          ),
        );
      },
    );

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(profilProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(profilProvider);
      if (auth.isLoading) return null;
      final logged = auth.value != null;
      final onLogin = state.matchedLocation == '/login';
      if (!logged && !onLogin) return '/login';
      if (logged && onLogin) return '/';
      final adminOnly = ['/gares', '/utilisateurs', '/parametres'];
      if (logged && !auth.value!.isAdmin && adminOnly.any(state.matchedLocation.startsWith)) {
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', pageBuilder: (c, s) => _page(s, const LoginScreen())),
      ShellRoute(
        builder: (c, s, child) => AppShell(location: s.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/', pageBuilder: (c, s) => _page(s, const DashboardScreen())),
          GoRoute(path: '/colis', pageBuilder: (c, s) => _page(s, const ColisListScreen())),
          GoRoute(path: '/colis/nouveau', pageBuilder: (c, s) => _page(s, const ColisFormScreen())),
          GoRoute(
              path: '/colis/:id',
              pageBuilder: (c, s) =>
                  _page(s, ColisDetailScreen(id: int.parse(s.pathParameters['id']!)))),
          GoRoute(path: '/scanner', pageBuilder: (c, s) => _page(s, const ScannerScreen())),
          GoRoute(path: '/recherche', pageBuilder: (c, s) => _page(s, const RechercheScreen())),
          GoRoute(path: '/rapports', pageBuilder: (c, s) => _page(s, const RapportsScreen())),
          GoRoute(path: '/gares', pageBuilder: (c, s) => _page(s, const GaresScreen())),
          GoRoute(path: '/utilisateurs', pageBuilder: (c, s) => _page(s, const UtilisateursScreen())),
          GoRoute(path: '/parametres', pageBuilder: (c, s) => _page(s, const ParametresScreen())),
        ],
      ),
    ],
  );
});
