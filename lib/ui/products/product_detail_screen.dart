import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/stock_math.dart';
import '../../data/models.dart';
import '../../data/shop_repository.dart';
import '../../services/session.dart';
import '../common.dart';
import '../operations/movement_form_screen.dart';
import '../operations/movement_tile.dart';
import 'product_form_screen.dart';

class _Detail {
  final StockItem? item;
  final List<Movement> movements;
  final bool hasMovements;
  _Detail(this.item, this.movements, this.hasMovements);
}

class ProductDetailScreen extends StatelessWidget {
  const ProductDetailScreen({super.key, required this.productId});
  final int productId;

  @override
  Widget build(BuildContext context) {
    return Reloading<_Detail>(
      load: (repo, uid) async {
        final moves = await repo.movements(uid, productId: productId);
        return _Detail(await repo.stockItem(uid, productId), moves, moves.isNotEmpty);
      },
      builder: (context, d) {
        final item = d.item;
        if (item == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(icon: Icons.search_off, message: 'Produit introuvable'),
          );
        }
        final p = item.product;
        return Scaffold(
          appBar: AppBar(
            title: Text(p.name),
            actions: [
              IconButton(
                tooltip: 'Modifier',
                icon: const Icon(Icons.edit),
                onPressed: () =>
                    Navigator.push(context, MaterialPageRoute(builder: (_) => ProductFormScreen(product: p))),
              ),
              PopupMenuButton<String>(
                onSelected: (v) => _menu(context, v, item, d.hasMovements),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'archive', child: Text(p.archived ? 'Réactiver' : 'Archiver')),
                  if (!d.hasMovements) const PopupMenuItem(value: 'delete', child: Text('Supprimer')),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${p.reference} · ${item.categoryName ?? 'Sans catégorie'}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  StatusBadge(item.status),
                ],
              ),
              if (p.archived)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Produit archivé : il n\'apparaît plus dans les ventes ni les entrées.'),
                ),
              const SizedBox(height: 12),
              KpiGrid(
                children: [
                  KpiCard(
                    label: 'Stock final',
                    value: Fmt.qtyUnit(item.stock, p.unit),
                    icon: Icons.inventory_2,
                    color: statusColor(context, item.status),
                    subtitle: 'Seuil d\'alerte : ${p.alertThreshold}',
                  ),
                  KpiCard(
                    label: 'Valeur du stock',
                    value: Fmt.money(item.stockValue),
                    icon: Icons.account_balance_wallet,
                    subtitle: 'CUMP ${Fmt.money(item.cump)}',
                  ),
                  KpiCard(
                    label: 'Ventes cumulées',
                    value: Fmt.money(item.salesAmount),
                    icon: Icons.point_of_sale,
                    subtitle: '${Fmt.qtyUnit(item.qtyOut, p.unit)} ${Fmt.plural(item.qtyOut, 'vendu')}',
                  ),
                  KpiCard(
                    label: 'Bénéfice cumulé',
                    value: Fmt.money(item.profit),
                    icon: Icons.trending_up,
                    color: item.profit >= 0 ? okColor : Theme.of(context).colorScheme.error,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      _line('Stock initial', '${p.initialStock} à ${Fmt.money(p.initialUnitCost)}'),
                      _line('Entrées', '+ ${item.qtyIn} (${Fmt.money(item.valueIn)})'),
                      _line('Sorties', '- ${item.qtyOut}'),
                      const Divider(),
                      _line('Prix de vente', Fmt.money(p.sellingPrice)),
                      _line('Marge unitaire au CUMP', Fmt.money(p.sellingPrice - item.cump)),
                      _line('Taux de marge', Fmt.percent(StockMath.marginRate(p.sellingPrice, item.cump))),
                      if (item.suggestedReorder > 0) ...[
                        const Divider(),
                        _line('Quantité à commander (suggestion)', Fmt.qtyUnit(item.suggestedReorder, p.unit)),
                      ],
                    ],
                  ),
                ),
              ),
              if (!p.archived) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: item.stock > 0 ? () => _open(context, MovementType.sale, p) : null,
                        icon: const Icon(Icons.point_of_sale),
                        label: const Text('Vendre'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () => _open(context, MovementType.entry, p),
                        icon: const Icon(Icons.add_shopping_cart),
                        label: const Text('Entrée'),
                      ),
                    ),
                  ],
                ),
              ],
              SectionTitle('Historique (${d.movements.length})'),
              if (d.movements.isEmpty)
                const Text('Aucune opération pour ce produit.')
              else
                Card(
                  child: Column(children: [for (final m in d.movements) MovementTile(movement: m, showProduct: false)]),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _line(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(k)),
        Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );

  void _open(BuildContext context, MovementType type, Product p) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => MovementFormScreen(type: type, productId: p.id),
    ),
  );

  Future<void> _menu(BuildContext context, String action, StockItem item, bool hasMovements) async {
    final repo = context.read<ShopRepository>();
    final uid = context.read<Session>().userId;
    final p = item.product;
    try {
      if (action == 'archive') {
        if (!p.archived && item.stock > 0) {
          final ok = await confirm(
            context,
            'Archiver ${p.name} ?',
            'Il reste ${Fmt.qtyUnit(item.stock, p.unit)} en stock. Le produit sera masqué des ventes et entrées.',
          );
          if (!ok) return;
        }
        await repo.setArchived(uid, p.id!, !p.archived);
      } else if (action == 'delete') {
        if (!context.mounted) return;
        final ok = await confirm(
          context,
          'Supprimer ${p.name} ?',
          'Cette action est définitive.',
          ok: 'Supprimer',
          danger: true,
        );
        if (!ok) return;
        await repo.deleteProduct(uid, p.id!);
        if (context.mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}
