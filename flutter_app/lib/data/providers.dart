import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/identifiant.dart';
import '../core/local_auth.dart';
import 'models.dart';
import 'offline.dart';
import 'repo.dart';

String errMsg(Object e) {
  if (estErreurReseau(e))
    return 'Pas de connexion internet. Réessayez quand le réseau revient.';
  if (e is PostgrestException) return e.message;
  if (e is AuthException) return e.message;
  if (e is String) return e;
  return e.toString().replaceFirst('Exception: ', '');
}

// ── Session ───────────────────────────────────────────────

/// Motifs pour lesquels l'utilisateur est déconnecté d'office (le compte n'existe plus ou est désactivé).
const _motifsFatals = {
  'compte_desactive',
  'profil_introuvable',
  'entreprise_introuvable',
};

String messageMotif(String? motif) => switch (motif) {
  'en_attente' => 'Votre entreprise est en attente de validation par l\'administrateur de la plateforme.',
  'suspendu' => 'Le compte de votre entreprise est suspendu. Contactez l\'administrateur de la plateforme.',
  'abonnement_expire' => 'L\'abonnement de votre entreprise a expiré. Contactez l\'administrateur de la plateforme pour le renouveler.',
  'compte_desactive' =>
    'Votre compte a été désactivé. Contactez votre administrateur.',
  'profil_introuvable' ||
  'entreprise_introuvable' => 'Ce compte n\'existe plus.',
  _ => 'Accès impossible.',
};

/// État d'authentification : qui est connecté, son entreprise, un éventuel blocage d'abonnement,
/// si l'on est hors connexion, et un message à afficher après une déconnexion forcée.
class AuthData {
  const AuthData({
    this.profil,
    this.company,
    this.motif,
    this.offline = false,
    this.message,
  });
  final Profil? profil;
  final Company? company;
  final String? motif;
  final bool offline;
  final String? message;

  bool get bloque => profil != null && !profil!.isSuper && motif != null;

  AuthData copyWith({bool? offline}) => AuthData(
    profil: profil,
    company: company,
    motif: motif,
    offline: offline ?? this.offline,
    message: message,
  );
}

/// Blocage calculé localement (utile hors ligne) à partir de l'entreprise mémorisée.
String? _motifLocal(Profil p, Company? c) {
  if (p.isSuper || c == null) return null;
  if (c.statut == 'en_attente') return 'en_attente';
  if (c.statut == 'suspendu') return 'suspendu';
  final fin = c.abonnementFin;
  if (fin != null &&
      DateTime.now().isAfter(
        DateTime(fin.year, fin.month, fin.day, 23, 59, 59),
      )) {
    return 'abonnement_expire';
  }
  return null;
}

class AuthNotifier extends AsyncNotifier<AuthData> {
  String? _identifiant;
  String? _mdpEnMemoire; // uniquement en mémoire vive, pour se reconnecter dès que le réseau revient
  Timer? _timer;
  StreamSubscription<List<ConnectivityResult>>? _conn;
  bool _occupe = false;

  @override
  Future<AuthData> build() async {
    _conn = Connectivity().onConnectivityChanged.listen((r) {
      if (!r.contains(ConnectivityResult.none)) revalider();
    });
    _timer = Timer.periodic(const Duration(minutes: 10), (_) => revalider());
    ref.onDispose(() {
      _conn?.cancel();
      _timer?.cancel();
    });

    if (!Repo.aUneSession) return const AuthData();
    final local = await LocalAuth.byUserId(Repo.userId!);
    if (local != null) {
      // Démarrage instantané (même sans internet) avec le compte mémorisé, puis vérification en arrière-plan.
      _identifiant = local.identifiant;
      Future.microtask(revalider);
      return AuthData(
        profil: local.profil,
        company: local.company,
        motif: _motifLocal(local.profil, local.company),
      );
    }
    try {
      final c = await Repo.maSession();
      return await _depuisServeur(c);
    } catch (e) {
      return const AuthData();
    }
  }

  Future<AuthData> _depuisServeur(SessionCheck c) async {
    if (c.profil == null || _motifsFatals.contains(c.motif)) {
      await _deconnecterDOffice(messageMotif(c.motif ?? 'profil_introuvable'));
      return AuthData(message: messageMotif(c.motif ?? 'profil_introuvable'));
    }
    if (_identifiant != null)
      await LocalAuth.refresh(_identifiant!, c.profil!, c.company);
    return AuthData(
      profil: c.profil,
      company: c.company,
      motif: c.valide ? null : c.motif,
    );
  }

