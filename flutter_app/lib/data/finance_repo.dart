import 'package:supabase_flutter/supabase_flutter.dart';

import 'finance_models.dart';

/// Accès aux données du module Comptabilité (nécessite une connexion : ces écrans ne fonctionnent pas hors ligne).
class FinanceRepo {
  static SupabaseClient get _db => Supabase.instance.client;

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static List<Map<String, dynamic>> _maps(Object? o) => [for (final m in (o as List)) Map<String, dynamic>.from(m as Map)];

  // ── Identité légale (paramètres de l'entreprise) ──
  static Future<IdentiteLegale> identite() async {
    final r = await _db.from('company_settings').select().limit(1).maybeSingle();
    return r == null ? const IdentiteLegale() : IdentiteLegale.fromJson(r);
  }

  static Future<void> enregistrerIdentite(int companyId, Map<String, dynamic> data) =>
      _db.from('company_settings').update(data).eq('company_id', companyId);

  // ── Employés ──
  static Future<List<Employe>> employes({bool seulementActifs = false}) async {
    var q = _db.from('finance_employes').select();
    if (seulementActifs) q = q.eq('actif', true);
    return _maps(await q.order('nom')).map(Employe.fromJson).toList();
  }

  static Future<void> enregistrerEmploye(Employe e) async {
    if (e.id == null) {
      await _db.from('finance_employes').insert(e.toJson());
    } else {
      await _db.from('finance_employes').update(e.toJson()).eq('id', e.id!);
    }
  }

  static Future<void> supprimerEmploye(int id) => _db.from('finance_employes').delete().eq('id', id);

  // ── Dépenses ──
  static Future<List<Depense>> depenses({DateTime? debut, DateTime? fin, String? categorie, int? gareId}) async {
    final out = <Depense>[];
    for (var from = 0; from < 20000; from += 1000) {
      var q = _db.from('finance_depenses').select();
      if (debut != null) q = q.gte('date_depense', _iso(debut));
      if (fin != null) q = q.lte('date_depense', _iso(fin));
      if (categorie != null) q = q.eq('categorie', categorie);
      if (gareId != null) q = q.eq('gare_id', gareId);
      final rows = await q.order('date_depense', ascending: false).order('id', ascending: false).range(from, from + 999);
      out.addAll(rows.map(Depense.fromJson));
      if (rows.length < 1000) break;
    }
    return out;
  }

  static Future<void> enregistrerDepense(Depense d) async {
    if (d.id == null) {
      await _db.from('finance_depenses').insert(d.toJson());
    } else {
      await _db.from('finance_depenses').update(d.toJson()).eq('id', d.id!);
    }
  }

  static Future<void> supprimerDepense(int id) => _db.from('finance_depenses').delete().eq('id', id);

  // ── Bulletins de salaire ──
  static Future<List<Bulletin>> bulletins({required DateTime mois}) async {
    final rows = await _db.from('finance_bulletins').select().eq('mois', _iso(DateTime(mois.year, mois.month)));
    return rows.map(Bulletin.fromJson).toList();
  }

  /// Bulletins payés dans la période (pour les bilans et rapports).
  static Future<List<Bulletin>> bulletinsPayes({DateTime? debut, DateTime? fin}) async {
    var q = _db.from('finance_bulletins').select().eq('statut', 'paye');
    if (debut != null) q = q.gte('date_paiement', _iso(debut));
    if (fin != null) q = q.lte('date_paiement', _iso(fin));
    return (await q).map(Bulletin.fromJson).toList();
  }

  /// Crée ou met à jour le bulletin (un seul par employé et par mois).
  static Future<void> enregistrerBulletin(Bulletin b) =>
      _db.from('finance_bulletins').upsert(b.toJson(), onConflict: 'employe_id,mois');

  static Future<void> supprimerBulletin(int id) => _db.from('finance_bulletins').delete().eq('id', id);

  // ── Documents ──
  static Future<List<FinanceDoc>> documents({TypeDoc? type, DateTime? debut, DateTime? fin}) async {
    var q = _db.from('finance_documents').select();
    if (type != null) q = q.eq('type', type.code);
    if (debut != null) q = q.gte('date_doc', _iso(debut));
    if (fin != null) q = q.lte('date_doc', _iso(fin));
    return (await q.order('date_doc', ascending: false).order('id', ascending: false).limit(1000)).map(FinanceDoc.fromJson).toList();
  }

  /// Crée (id nul) ou modifie un document ; renvoie le document enregistré (avec son numéro).
  static Future<FinanceDoc> enregistrerDocument(FinanceDoc d) async {
    if (d.id == null) {
      return FinanceDoc.fromJson(await _db.from('finance_documents').insert(d.toJson()).select().single());
    }
    return FinanceDoc.fromJson(await _db.from('finance_documents').update(d.toJson()).eq('id', d.id!).select().single());
  }

  static Future<void> supprimerDocument(int id) => _db.from('finance_documents').delete().eq('id', id);
}
