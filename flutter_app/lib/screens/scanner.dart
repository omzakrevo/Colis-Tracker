import 'package:flutter/material.dart';

import '../widgets/torche.dart';

import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/format.dart';
import '../core/identifiant.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../data/repo.dart';
import '../widgets/common.dart';

enum ScanMode {
  consulter('consulter', 'Consulter', Icons.search_rounded, Brand.emerald),
  embarquement(
    'embarquement',
    'Embarquer',
    Icons.inventory_2_rounded,
    Color(0xFFEA580C),
  ),
  dechargement(
    'dechargement',
    'Décharger',
    Icons.where_to_vote_rounded,
    Color(0xFF16A34A),
  );

  const ScanMode(this.code, this.label, this.icon, this.color);
  final String code, label;
  final IconData icon;
  final Color color;

  bool get batch => this != consulter;

  /// Le colis peut-il subir cette opération ?
  bool accepts(String statut) => switch (this) {
    embarquement => statut == 'enregistre',
    dechargement => statut == 'charge' || statut == 'en_route',
    consulter => true,
  };
}

class _ScanItem {
  _ScanItem(this.numero);
  final String numero;
  Colis? colis;
  bool loading = true;

  /// Barragiste sans internet : le colis ne peut pas être vérifié, il le sera à l'envoi.
  bool horsLigne = false;
}

