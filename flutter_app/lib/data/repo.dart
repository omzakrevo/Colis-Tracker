import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/identifiant.dart';
import 'models.dart';
import 'offline.dart';

SupabaseClient get _db => Supabase.instance.client;

class ColisFilter {
  const ColisFilter({
    this.search = '',
    this.statut,
    this.direction,
    this.debut,
    this.fin,
    this.ancienFirst = false,
  });

  final String search;
  final String? statut;

  /// 'envoi' | 'reception' | null — relatif à la gare de l'utilisateur.
  final String? direction;
  final DateTime? debut, fin;
  final bool ancienFirst;

  ColisFilter copyWith({
    String? search,
    Object? statut = _keep,
    Object? direction = _keep,
    Object? debut = _keep,
    Object? fin = _keep,
    bool? ancienFirst,
  }) => ColisFilter(
    search: search ?? this.search,
    statut: identical(statut, _keep) ? this.statut : statut as String?,
    direction: identical(direction, _keep)
        ? this.direction
        : direction as String?,
    debut: identical(debut, _keep) ? this.debut : debut as DateTime?,
    fin: identical(fin, _keep) ? this.fin : fin as DateTime?,
    ancienFirst: ancienFirst ?? this.ancienFirst,
  );

  int get activeCount =>
      [statut, direction, debut, fin].where((e) => e != null).length;

  static const _keep = Object();
}

class ScanResult {
  ScanResult(this.numero, this.ok, this.message);
  final String numero, message;
  final bool ok;
}

class Repo {
  // ── Auth ──────────────────────────────────────────────
  static const _delai = Duration(seconds: 12);

  /// Connexion à Supabase Auth (identifiant = téléphone ou nom d'utilisateur).
  static Future<void> signIn(String identifiant, String password) async {
    try {
      await _db.auth
          .signInWithPassword(
            email: emailDepuisIdentifiant(identifiant),
            password: password,
          )
          .timeout(_delai);
    } on AuthException catch (e) {
      if (estErreurReseau(e)) rethrow;
      throw 'Identifiants incorrects';
    }
  }

  static Future<void> logout() => _db.auth.signOut();

  static bool get aUneSession => _db.auth.currentSession != null;

  static String? get userId => _db.auth.currentUser?.id;

  /// Le compte et l'abonnement sont-ils toujours valides ? (appelle la base)
  static Future<SessionCheck> maSession() async {
    final r = await _db.rpc('ma_session').timeout(_delai);
    return SessionCheck.fromJson(Map<String, dynamic>.from(r as Map));
  }

  /// Inscription d'une nouvelle entreprise (sans être connecté) : elle reste en attente de validation.
  static Future<void> inscrireEntreprise({
    required String entreprise,
    required String ville,
    required String nomAdmin,
    required String telephone,
    required String password,
  }) async {
    await _db
        .rpc(
          'inscrire_entreprise',
          params: {
            'p_entreprise': entreprise,
            'p_ville': ville,
            'p_nom_admin': nomAdmin,
            'p_telephone': telephone,
            'p_password': password,
          },
        )
        .timeout(_delai);
  }

  // ── Mises à jour de l'application ─────────────────────
  /// Dernière version Android active (null s'il n'y en a pas).
  static Future<AppVersion?> derniereVersion() async {
    final r = await _db
        .from('app_versions')
        .select()
        .eq('plateforme', 'android')
        .eq('actif', true)
        .order('build_number', ascending: false)
        .limit(1)
        .maybeSingle()
        .timeout(_delai);
    return r == null ? null : AppVersion.fromJson(r);
  }

  /// Téléverse l'APK dans le stockage public « app-releases » et renvoie son lien (réservé au super administrateur).
  static Future<String> televerserApk(Uint8List octets, int buildNumber) async {
    final chemin = 'tchi-$buildNumber-${DateTime.now().millisecondsSinceEpoch}.apk';
    await _db.storage
        .from('app-releases')
        .uploadBinary(
          chemin,
          octets,
          fileOptions: const FileOptions(
            contentType: 'application/vnd.android.package-archive',
            upsert: true,
          ),
        );
    return _db.storage.from('app-releases').getPublicUrl(chemin);
  }

  static Future<List<AppVersion>> versions() async {
    final rows = await _db
        .from('app_versions')
        .select()
        .order('build_number', ascending: false);
    return rows.map(AppVersion.fromJson).toList();
  }

  static Future<void> publierVersion({
    required String versionName,
    required int buildNumber,
    required String apkUrl,
    String? notes,
    bool obligatoire = false,
  }) => _db.from('app_versions').insert({
    'version_name': versionName,
    'build_number': buildNumber,
    'apk_url': apkUrl,
    'notes': notes,
    'obligatoire': obligatoire,
  });

  static Future<void> majVersion(int id, Map<String, dynamic> data) =>
      _db.from('app_versions').update(data).eq('id', id);

  static Future<void> supprimerVersion(int id) =>
      _db.from('app_versions').delete().eq('id', id);

  // ── Super administrateur ──────────────────────────────
  static Future<List<Company>> entreprises() async {
    final rows = await _db
        .from('companies_detail')
        .select()
        .order('created_at', ascending: false);
    return rows.map(Company.fromJson).toList();
  }

  static Future<Map<String, dynamic>> saStats() async =>
      Map<String, dynamic>.from(await _db.rpc('sa_stats') as Map);

  /// Le super administrateur ouvre ou ferme le module Comptabilité d'une entreprise.
  static Future<void> definirModuleFinance(int id, bool actif) =>
      _db.rpc('entreprise_module_finance', params: {'p_company': id, 'p_actif': actif});

  static Future<void> definirAbonnement(
    int id,
    String statut,
    DateTime? fin, {
    String? plan,
    int? max,
  }) => _db.rpc(
    'sa_definir_abonnement',
    params: {
      'p_company': id,
      'p_statut': statut,
      'p_fin': fin == null ? null : _iso(fin),
      'p_plan': plan,
      'p_max': max,
    },
  );

