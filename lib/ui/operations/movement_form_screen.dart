import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/stock_math.dart';
import '../../data/models.dart';
import '../../data/shop_repository.dart';
import '../../services/session.dart';
import '../common.dart';
import '../product_picker.dart';

/// Motifs de perte proposés (le commerçant peut aussi écrire le sien).
const lossReasons = ['Casse', 'Périmé', 'Vol', 'Consommation personnelle', 'Cadeau / échantillon', 'Erreur de stock'];

/// Saisie d'une entrée (achat fournisseur) ou d'une perte (casse, vol, périmé...) —
/// équivalent de la feuille "Opération" des classeurs, avec les contrôles
/// qui y manquaient (référence existante, stock suffisant, date valide).
/// Les ventes passent par le panier ([CartScreen]).
class MovementFormScreen extends StatefulWidget {
  const MovementFormScreen({super.key, required this.type, this.productId})
    : assert(type != MovementType.sale, 'Les ventes passent par CartScreen');
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

  bool get _isLoss => widget.type == MovementType.loss;

  @override
  void initState() {
    super.initState();
    _qty.addListener(() => setState(() {}));
    _price.addListener(() => setState(() {}));
    _note.addListener(() => setState(() {}));
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
    final partners = _isLoss ? <String>[] : await repo.partners(uid, widget.type);
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
    if (_isLoss) return;
    // Coût d'achat proposé : le CUMP actuel (à corriger avec le prix de la facture).
    final v = item.cump;
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
    final picked = await pickProduct(context, _items, needsStock: _isLoss);
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
    final price = _isLoss ? item.cump : Fmt.parseNumber(_price.text)!;

    final lines = <String>[
      '${item.product.name} (${item.product.reference})',
      'Quantité : ${Fmt.qtyUnit(qty, item.product.unit)}',
      if (_isLoss) ...[
        'Motif : ${_note.text.trim()}',
        'Valeur perdue (au CUMP) : ${Fmt.money(qty * price)}',
        'Stock après : ${Fmt.qtyUnit(item.stock - qty, item.product.unit)}',
      ] else ...[
        'Coût d\'achat : ${Fmt.money(price)}',
        'Total : ${Fmt.money(qty * price)}',
        'Stock après : ${Fmt.qtyUnit(item.stock + qty, item.product.unit)}',
      ],
      'Date : ${Fmt.dateTime(date)}',
    ];
    final ok = await confirm(
      context,
      _isLoss ? 'Confirmer la perte' : 'Confirmer l\'entrée',
      lines.join('\n'),
      ok: 'Enregistrer',
      danger: _isLoss,
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
        partner: _isLoss ? null : _partner.text,
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
    final price = _isLoss ? (item?.cump ?? 0) : (Fmt.parseNumber(_price.text) ?? 0);
    final title = _isLoss ? 'Déclarer une perte' : 'Nouvelle entrée';

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
                  if (_isLoss)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Pour un article cassé, périmé, volé ou consommé : il sort du stock sans être vendu. '
                        'Sa valeur est comptée en perte dans les rapports.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
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
                            if (_isLoss && item != null && int.parse(v!.trim()) > item.stock) {
                              return 'Max. ${item.stock < 0 ? 0 : item.stock}';
                            }
                            return null;
                          },
                        ),
                      ),
                      if (!_isLoss) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _price,
                            keyboardType: TextInputType.number,
                            inputFormatters: intInput,
                            decoration: const InputDecoration(labelText: 'Coût unitaire *', suffixText: 'FCFA'),
                            validator: (v) => requiredAmount(v, allowZero: false),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_isLoss) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 0,
                      children: [
                        for (final r in lossReasons)
                          ChoiceChip(
                            label: Text(r),
                            selected: _note.text.trim() == r,
                            onSelected: (_) => _note.text = r,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _note,
                      decoration: const InputDecoration(
                        labelText: 'Motif *',
                        hintText: 'ex. bouteilles cassées pendant le transport',
                        prefixIcon: Icon(Icons.report_problem_outlined),
                      ),
                      validator: (v) => (v == null || v.trim().length < 3) ? 'Indiquez le motif de la perte' : null,
                    ),
                  ] else ...[
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
                          decoration: const InputDecoration(
                            labelText: 'Fournisseur (facultatif)',
                            prefixIcon: Icon(Icons.local_shipping_outlined),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _note,
                      decoration: const InputDecoration(
                        labelText: 'Note (facultatif)',
                        hintText: 'ex. n° de facture',
                        prefixIcon: Icon(Icons.notes),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Card(
                    color: _isLoss
                        ? Theme.of(context).colorScheme.errorContainer
                        : Theme.of(context).colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(_isLoss ? 'Valeur perdue' : 'Total', style: const TextStyle(fontSize: 16)),
                              ),
                              Text(
                                Fmt.money(qty * price),
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          if (!_isLoss && item != null && qty > 0 && price > 0) ...[
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
                    style: _isLoss
                        ? FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error)
                        : null,
                    onPressed: _busy ? null : _submit,
                    icon: Icon(_isLoss ? Icons.remove_circle_outline : Icons.add_shopping_cart),
                    label: Text(_isLoss ? 'Enregistrer la perte' : 'Enregistrer l\'entrée'),
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
