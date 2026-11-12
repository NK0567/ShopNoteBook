import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/shop_repository.dart';
import '../../services/session.dart';
import '../common.dart';
import '../product_picker.dart';
import 'documents.dart';
import 'quotes_screen.dart';
import 'ticket_screen.dart';

/// Vente au comptoir : panier d'un ou plusieurs articles (à l'unité ou par
/// carton/sac), tarif détail/gros, encaissement (comptant, partiel, crédit),
/// monnaie, reçu/facture — ou enregistrement en devis.
class CartScreen extends StatefulWidget {
  const CartScreen({super.key, this.productId, this.quote});

  /// Produit ajouté d'office au panier (vente lancée depuis une fiche produit).
  final int? productId;

  /// Devis à transformer en vente (lignes et client repris).
  final Quote? quote;

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _received = TextEditingController();
  final _client = TextEditingController();
  final _note = TextEditingController();
  final _scan = TextEditingController();
  final _scanFocus = FocusNode();
  List<StockItem> _items = [];
  List<String> _clients = [];
  List<PriceLevel> _levels = [];
  Map<int, ProductPricing> _pricing = {};
  final List<SaleLine> _lines = [];

  /// Lignes dont le prix est calculé (et donc recalculé si le tarif change).
  final List<bool> _autoPrice = [];
  String _method = paymentMethods.first;