  Future<void> _deconnecterDOffice(String message) async {
    try {
      await Repo.logout();
    } catch (_) {}
    await LocalAuth.forgetAll();
    _identifiant = null;
    _mdpEnMemoire = null;
    state = AsyncData(AuthData(message: message));
  }

  /// Connexion avec téléphone / identifiant + mot de passe (en ligne, sinon hors ligne si déjà mémorisé).
  Future<void> login(String identifiant, String password) async {
    final id = normaliserIdentifiant(identifiant);
    try {
      await Repo.signIn(id, password);
      final c = await Repo.maSession();
      if (c.profil == null || _motifsFatals.contains(c.motif)) {
        await Repo.logout();
        throw messageMotif(c.motif ?? 'profil_introuvable');
      }
      await LocalAuth.remember(id, password, c.profil!, c.company);
      _identifiant = id;
      _mdpEnMemoire = null;
      state = AsyncData(
        AuthData(
          profil: c.profil,
          company: c.company,
          motif: c.valide ? null : c.motif,
        ),
      );
    } catch (e) {
      if (e is String) rethrow;
      if (!estErreurReseau(e)) throw errMsg(e);
      await _loginHorsLigne(id, password);
    }
  }

  Future<void> _loginHorsLigne(String id, String password) async {
    final a = await LocalAuth.verify(id, password);
    if (a == null) {
      final connu = await LocalAuth.get(id);
      throw connu == null
          ? 'Pas de connexion internet. Connectez-vous d\'abord une fois en ligne sur cet appareil.'
          : 'Identifiants incorrects';
    }
    _identifiant = id;
    _mdpEnMemoire = password;
    state = AsyncData(
      AuthData(
        profil: a.profil,
        company: a.company,
        motif: _motifLocal(a.profil, a.company),
        offline: true,
      ),
    );
  }

  /// Vérifie auprès du serveur que le compte et l'abonnement sont toujours valides.
  /// En cas de problème, l'utilisateur est déconnecté et doit se reconnecter.
  Future<void> revalider() async {
    if (_occupe) return;
    final actuel = state.value;
    if (actuel?.profil == null) return;
    _occupe = true;
    try {
      if (!Repo.aUneSession) {
        if (_identifiant != null && _mdpEnMemoire != null) {
          await Repo.signIn(_identifiant!, _mdpEnMemoire!);
        } else {
          await _deconnecterDOffice(
            'Votre session a expiré. Reconnectez-vous.',
          );
          return;
        }
      }
      final c = await Repo.maSession();
      final data = await _depuisServeur(c);
      if (data.profil != null) {
        _mdpEnMemoire = null;
        state = AsyncData(data);
      }
    } catch (e) {
      if (estErreurReseau(e)) {
        final cur = state.value;
        if (cur != null && !cur.offline)
          state = AsyncData(cur.copyWith(offline: true));
      } else if (e is AuthException ||
          e is String ||
          (e is PostgrestException &&
              (e.code == 'PGRST301' ||
                  e.code == '401' ||
                  e.message.contains('JWT')))) {
        await _deconnecterDOffice(
          'Votre session n\'est plus valide. Reconnectez-vous.',
        );
      }
    } finally {
      _occupe = false;
    }
  }

