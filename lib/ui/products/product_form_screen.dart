import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/stock_math.dart';
import '../../data/models.dart';
import '../../data/shop_repository.dart';
import '../../services/session.dart';
import '../common.dart';

const unitSuggestions = ['unité', 'pièce', 'carton', 'paquet', 'sac', 'kg', 'litre', 'boîte', 'douzaine'];

/// Création / modification d'un produit.
class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({super.key, this.product});
  final Product? product;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _ref, _name, _unit, _threshold, _initialStock, _initialCost, _price;
  int? _categoryId;
  List<Category> _categories = [];
  bool _openingLocked = false;
  bool _busy = false;

  bool get _isEdit => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    final user = context.read<Session>().user!;
    String n(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    _ref = TextEditingController(text: p?.reference ?? '');
    _name = TextEditingController(text: p?.name ?? '');
    _unit = TextEditingController(text: p?.unit ?? 'unité');
    _threshold = TextEditingController(text: '${p?.alertThreshold ?? user.defaultAlertThreshold}');
    _initialStock = TextEditingController(text: '${p?.initialStock ?? 0}');
    _initialCost = TextEditingController(text: p == null ? '' : n(p.initialUnitCost));
    _price = TextEditingController(text: p == null ? '' : n(p.sellingPrice));
    _categoryId = p?.categoryId;
    for (final c in [_initialCost, _price]) {
      c.addListener(() => setState(() {}));
    }
    _load();
  }

  Future<void> _load() async {
    final repo = context.read<ShopRepository>();
    final uid = context.read<Session>().userId;
    final cats = await repo.categories(uid);
    final locked = _isEdit && await repo.hasMovements(widget.product!.id!);
    if (mounted) {
      setState(() {
        _categories = cats;
        _openingLocked = locked;
      });
    }
  }

  @override
  void dispose() {
    for (final c in [_ref, _name, _unit, _threshold, _initialStock, _initialCost, _price]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _addCategory() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Nouvelle catégorie'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Nom'),
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Ajouter')),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      final repo = context.read<ShopRepository>();
      final uid = context.read<Session>().userId;
      final id = await repo.addCategory(uid, name);
      final cats = await repo.categories(uid);
      setState(() {
        _categories = cats;
        _categoryId = id;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final price = Fmt.parseNumber(_price.text)!;
    final cost = Fmt.parseNumber(_initialCost.text)!;
    if (price > 0 && price < cost) {
      final ok = await confirm(context, 'Prix de vente inférieur au coût',
          'Le prix de vente (${Fmt.money(price)}) est inférieur au coût d\'achat (${Fmt.money(cost)}). '
          'Chaque vente sera à perte. Continuer ?');
      if (!ok) return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await context.read<ShopRepository>().saveProduct(
            context.read<Session>().userId,
            Product(
              id: widget.product?.id,
              reference: _ref.text,
              name: _name.text,
              categoryId: _categoryId,
              unit: _unit.text,
              alertThreshold: int.parse(_threshold.text.trim()),
              initialStock: int.parse(_initialStock.text.trim()),
              initialUnitCost: cost,
              sellingPrice: price,
              archived: widget.product?.archived ?? false,
            ),
          );
      if (!mounted) return;
      showSuccess(context, _isEdit ? 'Produit modifié' : 'Produit ajouté');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cost = Fmt.parseNumber(_initialCost.text) ?? 0;
    final price = Fmt.parseNumber(_price.text) ?? 0;
    final stock = int.tryParse(_initialStock.text.trim()) ?? 0;
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Modifier le produit' : 'Nouveau produit')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 130,
                child: TextFormField(
                  controller: _ref,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Référence *', hintText: 'ex. S1'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Obligatoire' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Désignation *'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Obligatoire' : null,
                ),
              ),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<int?>(
                  initialValue: _categories.any((c) => c.id == _categoryId) ? _categoryId : null,
                  key: ValueKey('cat-${_categories.length}-$_categoryId'),
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Catégorie'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Sans catégorie')),
                    for (final c in _categories) DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (v) => setState(() => _categoryId = v),
                ),
              ),
              IconButton(tooltip: 'Nouvelle catégorie', onPressed: _addCategory, icon: const Icon(Icons.add_circle_outline)),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: Autocomplete<String>(
                  initialValue: TextEditingValue(text: _unit.text),
                  optionsBuilder: (v) => unitSuggestions.where((u) => u.startsWith(v.text.toLowerCase())),
                  onSelected: (v) => _unit.text = v,
                  fieldViewBuilder: (context, ctrl, focus, _) => TextFormField(
                    controller: ctrl,
                    focusNode: focus,
                    onChanged: (v) => _unit.text = v,
                    decoration: const InputDecoration(labelText: 'Unité'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _threshold,
                  keyboardType: TextInputType.number,
                  inputFormatters: intInput,
                  decoration: const InputDecoration(labelText: 'Seuil d\'alerte *'),
                  validator: (v) => requiredInt(v, field: 'Le seuil'),
                ),
              ),
            ]),
            const SizedBox(height: 24),
            Text('Prix', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextFormField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: decimalInput,
              decoration: const InputDecoration(labelText: 'Prix de vente unitaire *', suffixText: 'FCFA'),
              validator: (v) => requiredAmount(v),
            ),
            const SizedBox(height: 24),
            Text('Stock d\'ouverture', style: Theme.of(context).textTheme.titleSmall),
            if (_openingLocked)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Figé : ce produit a déjà des entrées ou des sorties. Pour ajouter du stock, faites une entrée.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _initialStock,
                  enabled: !_openingLocked,
                  keyboardType: TextInputType.number,
                  inputFormatters: intInput,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Stock initial'),
                  validator: (v) => requiredInt(v, field: 'Le stock initial'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _initialCost,
                  enabled: !_openingLocked,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: decimalInput,
                  decoration: const InputDecoration(labelText: 'Coût d\'achat unitaire', suffixText: 'FCFA'),
                  validator: (v) {
                    final base = requiredAmount(v);
                    if (base != null) return base;
                    if ((int.tryParse(_initialStock.text.trim()) ?? 0) > 0 && Fmt.parseNumber(v) == 0) {
                      return 'Requis si stock initial > 0';
                    }
                    return null;
                  },
                ),
              ),
            ]),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  _line('Valeur du stock initial', Fmt.money(stock * cost)),
                  _line('Marge unitaire', price > 0 ? Fmt.money(price - cost) : '-'),
                  _line('Taux de marge', price > 0 ? Fmt.percent(StockMath.marginRate(price, cost)) : '-'),
                ]),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.save),
              label: Text(_isEdit ? 'Enregistrer les modifications' : 'Ajouter le produit'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [Expanded(child: Text(k)), Text(v, style: const TextStyle(fontWeight: FontWeight.bold))]),
      );
}