  /// Tarif de la vente (null = Détail).
  int? _levelId;
  int? _quoteId;

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
    for (final c in [_received, _client, _note, _scan]) {
      c.dispose();
    }
    _scanFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = context.read<ShopRepository>();
    final uid = context.read<Session>().userId;
    final items = await repo.inventory(uid);
    final clients = await repo.clients(uid);
    final levels = await repo.priceLevels(uid);
    final pricing = await repo.allPricing(uid);
    if (!mounted) return;
    setState(() {
      _items = items;
      _clients = clients;
      _levels = levels;
      _pricing = pricing;
      _loading = false;
    });
    final q = widget.quote;
    if (q != null && _lines.isEmpty) {
      _loadQuote(q);
      return;
    }
    final first = widget.productId == null ? null : items.where((i) => i.product.id == widget.productId).firstOrNull;
    if (first != null && first.stock > 0) await _editLine(first);
  }

  /// Reprend les lignes d'un devis (aux prix du devis) et son client.
  void _loadQuote(Quote q) {
    final missing = <String>[];
    setState(() {
      _quoteId = q.id;
      for (final l in q.lines) {
        final item = _items.where((i) => i.product.id == l.productId).firstOrNull;
        final already = _reserved[l.productId] ?? 0;
        if (item == null || item.stock - already < l.quantity) {
          missing.add(l.productName);
          continue;
        }
        _lines.add(
          SaleLine(item: item, quantity: l.quantity, unitPrice: l.unitPrice, packName: l.packName, packSize: l.packSize),
        );
        _autoPrice.add(false);
      }
      if (q.client != null) {
        _client.text = q.client!;
        _clientFieldKey++;
      }
      _syncReceived();
    });
    if (missing.isNotEmpty) {
      showError(context, BusinessException('Stock insuffisant, non repris : ${missing.join(', ')}'));
    }
  }

  void _syncReceived() {
    if (!_receivedEdited) _received.text = _total <= 0 ? '' : _total.round().toString();
  }

  String get _levelName =>
      _levelId == null ? Pricing.retailName : (_levels.where((l) => l.id == _levelId).firstOrNull?.name ?? Pricing.retailName);

  /// Prix calculé d'une ligne selon le tarif de la vente et les paliers.
  (double, String) _autoUnitPrice(StockItem item, int baseQty, ProductPack? pack) {
    final pricing = _pricing[item.product.id] ?? ProductPricing.empty;
    final choice = Pricing.resolve(
      basePrice: item.product.sellingPrice,
      levels: pricing.levelsFor(_levels),
      chosenLevelId: _levelId,
      quantity: baseQty,
    );
    if (pack != null && pack.price > 0) {
      final perUnit = pack.price / pack.quantity;
      // Le prix fixé du carton, sauf si un tarif est encore plus avantageux.
      if (perUnit <= choice.unitPrice) return (perUnit, pack.name);
    }
    return (choice.unitPrice, choice.levelName);
  }

  /// Change le tarif de la vente : les prix calculés sont mis à jour,
  /// les prix saisis à la main sont conservés.
  void _setLevel(int? levelId) {
    setState(() {
      _levelId = levelId;
      for (var i = 0; i < _lines.length; i++) {
        if (!_autoPrice[i]) continue;
        final l = _lines[i];
        final pack = _packOf(l);
        final (price, name) = _autoUnitPrice(l.item, l.quantity, pack);
        _lines[i] = SaleLine(
          item: l.item,
          quantity: l.quantity,
          unitPrice: price,
          packName: l.packName,
          packSize: l.packSize,
          levelName: name,
        );
      }
      _syncReceived();
    });
  }

  ProductPack? _packOf(SaleLine l) => !PackMath.isPack(l.packSize)
      ? null
      : (_pricing[l.item.product.id]?.packs ?? const <ProductPack>[])
            .where((p) => p.name == l.packName && p.quantity == l.packSize)
            .firstOrNull;

  Future<void> _addProduct() async {
    final picked = await pickProduct(context, _items, needsStock: true, reserved: _reserved);
    if (picked != null && mounted) await _editLine(picked);
  }

  /// Ajoute (ou modifie) la ligne d'un produit : conditionnement, quantité et prix.
  Future<void> _editLine(StockItem item, {int? index, ProductPack? pack}) async {
    final existing = index != null ? _lines[index] : null;
    final already = (_reserved[item.product.id] ?? 0) - (existing?.quantity ?? 0);
    final result = await showDialog<(SaleLine, bool)>(
      context: context,
      builder: (_) => _LineDialog(
        item: item,
        available: item.stock - already,
        initial: existing,
        initialAuto: index == null || _autoPrice[index],
        initialPack: pack,
        packs: _pricing[item.product.id]?.packs ?? const [],
        price: _autoUnitPrice,
      ),
    );
    if (result == null || !mounted) return;
    _putLine(result.$1, auto: result.$2, index: index);
  }

  void _putLine(SaleLine line, {required bool auto, int? index}) {
    setState(() {
      if (index != null) {
        _lines[index] = line;
        _autoPrice[index] = auto;
      } else {
        // Même produit, même conditionnement et même prix : une seule ligne.
        final same = _lines.indexWhere(
          (l) =>
              l.item.product.id == line.item.product.id &&
              l.unitPrice == line.unitPrice &&
              l.packSize == line.packSize &&
              l.packName == line.packName,
        );
        if (same >= 0) {
          _lines[same] = _lines[same].copyWith(quantity: _lines[same].quantity + line.quantity);
        } else {
          _lines.add(line);
          _autoPrice.add(auto);
        }
      }
      _syncReceived();
    });
  }

  void _removeLine(int i) => setState(() {
    _lines.removeAt(i);
    _autoPrice.removeAt(i);
    _syncReceived();
  });

  /// Douchette (lecteur code-barres USB) ou saisie : code-barres ou référence.
  Future<void> _onScan(String raw) async {
    final code = raw.trim();
    _scan.clear();
    _scanFocus.requestFocus();
    if (code.isEmpty) return;
    final found = await context.read<ShopRepository>().findByBarcode(context.read<Session>().userId, code);
    if (!mounted) return;
    StockItem? item;
    ProductPack? pack;
    if (found != null) {
      item = _items.where((i) => i.product.id == found.productId).firstOrNull;
      pack = found.pack;
    } else {
      final ref = Product.normalizeReference(code);
      item = _items.where((i) => i.product.reference == ref).firstOrNull;
    }
    if (item == null) {
      showError(context, BusinessException('Aucun produit actif pour « $code »'));
      return;
    }
    final size = pack?.quantity ?? 1;
    final available = item.stock - (_reserved[item.product.id] ?? 0);
    if (available < size) {
      showError(context, BusinessException('Stock insuffisant pour ${item.product.name}'));
      return;
    }
    // Scan = 1 article (ou 1 carton) au prix calculé, sans fenêtre : on enchaîne.
    final (price, level) = _autoUnitPrice(item, size, pack);
    _putLine(
      SaleLine(item: item, quantity: size, unitPrice: price, packName: pack?.name, packSize: pack?.quantity, levelName: level),
      auto: true,
    );
  }

  void _setReceived(double v) {
    _receivedEdited = true;
    _received.text = v.round().toString();
  }

  Future<void> _onClientChosen(String name) async {
    _client.text = name;
    final c = await context.read<ShopRepository>().clientByName(context.read<Session>().userId, name);
    if (!mounted || c == null) return;
    if (c.priceLevelId != null && _levels.any((l) => l.id == c.priceLevelId) && _levelId != c.priceLevelId) {
      _setLevel(c.priceLevelId);
      showSuccess(context, 'Tarif « $_levelName » appliqué pour ${c.name}');
    }
    if (c.balance >= 1 && mounted) {
      showSuccess(context, '${c.name} doit déjà ${Fmt.money(c.balance)}');
    }
  }

  List<String> _summary() => [
    for (final l in _lines) '• ${l.item.product.name} : ${l.quantityLabel} × ${Fmt.money(l.displayPrice)}',
    '',
    'Tarif : $_levelName',
    'Total : ${Fmt.money(_total)}',
  ];

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
      ..._summary(),
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
        priceLevelId: _levelId,
        quoteId: _quoteId,
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

  /// Enregistre le panier en devis (aucun effet sur le stock).
  Future<void> _saveQuote() async {
    if (_lines.isEmpty) return;
    final days = await promptText(
      context,
      title: 'Enregistrer en devis',
      message: '${_summary().join('\n')}\n\nLe stock ne bouge pas tant que le devis n\'est pas transformé en vente.',
      label: 'Valable combien de jours ?',
      initial: '15',
      keyboardType: TextInputType.number,
      inputFormatters: intInput,
      ok: 'Enregistrer',
    );
    final n = int.tryParse(days ?? '');
    if (n == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final now = DateTime.now();
      final q = await context.read<ShopRepository>().createQuote(
        userId: context.read<Session>().userId,
        lines: List.of(_lines),
        date: now,
        validUntil: n > 0 ? DateTime(now.year, now.month, now.day + n) : null,
        client: _client.text,
        note: _note.text,
      );
      if (!mounted) return;
      final share = await confirm(context, 'Devis ${q.code} enregistré', 'Total : ${Fmt.money(q.total)}', ok: 'Envoyer le PDF');
      if (share && mounted) await SalesDocuments.quote(context, q);
      if (mounted) Navigator.pop(context);
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
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton.icon(
                  onPressed: () => SalesDocuments.receipt(c, detail),
                  icon: const Icon(Icons.receipt_outlined, size: 18),
                  label: const Text('Reçu'),
                ),
                OutlinedButton.icon(
                  onPressed: () => SalesDocuments.invoice(c, detail),
                  icon: const Icon(Icons.description_outlined, size: 18),
                  label: const Text('Facture'),
                ),
                OutlinedButton.icon(
                  onPressed: () => SalesDocuments.deliveryNote(c, detail),
                  icon: const Icon(Icons.local_shipping_outlined, size: 18),
                  label: const Text('Bon de livraison'),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Terminer')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Nouvelle vente')),
        ],
      ),
    );
    if (!mounted) return;
    if (again == true && widget.quote == null) {
      setState(() {
        _lines.clear();
        _autoPrice.clear();
        _receivedEdited = false;
        _received.clear();
        _client.clear();
        _note.clear();
        _method = paymentMethods.first;
        _levelId = null;
        _quoteId = null;
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
        title: Text(widget.quote == null ? 'Nouvelle vente' : 'Vente du devis ${widget.quote!.code}'),
        actions: [
          IconButton(
            tooltip: 'Devis',
            icon: const Icon(Icons.request_quote_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QuotesScreen())),
          ),
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
                TextField(
                  controller: _scan,
                  focusNode: _scanFocus,
                  textInputAction: TextInputAction.done,
                  onSubmitted: _onScan,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.qr_code_scanner),
                    hintText: 'Scanner un code-barres ou taper une référence',
                    isDense: true,
                  ),
                ),
                if (_levels.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    initialValue: _levelId,
                    key: ValueKey('level-$_levelId'),
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Tarif de la vente',
                      prefixIcon: Icon(Icons.local_offer_outlined),
                      helperText: 'Les paliers de quantité s\'appliquent aussi tout seuls',
                    ),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('Détail')),
                      for (final l in _levels) DropdownMenuItem<int?>(value: l.id, child: Text(l.name)),
                    ],
                    onChanged: _busy ? null : _setLevel,
                  ),
                ],
                const SizedBox(height: 12),
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
                              [
                                '${_lines[i].quantityLabel} × ${Fmt.money(_lines[i].displayPrice)}',
                                if (_lines[i].levelName != null && _lines[i].levelName != Pricing.retailName)
                                  _lines[i].levelName!,
                              ].join(' · '),
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
                  initialValue: TextEditingValue(text: _client.text),
                  optionsBuilder: (v) => v.text.isEmpty
                      ? const Iterable<String>.empty()
                      : _clients.where((c) => c.toLowerCase().contains(v.text.toLowerCase())),
                  onSelected: _onClientChosen,
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
                if (widget.quote == null) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy || _lines.isEmpty ? null : _saveQuote,
                    icon: const Icon(Icons.request_quote_outlined),
                    label: const Text('Enregistrer en devis (pro forma)'),
                  ),
                ],
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

