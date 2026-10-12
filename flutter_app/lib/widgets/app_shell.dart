import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/providers.dart';

class _Item {
  const _Item(this.path, this.label, this.icon);
  final String path, label;
  final IconData icon;
}

const _principaux = [
  _Item('/', 'Accueil', Icons.space_dashboard_rounded),
  _Item('/colis', 'Colis', Icons.inventory_2_rounded),
  _Item('/scanner', 'Scanner', Icons.qr_code_scanner_rounded),
  _Item('/recherche', 'Recherche', Icons.search_rounded),
];

List<_Item> _menu(Profil me) => [
      ..._principaux,
      const _Item('/rapports', 'Rapports', Icons.insights_rounded),
      if (me.isAdmin) ...const [
        _Item('/gares', 'Gares', Icons.location_city_rounded),
        _Item('/utilisateurs', 'Utilisateurs', Icons.groups_rounded),
        _Item('/parametres', 'Paramètres', Icons.tune_rounded),
      ],
    ];

class Logo extends StatelessWidget {
  const Logo({super.key, this.size = 36, this.data});
  final double size;
  final String? data;

  @override
  Widget build(BuildContext context) {
    if (data != null && data!.contains(',')) {
      try {
        return ClipRRect(
          borderRadius: BorderRadius.circular(size * .28),
          child: Image.memory(base64Decode(data!.split(',').last),
              width: size, height: size, fit: BoxFit.cover),
        );
      } catch (_) {}
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          color: Brand.orange, borderRadius: BorderRadius.circular(size * .28)),
      child: Icon(Icons.inventory_2_rounded, color: Colors.white, size: size * .56),
    );
  }
}

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child, required this.location});
  final Widget child;
  final String location;

  bool _active(String path) =>
      path == '/' ? location == '/' : location.startsWith(path);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(realtimeProvider);
    final me = ref.watch(profilProvider).value;
    if (me == null) return const SizedBox.shrink();
    final settings = ref.watch(settingsProvider).value;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final menu = _menu(me);

    Future<void> logout() async {
      await ref.read(profilProvider.notifier).logout();
    }

    if (wide) {
      return Scaffold(
        body: Row(children: [
          _Sidebar(
              me: me, menu: menu, active: _active, settings: settings, onLogout: logout),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Padding(padding: const EdgeInsets.fromLTRB(32, 28, 32, 0), child: child),
              ),
            ),
          ),
        ]),
      );
    }

    final bottomIdx = _principaux.indexWhere((i) => _active(i.path));
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          Logo(size: 30, data: settings?.logo),
          const SizedBox(width: 10),
          Text(settings?.nom.toUpperCase() ?? 'VIP COLIS',
              style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: .5, fontSize: 17)),
        ]),
      ),
      drawer: Drawer(
        backgroundColor: Brand.emerald,
        child: _Sidebar(
            me: me, menu: menu, active: _active, settings: settings, onLogout: logout,
            onNavigate: () => Navigator.of(context).pop(), embedded: true),
      ),
      body: Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 0), child: child),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/colis/nouveau'),
        backgroundColor: Brand.orange,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nouveau', style: TextStyle(fontWeight: FontWeight.w800)),
      ).animate().scale(delay: 400.ms, duration: 500.ms, curve: Curves.easeOutBack),
      bottomNavigationBar: NavigationBar(
        selectedIndex: bottomIdx < 0 ? 0 : bottomIdx,
        backgroundColor: Colors.white,
        indicatorColor: Brand.orangeSoft,
        onDestinationSelected: (i) => context.go(_principaux[i].path),
        destinations: [
          for (final i in _principaux)
            NavigationDestination(icon: Icon(i.icon), label: i.label),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.me,
    required this.menu,
    required this.active,
    required this.settings,
    required this.onLogout,
    this.onNavigate,
    this.embedded = false,
  });

  final Profil me;
  final List<_Item> menu;
  final bool Function(String) active;
  final CompanySettings? settings;
  final VoidCallback onLogout;
  final VoidCallback? onNavigate;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: embedded ? null : 252,
      color: Brand.emerald,
      child: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Row(children: [
              Logo(size: 38, data: settings?.logo),
              const SizedBox(width: 12),
              Expanded(
                child: Text((settings?.nom ?? 'VIP Colis').toUpperCase(),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17, letterSpacing: .6)),
              ),
            ]),
          ).animate().fadeIn().slideX(begin: -.1, end: 0),
          Expanded(
            child: ListView(padding: const EdgeInsets.symmetric(horizontal: 12), children: [
              for (var n = 0; n < menu.length; n++)
                _SideTile(
                  item: menu[n],
                  selected: active(menu[n].path),
                  onTap: () {
                    onNavigate?.call();
                    context.go(menu[n].path);
                  },
                ).animate().fadeIn(delay: (50 * n).ms).slideX(begin: -.15, end: 0, delay: (50 * n).ms, curve: Curves.easeOutCubic),
            ]),
          ),
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: Brand.emeraldLight, borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(me.nom,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(roleLabel(me.role),
                  style: TextStyle(color: Colors.white.withValues(alpha: .6), fontSize: 12)),
              const SizedBox(height: 10),
              InkWell(
                onTap: onLogout,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Icon(Icons.logout_rounded, size: 16, color: Colors.white.withValues(alpha: .85)),
                    const SizedBox(width: 8),
                    Text('Déconnexion',
                        style: TextStyle(color: Colors.white.withValues(alpha: .85), fontSize: 13, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _SideTile extends StatelessWidget {
  const _SideTile({required this.item, required this.selected, required this.onTap});
  final _Item item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: AnimatedContainer(
              duration: 260.ms,
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: selected ? Brand.orange : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                Icon(item.icon, size: 19, color: selected ? Colors.white : Colors.white70),
                const SizedBox(width: 12),
                Text(item.label,
                    style: TextStyle(
                        color: selected ? Colors.white : Colors.white70,
                        fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                        fontSize: 14)),
              ]),
            ),
          ),
        ),
      );
}