  static Future<void> creerEntreprise({
    required String entreprise,
    required String ville,
    required String nomAdmin,
    required String telephone,
    required String password,
    DateTime? fin,
    String plan = 'standard',
    int max = 5,
  }) => _db.rpc(
    'sa_creer_entreprise',
    params: {
      'p_entreprise': entreprise,
      'p_ville': ville,
      'p_nom_admin': nomAdmin,
      'p_telephone': telephone,
      'p_password': password,
      'p_fin': fin == null ? null : _iso(fin),
      'p_plan': plan,
      'p_max': max,
    },
  );

  // ── Lecture avec mémoire locale ───────────────────────
  static const _delaiLecture = Duration(seconds: 10);
  static const _delaiEcriture = Duration(seconds: 15);

  /// Lit sur le serveur et mémorise le résultat ; sans réseau, renvoie la dernière copie mémorisée.
  static Future<T> _lire<T>(
    String cle,
    Future<T> Function() serveur,
    Object? Function(T) encoder,
    T Function(Object) decoder,
  ) async {
    try {
      final v = await serveur().timeout(_delaiLecture);
      await LocalStore.write(cle, encoder(v));
      return v;
    } catch (e) {
      if (!estErreurReseau(e)) rethrow;
      final c = await LocalStore.read(cle);
      if (c == null) rethrow;
      return decoder(c);
    }
  }

  static List<Map<String, dynamic>> _maps(Object o) => [
    for (final e in o as List) Map<String, dynamic>.from(e as Map),
  ];

  static Future<Map<int, String>> _garesNoms() async {
    final c = await LocalStore.read('gares');
    if (c == null) return {};
    return {for (final g in _maps(c).map(Gare.fromJson)) g.id: g.nom};
  }

  // ── Colis ─────────────────────────────────────────────
  static Future<List<Colis>> listColis(ColisFilter f, {int? maGareId}) async {
    List<Colis> base;
    try {
      base = await _listColisServeur(f, maGareId).timeout(_delaiLecture);
      final sansFiltre =
          f.activeCount == 0 && f.search.trim().isEmpty && !f.ancienFirst;
      if (sansFiltre) {
        await LocalStore.write(
          'colis_list',
          base.map((c) => c.toJson(light: true)).toList(),
        );
      }
    } catch (e) {
      if (!estErreurReseau(e)) rethrow;
      final c = await LocalStore.read('colis_list');
      if (c == null) rethrow;
      base = Outbox.filtrer(
        _maps(c).map(Colis.fromJson).toList(),
        f,
        maGareId: maGareId,
      );
    }
    final ops = await Outbox.pending();
    if (ops.isEmpty) return base;
    final avec = Outbox.appliquer(base, ops, garesNoms: await _garesNoms());
    return Outbox.filtrer(avec, f, maGareId: maGareId);
  }

  static Future<List<Colis>> _listColisServeur(
    ColisFilter f,
    int? maGareId,
  ) async {
    var q = _db.from('colis_detail').select();
    if (f.statut != null) q = q.eq('statut', f.statut!);
    if (f.debut != null) q = q.gte('date_envoi', _iso(f.debut!));
    if (f.fin != null) q = q.lte('date_envoi', _iso(f.fin!));
    if (maGareId != null && f.direction == 'envoi') {
      q = q.eq('gare_depart_id', maGareId);
    } else if (maGareId != null && f.direction == 'reception') {
      q = q.eq('gare_arrivee_id', maGareId);
    }
    final s = f.search.trim().replaceAll(RegExp(r'[,()%]'), ' ');
    if (s.isNotEmpty) {
      q = q.or(
        'numero.ilike.%$s%,expediteur_nom.ilike.%$s%,'
        'destinataire_nom.ilike.%$s%,expediteur_telephone.ilike.%$s%,'
        'destinataire_telephone.ilike.%$s%',
      );
    }
    final rows = await q
        .order('created_at', ascending: f.ancienFirst)
        .limit(500);
    return rows.map(Colis.fromJson).toList();
  }

  static Future<Colis> getColis(int id) async {
    if (id < 0) {
      final c = await _colisLocalParId(id);
      if (c != null) return c;
      // Déjà envoyé au serveur depuis : on retrouve son vrai identifiant.
      final reel = await Outbox.idReelPourLocal(id);
      if (reel != null) return getColis(reel);
      throw 'Colis introuvable';
    }
    Colis c;
    try {
      c = Colis.fromJson(
        await _db
            .from('colis_detail')
            .select()
            .eq('id', id)
            .single()
            .timeout(_delaiLecture),
      );
      await LocalStore.writeCapped('colis', id, c.toJson());
    } catch (e) {
      if (!estErreurReseau(e)) rethrow;
      final copie = await LocalStore.readCapped('colis', id);
      if (copie != null) {
        c = Colis.fromJson(Map<String, dynamic>.from(copie as Map));
      } else {
        final liste = await LocalStore.read('colis_list');
        final trouve = liste == null
            ? null
            : _maps(liste)
                  .map(Colis.fromJson)
                  .where((x) => x.id == id)
                  .firstOrNull;
        if (trouve == null) rethrow;
        c = trouve;
      }
    }
    final ops = await Outbox.pending();
    return ops.isEmpty ? c : Outbox.appliquer([c], ops).first;
  }

  /// Colis créé hors ligne et pas encore envoyé.
  static Future<Colis?> _colisLocalParId(int id) async {
    final ops = await Outbox.pending();
    final tous = Outbox.appliquer(const [], ops, garesNoms: await _garesNoms());
    return tous.where((c) => c.id == id).firstOrNull;
  }

  static Future<List<Colis>> _toutesLesCopies() async {
    final liste = await LocalStore.read('colis_list');
    return liste == null ? [] : _maps(liste).map(Colis.fromJson).toList();
  }

