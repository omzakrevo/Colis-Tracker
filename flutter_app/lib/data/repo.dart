import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/identifiant.dart';
import 'models.dart';

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

  static Future<List<AppVersion>> versions() async {
    final rows = await _db.from('app_versions').select().order('build_number', ascending: false);
    return rows.map(AppVersion.fromJson).toList();
  }

  static Future<void> publierVersion({
    required String versionName,
    required int buildNumber,
    required String apkUrl,
    String? notes,
    bool obligatoire = false,
  }) =>
      _db.from('app_versions').insert({
        'version_name': versionName,
        'build_number': buildNumber,
        'apk_url': apkUrl,
        'notes': notes,
        'obligatoire': obligatoire,
      });

  static Future<void> majVersion(int id, Map<String, dynamic> data) =>
      _db.from('app_versions').update(data).eq('id', id);

  static Future<void> supprimerVersion(int id) => _db.from('app_versions').delete().eq('id', id);

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

  // ── Colis ─────────────────────────────────────────────
  static Future<List<Colis>> listColis(ColisFilter f, {int? maGareId}) async {
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

  static Future<Colis> getColis(int id) async => Colis.fromJson(
    await _db.from('colis_detail').select().eq('id', id).single(),
  );

  static Future<Colis?> getColisByNumero(String numero) async {
    final r = await _db
        .from('colis_detail')
        .select()
        .eq('numero', numero.trim())
        .maybeSingle();
    return r == null ? null : Colis.fromJson(r);
  }

  static Future<List<Historique>> historique(int colisId) async {
    final rows = await _db
        .from('historique_detail')
        .select()
        .eq('colis_id', colisId)
        .order('date_changement');
    return rows.map(Historique.fromJson).toList();
  }

  static Future<Colis> creerColis(Map<String, dynamic> data) async {
    final r = await _db.from('colis').insert(data).select('id').single();
    return getColis(r['id'] as int);
  }

  static Future<void> changerStatut(int id, String statut, String? notes) =>
      _db.rpc(
        'changer_statut',
        params: {'p_id': id, 'p_statut': statut, 'p_notes': notes},
      );

  /// Embarquement / déchargement de plusieurs colis d'un coup (scan rapide).
  static Future<List<ScanResult>> scanLot(
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

  static Future<void> retirer(
    int id, {
    required String nom,
    required String telephone,
    String? piece,
    String? signature,
  }) => _db.rpc(
    'retirer_colis',
    params: {
      'p_id': id,
      'p_nom': nom,
      'p_telephone': telephone,
      'p_piece': piece,
      'p_signature': signature,
    },
  );

  // ── Gares ─────────────────────────────────────────────
  static Future<List<Gare>> gares() async =>
      (await _db.from('gares').select().order('nom'))
          .map(Gare.fromJson)
          .toList();

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
  static Future<List<Profil>> profils() async =>
      (await _db.from('vip_profiles').select().order('nom'))
          .map(Profil.fromJson)
          .toList();

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
  static Future<CompanySettings> settings() async {
    final r = await _db
        .from('company_settings')
        .select()
        .limit(1)
        .maybeSingle();
    return r == null ? CompanySettings.defaults : CompanySettings.fromJson(r);
  }

  static Future<void> saveSettings(int companyId, Map<String, dynamic> data) =>
      _db.from('company_settings').update(data).eq('company_id', companyId);

  // ── Rapports ──────────────────────────────────────────
  static Future<DashboardStats> dashboard() async => DashboardStats(
    Map<String, dynamic>.from(await _db.rpc('dashboard_stats') as Map),
  );

  static Future<List<JourStat>> colisParJour(
    DateTime? debut,
    DateTime? fin,
  ) async {
    final rows = await _db.rpc(
      'colis_par_jour',
      params: {
        'p_debut': debut == null ? null : _iso(debut),
        'p_fin': fin == null ? null : _iso(fin),
      },
    ) as List;
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
    final rows = await _db.rpc('recettes_par_gare') as List;
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
    final rows = await _db.rpc('recettes_par_agent') as List;
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
    final rows = await _db.rpc('statuts_summary') as List;
    return {
      for (final r in rows) r['statut'] as String: (r['total'] as num).toInt(),
    };
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
