import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/models.dart';
import '../data/repo.dart';

/// Nom + téléphone d'un client, avec reconnaissance automatique : dès qu'on tape quelques chiffres du
/// numéro (ou des lettres du nom), les clients déjà connus (colis envoyés/reçus, billets) sont proposés ;
/// un numéro entièrement saisi qui correspond à un seul client remplit le nom tout seul.
class ClientFields extends StatefulWidget {
  const ClientFields({
    super.key,
    required this.nom,
    required this.telephone,
    this.validator,
    this.onPick,
    this.nomLabel = 'Nom complet *',
    this.telLabel = 'Téléphone *',
  });

  final TextEditingController nom, telephone;
  final String? Function(String?)? validator;

  /// Appelé quand un client connu est choisi (ou reconnu) : permet de pré-remplir d'autres champs.
  final ValueChanged<ClientSuggestion>? onPick;
  final String nomLabel, telLabel;

  @override
  State<ClientFields> createState() => _ClientFieldsState();
}

class _ClientFieldsState extends State<ClientFields> {
  Timer? _debounce;
  List<ClientSuggestion> _res = [];
  ClientSuggestion? _reconnu;
  int _seq = 0;
  bool _remplissage = false;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  static String _chiffres(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  void _tape(String terme) {
    if (_remplissage) return;
    _debounce?.cancel();
    if (terme.trim().length < 2) {
      setState(() => _res = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final n = ++_seq;
      List<ClientSuggestion> r;
      try {
        r = await Repo.clientsSuggestions(terme);
      } catch (_) {
        r = [];
      }
      if (!mounted || n != _seq) return;
      final tel = _chiffres(widget.telephone.text);
      // Numéro complet reconnu : on remplit le nom sans qu'il y ait rien à choisir.
      final exact = tel.length >= 8
          ? r.where((c) => c.telephone == tel || c.telephone.endsWith(tel)).toList()
          : <ClientSuggestion>[];
      if (exact.length == 1 && widget.nom.text.trim().isEmpty) {
        _choisir(exact.first);
        return;
      }
      setState(() {
        _res = r;
        _reconnu = null;
      });
    });
  }

  void _choisir(ClientSuggestion c) {
    _remplissage = true;
    widget.nom.text = c.nom;
    widget.telephone.text = c.telephoneAffiche;
    _remplissage = false;
    setState(() {
      _res = [];
      _reconnu = c;
    });
    widget.onPick?.call(c);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
 textInputAction: TextInputAction.next,
          controller: widget.telephone,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: widget.telLabel,
            hintText: '+226 70 00 00 00',
            prefixIcon: const Icon(Icons.phone_rounded),
          ),
          validator: widget.validator,
          onChanged: _tape,
        ),
        const SizedBox(height: 12),
        TextFormField(
 textInputAction: TextInputAction.next,
          controller: widget.nom,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: widget.nomLabel,
            prefixIcon: const Icon(Icons.person_rounded),
          ),
          validator: widget.validator,
          onChanged: _tape,
        ),
        if (_reconnu != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                const Icon(Icons.verified_rounded, size: 18, color: Color(0xFF16A34A)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Client connu : ${_reconnu!.nbColis} colis, ${_reconnu!.nbTickets} billet${_reconnu!.nbTickets > 1 ? 's' : ''}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF16A34A),
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (_res.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Brand.orange.withValues(alpha: .4)),
            ),
            child: Column(
              children: [
                for (final c in _res)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.history_rounded, size: 20),
                    title: Text(
                      c.nom,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${c.telephoneAffiche} · ${c.nbColis} colis · ${c.nbTickets} billet${c.nbTickets > 1 ? 's' : ''}',
                    ),
                    onTap: () => _choisir(c),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