  static Future<Colis?> getColisByNumero(String numero) async {
    final n = numero.trim().toUpperCase();
    try {
      if (n.startsWith('LOC-')) {
        // Étiquette imprimée hors ligne : le serveur conserve le numéro provisoire.
        final r = await _db
            .from('colis')
            .select('id')
            .eq('numero_provisoire', n)
            .maybeSingle()
            .timeout(_delaiLecture);
        if (r != null) return await getColis(r['id'] as int);
      } else {
        final r = await _db
            .from('colis_detail')
            .select()
            .eq('numero', n)
            .maybeSingle()
            .timeout(_delaiLecture);
        if (r != null) {
          final c = Colis.fromJson(r);
          final ops = await Outbox.pending();
          return ops.isEmpty ? c : Outbox.appliquer([c], ops).first;
        }
      }
    } catch (e) {
      if (!estErreurReseau(e)) rethrow;
    }
    // Sans réseau (ou colis créé hors ligne) : copies locales + opérations en attente.
    final ops = await Outbox.pending();
    final locaux = Outbox.appliquer(
      await _toutesLesCopies(),
      ops,
      garesNoms: await _garesNoms(),
    );
    return locaux.where((c) => c.numero.toUpperCase() == n).firstOrNull;
  }

  /// Informations minimales d'un colis pour le scan (le barragiste n'a pas accès aux données des clients).
  static Future<Colis?> infoScan(String numero) async {
    final rows =
        await _db
                .rpc('colis_scan_info', params: {'p_numero': numero})
                .timeout(_delaiLecture)
            as List;
    if (rows.isEmpty) return null;
    final m = Map<String, dynamic>.from(rows.first as Map);
    final now = DateTime.now();
    return Colis(
      id: 0,
      numero: m['numero'] as String,
      expediteurNom: '',
      expediteurTelephone: '',
      destinataireNom: '',
      destinataireTelephone: '',
      gareDepartId: 0,
      gareArriveeId: 0,
      gareArriveeNom: m['gare_arrivee_nom'] as String?,
      description: '',
      nombre: 1,
      prix: 0,
      statut: m['statut'] as String,
      dateEnvoi: now,
      createdAt: now,
    );
  }

  static Future<List<Historique>> historique(int colisId) async {
    List<Historique> base = [];
    if (colisId >= 0) {
      try {
        final rows = await _db
            .from('historique_detail')
            .select()
            .eq('colis_id', colisId)
            .order('date_changement')
            .timeout(_delaiLecture);
        base = rows.map(Historique.fromJson).toList();
        await LocalStore.writeCapped(
          'histo',
          colisId,
          base.map((h) => h.toJson()).toList(),
        );
      } catch (e) {
        if (!estErreurReseau(e)) rethrow;
        final c = await LocalStore.readCapped('histo', colisId);
        if (c != null) base = _maps(c).map(Historique.fromJson).toList();
      }
    }
    final ops = await Outbox.pending();
    if (ops.isEmpty) return base;
    Colis? colis;
    try {
      colis = await getColis(colisId);
    } catch (_) {}
    return Outbox.historiqueLocal(colis, base, ops);
  }

  /// Enregistre un colis. Sans internet, il est gardé sur l'appareil avec un numéro provisoire
  /// (LOC-…) et envoyé automatiquement au retour du réseau (alors `enAttente` vaut vrai).
  static Future<Colis> creerColis(
    Map<String, dynamic> data, {
    String? agentNom,
  }) async {
    final ref = Outbox.nouvelleRef();
    final payload = {
      ...data,
      'client_ref': ref,
      'numero_provisoire': Outbox.provisoire(ref),
    };
    try {
      return await _envoyerCreation(payload).timeout(_delaiEcriture);
    } catch (e) {
      if (!estErreurReseau(e)) rethrow;
    }
    final op = await Outbox.ajouter('creer', {
      ...payload,
      '_agent_nom': agentNom,
    });
    return Outbox.colisLocal(
      op.payload,
      garesNoms: await _garesNoms(),
      agentNom: agentNom,
    );
  }

  /// Insère le colis ; si une tentative précédente est déjà passée (réponse perdue), la retrouve au lieu de créer un doublon.
  static Future<Colis> _envoyerCreation(Map<String, dynamic> payload) async {
    final data = Map<String, dynamic>.from(payload)..remove('_agent_nom');
    int id;
    try {
      final r = await _db.from('colis').insert(data).select('id').single();
      id = r['id'] as int;
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow;
      final r = await _db
          .from('colis')
          .select('id')
          .eq('client_ref', data['client_ref'] as String)
          .single();
      id = r['id'] as int;
    }
    await Outbox.memoriserIdReel(data['client_ref'] as String, id);
    return Colis.fromJson(
      await _db.from('colis_detail').select().eq('id', id).single(),
    );
  }

  // ── Billets de transport ──────────────────────────────
  static Future<List<Ticket>> listTickets() async {
    final base = await _lire<List<Ticket>>(
      'tickets_list',
      () async =>
          (await _db
                  .from('tickets_detail')
                  .select()
                  .order('created_at', ascending: false)
                  .limit(300))
              .map(Ticket.fromJson)
              .toList(),
      (l) => l.map((t) => t.toJson()).toList(),
      (o) => _maps(o).map(Ticket.fromJson).toList(),
    );
    final ops = await Outbox.pending();
    if (!ops.any((o) => o.type == 'ticket')) return base;
    return Outbox.appliquerTickets(base, ops, garesNoms: await _garesNoms());
  }

  static Future<Ticket> getTicket(int id) async {
    if (id < 0) {
      final ops = await Outbox.pending();
      final t = Outbox.appliquerTickets(
        const [],
        ops,
        garesNoms: await _garesNoms(),
      ).where((t) => t.id == id).firstOrNull;
      if (t != null) return t;
      final reel = await Outbox.idReelPourLocal(id);
      if (reel == null) throw 'Billet introuvable';
      id = reel;
    }
    try {
      return Ticket.fromJson(
        await _db
            .from('tickets_detail')
            .select()
            .eq('id', id)
            .single()
            .timeout(_delaiLecture),
      );
    } catch (e) {
      if (!estErreurReseau(e)) rethrow;
      final copie = (await LocalStore.read('tickets_list'));
      final t = copie == null
          ? null
          : _maps(copie).map(Ticket.fromJson).where((t) => t.id == id).firstOrNull;
      if (t == null) rethrow;
      return t;
    }
  }

