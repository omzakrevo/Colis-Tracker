import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config.dart';
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
  }) =>
      ColisFilter(
        search: search ?? this.search,
        statut: identical(statut, _keep) ? this.statut : statut as String?,
        direction:
            identical(direction, _keep) ? this.direction : direction as String?,
        debut: identical(debut, _keep) ? this.debut : debut as DateTime?,
        fin: identical(fin, _keep) ? this.fin : fin as DateTime?,
        ancienFirst: ancienFirst ?? this.ancienFirst,
      );

  int get activeCount =>
      [statut, direction, debut, fin].where((e) => e != null).length;

  static const _keep = Object();
}

class Repo {
  // ── Auth ──────────────────────────────────────────────
  static Future<Profil> login(String username, String password) async {
    final email = '${username.trim().toLowerCase()}@${AppConfig.emailDomain}';
    try {
      await _db.auth.signInWithPassword(email: email, password: password);
    } on AuthException {
      throw 'Identifiants incorrects';
    }
    final p = await currentProfil();
    if (p == null || !p.actif) {
      await _db.auth.signOut();
      throw 'Compte désactivé';
    }
    return p;
  }

  static Future<void> logout() => _db.auth.signOut();

  static Future<Profil?> currentProfil() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return null;
    final r = await _db.from('vip_profiles').select().eq('id', uid).maybeSingle();
    return r == null ? null : Profil.fromJson(r);
  }

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
      q = q.or('numero.ilike.%$s%,expediteur_nom.ilike.%$s%,'
          'destinataire_nom.ilike.%$s%,expediteur_telephone.ilike.%$s%,'
          'destinataire_telephone.ilike.%$s%');
    }
    final rows = await q.order('created_at', ascending: f.ancienFirst).limit(500);
    return rows.map(Colis.fromJson).toList();
  }

  static Future<Colis> getColis(int id) async =>
      Colis.fromJson(await _db.from('colis_detail').select().eq('id', id).single());

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
      _db.rpc('changer_statut',
          params: {'p_id': id, 'p_statut': statut, 'p_notes': notes});

  static Future<void> retirer(int id,
          {required String nom,
          required String telephone,
          String? piece,
          String? signature}) =>
      _db.rpc('retirer_colis', params: {
        'p_id': id,
        'p_nom': nom,
        'p_telephone': telephone,
        'p_piece': piece,
        'p_signature': signature,
      });

  // ── Gares ─────────────────────────────────────────────
  static Future<List<Gare>> gares() async =>
      (await _db.from('gares').select().order('nom')).map(Gare.fromJson).toList();

  static Future<void> saveGare(int? id, Map<String, dynamic> data) async {
    if (id == null) {
      await _db.from('gares').insert(data);
    } else {
      await _db.from('gares').update(data).eq('id', id);
    }
  }

  static Future<void> deleteGare(int id) => _db.from('gares').delete().eq('id', id);

  // ── Utilisateurs ──────────────────────────────────────
  static Future<List<Profil>> profils() async =>
      (await _db.from('vip_profiles').select().order('nom')).map(Profil.fromJson).toList();

  static Future<void> creerUtilisateur({
    required String username,
    required String password,
    required String nom,
    required String role,
    int? gareId,
    String? telephone,
  }) =>
      _db.rpc('admin_creer_utilisateur', params: {
        'p_username': username,
        'p_password': password,
        'p_nom': nom,
        'p_role': role,
        'p_gare_id': gareId,
        'p_telephone': telephone,
      });

  static Future<void> majProfil(String id, Map<String, dynamic> data) =>
      _db.from('vip_profiles').update(data).eq('id', id);

  static Future<void> changerMotDePasse(String id, String password) => _db
      .rpc('admin_changer_mot_de_passe', params: {'p_user': id, 'p_password': password});

  // ── Paramètres société ────────────────────────────────
  static Future<CompanySettings> settings() async {
    final r = await _db.from('company_settings').select().eq('id', 1).maybeSingle();
    return r == null ? CompanySettings.defaults : CompanySettings.fromJson(r);
  }

  static Future<void> saveSettings(Map<String, dynamic> data) =>
      _db.from('company_settings').update(data).eq('id', 1);

  // ── Rapports ──────────────────────────────────────────
  static Future<DashboardStats> dashboard() async =>
      DashboardStats(Map<String, dynamic>.from(await _db.rpc('dashboard_stats') as Map));

  static Future<List<JourStat>> colisParJour(DateTime? debut, DateTime? fin) async {
    final rows = await _db.rpc('colis_par_jour', params: {
      'p_debut': debut == null ? null : _iso(debut),
      'p_fin': fin == null ? null : _iso(fin),
    }) as List;
    return rows
        .map((r) => JourStat(DateTime.parse(r['date'] as String),
            (r['total'] as num).toInt(), (r['recette'] as num).toDouble()))
        .toList();
  }

  static Future<List<LigneStat>> recettesParGare() async {
    final rows = await _db.rpc('recettes_par_gare') as List;
    return rows
        .map((r) => LigneStat(r['gare_nom'] as String,
            (r['total_colis'] as num).toInt(), (r['recette_totale'] as num).toDouble()))
        .toList();
  }

  static Future<List<LigneStat>> recettesParAgent() async {
    final rows = await _db.rpc('recettes_par_agent') as List;
    return rows
        .map((r) => LigneStat(r['agent_nom'] as String,
            (r['total_colis'] as num).toInt(), (r['recette_totale'] as num).toDouble()))
        .toList();
  }

  static Future<Map<String, int>> statutsSummary() async {
    final rows = await _db.rpc('statuts_summary') as List;
    return {for (final r in rows) r['statut'] as String: (r['total'] as num).toInt()};
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
