import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/stock_math.dart';
import '../../data/models.dart';
import '../../data/shop_repository.dart';
import '../../services/session.dart';
import '../common.dart';

/// Saisie d'une entrée (achat fournisseur) ou d'une sortie (vente) —
/// équivalent de la feuille "Opération" des classeurs, avec les contrôles
/// qui y manquaient (référence existante, stock suffisant, date valide).
class MovementFormScreen extends StatefulWidget {
  const MovementFormScreen({super.key, required this.type, this.productId});
  final MovementType type;
  final int? productId;

  @override
  State<MovementFormScreen> createState() => _MovementFormScreenState();
}

class _MovementFormScreenState extends State<MovementFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _qty = TextEditingController();
  final _price = TextEditingController();
  final _partner = TextEditingController();
  final _note = TextEditingController();
  List<StockItem> _items = [];
  List<String> _partners = [];
  StockItem? _selected;

  /// null = « maintenant » : l'heure est prise au moment de l'enregistrement.
  DateTime? _pickedDate;
  DateTime get _date => _pickedDate ?? DateTime.now();
  bool _busy = false;
  bool _loading = true;
  int _resetCount = 0;

  bool get _isSale => widget.type == MovementType.sale;

  @override
  void initState() {
    super.initState();
    _qty.addListener(() => setState(() {}));
    _price.addListener(() => setState(() {}));
    _load(selectId: widget.productId);
  }

  @override
  void dispose() {
    for (final c in [_qty, _price, _partner, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load({int? selectId}) async {
    final repo = context.read<ShopRepository>();
    final uid = context.read<Session>().userId;
    final items = await repo.inventory(uid);
    final partners = await repo.partners(uid, widget.type);
    if (!mounted) return;
    setState(() {
      _items = items;
      _partners = partners;
      _loading = false;
      final id = selectId ?? _selected?.product.id;
      _selected = id == null ? null : items.where((i) => i.product.id == id).firstOrNull;
      if (selectId != null && _selected != null) _prefillPrice(_selected!);
    });
  }

  void _prefillPrice(StockItem item) {
    final v = _isSale ? item.product.sellingPrice : item.cump;
    _price.text = v <= 0 ? '' : v.round().toString();
  }

  void _reset() {
    _formKey.currentState?.reset();
    _qty.clear();
    _price.clear();
    _partner.clear();
    _note.clear();
    setState(() {
      _selected = null;
      _pickedDate = null;
      _resetCount++;
    });
  }

  Future<void> _pickProduct() async {
    final picked = await showModalBottomSheet<StockItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ProductPicker(items: _items, forSale: _isSale),
    );
    if (picked != null) {
      setState(() => _selected = picked);
      _prefillPrice(picked);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      helpText: 'Date de l\'opération',
    );
    if (d == null) return;
    final today = DateUtils.isSameDay(d, now);
    setState(() => _pickedDate = today ? null : DateTime(d.year, d.month, d.day, 12));
  }

  Future<void> _submit() async {
    if (_selected == null) {
      showError(context, const BusinessException('Choisissez un produit'));
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    final item = _selected!;
    final qty = int.parse(_qty.text.trim());
    final date = _date;
    final price = Fmt.parseNumber(_price.text)!;
    final total = qty * price;

    final lines = <String>[
      '${item.product.name} (${item.product.reference})',
      'Quantité : ${Fmt.qtyUnit(qty, item.product.unit)}',
      '${_isSale ? 'Prix de vente' : 'Coût d\'achat'} : ${Fmt.money(price)}',
      'Total : ${Fmt.money(total)}',
      'Date : ${Fmt.dateTime(date)}',
    ];
    if (_isSale) {
      final profit = StockMath.saleProfit(qty, price, item.cump);
      lines.add('Bénéfice estimé : ${Fmt.money(profit)}');
      if (price < item.cump) lines.add('\n⚠ Vente à perte : prix inférieur au CUMP (${Fmt.money(item.cump)}).');
    }
    final ok = await confirm(
      context,
      _isSale ? 'Confirmer la vente' : 'Confirmer l\'entrée',
      lines.join('\n'),
      ok: 'Enregistrer',
    );
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    try {
      final m = await context.read<ShopRepository>().recordMovement(
        userId: context.read<Session>().userId,
        type: widget.type,
        productId: item.product.id!,
        quantity: qty,
        unitPrice: price,
        date: date,
        partner: _partner.text,
        note: _note.text,
      );
      if (!mounted) return;
      showSuccess(context, '${m.type.label} ${m.code} enregistrée — ${Fmt.money(m.total)}');
      final keepProduct = widget.productId != null;
      _reset();
      await _load(selectId: keepProduct ? item.product.id : null);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _selected;
    final qty = int.tryParse(_qty.text.trim()) ?? 0;
    final price = Fmt.parseNumber(_price.text) ?? 0;
    final title = _isSale ? 'Nouvelle vente' : 'Nouvelle entrée';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [TextButton(onPressed: _busy ? null : _reset, child: const Text('Effacer'))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? const EmptyState(
              icon: Icons.inventory_2_outlined,
              message: 'Aucun produit actif. Ajoutez d\'abord vos produits dans l\'onglet Stock.',
            )
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  InkWell(
                    onTap: _pickProduct,
                    borderRadius: BorderRadius.circular(4),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Produit *',
                        prefixIcon: Icon(Icons.inventory_2_outlined),
                        suffixIcon: Icon(Icons.arrow_drop_down),
                      ),
                      child: Text(
                        item == null
                            ? 'Rechercher par nom ou référence'
                            : '${item.product.reference} — ${item.product.name}',
                        overflow: TextOverflow.ellipsis,
                        style: item == null ? TextStyle(color: Theme.of(context).hintColor) : null,
                      ),
                    ),
                  ),
                  if (item != null) ...[
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            _line('Catégorie', item.categoryName ?? 'Sans catégorie'),
                            _line('Unité', item.product.unit),
                            Row(
                              children: [
                                const Expanded(child: Text('Stock disponible')),
                                Text(
                                  '${Fmt.qtyUnit(item.stock, item.product.unit)}  ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: statusColor(context, item.status),
                                  ),
                                ),
                                StatusBadge(item.status, compact: true),
                              ],
                            ),
                            _line('CUMP actuel', Fmt.money(item.cump)),
                            if (_isSale) _line('Prix de vente catalogue', Fmt.money(item.product.sellingPrice)),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: _pickDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Date', prefixIcon: Icon(Icons.event)),
                      child: Text(_pickedDate == null ? 'Maintenant' : Fmt.date(_pickedDate!)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _qty,
                          keyboardType: TextInputType.number,
                          inputFormatters: intInput,
                          decoration: InputDecoration(labelText: 'Quantité *', suffixText: item?.product.unit),
                          validator: (v) {
                            final err = requiredInt(v, min: 1, field: 'La quantité');
                            if (err != null) return err;
                            if (_isSale && item != null && int.parse(v!.trim()) > item.stock) {
                              return 'Max. ${item.stock < 0 ? 0 : item.stock}';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _price,
                          keyboardType: TextInputType.number,
                          inputFormatters: intInput,
                          decoration: InputDecoration(
                            labelText: _isSale ? 'Prix unitaire *' : 'Coût unitaire *',
                            suffixText: 'FCFA',
                          ),
                          validator: (v) => requiredAmount(v, allowZero: _isSale),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Autocomplete<String>(
                    key: ValueKey(_resetCount),
                    optionsBuilder: (v) => v.text.isEmpty
                        ? const Iterable<String>.empty()
                        : _partners.where((p) => p.toLowerCase().contains(v.text.toLowerCase())),
                    onSelected: (v) => _partner.text = v,
                    fieldViewBuilder: (context, ctrl, focus, _) {
                      return TextFormField(
                        controller: ctrl,
                        focusNode: focus,
                        textCapitalization: TextCapitalization.words,
                        onChanged: (v) => _partner.text = v,
                        decoration: InputDecoration(
                          labelText: _isSale ? 'Client (facultatif)' : 'Fournisseur (facultatif)',
                          prefixIcon: Icon(_isSale ? Icons.person_outline : Icons.local_shipping_outlined),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _note,
                    decoration: InputDecoration(
                      labelText: 'Note (facultatif)',
                      hintText: _isSale ? '' : 'ex. n° de facture',
                      prefixIcon: const Icon(Icons.notes),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Expanded(child: Text('Total', style: TextStyle(fontSize: 16))),
                              Text(
                                Fmt.money(qty * price),
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          if (_isSale && item != null && qty > 0) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Expanded(child: Text('Bénéfice estimé')),
                                Text(
                                  Fmt.money(StockMath.saleProfit(qty, price, item.cump)),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: price < item.cump ? Theme.of(context).colorScheme.error : okColor,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (!_isSale && item != null && qty > 0 && price > 0) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Expanded(child: Text('Nouveau CUMP')),
                                Text(
                                  Fmt.money(
                                    StockMath.cump(
                                      initialStock: item.product.initialStock,
                                      initialUnitCost: item.product.initialUnitCost,
                                      qtyIn: item.qtyIn + qty,
                                      valueIn: item.valueIn + qty * price,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _busy ? null : _submit,
                    icon: Icon(_isSale ? Icons.point_of_sale : Icons.add_shopping_cart),
                    label: Text(_isSale ? 'Enregistrer la vente' : 'Enregistrer l\'entrée'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _line(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(k)),
        Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

class _ProductPicker extends StatefulWidget {
  const _ProductPicker({required this.items, required this.forSale});
  final List<StockItem> items;
  final bool forSale;

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
                        final disabled = widget.forSale && it.stock <= 0;
                        return ListTile(
                          enabled: !disabled,
                          title: Text(it.product.name),
                          subtitle: Text('${it.product.reference} · ${it.categoryName ?? 'Sans catégorie'}'),
                          trailing: Text(
                            disabled ? 'Rupture' : Fmt.qtyUnit(it.stock, it.product.unit),
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