  /// Vend un billet. Sans internet, il est gardé sur l'appareil (numéro provisoire LOC-…) puis envoyé au retour du réseau.
  static Future<Ticket> creerTicket(
    Map<String, dynamic> data, {
    String? vendeurNom,
    int? siegeSecours,
  }) async {
    final ref = Outbox.nouvelleRef();
    final payload = {
      ...data,
      'client_ref': ref,
      'numero_provisoire': Outbox.provisoire(ref),
    };
    try {
      return await _envoyerTicket(payload).timeout(_delaiEcriture);
    } catch (e) {
      if (!estErreurReseau(e)) rethrow;
    }
    // Hors ligne : le serveur ne peut pas attribuer la place, on garde celle proposée sur le téléphone.
    final op = await Outbox.ajouter('ticket', {
      ...payload,
      if (payload['siege'] == null && siegeSecours != null) 'siege': '$siegeSecours',
      '_vendeur_nom': vendeurNom,
    });
    return Outbox.ticketLocal(
      op.payload,
      garesNoms: await _garesNoms(),
      vendeurNom: vendeurNom,
    );
  }

  static Future<Ticket> _envoyerTicket(Map<String, dynamic> payload) async {
    final data = Map<String, dynamic>.from(payload)
      ..remove('_vendeur_nom')
      ..remove('numero_provisoire');
    int id;
    try {
      final r = await _db.from('tickets').insert(data).select('id').single();
      id = r['id'] as int;
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow;
      final r = await _db
          .from('tickets')
          .select('id')
          .eq('client_ref', data['client_ref'] as String)
          .single();
      id = r['id'] as int;
    }
    await Outbox.memoriserIdReel(data['client_ref'] as String, id);
    return Ticket.fromJson(
      await _db.from('tickets_detail').select().eq('id', id).single(),
    );
  }

  /// Places d'un voyage. Sans internet (ou serveur pas à jour), calcul à partir des billets gardés sur l'appareil.
  static Future<PlacesVoyage> placesVoyage({
    required int depart,
    required int arrivee,
    required DateTime date,
    String? heure,
  }) async {
    final h = (heure ?? '').trim();
    try {
      final rows = await _db
          .rpc('places_prises', params: {
            'p_depart': depart,
            'p_arrivee': arrivee,
            'p_date': _iso(date),
            'p_heure': h.isEmpty ? null : h,
          })
          .timeout(const Duration(seconds: 6));
      final l = _maps(rows);
      if (l.isNotEmpty) {
        return PlacesVoyage(
          (l.first['capacite'] as num?)?.toInt() ?? 50,
          {for (final p in (l.first['prises'] as List? ?? const [])) (p as num).toInt()},
        );
      }
    } catch (_) {
      // repli ci-dessous
    }
    var capacite = 50;
    try {
      capacite = (await trajets())
          .where((t) => t.gareDepartId == depart && t.gareArriveeId == arrivee)
          .map((t) => t.capacite)
          .firstOrNull ?? 50;
    } catch (_) {}
    final prises = <int>{};
    try {
      for (final t in await listTickets()) {
        if (t.annule || t.gareDepartId != depart || t.gareArriveeId != arrivee) continue;
        if (_iso(t.dateVoyage) != _iso(date) || (t.heureDepart ?? '').trim() != h) continue;
        final n = int.tryParse((t.siege ?? '').trim());
        if (n != null) prises.add(n);
      }
    } catch (_) {}
    return PlacesVoyage(capacite, prises);
  }

  static Future<void> annulerTicket(int id) =>
      _db.rpc('annuler_ticket', params: {'p_id': id});

  /// Clients déjà connus dont le nom ou le téléphone commence par ce qui est tapé (colis et billets).
  /// Sans internet : recherche dans les colis et billets gardés sur l'appareil.
  static Future<List<ClientSuggestion>> clientsSuggestions(
    String terme,
  ) async {
    final t = terme.trim();
    if (t.length < 2) return [];
    try {
      final rows = await _db
          .rpc('clients_suggestions', params: {'p_terme': t})
          .timeout(const Duration(seconds: 6));
      return _maps(rows).map(ClientSuggestion.fromJson).toList();
    } catch (e) {
      if (!estErreurReseau(e)) rethrow;
    }
    final chiffres = t.replaceAll(RegExp(r'[^0-9]'), '');
    final minuscule = t.toLowerCase();
    final trouves = <String, ClientSuggestion>{};
    void voir(String nom, String tel, {bool colis = false}) {
      final d = tel.replaceAll(RegExp(r'[^0-9]'), '');
      if (d.length < 6 || nom.trim().isEmpty) return;
      final ok =
          (chiffres.isNotEmpty && d.contains(chiffres)) ||
          nom.toLowerCase().contains(minuscule);
      if (!ok || trouves.length >= 8 && !trouves.containsKey(d)) return;
      final avant = trouves[d];
      trouves[d] = ClientSuggestion(
        nom: nom.trim(),
        telephone: d,
        nbColis: (avant?.nbColis ?? 0) + (colis ? 1 : 0),
        nbTickets: (avant?.nbTickets ?? 0) + (colis ? 0 : 1),
        dernierDepartId: avant?.dernierDepartId,
        dernierArriveeId: avant?.dernierArriveeId,
      );
    }

    for (final c in await _toutesLesCopies()) {
      voir(c.expediteurNom, c.expediteurTelephone, colis: true);
      voir(c.destinataireNom, c.destinataireTelephone, colis: true);
    }
    final copieBillets = await LocalStore.read('tickets_list');
    if (copieBillets != null) {
      for (final b in _maps(copieBillets).map(Ticket.fromJson)) {
        voir(b.clientNom, b.clientTelephone);
      }
    }
    return trouves.values.toList();
  }

  // ── Trajets (prix et horaires) ────────────────────────
  static Future<List<Trajet>> trajets() => _lire(
    'trajets',
    () async =>
        (await _db.from('trajets').select().order('gare_depart_id'))
            .map(Trajet.fromJson)
            .toList(),
    (l) => l.map((t) => t.toJson()).toList(),
    (o) => _maps(o).map(Trajet.fromJson).toList(),
  );

