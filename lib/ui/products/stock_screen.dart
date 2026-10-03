import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/shop_repository.dart';
import '../../services/pdf_reports.dart';
import '../../services/session.dart';
import '../common.dart';
import 'product_detail_screen.dart';
import 'product_form_screen.dart';

enum _StockFilter { all, alerts, archived }

/// Inventaire en temps réel (feuilles "Marchandise" + "Inventaire").
class StockScreen extends StatefulWidget {
  const StockScreen({super.key});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  final _search = TextEditingController();
  String _query = '';
  int? _categoryId;
  _StockFilter _filter = _StockFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(StockItem i) {
    if (_filter == _StockFilter.archived && !i.product.archived) return false;
    if (_filter != _StockFilter.archived && i.product.archived) return false;
    if (_filter == _StockFilter.alerts && !i.status.isAlert) return false;
    if (_categoryId != null && i.product.categoryId != _categoryId) return false;
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return i.product.name.toLowerCase().contains(q) ||
        i.product.reference.toLowerCase().contains(q) ||
        (i.categoryName?.toLowerCase().contains(q) ?? false);
  }

  Future<void> _exportPdf(List<StockItem> items, {required bool reorder}) async {
    final user = context.read<Session>().user!;
    try {
      final active = items.where((i) => !i.product.archived).toList();
      final bytes = reorder
          ? await PdfReports.reorder(user, ShopRepository.alerts(active))
          : await PdfReports.inventory(user, active);
      await PdfReports.share(bytes, reorder ? 'reapprovisionnement.pdf' : 'inventaire.pdf');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Reloading<(List<StockItem>, List<Category>)>(
      load: (repo, uid) async => (await repo.inventory(uid, includeArchived: true), await repo.categories(uid)),
      builder: (context, data) {
        final (all, categories) = data;
        // Catégorie filtrée supprimée entre-temps : on retire le filtre.
        if (_categoryId != null && !categories.any((c) => c.id == _categoryId)) _categoryId = null;
        final items = all.where(_matches).toList();
        final active = all.where((i) => !i.product.archived);
        final totalValue = active.fold<double>(0, (s, i) => s + i.stockValue);
        final alertCount = active.where((i) => i.status.isAlert).length;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Stock'),
            actions: [
              PopupMenuButton<String>(
                tooltip: 'Exporter',
                icon: const Icon(Icons.picture_as_pdf_outlined),
                onSelected: (v) => _exportPdf(all, reorder: v == 'reorder'),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'inventory', child: Text('Inventaire complet (PDF)')),
                  PopupMenuItem(value: 'reorder', child: Text('Produits à réapprovisionner (PDF)')),
                ],
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductFormScreen())),
            icon: const Icon(Icons.add),
            label: const Text('Produit'),
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v.trim()),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Rechercher (nom, référence, catégorie)',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(() {
                              _search.clear();
                              _query = '';
                            }),
                          ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 0,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ChoiceChip(
                        label: Text('Tous (${active.length})'),
                        selected: _filter == _StockFilter.all,
                        onSelected: (_) => setState(() => _filter = _StockFilter.all),
                      ),
                      ChoiceChip(
                        label: Text('Alertes ($alertCount)'),
                        selected: _filter == _StockFilter.alerts,
                        onSelected: (_) => setState(() => _filter = _StockFilter.alerts),
                      ),
                      ChoiceChip(
                        label: const Text('Archivés'),
                        selected: _filter == _StockFilter.archived,
                        onSelected: (_) => setState(() => _filter = _StockFilter.archived),
                      ),
                      PopupMenuButton<int>(
                        tooltip: 'Catégorie',
                        onSelected: (v) => setState(() => _categoryId = v < 0 ? null : v),
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: -1, child: Text('Toutes catégories')),
                          for (final c in categories) PopupMenuItem(value: c.id, child: Text(c.name)),
                        ],
                        child: Chip(
                          avatar: const Icon(Icons.filter_list, size: 18),
                          label: Text(categories.where((c) => c.id == _categoryId).firstOrNull?.name ?? 'Catégorie'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    spacing: 12,
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      Text(Fmt.count(items.length, 'produit'), style: Theme.of(context).textTheme.bodySmall),
                      Text(
                        'Valeur du stock : ${Fmt.money(totalValue)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? EmptyState(
                        icon: Icons.inventory_2_outlined,
                        message: all.isEmpty ? 'Aucun produit pour le moment.' : 'Aucun produit ne correspond.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (context, i) => _StockTile(item: items[i]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StockTile extends StatelessWidget {
  const _StockTile({required this.item});
  final StockItem item;

  @override
  Widget build(BuildContext context) {
    final p = item.product;
    final color = statusColor(context, item.status);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailScreen(productId: p.id!))),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 5, color: p.archived ? Colors.grey : color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${p.reference} · ${item.categoryName ?? 'Sans catégorie'}',
                              style: Theme.of(context).textTheme.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'PV ${Fmt.money(p.sellingPrice)} · CUMP ${Fmt.money(item.cump)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            Fmt.qtyUnit(item.stock, p.unit),
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color),
                          ),
                          const SizedBox(height: 4),
                          StatusBadge(item.status, compact: true),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