class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  final _ctl = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  final _manual = TextEditingController();
  final _manualFocus = FocusNode();
  final _items = <_ScanItem>[];
  final _camKey = GlobalKey();
  late ScanMode _mode;
  bool _busy = false, _validating = false;
  String? _lastCode;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Barragiste et convoyeur ne font que l'embarquement et le déchargement (pas de consultation).
  bool get _barragiste =>
      ref.read(profilProvider).value?.scanRestreint ?? false;

  List<ScanMode> get _modes => _barragiste
      ? const [ScanMode.embarquement, ScanMode.dechargement]
      : ScanMode.values;

  @override
  void initState() {
    super.initState();
    _mode = _barragiste ? ScanMode.embarquement : ScanMode.consulter;
  }

  @override
  void dispose() {
    _ctl.dispose();
    _manual.dispose();
    _manualFocus.dispose();
    super.dispose();
  }

  void _setMode(ScanMode m) {
    if (m == _mode) return;
    setState(() {
      _mode = m;
      _items.clear();
    });
    // Le passage entre les deux mises en page recrée le lecteur : on s'assure que la caméra tourne.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _ctl.value.isRunning || _ctl.value.isStarting) return;
      try {
        await _ctl.start();
      } catch (_) {}
    });
  }

  /// Un scan (caméra, saisie ou lecteur Bluetooth).
  Future<void> _onCode(String raw, {bool fromCamera = false}) async {
    final numero = raw.trim().toUpperCase();
    if (numero.isEmpty) return;
    final now = DateTime.now();
    if (fromCamera &&
        numero == _lastCode &&
        now.difference(_lastAt).inMilliseconds < 2500)
      return;
    _lastCode = numero;
    _lastAt = now;

    if (!_mode.batch) return _open(numero);

    if (_items.any((i) => i.numero == numero)) {
      HapticFeedback.heavyImpact();
      toast(context, 'Déjà scanné : $numero', error: true);
      return;
    }
    final item = _ScanItem(numero);
    setState(() => _items.insert(0, item));
    HapticFeedback.selectionClick();
    SystemSound.play(SystemSoundType.click);
    try {
      item.colis = _barragiste
          ? await Repo.infoScan(numero)
          : await Repo.getColisByNumero(numero);
    } catch (e) {
      item.colis = null;
      item.horsLigne = _barragiste && estErreurReseau(e);
    }
    item.loading = false;
    if (!mounted) return;
    setState(() {});
    if (!item.horsLigne &&
        (item.colis == null || !_mode.accepts(item.colis!.statut))) {
      HapticFeedback.heavyImpact();
    }
  }

  Future<void> _open(String numero) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final c = await Repo.getColisByNumero(numero);
      if (!mounted) return;
      if (c == null) {
        toast(context, 'Colis introuvable : $numero', error: true);
        await Future<void>.delayed(const Duration(seconds: 2));
      } else {
        HapticFeedback.mediumImpact();
        await context.push('/colis/${c.id}');
      }
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<_ScanItem> get _valides => _items
      .where(
        (i) =>
            !i.loading &&
            (i.horsLigne ||
                (i.colis != null && _mode.accepts(i.colis!.statut))),
      )
      .toList();

  Future<void> _valider() async {
    final lot = _valides;
    if (lot.isEmpty || _validating) return;
    setState(() => _validating = true);
    try {
      final res = await Repo.scanLot(
        _mode.code,
        lot.map((i) => i.numero).toList(),
      );
      ref.read(tickProvider.notifier).bump();
      if (!mounted) return;
      final ok = res.where((r) => r.ok).map((r) => r.numero).toSet();
      setState(() => _items.removeWhere((i) => ok.contains(i.numero)));
      HapticFeedback.mediumImpact();
      await showDialog<void>(
        context: context,
        builder: (_) => _ResultDialog(_mode, res),
      );
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    } finally {
      if (mounted) setState(() => _validating = false);
    }
  }

  Widget _camera() => ClipRRect(
    key: _camKey,
    borderRadius: BorderRadius.circular(28),
    child: Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _ctl,
          onDetect: (cap) {
            final v = cap.barcodes.firstOrNull?.rawValue;
            if (v != null) _onCode(v, fromCamera: true);
          },
          errorBuilder: (_, e) => Container(
            color: Brand.emerald,
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            child: const Text(
              'Caméra indisponible.\nAutorisez l\'accès ou saisissez le numéro ci-dessous.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
        _Overlay(color: _mode.color),
        BoutonTorche(controller: _ctl),
        if (_busy)
          Container(
            color: Colors.black38,
            child: const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
      ],
    ),
  );

  Widget _manualField() => Row(
    children: [
      Expanded(
        child: TextField(
          controller: _manual,
          focusNode: _manualFocus,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.done,
          onSubmitted: (v) {
            _onCode(v);
            _manual.clear();
            _manualFocus.requestFocus();
          },
          decoration: const InputDecoration(
            hintText: 'Saisir ou scanner (lecteur) : COL-2026-123456',
            prefixIcon: Icon(Icons.keyboard_rounded),
          ),
        ),
      ),
      const SizedBox(width: 10),
      FilledButton(
        style: FilledButton.styleFrom(
          minimumSize: const Size(56, 52),
          backgroundColor: _mode.color,
        ),
        onPressed: () {
          _onCode(_manual.text);
          _manual.clear();
        },
        child: const Icon(Icons.arrow_forward_rounded),
      ),
    ],
  );

  Widget _modeSelector() => SizedBox(
    height: 52,
    child: Row(
      children: [
        for (final m in _modes)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: m == _modes.last ? 0 : 8),
              child: GestureDetector(
                onTap: () => _setMode(m),
                child: AnimatedContainer(
                  duration: 250.ms,
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    color: _mode == m ? m.color : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _mode == m ? m.color : Brand.line,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        m.icon,
                        size: 18,
                        color: _mode == m ? Colors.white : Brand.muted,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          m.label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                            color: _mode == m ? Colors.white : Brand.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _list({bool defile = false}) {
    if (_items.isEmpty) {
      return EmptyState(
        icon: _mode.icon,
        text: _mode == ScanMode.embarquement
            ? 'Scannez les colis à embarquer'
            : 'Scannez les colis à décharger',
      );
    }
    return ListView.separated(
      // Écran étroit : la liste fait partie de la page qui défile (sinon elle est écrasée sous la caméra).
      shrinkWrap: defile,
      physics: defile ? const NeverScrollableScrollPhysics() : null,
      padding: EdgeInsets.only(bottom: defile ? 12 : 100),
      itemCount: _items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final it = _items[i];
        final c = it.colis;
        final ok = it.horsLigne || (c != null && _mode.accepts(c.statut));
        final color = it.loading
            ? Brand.muted
            : (ok ? _mode.color : const Color(0xFFDC2626));
        final subtitle = it.loading
            ? 'Vérification…'
            : it.horsLigne
            ? 'Hors ligne — vérifié à l\'envoi'
            : c == null
            ? 'Colis introuvable'
            : ok
            ? [
                c.destinataireNom,
                c.gareArriveeNom ?? '—',
              ].where((x) => x.isNotEmpty).join(' · ')
            : 'Statut actuel : ${Statut.of(c.statut).label} — ignoré';
        return Container(
              key: ValueKey(it.numero),
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .08),
                border: Border.all(color: color.withValues(alpha: .35)),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(
                    it.loading
                        ? Icons.hourglass_top_rounded
                        : (ok
                              ? Icons.check_circle_rounded
                              : Icons.error_rounded),
                    color: color,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          it.numero,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          subtitle,
                          style: TextStyle(fontSize: 12.5, color: color),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _items.remove(it)),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
            )
            .animate()
            .fadeIn(duration: 250.ms)
            .slideX(begin: .1, end: 0, curve: Curves.easeOutCubic);
      },
    );
  }

  Widget _validateBar() {
    final n = _valides.length;
    final ignored = _items.where((i) => !i.loading).length - n;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _mode.color),
            onPressed: n == 0 || _validating ? null : _valider,
            icon: _validating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Icon(_mode.icon),
            label: Text(
              n == 0
                  ? 'Aucun colis à valider'
                  : '${_mode == ScanMode.embarquement ? 'Embarquer' : 'Décharger'} $n colis'
                        '${ignored > 0 ? '  ($ignored ignoré${ignored > 1 ? 's' : ''})' : ''}',
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final header = const PageHeader(
      'Scanner',
      subtitle: 'Scan rapide : choisissez une action puis scannez les colis.',
    );

    if (!_mode.batch) {
      return ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          header,
          _modeSelector().reveal(),
          const SizedBox(height: 16),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: AspectRatio(aspectRatio: 1, child: _camera()),
            ),
          ).reveal(1),
          const SizedBox(height: 16),
          _manualField().reveal(2),
        ],
      );
    }

    final camera = ConstrainedBox(
      constraints: BoxConstraints(maxHeight: wide ? 420 : 230),
      child: AspectRatio(aspectRatio: wide ? 1 : 16 / 9, child: _camera()),
    );

    final clavier = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (wide || !clavier) header,
        _modeSelector(),
        const SizedBox(height: 12),
        Expanded(
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 420,
                      child: Column(
                        children: [
                          camera,
                          const SizedBox(height: 12),
                          _manualField(),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(child: _list()),
                          _validateBar(),
                        ],
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    // Tout défile ensemble : on peut descendre voir les colis déjà scannés.
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.only(bottom: 8),
                        children: [
                          Center(child: camera),
                          const SizedBox(height: 10),
                          _manualField(),
                          const SizedBox(height: 10),
                          if (_items.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                '${_items.length} colis scanné${_items.length > 1 ? 's' : ''}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          _list(defile: true),
                        ],
                      ),
                    ),
                    _validateBar(),
                  ],
                ),
        ),
      ],
    );
  }
}

