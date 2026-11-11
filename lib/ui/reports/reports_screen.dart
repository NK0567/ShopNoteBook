import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/period.dart';
import '../../data/models.dart';
import '../../data/shop_repository.dart';
import '../../services/pdf_reports.dart';
import '../../services/session.dart';
import '../charts.dart';
import '../common.dart';
import '../products/product_detail_screen.dart';

class _ReportData {
  final PeriodSummary summary;
  final List<ProductRanking> ranking;
  final List<CategoryShare> salesByCategory;
  final List<CategoryShare> stockByCategory;
  final List<Category> categories;
  final double stockValue;
  final List<CategoryShare> suppliers;
  _ReportData(
    this.summary,
    this.ranking,
    this.salesByCategory,
    this.stockByCategory,
    this.categories,
    this.stockValue,
    this.suppliers,
  );
}

/// Bénéfices, classement des ventes et analyses par catégorie
/// (feuilles "Traitement" et "Tableau de bord").
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  Period _period = Period.of(PeriodKind.month);
  int? _categoryId;
  bool _exporting = false;

  Future<void> _choosePeriod(PeriodKind kind) async {
    if (kind != PeriodKind.custom) {
      setState(() => _period = Period.of(kind));
      return;
    }
    final now = DateTime.now();
    final range = await showDateRangePicker(context: context, firstDate: DateTime(now.year - 5), lastDate: now);
    if (range != null) setState(() => _period = Period.custom(range.start, range.end));
  }

  Future<_ReportData> _load(ShopRepository repo, int uid) async {
    final inventory = await repo.inventory(uid);
    final filtered = _categoryId == null
        ? inventory
        : inventory.where((i) => i.product.categoryId == _categoryId).toList();
    return _ReportData(
      await repo.periodSummary(uid, from: _period.from, to: _period.to, categoryId: _categoryId),
      await repo.salesRanking(uid, from: _period.from, to: _period.to, categoryId: _categoryId),
      await repo.movementsByCategory(uid, MovementType.sale, from: _period.from, to: _period.to),
      ShopRepository.stockValueByCategory(inventory),
      await repo.categories(uid),
      filtered.fold<double>(0, (s, i) => s + i.stockValue),
      await repo.purchasesBySupplier(uid, from: _period.from, to: _period.to),
    );
  }

  Future<void> _export(_ReportData d) async {
    setState(() => _exporting = true);
    try {
      final repo = context.read<ShopRepository>();
      final session = context.read<Session>();
      final moves = await repo.movements(
        session.userId,
        type: MovementType.sale,
        from: _period.from,
        to: _period.to,
        categoryId: _categoryId,
      );
      final catName = d.categories.where((c) => c.id == _categoryId).firstOrNull?.name;
      final label = catName == null ? _period.label : '${_period.label} — $catName';
      final bytes = await PdfReports.periodReport(
        session.user!,
        periodLabel: label,
        summary: d.summary,
        ranking: d.ranking,
        movements: moves,
      );
      await PdfReports.share(bytes, 'rapport.pdf');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Reloading<_ReportData>(
      deps: [_period.from, _period.to, _categoryId],
      load: _load,
      builder: (context, d) {
        final s = d.summary;
        if (_categoryId != null && !d.categories.any((c) => c.id == _categoryId)) {
          // Catégorie filtrée supprimée entre-temps : on recharge sans filtre.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _categoryId = null);
          });
        }
        return Scaffold(
          appBar: AppBar(
            title: const Text('Rapports'),
            actions: [
              IconButton(
                tooltip: 'Exporter en PDF',
                onPressed: _exporting ? null : () => _export(d),
                icon: const Icon(Icons.picture_as_pdf_outlined),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  PopupMenuButton<PeriodKind>(
                    onSelected: _choosePeriod,
                    itemBuilder: (_) => [
                      for (final k in PeriodKind.values) PopupMenuItem(value: k, child: Text(k.label)),
                    ],
                    child: Chip(avatar: const Icon(Icons.date_range, size: 18), label: Text(_period.label)),
                  ),
                  DropdownButton<int?>(
                    value: d.categories.any((c) => c.id == _categoryId) ? _categoryId : null,
                    underline: const SizedBox.shrink(),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Toutes catégories')),
                      for (final c in d.categories) DropdownMenuItem(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: (v) => setState(() => _categoryId = v),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              KpiGrid(
                children: [
                  KpiCard(
                    label: 'Chiffre d\'affaires',
                    value: Fmt.money(s.salesAmount),
                    icon: Icons.point_of_sale,
                    subtitle: '${Fmt.count(s.salesCount, 'vente')} · ${Fmt.count(s.qtyOut, 'article')}',
                  ),
                  KpiCard(
                    label: 'Bénéfice net',
                    value: Fmt.money(s.netProfit),
                    icon: Icons.trending_up,
                    color: s.netProfit >= 0 ? okColor : Theme.of(context).colorScheme.error,
                    subtitle: s.valueLoss > 0
                        ? 'Ventes ${Fmt.money(s.profit)} − pertes ${Fmt.money(s.valueLoss)}'
                        : 'Marge ${Fmt.percent(s.marginRate)}',
                  ),
                  KpiCard(
                    label: 'Pertes',
                    value: Fmt.money(s.valueLoss),
                    icon: Icons.remove_circle_outline,
                    color: s.valueLoss > 0 ? Theme.of(context).colorScheme.error : okColor,
                    subtitle: s.qtyLoss > 0 ? Fmt.count(s.qtyLoss, 'article') : 'Aucune perte',
                  ),
                  if (_categoryId == null)
                    KpiCard(
                      label: 'Argent encaissé',
                      value: Fmt.money(s.cashIn),
                      icon: Icons.payments_outlined,
                      subtitle: s.cashIn + 1 < s.salesAmount
                          ? 'Une partie des ventes est à crédit'
                          : 'Ventes et remboursements',
                    ),
                  KpiCard(
                    label: 'Achats (entrées)',
                    value: Fmt.money(s.valueIn),
                    icon: Icons.add_shopping_cart,
                    subtitle: '${Fmt.count(s.qtyIn, 'article')} ${Fmt.plural(s.qtyIn, 'reçu')}',
                  ),
                  KpiCard(
                    label: 'Valeur du stock actuel',
                    value: Fmt.money(d.stockValue),
                    icon: Icons.inventory,
                    subtitle: 'au CUMP',
                  ),
                ],
              ),
              const SectionTitle('Classement des ventes'),
              if (d.ranking.isEmpty)
                const Card(child: ListTile(title: Text('Aucune vente sur cette période')))
              else
                Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < d.ranking.length; i++)
                        ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 14,
                            child: Text('${i + 1}', style: const TextStyle(fontSize: 12)),
                          ),
                          title: Text(d.ranking[i].name),
                          subtitle: Text(
                            '${Fmt.count(d.ranking[i].quantity, 'vendu')} · bénéfice ${Fmt.money(d.ranking[i].profit)}',
                          ),
                          trailing: Text(
                            Fmt.money(d.ranking[i].amount),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => ProductDetailScreen(productId: d.ranking[i].productId)),
                          ),
                        ),
                    ],
                  ),
                ),
              const SectionTitle('Ventes par catégorie'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: CategoryPie(shares: d.salesByCategory),
                ),
              ),
              const SectionTitle('Valeur du stock par catégorie'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: CategoryPie(shares: d.stockByCategory),
                ),
              ),
              const SectionTitle('Achats par fournisseur'),
              if (d.suppliers.isEmpty)
                const Card(child: ListTile(title: Text('Aucun achat sur cette période')))
              else
                Card(
                  child: Column(
                    children: [
                      for (final sup in d.suppliers)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.local_shipping_outlined),
                          title: Text(sup.category),
                          trailing: Text(Fmt.money(sup.value), style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
