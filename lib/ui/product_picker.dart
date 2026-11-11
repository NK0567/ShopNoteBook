import 'package:flutter/material.dart';

import '../core/format.dart';
import '../data/models.dart';
import 'common.dart';

/// Ouvre la liste de recherche des produits actifs.
/// [needsStock] : les produits sans stock disponible sont grisés (ventes, pertes).
/// [reserved] : quantités déjà prises dans le panier, déduites du disponible.
Future<StockItem?> pickProduct(
  BuildContext context,
  List<StockItem> items, {
  bool needsStock = false,
  Map<int, int> reserved = const {},
}) => showModalBottomSheet<StockItem>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _ProductPicker(items: items, needsStock: needsStock, reserved: reserved),
);

class _ProductPicker extends StatefulWidget {
  const _ProductPicker({required this.items, required this.needsStock, required this.reserved});
  final List<StockItem> items;
  final bool needsStock;
  final Map<int, int> reserved;

  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final list = widget.items
        .where(
          (i) => q.isEmpty || i.product.name.toLowerCase().contains(q) || i.product.reference.toLowerCase().contains(q),
        )
        .toList();
    // La feuille remonte au-dessus du clavier et la liste rétrécit au lieu d'être masquée.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final height = MediaQuery.sizeOf(context).height * 0.75 - keyboard;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SizedBox(
        height: height < 220 ? 220 : height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _q = v.trim()),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Nom ou référence',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text('Aucun produit trouvé'))
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final it = list[i];
                        final available = it.stock - (widget.reserved[it.product.id] ?? 0);
                        final disabled = widget.needsStock && available <= 0;
                        return ListTile(
                          enabled: !disabled,
                          title: Text(it.product.name),
                          subtitle: Text(
                            '${it.product.reference} · ${it.categoryName ?? 'Sans catégorie'}'
                            '${it.product.sellingPrice > 0 ? ' · ${Fmt.money(it.product.sellingPrice)}' : ''}',
                          ),
                          trailing: Text(
                            disabled ? 'Rupture' : Fmt.qtyUnit(available < 0 ? 0 : available, it.product.unit),
                            style: TextStyle(color: statusColor(context, it.status), fontWeight: FontWeight.bold),
                          ),
                          onTap: () => Navigator.pop(context, it),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
