import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/shop_repository.dart';
import '../../services/pdf_reports.dart';
import '../../services/session.dart';
import '../common.dart';
import '../product_picker.dart';
import 'ticket_screen.dart';

/// Vente au comptoir : un panier d'un ou plusieurs articles, encaissement
/// (comptant, partiel ou à crédit), calcul de la monnaie et reçu.
class CartScreen extends StatefulWidget {
  const CartScreen({super.key, this.productId});

  /// Produit ajouté d'office au panier (vente lancée depuis une fiche produit).
  final int? productId;

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _received = TextEditingController();
  final _client = TextEditingController();
  final _note = TextEditingController();
  List<StockItem> _items = [];
  List<String> _clients = [];
  final List<SaleLine> _lines = [];
  String _method = paymentMethods.first;

  /// Tant que le commerçant n'a pas touché au montant reçu, il suit le total.
  bool _receivedEdited = false;
  bool _loading = true;
  bool _busy = false;
  int _clientFieldKey = 0;

  double get _total => _lines.fold(0, (s, l) => s + l.total);
  double get _profit => _lines.fold(0, (s, l) => s + l.profit);
  double get _receivedAmount => _receivedEdited ? (Fmt.parseNumber(_received.text) ?? 0) : _total;
  double get _change => _receivedAmount - _total;

  Map<int, int> get _reserved {
    final m = <int, int>{};
    for (final l in _lines) {
      m[l.item.product.id!] = (m[l.item.product.id!] ?? 0) + l.quantity;
    }
    return m;
  }

  @override
  void initState() {
    super.initState();
    _received.addListener(() => setState(() {}));
    _client.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _received.dispose();
    _client.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = context.read<ShopRepository>();
    final uid = context.read<Session>().userId;
    final items = await repo.inventory(uid);
    final clients = await repo.clients(uid);
    if (!mounted) return;
    setState(() {
      _items = items;
      _clients = clients;
      _loading = false;
    });
    final first = widget.productId == null ? null : items.where((i) => i.product.id == widget.productId).firstOrNull;
    if (first != null && first.stock > 0) await _editLine(first);
  }

  void _syncReceived() {
    if (!_receivedEdited) _received.text = _total <= 0 ? '' : _total.round().toString();
  }

  Future<void> _addProduct() async {
    final picked = await pickProduct(context, _items, needsStock: true, reserved: _reserved);
    if (picked != null && mounted) await _editLine(picked);
  }

  /// Ajoute (ou modifie) la ligne d'un produit : quantité et prix.
  Future<void> _editLine(StockItem item, {int? index}) async {
    final existing = index != null ? _lines[index] : null;
    final already = (_reserved[item.product.id] ?? 0) - (existing?.quantity ?? 0);
    final line = await showDialog<SaleLine>(
      context: context,
      builder: (_) => _LineDialog(item: item, available: item.stock - already, initial: existing),
    );
    if (line == null || !mounted) return;
    setState(() {
      if (index != null) {
        _lines[index] = line;
      } else {
        // Même produit au même prix : on regroupe sur une seule ligne.
        final same = _lines.indexWhere((l) => l.item.product.id == item.product.id && l.unitPrice == line.unitPrice);
        if (same >= 0) {
          _lines[same] = _lines[same].copyWith(quantity: _lines[same].quantity + line.quantity);
        } else {
          _lines.add(line);
        }
      }
      _syncReceived();
    });
  }

  void _removeLine(int i) => setState(() {
    _lines.removeAt(i);
    _syncReceived();
  });

  void _setReceived(double v) {
    _receivedEdited = true;
    _received.text = v.round().toString();
  }

