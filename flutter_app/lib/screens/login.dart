import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../data/providers.dart';
import '../widgets/app_shell.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _loading = false, _hide = true;
  String? _error;
  int _shake = 0;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(profilProvider.notifier).login(_user.text, _pass.text);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errMsg(e);
          _shake++;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final formPanel = _buildForm();
    return Scaffold(
      backgroundColor: Colors.white,
      body: wide
          ? Row(children: [
              const Expanded(flex: 11, child: _Hero()),
              Expanded(flex: 9, child: Center(child: formPanel)),
            ])
          : Stack(children: [
              const Positioned.fill(child: _Hero(compact: true)),
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                        color: Colors.white, borderRadius: BorderRadius.circular(28)),
                    child: formPanel,
                  ).animate().fadeIn(delay: 250.ms).slideY(begin: .15, end: 0, curve: Curves.easeOutCubic, duration: 600.ms),
                ),
              ),
            ]),
    );
  }

  Widget _buildForm() {
    final form = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Bon retour 👋',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -.8))
                .animate().fadeIn(delay: 200.ms).slideY(begin: .3, end: 0),
            const SizedBox(height: 6),
            const Text('Connectez-vous pour gérer vos expéditions.',
                    style: TextStyle(color: Brand.muted))
                .animate().fadeIn(delay: 300.ms),
            const SizedBox(height: 28),
            TextFormField(
              controller: _user,
              autofillHints: const [AutofillHints.username],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                  labelText: 'Nom d\'utilisateur', prefixIcon: Icon(Icons.person_outline_rounded)),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Nom d\'utilisateur requis' : null,
            ).animate().fadeIn(delay: 380.ms).slideY(begin: .3, end: 0),
            const SizedBox(height: 14),
            TextFormField(
              controller: _pass,
              obscureText: _hide,
              autofillHints: const [AutofillHints.password],
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Mot de passe',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_hide ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                  onPressed: () => setState(() => _hide = !_hide),
                ),
              ),
              validator: (v) => (v ?? '').isEmpty ? 'Mot de passe requis' : null,
            ).animate().fadeIn(delay: 450.ms).slideY(begin: .3, end: 0),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Row(children: [
                  const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: const TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.w600))),
                ]),
              ).animate(key: ValueKey(_shake)).shakeX(hz: 5, amount: 6, duration: 450.ms),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _loading ? null : _submit,
                child: AnimatedSwitcher(
                  duration: 200.ms,
                  child: _loading
                      ? const SizedBox(
                          key: ValueKey('l'), width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : const Text('Se connecter', key: ValueKey('t')),
                ),
              ),
            ).animate().fadeIn(delay: 520.ms).slideY(begin: .3, end: 0),
          ]),
        ),
      ),
    );
    return form;
  }
}

/// Panneau d'accueil animé : un camion parcourt la route entre deux gares.
class _Hero extends StatelessWidget {
  const _Hero({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Brand.emerald, Color(0xFF123A32)]),
      ),
      child: Stack(children: [
        for (final b in _bubbles)
          Positioned(
            left: b.$1 * MediaQuery.sizeOf(context).width,
            top: b.$2 * MediaQuery.sizeOf(context).height,
            child: Icon(Icons.inventory_2_rounded, size: b.$3, color: Colors.white.withValues(alpha: .06))
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .moveY(begin: -14, end: 14, duration: (3000 + b.$3 * 30).ms, curve: Curves.easeInOut)
                .rotate(begin: -.04, end: .04, duration: 4000.ms),
          ),
        if (!compact)
          Padding(
            padding: const EdgeInsets.all(56),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              const Logo(size: 64)
                  .animate().scale(duration: 700.ms, curve: Curves.easeOutBack).then().shake(hz: 2, duration: 500.ms),
              const SizedBox(height: 28),
              const Text('VIP COLIS',
                      style: TextStyle(color: Colors.white, fontSize: 46, fontWeight: FontWeight.w800, letterSpacing: 1.5))
                  .animate().fadeIn(delay: 200.ms).slideX(begin: -.1, end: 0),
              const SizedBox(height: 14),
              Text('Le centre névralgique de vos expéditions.\nSuivez, gérez et sécurisez chaque colis à travers tout le réseau.',
                      style: TextStyle(color: Colors.white.withValues(alpha: .75), fontSize: 18, height: 1.5))
                  .animate().fadeIn(delay: 400.ms).slideX(begin: -.1, end: 0),
              const SizedBox(height: 56),
              const _RoadAnimation(),
            ]),
          ),
      ]),
    );
  }

  static const _bubbles = [
    (.05, .08, 70.0), (.55, .12, 46.0), (.82, .3, 90.0),
    (.12, .55, 54.0), (.6, .62, 76.0), (.35, .85, 44.0), (.9, .86, 58.0),
  ];
}

class _RoadAnimation extends StatelessWidget {
  const _RoadAnimation();

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 64,
        child: LayoutBuilder(builder: (context, c) {
          return Stack(children: [
            Positioned(
              left: 0, right: 0, bottom: 10,
              child: Container(height: 3, color: Colors.white.withValues(alpha: .18)),
            ),
            Positioned(
              left: 0, bottom: 4,
              child: Icon(Icons.location_on_rounded, color: Colors.white.withValues(alpha: .5)),
            ),
            Positioned(
              right: 0, bottom: 4,
              child: const Icon(Icons.location_on_rounded, color: Brand.orange),
            ),
            Positioned(
              left: 0, bottom: 10,
              child: const Icon(Icons.local_shipping_rounded, color: Brand.orange, size: 38)
                  .animate(onPlay: (ctl) => ctl.repeat())
                  .moveX(begin: 0, end: c.maxWidth - 44, duration: 4200.ms, curve: Curves.easeInOut)
                  .then(delay: 300.ms),
            ),
          ]);
        }),
      );
}
