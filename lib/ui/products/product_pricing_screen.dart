import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/shop_repository.dart';
import '../../services/session.dart';
import '../common.dart';
import '../settings/shop_settings_screens.dart';

/// Prix par tarif (demi-gros, gros…) et conditionnements (carton, sac…) d'un produit.
class ProductPricingScreen extends StatefulWidget {
  const ProductPricingScreen({super.key, required this.item});
  final StockItem item;

  @override
  State<ProductPricingScreen> createState() => _ProductPricingScreenState();
}

class _LevelFields {
  _LevelFields(this.level, double price, int minQty)
    : price = TextEditingController(text: price > 0 ? price.round().toString() : ''),
      minQty = TextEditingController(text: minQty > 0 ? '$minQty' : '');
  final PriceLevel level;
  final TextEditingController price;
  final TextEditingController minQty;

  void dispose() {
    price.dispose();
    minQty.dispose();
  }
}

class _PackFields {
  _PackFields([ProductPack? p])
    : name = TextEditingController(text: p?.name ?? 'Carton'),
      quantity = TextEditingController(text: p == null ? '' : '${p.quantity}'),
      price = TextEditingController(text: (p?.price ?? 0) > 0 ? p!.price.round().toString() : ''),
      barcode = TextEditingController(text: p?.barcode ?? '');
  final TextEditingController name, quantity, price, barcode;

  void dispose() {
    for (final c in [name, quantity, price, barcode]) {
      c.dispose();
    }
  }
}

class _ProductPricingScreenState extends State<ProductPricingScreen> {
  final _formKey = GlobalKey<FormState>();
  List<_LevelFields> _levels = [];
  final List<_PackFields> _packs = [];
  bool _loading = true;
  bool _busy = false;

  Product get _p => widget.item.product;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final l in _levels) {
      l.dispose();
    }
    for (final p in _packs) {
      p.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final repo = context.read<ShopRepository>();
    final uid = context.read<Session>().userId;
    final levels = await repo.priceLevels(uid);
    final pricing = await repo.productPricing(_p.id!);
    if (!mounted) return;
    setState(() {
      for (final l in _levels) {
        l.dispose();
      }
      _levels = [
        for (final l in levels)
          _LevelFields(
            l,
            pricing.levelPrices[l.id] ?? 0,
            // Palier : celui du produit, sinon celui proposé par le tarif.
            pricing.levelPrices.containsKey(l.id) ? (pricing.levelMinQty[l.id] ?? 0) : l.minQty,
          ),
      ];
      if (_packs.isEmpty) {
        _packs.addAll(pricing.packs.map(_PackFields.new));
      }
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.read<ShopRepository>().saveProductPricing(
        context.read<Session>().userId,
        _p.id!,
        levelPrices: {
          for (final l in _levels)
            l.level.id: (
              price: Fmt.parseNumber(l.price.text) ?? 0,
              minQty: int.tryParse(l.minQty.text.trim()) ?? 0,
            ),
        },
        packs: [
          for (final p in _packs)
            ProductPack(
              name: p.name.text,
              quantity: int.tryParse(p.quantity.text.trim()) ?? 0,
              price: Fmt.parseNumber(p.price.text) ?? 0,
              barcode: p.barcode.text,
            ),
        ],
      );
      if (!mounted) return;
      showSuccess(context, 'Tarifs enregistrés');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _priceCheck(String? v) {
    final price = Fmt.parseNumber(v);
    if ((v ?? '').trim().isEmpty) return null;
    if (price == null || price < 0) return 'Montant invalide';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cump = widget.item.cump;
    return Scaffold(
      appBar: AppBar(title: const Text('Tarifs et conditionnements')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  Text(_p.name, style: theme.textTheme.titleMedium),
                  Text(
                    'Prix « Détail » : ${Fmt.money(_p.sellingPrice)} / ${_p.unit}  ·  Coût moyen : ${Fmt.money(cump)}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SectionTitle('Prix par tarif (à l\'unité de base)'),
                  if (_levels.isEmpty)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.info_outline),
                        title: const Text('Aucun tarif en plus du prix Détail'),
                        subtitle: const Text('Créez par exemple « Demi-gros » et « Gros » dans Réglages > Tarifs.'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          await Navigator.push(context, MaterialPageRoute(builder: (_) => const PriceLevelsScreen()));
                          if (mounted) await _load();
                        },
                      ),
                    ),
                  for (final l in _levels)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: l.price,
                              keyboardType: TextInputType.number,
                              inputFormatters: intInput,
                              decoration: InputDecoration(
                                labelText: l.level.name,
                                suffixText: 'FCFA',
                                helperText: 'Vide = non proposé',
                              ),
                              validator: (v) {
                                final err = _priceCheck(v);
                                if (err != null) return err;
                                final price = Fmt.parseNumber(v) ?? 0;
                                if (price > 0 && price < cump) return 'Sous le coût moyen';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: l.minQty,
                              keyboardType: TextInputType.number,
                              inputFormatters: intInput,
                              decoration: const InputDecoration(labelText: 'Dès (qté)', helperText: 'Vide = au choix'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SectionTitle('Conditionnements'),
                  Text(
                    'Ex. « Carton » de 24 ${Fmt.plural(24, _p.unit)}, « Sac » de 50. Le stock reste compté en ${Fmt.plural(2, _p.unit)} ; '
                    'vous pouvez vendre et réceptionner par conditionnement.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < _packs.length; i++) _packCard(i),
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _packs.add(_PackFields())),
                    icon: const Icon(Icons.add),
                    label: const Text('Ajouter un conditionnement'),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: const Icon(Icons.save),
                    label: const Text('Enregistrer'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _packCard(int i) {
    final p = _packs[i];
    final qty = int.tryParse(p.quantity.text.trim()) ?? 0;
    final auto = qty > 1 ? _p.sellingPrice * qty : 0;
    return Card(
      key: ObjectKey(p),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: p.name,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Nom', hintText: 'Carton, Sac, Paquet…'),
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Obligatoire' : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: p.quantity,
                    keyboardType: TextInputType.number,
                    inputFormatters: intInput,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(labelText: 'Contient', suffixText: Fmt.plural(2, _p.unit)),
                    validator: (v) => requiredInt(v, min: 2, field: 'La contenance'),
                  ),
                ),
                IconButton(
                  tooltip: 'Retirer',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    final removed = _packs.removeAt(i);
                    setState(() {});
                    // Libéré après le rebuild : les champs l'utilisent encore pendant ce frame.
                    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: p.price,
                    keyboardType: TextInputType.number,
                    inputFormatters: intInput,
                    decoration: InputDecoration(
                      labelText: 'Prix du conditionnement',
                      suffixText: 'FCFA',
                      helperText: auto > 0 ? 'Vide = ${Fmt.money(auto)} (prix détail × $qty)' : 'Vide = prix détail × contenance',
                      helperMaxLines: 2,
                    ),
                    validator: _priceCheck,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: p.barcode,
                    decoration: const InputDecoration(labelText: 'Code-barres', prefixIcon: Icon(Icons.qr_code, size: 20)),
                  ),
                ),
                const SizedBox(width: 40),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
