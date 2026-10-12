import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'repo.dart';

String errMsg(Object e) {
  if (e is PostgrestException) return e.message;
  if (e is AuthException) return e.message;
  if (e is String) return e;
  return e.toString().replaceFirst('Exception: ', '');
}

// ── Session ───────────────────────────────────────────────
class ProfilNotifier extends AsyncNotifier<Profil?> {
  @override
  Future<Profil?> build() => Repo.currentProfil();

  Future<void> login(String username, String password) async {
    final p = await Repo.login(username, password);
    state = AsyncData(p);
  }

  Future<void> logout() async {
    await Repo.logout();
    state = const AsyncData(null);
  }
}

final profilProvider =
    AsyncNotifierProvider<ProfilNotifier, Profil?>(ProfilNotifier.new);

// ── Temps réel : tout changement de colis relance les listes ──
class TickNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final tickProvider = NotifierProvider<TickNotifier, int>(TickNotifier.new);

final realtimeProvider = Provider<void>((ref) {
  final client = Supabase.instance.client;
  Timer? debounce;
  final channel = client.channel('vip-colis-live');
  for (final table in ['colis', 'historique_colis']) {
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: table,
      callback: (_) {
        debounce?.cancel();
        debounce = Timer(const Duration(milliseconds: 400),
            () => ref.read(tickProvider.notifier).bump());
      },
    );
  }
  channel.subscribe();
  ref.onDispose(() {
    debounce?.cancel();
    client.removeChannel(channel);
  });
});

// ── Données ───────────────────────────────────────────────
class ColisFilterNotifier extends Notifier<ColisFilter> {
  @override
  ColisFilter build() => const ColisFilter();
  void set(ColisFilter f) => state = f;
}

final colisFilterProvider =
    NotifierProvider<ColisFilterNotifier, ColisFilter>(ColisFilterNotifier.new);

final colisListProvider = FutureProvider<List<Colis>>((ref) {
  ref.watch(tickProvider);
  final f = ref.watch(colisFilterProvider);
  final me = ref.watch(profilProvider).value;
  return Repo.listColis(f, maGareId: me?.gareId);
});

final colisProvider = FutureProvider.family<Colis, int>((ref, id) {
  ref.watch(tickProvider);
  return Repo.getColis(id);
});

final historiqueProvider = FutureProvider.family<List<Historique>, int>((ref, id) {
  ref.watch(tickProvider);
  return Repo.historique(id);
});

final garesProvider = FutureProvider<List<Gare>>((ref) => Repo.gares());
final profilsProvider = FutureProvider<List<Profil>>((ref) => Repo.profils());
final settingsProvider = FutureProvider<CompanySettings>((ref) => Repo.settings());

final dashboardProvider = FutureProvider<DashboardStats>((ref) {
  ref.watch(tickProvider);
  return Repo.dashboard();
});

final recentColisProvider = FutureProvider<List<Colis>>((ref) {
  ref.watch(tickProvider);
  return Repo.listColis(const ColisFilter());
});

class RapportPeriode {
  const RapportPeriode(this.debut, this.fin);
  final DateTime? debut, fin;
}

class RapportPeriodeNotifier extends Notifier<RapportPeriode> {
  @override
  RapportPeriode build() => RapportPeriode(
      DateTime.now().subtract(const Duration(days: 29)), DateTime.now());
  void set(RapportPeriode p) => state = p;
}

final rapportPeriodeProvider =
    NotifierProvider<RapportPeriodeNotifier, RapportPeriode>(
        RapportPeriodeNotifier.new);

final colisParJourProvider = FutureProvider<List<JourStat>>((ref) {
  ref.watch(tickProvider);
  final p = ref.watch(rapportPeriodeProvider);
  return Repo.colisParJour(p.debut, p.fin);
});

final recettesGareProvider = FutureProvider<List<LigneStat>>((ref) {
  ref.watch(tickProvider);
  return Repo.recettesParGare();
});

final recettesAgentProvider = FutureProvider<List<LigneStat>>((ref) {
  ref.watch(tickProvider);
  return Repo.recettesParAgent();
});

final statutsProvider = FutureProvider<Map<String, int>>((ref) {
  ref.watch(tickProvider);
  return Repo.statutsSummary();
});