  Future<void> _submit() async {
    if (_lines.isEmpty) {
      showError(context, const BusinessException('Ajoutez au moins un article'));
      return;
    }
    final paid = _receivedAmount;
    final credit = _total - paid;
    final client = _client.text.trim();
    if (credit >= 1 && client.isEmpty) {
      showError(context, const BusinessException('Vente à crédit : indiquez le nom du client'));
      return;
    }
    final belowCost = _lines.where((l) => l.unitPrice < l.item.cump).toList();
    final summary = [
      for (final l in _lines) '• ${l.item.product.name} : ${l.quantity} × ${Fmt.money(l.unitPrice)}',
      '',
      'Total : ${Fmt.money(_total)}',
      if (credit >= 1) ...[
        'Payé maintenant : ${Fmt.money(paid < 0 ? 0 : paid)} ($_method)',
        'Reste à crédit : ${Fmt.money(credit)} — $client',
      ] else ...[
        'Encaissé : ${Fmt.money(_total)} ($_method)',
        if (_change >= 1) 'Monnaie à rendre : ${Fmt.money(_change)}',
      ],
      if (belowCost.isNotEmpty)
        '\n⚠ Vente à perte : ${belowCost.map((l) => l.item.product.name).join(', ')} '
            '(prix inférieur au coût moyen).',
    ];
    final ok = await confirm(context, 'Confirmer la vente', summary.join('\n'), ok: 'Encaisser');
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    try {
      final detail = await context.read<ShopRepository>().recordSale(
        userId: context.read<Session>().userId,
        lines: List.of(_lines),
        date: DateTime.now(),
        client: client,
        paid: paid < 0 ? 0 : paid,
        method: _method,
        note: _note.text,
      );
      if (!mounted) return;
      final change = _change;
      await _showDone(detail, change);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showDone(TicketDetail detail, double change) async {
    final t = detail.ticket;
    final again = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: okColor, size: 40),
        title: Text('Vente ${t.code} enregistrée'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total : ${Fmt.money(t.total)}'),
            if (change >= 1)
              Text('Monnaie à rendre : ${Fmt.money(change)}', style: const TextStyle(fontWeight: FontWeight.bold)),
            if (t.isCredit)
              Text(
                'Crédit de ${Fmt.money(t.balance)} au nom de ${t.client}',
                style: TextStyle(color: Theme.of(c).colorScheme.error, fontWeight: FontWeight.bold),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final user = c.read<Session>().user!;
              try {
                await PdfReports.share(await PdfReports.receipt(user, detail), 'recu-${t.code}.pdf');
              } catch (e) {
                if (c.mounted) showError(c, e);
              }
            },
            child: const Text('Reçu'),
          ),
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Terminer')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Nouvelle vente')),
        ],
      ),
    );
    if (!mounted) return;
    if (again == true) {
      setState(() {
        _lines.clear();
        _receivedEdited = false;
        _received.clear();
        _client.clear();
        _note.clear();
        _method = paymentMethods.first;
        _clientFieldKey++;
      });
      await _load();
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final credit = _total - _receivedAmount;
    final isCredit = _lines.isNotEmpty && credit >= 1;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nouvelle vente'),
        actions: [
          IconButton(
            tooltip: 'Tickets récents',
            icon: const Icon(Icons.receipt_long),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TicketsScreen())),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? const EmptyState(
              icon: Icons.inventory_2_outlined,
              message: 'Aucun produit actif. Ajoutez d\'abord vos produits dans l\'onglet Stock.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Articles', style: theme.textTheme.titleMedium)),
                    FilledButton.tonalIcon(
                      onPressed: _busy ? null : _addProduct,
                      icon: const Icon(Icons.add),
                      label: const Text('Ajouter'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_lines.isEmpty)
                  Card(
                    child: InkWell(
                      onTap: _addProduct,
                      child: const Padding(
                        padding: EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Icon(Icons.add_shopping_cart, size: 40),
                            SizedBox(height: 8),
                            Text('Touchez pour ajouter un article', textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  Card(
                    child: Column(
                      children: [
                        for (var i = 0; i < _lines.length; i++)
                          ListTile(
                            onTap: () => _editLine(_lines[i].item, index: i),
                            title: Text(_lines[i].item.product.name),
                            subtitle: Text(
                              '${Fmt.qtyUnit(_lines[i].quantity, _lines[i].item.product.unit)} × ${Fmt.money(_lines[i].unitPrice)}',
                              style: _lines[i].unitPrice < _lines[i].item.cump
                                  ? TextStyle(color: theme.colorScheme.error)
                                  : null,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(Fmt.money(_lines[i].total), style: const TextStyle(fontWeight: FontWeight.bold)),
                                IconButton(
                                  tooltip: 'Retirer',
                                  icon: const Icon(Icons.close),
                                  onPressed: () => _removeLine(i),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                Card(
                  color: theme.colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Expanded(child: Text('Total', style: TextStyle(fontSize: 16))),
                            Text(Fmt.money(_total), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        if (_lines.isNotEmpty)
                          Row(
                            children: [
                              const Expanded(child: Text('Bénéfice estimé')),
                              Text(
                                Fmt.money(_profit),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _profit < 0 ? theme.colorScheme.error : okColor,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                const SectionTitle('Paiement'),
                TextField(
                  controller: _received,
                  keyboardType: TextInputType.number,
                  inputFormatters: intInput,
                  onChanged: (_) => _receivedEdited = true,
                  decoration: const InputDecoration(
                    labelText: 'Montant reçu du client',
                    suffixText: 'FCFA',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    ActionChip(
                      label: const Text('Montant exact'),
                      onPressed: _lines.isEmpty ? null : () => _setReceived(_total),
                    ),
                    for (final note in const [1000, 2000, 5000, 10000])
                      if (note > _total && _lines.isNotEmpty)
                        ActionChip(label: Text(Fmt.money(note)), onPressed: () => _setReceived(note.toDouble())),
                    ActionChip(
                      avatar: const Icon(Icons.schedule, size: 18),
                      label: const Text('Tout à crédit'),
                      onPressed: _lines.isEmpty
                          ? null
                          : () {
                              _receivedEdited = true;
                              _received.text = '0';
                            },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_lines.isNotEmpty && _change >= 1)
                  _Banner(
                    icon: Icons.currency_exchange,
                    color: okColor,
                    text: 'Monnaie à rendre : ${Fmt.money(_change)}',
                  ),
                if (isCredit)
                  _Banner(
                    icon: Icons.schedule,
                    color: theme.colorScheme.error,
                    text: 'Reste à crédit : ${Fmt.money(credit)} — nom du client obligatoire',
                  ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _method,
                  decoration: const InputDecoration(labelText: 'Mode de paiement', prefixIcon: Icon(Icons.wallet)),
                  items: [for (final m in paymentMethods) DropdownMenuItem(value: m, child: Text(m))],
                  onChanged: (v) => setState(() => _method = v ?? paymentMethods.first),
                ),
                const SizedBox(height: 12),
                Autocomplete<String>(
                  key: ValueKey(_clientFieldKey),
                  optionsBuilder: (v) => v.text.isEmpty
                      ? const Iterable<String>.empty()
                      : _clients.where((c) => c.toLowerCase().contains(v.text.toLowerCase())),
                  onSelected: (v) => _client.text = v,
                  fieldViewBuilder: (context, ctrl, focus, _) => TextField(
                    controller: ctrl,
                    focusNode: focus,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (v) => _client.text = v,
                    decoration: InputDecoration(
                      labelText: isCredit ? 'Nom du client *' : 'Client (facultatif)',
                      prefixIcon: const Icon(Icons.person_outline),
                      errorText: isCredit && _client.text.trim().isEmpty ? 'Obligatoire pour une vente à crédit' : null,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _note,
                  decoration: const InputDecoration(labelText: 'Note (facultatif)', prefixIcon: Icon(Icons.notes)),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _busy || _lines.isEmpty ? null : _submit,
                  icon: const Icon(Icons.point_of_sale),
                  label: Text(_lines.isEmpty ? 'Encaisser' : 'Encaisser ${Fmt.money(_total)}'),
                ),
              ],
            ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 4),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      border: Border.all(color: color),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ),
  );
}

/// Choix de la quantité et du prix d'un article du panier.
class _LineDialog extends StatefulWidget {
  const _LineDialog({required this.item, required this.available, this.initial});
  final StockItem item;
  final int available;
  final SaleLine? initial;

  @override
  State<_LineDialog> createState() => _LineDialogState();
}

class _LineDialogState extends State<_LineDialog> {
  late final _qty = TextEditingController(text: '${widget.initial?.quantity ?? 1}');
  late final _price = TextEditingController(
    text: (widget.initial?.unitPrice ?? widget.item.product.sellingPrice).round().toString(),
  );
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _qty.addListener(() => setState(() {}));
    _price.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _qty.dispose();
    _price.dispose();
    super.dispose();
  }

  void _step(int d) {
    final q = (int.tryParse(_qty.text) ?? 0) + d;
    if (q >= 1 && q <= widget.available) _qty.text = '$q';
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.item.product;
    final qty = int.tryParse(_qty.text) ?? 0;
    final price = Fmt.parseNumber(_price.text) ?? 0;
    final belowCost = price < widget.item.cump && price > 0;
    return AlertDialog(
      title: Text(p.name),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Disponible : ${Fmt.qtyUnit(widget.available, p.unit)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Moins',
                    onPressed: qty > 1 ? () => _step(-1) : null,
                    icon: const Icon(Icons.remove),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _qty,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      inputFormatters: intInput,
                      decoration: InputDecoration(labelText: 'Quantité', suffixText: p.unit),
                      validator: (v) {
                        final err = requiredInt(v, min: 1, field: 'La quantité');
                        if (err != null) return err;
                        if (int.parse(v!.trim()) > widget.available) return 'Max. ${widget.available}';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Plus',
                    onPressed: qty < widget.available ? () => _step(1) : null,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _price,
                keyboardType: TextInputType.number,
                inputFormatters: intInput,
                decoration: InputDecoration(
                  labelText: 'Prix unitaire',
                  suffixText: 'FCFA',
                  helperText: 'Coût moyen : ${Fmt.money(widget.item.cump)}',
                ),
                validator: (v) => requiredAmount(v),
              ),
              const SizedBox(height: 12),
              Text(
                'Total : ${Fmt.money(qty * price)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              if (belowCost)
                Text(
                  'Attention : prix inférieur au coût moyen (vente à perte)',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              SaleLine(
                item: widget.item,
                quantity: int.parse(_qty.text.trim()),
                unitPrice: Fmt.parseNumber(_price.text)!,
              ),
            );
          },
          child: Text(widget.initial == null ? 'Ajouter' : 'Modifier'),
        ),
      ],
    );
  }
}