  static Future<void> enregistrerTrajet(
    int? id,
    Map<String, dynamic> data,
  ) async {
    if (id == null) {
      await _db.from('trajets').insert(data);
    } else {
      await _db.from('trajets').update(data).eq('id', id);
    }
  }

  static Future<void> supprimerTrajet(int id) =>
      _db.from('trajets').delete().eq('id', id);

  // ── Vérification des billets (utilisable sans internet) ──
  static const _kVerif = 'billets_verif';

  /// Recopie sur le téléphone les billets récents et à venir, pour pouvoir les vérifier sans internet.
  static Future<void> rafraichirBilletsAVerifier() async {
    try {
      final rows = await _db
          .rpc('billets_a_verifier')
          .timeout(const Duration(seconds: 12));
      final locales = await _verifsLocales();
      final liste = [
        for (final m in _maps(rows))
          BilletVerif.fromJson(m).avecVerifications(
            (m['nb_verifications'] as num).toInt() +
                (locales[(m['numero'] as String)] ?? 0),
          ),
      ];
      await LocalStore.write(_kVerif, liste.map((b) => b.toJson()).toList());
    } catch (_) {
      // hors ligne ou rôle sans accès : on garde la copie existante
    }
  }

  /// Nombre de vérifications faites hors ligne, pas encore envoyées, par numéro de billet.
  static Future<Map<String, int>> _verifsLocales() async {
    final n = <String, int>{};
    for (final o in await Outbox.pending()) {
      if (o.type == 'verif') {
        final num = o.payload['numero'] as String;
        n[num] = (n[num] ?? 0) + 1;
      }
    }
    return n;
  }

  static Future<List<BilletVerif>> _billetsLocaux() async {
    final c = await LocalStore.read(_kVerif);
    final liste = c == null
        ? <BilletVerif>[]
        : _maps(c).map(BilletVerif.fromJson).toList();
    // Billets vendus sur cet appareil et pas encore envoyés : vérifiables aussi.
    final ops = await Outbox.pending();
    for (final t in Outbox.appliquerTickets(
      const [],
      ops,
      garesNoms: await _garesNoms(),
    )) {
      liste.add(
        BilletVerif(
          id: t.id,
          numero: t.numero,
          clientNom: t.clientNom,
          clientTelephone: t.clientTelephone,
          gareDepartNom: t.gareDepartNom,
          gareArriveeNom: t.gareArriveeNom,
          dateVoyage: t.dateVoyage,
          heureDepart: t.heureDepart,
          siege: t.siege,
          statut: 'emis',
        ),
      );
    }
    return liste;
  }

  /// Vérifie un billet à l'embarquement (autant de fois que nécessaire). Sans internet, la vérification
  /// se fait dans la copie gardée sur le téléphone et sera enregistrée au retour du réseau.
  static Future<VerifResultat> verifierBillet(String numero) async {
    final num = numero.trim().toUpperCase();
    final ref = Outbox.nouvelleRef();
    try {
      final rows = await _db
          .rpc(
            'verifier_billet',
            params: {'p_numero': num, 'p_ref': ref},
          )
          .timeout(const Duration(seconds: 8));
      final l = _maps(rows);
      if (l.isEmpty) {
        // Un billet vendu hors ligne sur cet appareil n'est pas encore connu du serveur.
        final local = (await _billetsLocaux())
            .where((b) => b.numero == num && b.id < 0)
            .firstOrNull;
        if (local != null) return await _verifLocale(local, num);
        return VerifResultat(message: 'Billet introuvable');
      }
      final b = BilletVerif.fromJson(l.first);
      await _memoriserVerif(b);
      return VerifResultat(billet: b);
    } catch (e) {
      if (!estErreurReseau(e)) rethrow;
    }
    final local = (await _billetsLocaux())
        .where((b) => b.numero == num)
        .firstOrNull;
    if (local == null) {
      return VerifResultat(
        message:
            'Billet introuvable dans la mémoire du téléphone. Sans internet, seuls les billets déjà synchronisés peuvent être vérifiés.',
        horsLigne: true,
      );
    }
    return _verifLocale(local, num);
  }

  static Future<VerifResultat> _verifLocale(BilletVerif local, String num) async {
    await Outbox.ajouter('verif', {
      'numero': num,
      'ref': Outbox.nouvelleRef(),
      'at': DateTime.now().toUtc().toIso8601String(),
    });
    final b = local.avecVerifications(local.nbVerifications + 1);
    await _memoriserVerif(b);
    return VerifResultat(billet: b, horsLigne: true);
  }

  static Future<void> _memoriserVerif(BilletVerif b) async {
    final c = await LocalStore.read(_kVerif);
    if (c == null) return;
    final liste = _maps(c).map(BilletVerif.fromJson).toList();
    final i = liste.indexWhere((x) => x.numero == b.numero);
    if (i < 0) return;
    liste[i] = b;
    await LocalStore.write(_kVerif, liste.map((x) => x.toJson()).toList());
  }

  // ── SMS (SMSBUS) ──────────────────────────────────────
  static Future<SmsConfig?> smsConfig() async {
    // Colonnes listées une à une : le mot de passe n'est pas lisible, « select * » serait refusé.
    const base =
        'company_id, actif, username, sender, port, indicatif, sms_colis_envoi, sms_colis_arrive, sms_colis_retire, '
        'sms_billet, tpl_envoi_exp, tpl_envoi_dest, tpl_arrive, tpl_retire, tpl_billet, terminal_id, solde_texte, '
        'solde_le, source, bloque';
    List<Map<String, dynamic>> rows;
    try {
      rows = await _db.from('sms_settings').select('$base, rapport_actif, rapport_heure, rapport_numeros');
    } on PostgrestException catch (e) {
      // Colonnes du rapport quotidien absentes : serveur pas encore à jour (migration 26).
      if (!(e.code == '42703' || e.message.contains('rapport_'))) rethrow;
      rows = await _db.from('sms_settings').select(base);
    }
    return rows.isEmpty ? null : SmsConfig.fromJson(rows.first);
  }

  /// Envoie tout de suite le rapport du jour aux numéros choisis (essai).
  static Future<int> testerRapportSms() async {
    final r = await _db.rpc('sms_rapport_tester');
    return (r as num?)?.toInt() ?? 0;
  }

