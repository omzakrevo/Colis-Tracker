import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/finance_models.dart';
import '../data/finance_repo.dart';
import '../data/providers.dart';
import '../widgets/common.dart';
import 'finance_ui.dart';

/// Identité légale de l'entreprise (IFU, RCCM…), imprimée sur les documents officiels de la comptabilité.
class IdentiteLegaleCard extends ConsumerStatefulWidget {
  const IdentiteLegaleCard({super.key});

  @override
  ConsumerState<IdentiteLegaleCard> createState() => _IdentiteState();
}

class _IdentiteState extends ConsumerState<IdentiteLegaleCard> {
  final _c = {for (final k in ['ifu', 'rccm', 'regime_fiscal', 'compte_bancaire', 'numero_cnss', 'representant_nom', 'representant_fonction', 'tva_taux', 'cnss_taux']) k: TextEditingController()};
  bool _charge = false, _saving = false;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _load(IdentiteLegale i) {
    if (_charge) return;
    _charge = true;
    String t(double v) => v.toString().replaceAll(RegExp(r'\.0$'), '');
    _c['ifu']!.text = i.ifu;
    _c['rccm']!.text = i.rccm;
    _c['regime_fiscal']!.text = i.regimeFiscal;
    _c['compte_bancaire']!.text = i.compteBancaire;
    _c['numero_cnss']!.text = i.numeroCnss;
    _c['representant_nom']!.text = i.representantNom;
    _c['representant_fonction']!.text = i.representantFonction;
    _c['tva_taux']!.text = t(i.tvaTaux);
    _c['cnss_taux']!.text = t(i.cnssTaux);
  }

  Future<void> _enregistrer() async {
    final cid = ref.read(profilProvider).value?.companyId;
    if (cid == null) return;
    setState(() => _saving = true);
    try {
      await FinanceRepo.enregistrerIdentite(cid, {
        for (final k in ['ifu', 'rccm', 'regime_fiscal', 'compte_bancaire', 'numero_cnss', 'representant_nom', 'representant_fonction']) k: _c[k]!.text.trim(),
        'tva_taux': double.tryParse(_c['tva_taux']!.text.replaceAll(',', '.')) ?? 0,
        'cnss_taux': double.tryParse(_c['cnss_taux']!.text.replaceAll(',', '.')) ?? 0,
      });
      ref.invalidate(identiteProvider);
      if (mounted) toast(context, 'Identité légale enregistrée');
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = ref.watch(identiteProvider);
    return i.when(
      loading: () => const SizedBox(height: 60),
      error: (e, _) => Text(errMsg(e)),
      data: (id) {
        _load(id);
        const esp = SizedBox(height: 12);
        return SectionCard(
          title: 'Identité légale (documents officiels)',
          icon: Icons.verified_rounded,
          accent: const Color(0xFF2563EB),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Ces informations figurent sur les factures, décharges, contrats et bulletins de salaire.', style: TextStyle(color: Color(0xFF6B7280), fontSize: 12.5)),
              esp,
              Row(children: [Expanded(child: champTexte(_c['ifu']!, 'Numéro IFU')), const SizedBox(width: 10), Expanded(child: champTexte(_c['rccm']!, 'RCCM'))]),
              esp,
              Row(children: [Expanded(child: champTexte(_c['regime_fiscal']!, 'Régime fiscal (RSI, RNI…)')), const SizedBox(width: 10), Expanded(child: champTexte(_c['numero_cnss']!, 'N° CNSS employeur'))]),
              esp,
              champTexte(_c['compte_bancaire']!, 'Compte bancaire (RIB, IBAN)'),
              esp,
              Row(children: [Expanded(child: champTexte(_c['representant_nom']!, 'Responsable de la compagnie')), const SizedBox(width: 10), Expanded(child: champTexte(_c['representant_fonction']!, 'Fonction'))]),
              esp,
              Row(
                children: [
                  Expanded(child: champTexte(_c['tva_taux']!, 'TVA sur factures (%)', clavier: const TextInputType.numberWithOptions(decimal: true), aide: '0 si non assujetti')),
                  const SizedBox(width: 10),
                  Expanded(child: champTexte(_c['cnss_taux']!, 'CNSS salariale (%)', clavier: const TextInputType.numberWithOptions(decimal: true), aide: 'Retenue proposée sur les bulletins')),
                ],
              ),
              const SizedBox(height: 14),
              FilledButton.icon(onPressed: _saving ? null : _enregistrer, icon: const Icon(Icons.save_rounded), label: const Text('Enregistrer l\'identité légale')),
            ],
          ),
        );
      },
    );
  }
}