class _ResultDialog extends StatelessWidget {
  const _ResultDialog(this.mode, this.results);
  final ScanMode mode;
  final List<ScanResult> results;

  @override
  Widget build(BuildContext context) {
    final ok = results.where((r) => r.ok).length;
    final ko = results.length - ok;
    return AlertDialog(
      title: Text(
        mode == ScanMode.embarquement
            ? 'Embarquement terminé'
            : 'Déchargement terminé',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle_rounded, color: mode.color),
                const SizedBox(width: 8),
                Text(
                  '$ok colis ${mode == ScanMode.embarquement ? 'embarqué' : 'déchargé'}${ok > 1 ? 's' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            if (ko > 0) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.error_rounded, color: Color(0xFFDC2626)),
                  const SizedBox(width: 8),
                  Text(
                    '$ko en erreur',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final r in results.where((r) => !r.ok))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text(
                          '${r.numero} — ${r.message}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 44),
            backgroundColor: mode.color,
          ),
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

class _Overlay extends StatelessWidget {
  const _Overlay({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final box = c.maxWidth * .66;
      final left = (c.maxWidth - box) / 2;
      final top = (c.maxHeight - box) / 2;
      return Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            width: box,
            height: box,
            child:
                Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: color, width: 3),
                        borderRadius: BorderRadius.circular(24),
                      ),
                    )
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .scale(
                      begin: const Offset(.97, .97),
                      end: const Offset(1.02, 1.02),
                      duration: 1100.ms,
                    ),
          ),
          Positioned(
            left: left + 14,
            width: box - 28,
            top: top + 14,
            child:
                Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(9),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: .8),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                    )
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .moveY(
                      begin: 0,
                      end: box - 34,
                      duration: 1700.ms,
                      curve: Curves.easeInOut,
                    ),
          ),
        ],
      );
    },
  );
}
