import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config.dart';
import 'core/theme.dart';
import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR');
  if (AppConfig.isConfigured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );
  }
  runApp(const ProviderScope(child: TchiApp()));
}

class TchiApp extends ConsumerWidget {
  const TchiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!AppConfig.isConfigured) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: Brand.theme(),
        home: const _MissingConfig(),
      );
    }
    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: Brand.theme(),
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => _Adaptatif(child: child ?? const SizedBox.shrink()),
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}

/// Adapte l'affichage aux petits écrans (terminaux POS, téléphones d'entrée de gamme) :
/// taille de texte plafonnée (le réglage « grande police » d'Android remplit l'écran) et champs plus compacts.
class _Adaptatif extends StatelessWidget {
  const _Adaptatif({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final petit = mq.size.shortestSide < 400 || mq.size.height < 700;
    final plafond = petit ? 1.0 : 1.15;
    final echelle = mq.textScaler.scale(1.0).clamp(0.85, plafond).toDouble();
    final theme = Theme.of(context);
    return MediaQuery(
      data: mq.copyWith(textScaler: TextScaler.linear(echelle)),
      child: petit
          ? Theme(
              data: theme.copyWith(
                visualDensity: VisualDensity.compact,
                inputDecorationTheme: theme.inputDecorationTheme.copyWith(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                ),
              ),
              child: child,
            )
          : child,
    );
  }
}

class _MissingConfig extends StatelessWidget {
  const _MissingConfig();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: SelectableText(
          'Supabase n\'est pas configuré.\n\n'
          'Lancez l\'application avec :\n'
          '--dart-define=SUPABASE_URL=https://votre-serveur\n'
          '--dart-define=SUPABASE_ANON_KEY=votre_clé_anon',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}