  static Future<void> enregistrerSms(Map<String, dynamic> data) =>
      _db.rpc('sms_enregistrer', params: {'p': data});

  static Future<List<SmsLigne>> smsJournal() async {
    try {
      await _db.rpc('sms_rafraichir');
    } catch (_) {}
    final rows = await _db
        .from('sms_outbox')
        .select()
        .order('created_at', ascending: false)
        .limit(100);
    return rows.map(SmsLigne.fromJson).toList();
  }

  /// Demande le solde à SMSBUS puis le lit (la réponse arrive quelques secondes plus tard).
  static Future<({String? solde, DateTime? le})> soldeSms() async {
    await _db.rpc('sms_solde_demander');
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      final rows = await _db.rpc('sms_solde_lire');
      final l = _maps(rows);
      final m = l.isEmpty ? null : l.first;
      final le = m?['mis_a_jour'] == null
          ? null
          : DateTime.parse(m!['mis_a_jour'] as String).toLocal();
      // Un solde reçu il y a moins de 20 s est celui qu'on vient de demander.
      if (le != null && DateTime.now().difference(le).inSeconds < 20) {
        return (solde: m!['solde'] as String?, le: le);
      }
    }
    throw 'SMSBUS n\'a pas répondu. Vérifiez l\'identifiant Terminal Web et le port.';
  }

  static Future<SmsGlobal> smsGlobal() async {
    final l = _maps(await _db.rpc('sms_global_lire'));
    return l.isEmpty ? SmsGlobal() : SmsGlobal.fromJson(l.first);
  }

  static Future<void> enregistrerSmsGlobal(Map<String, dynamic> data) =>
      _db.rpc('sms_global_enregistrer', params: {'p': data});

  static Future<void> testerSmsGlobal(String telephone) =>
      _db.rpc('sms_global_tester', params: {'p_tel': telephone});

  /// Demande le solde du compte de la plateforme puis le lit.
  static Future<({String? solde, DateTime? le})> soldeSmsGlobal() async {
    await _db.rpc('sms_global_solde_demander');
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      final g = await smsGlobal();
      final le = g.soldeLe;
      if (le != null && DateTime.now().difference(le).inSeconds < 20) return (solde: g.soldeTexte, le: le);
    }
    throw 'SMSBUS n\'a pas répondu. Vérifiez l\'identifiant Terminal Web et le port.';
  }

  static Future<List<SmsEntreprise>> smsEntreprises() async =>
      _maps(await _db.rpc('sms_entreprises')).map(SmsEntreprise.fromJson).toList();

  static Future<void> reglerSmsEntreprise(int companyId, {bool? bloque, String? source}) =>
      _db.rpc('sms_entreprise_regler', params: {'p_company': companyId, 'p_bloque': bloque, 'p_source': source});

  static Future<void> renvoyerSms(int id) =>
      _db.rpc('sms_renvoyer', params: {'p_id': id});

  static Future<void> testerSms(String telephone) =>
      _db.rpc('sms_tester', params: {'p_tel': telephone});

  /// Renvoie `true` si le serveur a pris en compte le changement, `false` s'il est en attente d'envoi.
  static Future<bool> changerStatut(
    int id,
    String statut,
    String? notes,
  ) async {
    final cible = await _cible(id);
    if (id >= 0) {
      try {
        await _rpcStatut(id, statut, notes).timeout(_delaiEcriture);
        return true;
      } catch (e) {
        if (!estErreurReseau(e)) rethrow;
      }
    }
    await Outbox.ajouter('statut', {
      ...cible,
      'statut': statut,
      'notes': notes,
    });
    return false;
  }

  static Future<void> _rpcStatut(int id, String statut, String? notes) =>
      _db.rpc(
        'changer_statut',
        params: {'p_id': id, 'p_statut': statut, 'p_notes': notes},
      );

  /// Désigne le colis visé par une opération : vrai identifiant, ou référence s'il n'existe encore que sur l'appareil.
  static Future<Map<String, dynamic>> _cible(int id) async {
    if (id >= 0) return {'id': id};
    final ref = await Outbox.refPourId(id);
    if (ref == null) throw 'Colis introuvable';
    return {'ref': ref};
  }

  /// Embarquement / déchargement de plusieurs colis d'un coup (scan rapide).
  /// Sans internet, le lot est mis en attente et les résultats sont marqués « en attente d'envoi ».
  static Future<List<ScanResult>> scanLot(
    String mode,
    List<String> numeros,
  ) async {
    try {
      return await _scanLotServeur(mode, numeros).timeout(_delaiEcriture);
    } catch (e) {
      if (!estErreurReseau(e)) rethrow;
    }
    await Outbox.ajouter('scan', {'mode': mode, 'numeros': numeros});
    return [
      for (final n in numeros)
        ScanResult(
          n,
          true,
          mode == 'embarquement'
              ? 'Embarqué — en attente d\'envoi'
              : 'Déchargé — en attente d\'envoi',
        ),
    ];
  }

  static Future<List<ScanResult>> _scanLotServeur(
    String mode,
    List<String> numeros,
  ) async {
    final rows = await _db.rpc(
      'scan_lot',
      params: {'p_mode': mode, 'p_numeros': numeros},
    ) as List;
    return rows
        .map(
          (r) => ScanResult(
            r['r_numero'] as String,
            r['r_ok'] as bool,
            r['r_message'] as String,
          ),
        )
        .toList();
  }

  /// Renvoie `true` si le retrait est enregistré sur le serveur, `false` s'il est en attente d'envoi.
  static Future<bool> retirer(
    int id, {
    required String nom,
    required String telephone,
    String? piece,
    String? signature,
  }) async {
    final cible = await _cible(id);
    if (id >= 0) {
      try {
        await _rpcRetrait(
          id,
          nom,
          telephone,
          piece,
          signature,
        ).timeout(_delaiEcriture);
        return true;
      } catch (e) {
        if (!estErreurReseau(e)) rethrow;
      }
    }
    await Outbox.ajouter('retirer', {
      ...cible,
      'nom': nom,
      'telephone': telephone,
      'piece': piece,
      'signature': signature,
    });
    return false;
  }

  static Future<void> _rpcRetrait(
    int id,
    String nom,
    String telephone,
    String? piece,
    String? signature,
  ) => _db.rpc(
    'retirer_colis',
    params: {
      'p_id': id,
      'p_nom': nom,
      'p_telephone': telephone,
      'p_piece': piece,
      'p_signature': signature,
    },
  );

  // ── Synchronisation des opérations faites hors ligne ──
  static bool _erreurSession(Object e) =>
      e is AuthException ||
      (e is PostgrestException &&
          (e.code == 'PGRST301' ||
              e.code == '401' ||
              e.message.contains('JWT')));

  static String _message(Object e) => e is PostgrestException
      ? e.message
      : e is String
      ? e
      : e.toString().replaceFirst('Exception: ', '');

  /// Envoie dans l'ordre les opérations en attente. S'arrête au premier problème de réseau ou de session
  /// (elles seront renvoyées plus tard) ; une opération refusée par le serveur est mise de côté avec son motif.
  /// Renvoie le nombre d'opérations traitées.
  static Future<int> synchroniser() async {
    var faits = 0;
    while (true) {
      final ops = await Outbox.pending();
      if (ops.isEmpty) return faits;
      final op = ops.first;
      try {
        await _executer(op);
        await Outbox.terminer(op.id);
        faits++;
      } catch (e) {
        if (estErreurReseau(e) || _erreurSession(e)) return faits;
        await Outbox.rejeter(op, _message(e));
        faits++;
      }
    }
  }

  static Future<int> _idDe(Map<String, dynamic> p) async {
    final id = (p['id'] as num?)?.toInt();
    if (id != null) return id;
    final reel = await Outbox.idReel(p['ref'] as String);
    if (reel == null) throw 'Le colis n\'a pas pu être créé';
    return reel;
  }

  static Future<void> _executer(OutboxOp op) async {
    final p = op.payload;
    switch (op.type) {
      case 'creer':
        await _envoyerCreation(p);
      case 'ticket':
        await _envoyerTicket(p);
      case 'verif':
        final rows = await _db.rpc(
          'verifier_billet',
          params: {
            'p_numero': p['numero'],
            'p_ref': p['ref'],
            'p_at': p['at'],
          },
        );
        if (_maps(rows).isEmpty) throw 'Billet ${p['numero']} introuvable';
      case 'statut':
        await _rpcStatut(
          await _idDe(p),
          p['statut'] as String,
          p['notes'] as String?,
        );
      case 'retirer':
        await _rpcRetrait(
          await _idDe(p),
          p['nom'] as String,
          p['telephone'] as String,
          p['piece'] as String?,
          p['signature'] as String?,
        );
      case 'scan':
        final res = await _scanLotServeur(
          p['mode'] as String,
          List<String>.from(p['numeros'] as List),
        );
        for (final r in res.where((r) => !r.ok)) {
          await Outbox.rejeter(
            OutboxOp(
              id: Outbox.nouvelleRef(),
              type: 'scan',
              payload: {
                'mode': p['mode'],
                'numeros': [r.numero],
              },
              createdAt: op.createdAt,
            ),
            '${r.numero} : ${r.message}',
          );
        }
      default:
        throw 'Opération inconnue';
    }
  }

  // ── Gares ─────────────────────────────────────────────
  static Future<List<Gare>> gares() => _lire(
    'gares',
    () async =>
        (await _db.from('gares').select().order('nom'))
            .map(Gare.fromJson)
            .toList(),
    (l) => l.map((g) => g.toJson()).toList(),
    (o) => _maps(o).map(Gare.fromJson).toList(),
  );

  static Future<void> saveGare(int? id, Map<String, dynamic> data) async {
    if (id == null) {
      await _db.from('gares').insert(data);
    } else {
      await _db.from('gares').update(data).eq('id', id);
    }
  }

  static Future<void> deleteGare(int id) =>
      _db.from('gares').delete().eq('id', id);

  // ── Utilisateurs ──────────────────────────────────────
  static Future<List<Profil>> profils() => _lire(
    'profils',
    () async =>
        (await _db.from('vip_profiles').select().order('nom'))
            .map(Profil.fromJson)
            .toList(),
    (l) => l.map((p) => p.toJson()).toList(),
    (o) => _maps(o).map(Profil.fromJson).toList(),
  );

  static Future<void> creerUtilisateur({
    required String username,
    required String password,
    required String nom,
    required String role,
    int? gareId,
    String? telephone,
  }) => _db.rpc(
    'admin_creer_utilisateur',
    params: {
      'p_username': username,
      'p_password': password,
      'p_nom': nom,
      'p_role': role,
      'p_gare_id': gareId,
      'p_telephone': telephone,
    },
  );

  static Future<void> majProfil(String id, Map<String, dynamic> data) =>
      _db.from('vip_profiles').update(data).eq('id', id);

  static Future<void> changerMotDePasse(String id, String password) => _db.rpc(
    'admin_changer_mot_de_passe',
    params: {'p_user': id, 'p_password': password},
  );

  // ── Paramètres société ────────────────────────────────
  static Future<CompanySettings> settings() => _lire(
    'settings',
    () async {
      final r = await _db
          .from('company_settings')
          .select()
          .limit(1)
          .maybeSingle();
      return r == null ? CompanySettings.defaults : CompanySettings.fromJson(r);
    },
    (c) => c.toJson(),
    (o) => CompanySettings.fromJson(Map<String, dynamic>.from(o as Map)),
  );

  static Future<void> saveSettings(int companyId, Map<String, dynamic> data) =>
      _db.from('company_settings').update(data).eq('company_id', companyId);

  // ── Rapports ──────────────────────────────────────────
  static Future<DashboardStats> dashboard() => _lire(
    'dashboard',
    () async => DashboardStats(
      Map<String, dynamic>.from(await _db.rpc('dashboard_stats') as Map),
    ),
    (d) => d.m,
    (o) => DashboardStats(Map<String, dynamic>.from(o as Map)),
  );

  /// Résultat brut d'une fonction de rapport (liste de lignes), avec copie locale pour le hors ligne.
  static Future<List<Map<String, dynamic>>> _rapport(
    String cle,
    String fonction, [
    Map<String, dynamic>? params,
  ]) => _lire<List<Map<String, dynamic>>>(
    cle,
    () async => _maps(await _db.rpc(fonction, params: params) as List),
    (l) => l,
    _maps,
  );

  static Future<List<JourStat>> colisParJour(
    DateTime? debut,
    DateTime? fin,
  ) async {
    final d = debut == null ? '' : _iso(debut);
    final f = fin == null ? '' : _iso(fin);
    final rows = await _rapport('rapport_jour_${d}_$f', 'colis_par_jour', {
      'p_debut': debut == null ? null : d,
      'p_fin': fin == null ? null : f,
    });
    return rows
        .map(
          (r) => JourStat(
            DateTime.parse(r['date'] as String),
            (r['total'] as num).toInt(),
            (r['recette'] as num).toDouble(),
          ),
        )
        .toList();
  }

  static Future<List<LigneStat>> recettesParGare() async {
    final rows = await _rapport('rapport_gare', 'recettes_par_gare');
    return rows
        .map(
          (r) => LigneStat(
            r['gare_nom'] as String,
            (r['total_colis'] as num).toInt(),
            (r['recette_totale'] as num).toDouble(),
          ),
        )
        .toList();
  }

  static Future<List<LigneStat>> recettesParAgent() async {
    final rows = await _rapport('rapport_agent', 'recettes_par_agent');
    return rows
        .map(
          (r) => LigneStat(
            r['agent_nom'] as String,
            (r['total_colis'] as num).toInt(),
            (r['recette_totale'] as num).toDouble(),
          ),
        )
        .toList();
  }

  static Future<Map<String, int>> statutsSummary() async {
    final rows = await _rapport('rapport_statuts', 'statuts_summary');
    return {
      for (final r in rows) r['statut'] as String: (r['total'] as num).toInt(),
    };
  }

  // ── Rapports détaillés ────────────────────────────────
  static const _colisRapportCols =
      'id, numero, expediteur_nom, expediteur_telephone, destinataire_nom, destinataire_telephone, '
      'gare_depart_id, gare_arrivee_id, gare_depart_nom, gare_arrivee_nom, description, nombre, poids, valeur, '
      'prix, statut, date_envoi, created_at, agent_id, agent_nom';

  /// Tous les colis de la période (jusqu'à 20 000), filtrables par agent, gare de départ et statut.
  /// Sans photo ni signature : seulement ce qu'il faut pour les tableaux.
  static Future<List<Colis>> rapportColis({
    DateTime? debut,
    DateTime? fin,
    String? agentId,
    int? gareDepartId,
    String? statut,
    bool inclureTraites = false,
  }) async {
    // « Mes rapports » (agent, guichet) : ce que j'ai enregistré + ce que j'ai fait avancer (arrivée, retrait…).
    var ids = <int>[];
    if (inclureTraites && agentId != null) {
      final h = await _db
          .from('historique_colis')
          .select('colis_id')
          .eq('agent_id', agentId)
          .gte('date_changement', debut == null ? '2000-01-01' : _iso(debut))
          .lt('date_changement', fin == null ? '2100-01-01' : _iso(fin.add(const Duration(days: 1))))
          .limit(2000);
      ids = {for (final r in h) (r['colis_id'] as num).toInt()}.toList();
    }
    Future<List<Colis>> lire(String cols) async {
      final out = <Colis>[];
      for (var from = 0; from < 20000; from += 1000) {
        var q = _db.from('colis_detail').select(cols);
        if (debut != null) q = q.gte('date_envoi', _iso(debut));
        if (fin != null) q = q.lte('date_envoi', _iso(fin));
        if (agentId != null) q = ids.isEmpty ? q.eq('agent_id', agentId) : q.or('agent_id.eq.$agentId,id.in.(${ids.join(',')})');
        if (gareDepartId != null) q = q.eq('gare_depart_id', gareDepartId);
        if (statut != null) q = q.eq('statut', statut);
        final rows = await q.order('created_at', ascending: false).range(from, from + 999);
        out.addAll(rows.map(Colis.fromJson));
        if (rows.length < 1000) break;
      }
      return out;
    }

    try {
      // billet_numero n'existe qu'après la migration 24.
      return await lire('$_colisRapportCols, billet_numero');
    } on PostgrestException catch (e) {
      if (!(e.message.contains('billet_numero') || e.code == '42703')) rethrow;
      return lire(_colisRapportCols);
    }
  }

  /// Billets vendus pendant la période (date de vente), filtrables par vendeur et gare de départ.
  static Future<List<Ticket>> rapportBillets({
    DateTime? debut,
    DateTime? fin,
    String? vendeurId,
    int? gareDepartId,
  }) async {
    final out = <Ticket>[];
    for (var from = 0; from < 20000; from += 1000) {
      var q = _db.from('tickets_detail').select();
      if (debut != null) q = q.gte('created_at', DateTime(debut.year, debut.month, debut.day).toUtc().toIso8601String());
      if (fin != null) {
        q = q.lt('created_at', DateTime(fin.year, fin.month, fin.day).add(const Duration(days: 1)).toUtc().toIso8601String());
      }
      if (vendeurId != null) q = q.eq('vendeur_id', vendeurId);
      if (gareDepartId != null) q = q.eq('gare_depart_id', gareDepartId);
      final rows = await q.order('created_at', ascending: false).range(from, from + 999);
      out.addAll(rows.map(Ticket.fromJson));
      if (rows.length < 1000) break;
    }
    return out;
  }

  /// Efface toutes les saisies de l'entreprise (colis, billets, clients, SMS…) ; réservé à l'administrateur.
  static Future<Map<String, dynamic>> reinitialiserDonnees(String confirmation) async {
    final r = await _db.rpc('reinitialiser_donnees', params: {'p_confirmation': confirmation});
    // Cette copie locale ne doit plus montrer les données effacées.
    await LocalStore.viderDonneesMetier();
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