  /// Déconnexion volontaire : le compte reste mémorisé pour un prochain accès hors ligne.
  Future<void> logout() async {
    try {
      await Repo.logout();
    } catch (_) {}
    _mdpEnMemoire = null;
    state = const AsyncData(AuthData());
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, AuthData>(
  AuthNotifier.new,
);

/// Profil connecté (null si personne).
final profilProvider = Provider<AsyncValue<Profil?>>(
  (ref) => ref.watch(authProvider).whenData((d) => d.profil),
);

/// Détails de session (entreprise, blocage, hors ligne).
final sessionProvider = Provider<AuthData>(
  (ref) => ref.watch(authProvider).value ?? const AuthData(),
);

// ── Synchronisation des opérations faites hors ligne ──────

class SyncState {
  const SyncState({
    this.pending = 0,
    this.rejected = const [],
    this.syncing = false,
  });
  final int pending;
  final List<OutboxOp> rejected;
  final bool syncing;
}

/// Envoie au serveur, dès que le réseau revient, ce qui a été fait sans internet.
class SyncNotifier extends Notifier<SyncState> {
  bool _busy = false;

  @override
  SyncState build() {
    void onChange() => _refresh();
    Outbox.changes.addListener(onChange);
    final conn = Connectivity().onConnectivityChanged.listen((r) {
      if (!r.contains(ConnectivityResult.none)) sync();
    });
    final timer = Timer.periodic(const Duration(seconds: 45), (_) => sync());
    // Billets à vérifier : copie mise à jour sur le téléphone à chaque changement et régulièrement.
    ref.listen(tickProvider, (_, _) => _majVerif());
    ref.listen(authProvider, (_, next) {
      _refresh();
      if (next.value?.profil != null) _majVerif();
      final d = next.value;
      if (d?.profil != null && !d!.offline) sync();
    });
    ref.onDispose(() {
      Outbox.changes.removeListener(onChange);
      conn.cancel();
      timer.cancel();
    });
    Future.microtask(() async {
      await _refresh();
      await sync();
    });
    return const SyncState();
  }

  Future<void> _majVerif() async {
    final me = ref.read(profilProvider).value;
    if (me == null || !me.peutVerifierBillets || !Repo.aUneSession) return;
    await Repo.rafraichirBilletsAVerifier();
  }

  Future<void> _refresh() async {
    final p = await Outbox.pending();
    final r = await Outbox.rejected();
    if (!ref.mounted) return;
    state = SyncState(pending: p.length, rejected: r, syncing: _busy);
  }

  Future<void> sync() async {
    if (_busy || !Repo.aUneSession) return;
    final me = ref.read(profilProvider).value;
    if (me == null || me.isSuper) return;
    if ((await Outbox.pending()).isEmpty) {
      await _majVerif();
      return;
    }
    _busy = true;
    await _refresh();
    try {
      final n = await Repo.synchroniser();
      if (n > 0 && ref.mounted) ref.read(tickProvider.notifier).bump();
      await _majVerif();
    } catch (_) {
      // réseau ou session : on réessaiera au prochain passage
    } finally {
      _busy = false;
      await _refresh();
    }
  }

  Future<void> oublier(String id) => Outbox.oublierRejet(id);
}

final syncProvider = NotifierProvider<SyncNotifier, SyncState>(
  SyncNotifier.new,
);

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
  for (final table in ['colis', 'historique_colis', 'tickets']) {
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: table,
      callback: (_) {
        debounce?.cancel();
        debounce = Timer(
          const Duration(milliseconds: 400),
          () => ref.read(tickProvider.notifier).bump(),
        );
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

final colisFilterProvider = NotifierProvider<ColisFilterNotifier, ColisFilter>(
  ColisFilterNotifier.new,
);

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

final historiqueProvider = FutureProvider.family<List<Historique>, int>((
  ref,
  id,
) {
  ref.watch(tickProvider);
  return Repo.historique(id);
});

final ticketsProvider = FutureProvider<List<Ticket>>((ref) {
  ref.watch(tickProvider);
  return Repo.listTickets();
});

final ticketProvider = FutureProvider.family<Ticket, int>((ref, id) {
  ref.watch(tickProvider);
  return Repo.getTicket(id);
});

final trajetsProvider = FutureProvider<List<Trajet>>((ref) {
  ref.watch(tickProvider);
  return Repo.trajets();
});

final smsConfigProvider = FutureProvider<SmsConfig?>((ref) => Repo.smsConfig());
final smsGlobalProvider = FutureProvider<SmsGlobal>((ref) => Repo.smsGlobal());
final smsEntreprisesProvider = FutureProvider<List<SmsEntreprise>>((ref) => Repo.smsEntreprises());

final garesProvider = FutureProvider<List<Gare>>((ref) => Repo.gares());
final profilsProvider = FutureProvider<List<Profil>>((ref) => Repo.profils());
final settingsProvider = FutureProvider<CompanySettings>(
  (ref) => Repo.settings(),
);

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
    DateTime.now().subtract(const Duration(days: 29)),
    DateTime.now(),
  );
  void set(RapportPeriode p) => state = p;
}

final rapportPeriodeProvider =
    NotifierProvider<RapportPeriodeNotifier, RapportPeriode>(
      RapportPeriodeNotifier.new,
    );

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

// ── Mise à jour de l'application (Android) ────────────────

/// Revérifie toutes les 20 minutes si une nouvelle version est en ligne (sans attendre un redémarrage).
final verifMiseAJourProvider = Provider<void>((ref) {
  final t = Timer.periodic(const Duration(minutes: 20), (_) => ref.invalidate(miseAJourProvider));
  ref.onDispose(t.cancel);
});

/// Version plus récente que celle installée, sinon null. Ne s'applique qu'à l'application Android.
final miseAJourProvider = FutureProvider<AppVersion?>((ref) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
  try {
    final installee =
        int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;
    final derniere = await Repo.derniereVersion();
    return (derniere != null && derniere.buildNumber > installee)
        ? derniere
        : null;
  } catch (_) {
    return null; // hors ligne ou erreur : on réessaiera plus tard
  }
});
