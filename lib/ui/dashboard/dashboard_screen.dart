import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/period.dart';
import '../../data/models.dart';
import '../../data/shop_repository.dart';
import '../../services/session.dart';
import '../charts.dart';
import '../common.dart';
import '../home_shell.dart';
import '../operations/movement_form_screen.dart';
import '../sales/cart_screen.dart';
import '../sales/credits_screen.dart';
import '../products/product_detail_screen.dart';
import '../products/product_form_screen.dart';

class _DashboardData {
  final List<StockItem> inventory;
  final PeriodSummary today;
  final PeriodSummary month;
  final List<ProductRanking> top;
  final List<DateTime> days;
  final Map<DateTime, double> daily;
  final double credit;
  final int creditClients;

  _DashboardData(
    this.inventory,
    this.today,
    this.month,
    this.top,
    this.days,
    this.daily,
    this.credit,
    this.creditClients,
  );
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  static Future<_DashboardData> _load(ShopRepository repo, int userId) async {
    final today = Period.of(PeriodKind.today);
    final month = Period.of(PeriodKind.month);
    final week = Period.of(PeriodKind.week);
    final f = week.from!;
    final days = [for (var i = 0; i < 7; i++) DateTime(f.year, f.month, f.day + i)];
    final debts = await repo.clientDebts(userId);
    return _DashboardData(
      await repo.inventory(userId),
      await repo.periodSummary(userId, from: today.from, to: today.to),
      await repo.periodSummary(userId, from: month.from, to: month.to),
      await repo.salesRanking(userId, from: month.from, to: month.to, limit: 3),
      days,
      await repo.dailySales(userId, from: week.from!, to: week.to!),
      debts.fold<double>(0, (s, d) => s + d.balance),
      debts.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<Session>().user!;
    return Scaffold(
      appBar: AppBar(
        title: Text(user.businessName),
        actions: [
          IconButton(
            tooltip: 'Verrouiller',
            icon: const Icon(Icons.lock_outline),
            onPressed: context.read<Session>().lock,
          ),
        ],
      ),
      body: Reloading<_DashboardData>(
        load: _load,
        builder: (context, d) {
          if (d.inventory.isEmpty) {
            return EmptyState(
              icon: Icons.storefront,
              message: 'Bienvenue ${user.name} !\nCommencez par ajouter les produits de votre boutique.',
              action: FilledButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductFormScreen())),
                icon: const Icon(Icons.add),
                label: const Text('Ajouter un produit'),
              ),
            );
          }
          final alerts = ShopRepository.alerts(d.inventory);
          final stockValue = d.inventory.fold<double>(0, (s, i) => s + i.stockValue);
          final critical = alerts.where((a) => a.status.isCritical).length;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Text('Bonjour ${user.name.split(' ').first}', style: Theme.of(context).textTheme.titleLarge),
              Text(Fmt.date(DateTime.now()), style: Theme.of(context).textTheme.bodySmall),
              if (!user.hasRecoveryCode) ...[
                const SizedBox(height: 8),
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: ListTile(
                    leading: const Icon(Icons.key_outlined),
                    title: const Text('Créez votre code de secours'),
                    subtitle: const Text('Sans lui, un mot de passe oublié = boutique perdue.'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => HomeShell.goToTab(context, HomeShell.tabSettings),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartScreen())),
                      icon: const Icon(Icons.point_of_sale),
                      label: const Text('Vente'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () => _openForm(context, MovementType.entry),
                      icon: const Icon(Icons.add_shopping_cart),
                      label: const Text('Entrée'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              KpiGrid(
                children: [
                  KpiCard(
                    label: 'Ventes du jour',
                    value: Fmt.money(d.today.salesAmount),
                    icon: Icons.today,
                    subtitle: '${Fmt.count(d.today.salesCount, 'vente')} · bénéfice ${Fmt.money(d.today.profit)}',
                  ),
                  KpiCard(
                    label: 'Bénéfice du mois',
                    value: Fmt.money(d.month.profit),
                    icon: Icons.trending_up,
                    color: okColor,
                    subtitle: 'CA ${Fmt.money(d.month.salesAmount)}',
                  ),
                  KpiCard(
                    label: 'Valeur du stock',
                    value: Fmt.money(stockValue),
                    icon: Icons.inventory,
                    subtitle: '${Fmt.count(d.inventory.length, 'produit')}, au CUMP',
                    onTap: () => HomeShell.goToTab(context, HomeShell.tabStock),
                  ),
                  KpiCard(
                    label: 'Alertes de stock',
                    value: '${alerts.length}',
                    icon: Icons.warning_amber,
                    color: alerts.isEmpty ? okColor : Color(critical > 0 ? user.criticalColor : user.warningColor),
                    subtitle: critical > 0 ? '${Fmt.count(critical, 'urgente')} ou en rupture' : 'Aucune urgence',
                    onTap: () => HomeShell.goToTab(context, HomeShell.tabStock),
                  ),
                  KpiCard(
                    label: 'Crédits clients',
                    value: Fmt.money(d.credit),
                    icon: Icons.handshake_outlined,
                    color: d.credit >= 1 ? Theme.of(context).colorScheme.error : okColor,
                    subtitle: d.creditClients == 0
                        ? 'Personne ne vous doit rien'
                        : Fmt.count(d.creditClients, 'client'),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreditsScreen())),
                  ),
                  KpiCard(
                    label: 'Encaissé aujourd\'hui',
                    value: Fmt.money(d.today.cashIn),
                    icon: Icons.payments_outlined,
                    subtitle: d.today.valueLoss > 0
                        ? 'Pertes : ${Fmt.money(d.today.valueLoss)}'
                        : 'Ventes + remboursements',
                  ),
                ],
              ),
              const SectionTitle('Ventes des 7 derniers jours'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                  child: DailyBars(days: d.days, values: d.daily),
                ),
              ),
              const SectionTitle('Meilleures ventes du mois'),
              if (d.top.isEmpty)
                const Card(
                  child: ListTile(leading: Icon(Icons.info_outline), title: Text('Aucune vente ce mois-ci')),
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < d.top.length; i++)
                        ListTile(
                          leading: CircleAvatar(child: Text('${i + 1}')),
                          title: Text(d.top[i].name),
                          subtitle: Text(
                            '${Fmt.count(d.top[i].quantity, 'vendu')} · bénéfice ${Fmt.money(d.top[i].profit)}',
                          ),
                          trailing: Text(
                            Fmt.money(d.top[i].amount),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onTap: () => _openProduct(context, d.top[i].productId),
                        ),
                    ],
                  ),
                ),
              SectionTitle(
                'À réapprovisionner',
                trailing: alerts.length > 5
                    ? TextButton(
                        onPressed: () => HomeShell.goToTab(context, HomeShell.tabStock),
                        child: Text('Tout voir (${alerts.length})'),
                      )
                    : null,
              ),
              if (alerts.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.check_circle, color: okColor),
                    title: Text('Tous les stocks sont à un niveau satisfaisant'),
                  ),
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (final a in alerts.take(5))
                        ListTile(
                          leading: Icon(Icons.warning_amber, color: statusColor(context, a.status)),
                          title: Text(a.product.name),
                          subtitle: Text(
                            'Stock ${Fmt.qtyUnit(a.stock, a.product.unit)} · seuil ${a.product.alertThreshold}',
                          ),
                          trailing: StatusBadge(a.status, compact: true),
                          onTap: () => _openProduct(context, a.product.id!),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _openForm(BuildContext context, MovementType type) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => MovementFormScreen(type: type)));

  void _openProduct(BuildContext context, int productId) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailScreen(productId: productId)));
}
