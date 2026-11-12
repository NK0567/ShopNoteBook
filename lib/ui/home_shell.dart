import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/session.dart';
import 'brand_logo.dart';
import 'dashboard/dashboard_screen.dart';
import 'operations/operations_screen.dart';
import 'products/stock_screen.dart';
import 'reports/reports_screen.dart';
import 'settings/settings_screen.dart';

/// Navigation principale + surveillance de l'inactivité (verrouillage auto).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  /// Permet aux écrans enfants de changer d'onglet (ex. "voir toutes les alertes").
  static void goToTab(BuildContext context, int index) =>
      context.findAncestorStateOfType<_HomeShellState>()?._select(index);

  static const int tabStock = 1;
  static const int tabOperations = 2;
  static const int tabSettings = 4;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  Timer? _timer;
  late final AppLifecycleListener _lifecycle;

  static const _destinations = [
    NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Accueil'),
    NavigationDestination(
      icon: Icon(Icons.inventory_2_outlined),
      selectedIcon: Icon(Icons.inventory_2),
      label: 'Stock',
    ),
    NavigationDestination(icon: Icon(Icons.swap_vert), label: 'Opérations'),
    NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Rapports'),
    NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Réglages'),
  ];

  @override
  void initState() {
    super.initState();
    final session = context.read<Session>();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => session.checkInactivity());
    _lifecycle = AppLifecycleListener(onResume: session.checkInactivity, onShow: session.checkInactivity);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  void _select(int i) => setState(() => _index = i);

  static const _pages = [DashboardScreen(), StockScreen(), OperationsScreen(), ReportsScreen(), SettingsScreen()];

  /// Au-delà de cette largeur (ordinateur, tablette en paysage) : menu latéral.
  static const double wideBreakpoint = 840;

  @override
  Widget build(BuildContext context) {
    final stack = IndexedStack(index: _index, children: _pages);
    if (MediaQuery.sizeOf(context).width >= wideBreakpoint) {
      final scheme = Theme.of(context).colorScheme;
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: _select,
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: const BrandLogo(size: 44),
              ),
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(icon: d.icon, selectedIcon: d.selectedIcon, label: Text(d.label)),
              ],
            ),
            VerticalDivider(width: 1, color: scheme.outlineVariant),
            // Contenu centré et limité en largeur : lisible sur grand écran.
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1100), child: stack),
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      body: stack,
      // Libellés limités à 110 % : au-delà, « Opérations » se coupe sur deux lignes.
      bottomNavigationBar: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.1,
        child: NavigationBar(selectedIndex: _index, onDestinationSelected: _select, destinations: _destinations),
      ),
    );
  }
}