/// Choix du conditionnement, de la quantité et du prix d'un article du panier.
/// Renvoie la ligne et « prix calculé automatiquement ? ».
class _LineDialog extends StatefulWidget {
  const _LineDialog({
    required this.item,
    required this.available,
    required this.packs,
    required this.price,
    this.initial,
    this.initialAuto = true,
    this.initialPack,
  });
  final StockItem item;
  final int available;
  final List<ProductPack> packs;

  /// Calcul du prix unitaire (et nom du tarif) pour une quantité à l'unité de base.
  final (double, String) Function(StockItem item, int baseQty, ProductPack? pack) price;
  final SaleLine? initial;
  final bool initialAuto;
  final ProductPack? initialPack;

  @override
  State<_LineDialog> createState() => _LineDialogState();
}

class _LineDialogState extends State<_LineDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _qty;
  late final TextEditingController _price;

  /// null = vente à l'unité de base.
  ProductPack? _pack;
  late bool _auto = widget.initialAuto;
  String _levelName = Pricing.retailName;

  int get _size => _pack?.quantity ?? 1;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    _pack = widget.initialPack;
    if (init != null && PackMath.isPack(init.packSize)) {
      _pack = widget.packs.where((p) => p.name == init.packName && p.quantity == init.packSize).firstOrNull;
    }
    final count = init == null ? 1 : init.quantity ~/ _size;
    _qty = TextEditingController(text: '$count');
    _price = TextEditingController(text: init == null ? '' : (init.unitPrice * _size).round().toString());
    if (init == null || _auto) _recompute();
    _qty.addListener(() {
      if (_auto) _recompute();
      setState(() {});
    });
    _price.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _qty.dispose();
    _price.dispose();
    super.dispose();
  }

  void _recompute() {
    final count = int.tryParse(_qty.text) ?? 1;
    final (unit, name) = widget.price(widget.item, (count < 1 ? 1 : count) * _size, _pack);
    _levelName = name;
    final text = (unit * _size).round().toString();
    if (_price.text != text) _price.text = text;
  }

  int get _maxCount => widget.available ~/ _size;

  void _step(int d) {
    final q = (int.tryParse(_qty.text) ?? 0) + d;
    if (q >= 1 && q <= _maxCount) _qty.text = '$q';
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.item.product;
    final count = int.tryParse(_qty.text) ?? 0;
    final price = Fmt.parseNumber(_price.text) ?? 0;
    final perUnit = price / _size;
    final belowCost = perUnit < widget.item.cump && price > 0;
    final unitLabel = _pack?.name ?? p.unit;
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
                'Disponible : ${PackMath.stockLabel(widget.available, p.unit, _pack?.name, _pack?.quantity)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (widget.packs.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    ChoiceChip(
                      label: Text(p.unit),
                      selected: _pack == null,
                      onSelected: (_) => setState(() {
                        _pack = null;
                        _auto = true;
                        _recompute();
                      }),
                    ),
                    for (final pk in widget.packs)
                      ChoiceChip(
                        label: Text('${pk.name} de ${pk.quantity}'),
                        selected: _pack == pk,
                        onSelected: pk.quantity > widget.available
                            ? null
                            : (_) => setState(() {
                                _pack = pk;
                                _auto = true;
                                if ((int.tryParse(_qty.text) ?? 0) > _maxCount) _qty.text = '1';
                                _recompute();
                              }),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Moins',
                    onPressed: count > 1 ? () => _step(-1) : null,
                    icon: const Icon(Icons.remove),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _qty,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      inputFormatters: intInput,
                      decoration: InputDecoration(labelText: 'Quantité', suffixText: Fmt.plural(count, unitLabel)),
                      validator: (v) {
                        final err = requiredInt(v, min: 1, field: 'La quantité');
                        if (err != null) return err;
                        if (int.parse(v!.trim()) > _maxCount) return 'Max. $_maxCount';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Plus',
                    onPressed: count < _maxCount ? () => _step(1) : null,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _price,
                keyboardType: TextInputType.number,
                inputFormatters: intInput,
                onChanged: (_) => _auto = false,
                decoration: InputDecoration(
                  labelText: 'Prix par $unitLabel',
                  suffixText: 'FCFA',
                  helperText: _auto
                      ? 'Tarif appliqué : $_levelName · coût moyen ${Fmt.money(widget.item.cump * _size)}'
                      : 'Prix saisi à la main · coût moyen ${Fmt.money(widget.item.cump * _size)}',
                  helperMaxLines: 2,
                  suffixIcon: _auto
                      ? null
                      : IconButton(
                          tooltip: 'Revenir au prix du tarif',
                          icon: const Icon(Icons.restart_alt),
                          onPressed: () => setState(() {
                            _auto = true;
                            _recompute();
                          }),
                        ),
                ),
                validator: (v) => requiredAmount(v),
              ),
              const SizedBox(height: 12),
              Text(
                'Total : ${Fmt.money(count * price)}',
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
            final n = int.parse(_qty.text.trim());
            Navigator.pop(context, (
              SaleLine(
                item: widget.item,
                quantity: n * _size,
                unitPrice: Fmt.parseNumber(_price.text)! / _size,
                packName: _pack?.name,
                packSize: _pack?.quantity,
                levelName: _auto ? _levelName : null,
              ),
              _auto,
            ));
          },
          child: Text(widget.initial == null ? 'Ajouter' : 'Modifier'),
        ),
      ],
    );
  }
}
