import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/shop_repository.dart';
import '../../services/session.dart';
import '../common.dart';

/// « Ma boutique » : type de commerce, coordonnées et mentions des factures.
class ShopProfileScreen extends StatefulWidget {
  const ShopProfileScreen({super.key});

  @override
  State<ShopProfileScreen> createState() => _ShopProfileScreenState();
}

class _ShopProfileScreenState extends State<ShopProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _activity = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _phone = TextEditingController();
  final _niu = TextEditingController();
  final _rccm = TextEditingController();
  final _footer = TextEditingController();
  final _vatRate = TextEditingController();
  ShopType _type = ShopType.retail;
  bool _vat = false;
  int _receiptWidth = 80;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_activity, _address, _city, _phone, _niu, _rccm, _footer, _vatRate]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final p = await context.read<ShopRepository>().shopProfile(context.read<Session>().userId);
    if (!mounted) return;
    setState(() {
      _type = p.shopType;
      _activity.text = p.activity ?? '';
      _address.text = p.address ?? '';
      _city.text = p.city ?? '';
      _phone.text = p.phone ?? '';
      _niu.text = p.niu ?? '';
      _rccm.text = p.rccm ?? '';
      _footer.text = p.invoiceFooter ?? '';
      _vat = p.vatEnabled;
      _vatRate.text = Fmt.number(p.vatRate);
      _receiptWidth = p.receiptWidth;
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.read<ShopRepository>().saveShopProfile(
        context.read<Session>().userId,
        ShopProfile(
          shopType: _type,
          activity: _activity.text,
          address: _address.text,
          city: _city.text,
          phone: _phone.text,
          niu: _niu.text,
          rccm: _rccm.text,
          invoiceFooter: _footer.text,
          vatEnabled: _vat,
          vatRate: Fmt.parseNumber(_vatRate.text) ?? Vat.defaultRate,
          receiptWidth: _receiptWidth,
        ),
      );
      if (!mounted) return;
      showSuccess(context, 'Boutique enregistrée');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Ma boutique')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  const SectionTitle('Type de commerce'),
                  RadioGroup<ShopType>(
                    groupValue: _type,
                    onChanged: (v) => setState(() => _type = v ?? _type),
                    child: Column(
                      children: [
                        for (final t in ShopType.values)
                          Card(
                            color: t == _type ? theme.colorScheme.primaryContainer : null,
                            child: RadioListTile<ShopType>(
                              value: t,
                              title: Text(t.label, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(t.description),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      'Le type propose seulement des tarifs de départ (Demi-gros, Gros). '
                      'Vous pouvez ensuite tout modifier dans « Tarifs ».',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  const SectionTitle('Coordonnées (en-tête des reçus et factures)'),
                  TextFormField(
                    controller: _activity,
                    decoration: const InputDecoration(
                      labelText: 'Activité',
                      hintText: 'Ex. Alimentation générale, Quincaillerie',
                      prefixIcon: Icon(Icons.storefront),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _address,
                    decoration: const InputDecoration(
                      labelText: 'Adresse',
                      hintText: 'Ex. Marché Central, porte 12',
                      prefixIcon: Icon(Icons.place_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _city,
                    decoration: const InputDecoration(labelText: 'Ville', prefixIcon: Icon(Icons.location_city)),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Téléphone', prefixIcon: Icon(Icons.phone_outlined)),
                  ),
                  const SectionTitle('Identifiants officiels'),
                  TextFormField(
                    controller: _niu,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'NIU (Numéro d\'Identifiant Unique)',
                      helperText: 'Figure sur votre carte de contribuable',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _rccm,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'RCCM (registre du commerce)',
                      prefixIcon: Icon(Icons.gavel_outlined),
                    ),
                  ),
                  const SectionTitle('Factures'),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _vat,
                    onChanged: (v) => setState(() => _vat = v),
                    title: const Text('Boutique assujettie à la TVA'),
                    subtitle: const Text('Les factures détaillent HT, TVA et TTC (vos prix restent TTC)'),
                  ),
                  if (_vat)
                    TextFormField(
                      controller: _vatRate,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Taux de TVA',
                        suffixText: '%',
                        helperText: 'Cameroun : 19,25 % (17,5 % + centimes additionnels)',
                      ),
                      validator: (v) {
                        final r = Fmt.parseNumber(v);
                        if (r == null || r < 0 || r >= 100) return 'Taux invalide';
                        return null;
                      },
                    ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _footer,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Message en bas des documents',
                      hintText: 'Ex. Merci de votre confiance. Les marchandises vendues ne sont ni reprises ni échangées.',
                      prefixIcon: Icon(Icons.short_text),
                    ),
                  ),
                  const SectionTitle('Imprimante de tickets'),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 58, label: Text('58 mm')),
                      ButtonSegment(value: 80, label: Text('80 mm')),
                    ],
                    selected: {_receiptWidth},
                    onSelectionChanged: (s) => setState(() => _receiptWidth = s.first),
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
}

/// Tarifs (grilles de prix) : Demi-gros, Gros, Revendeur, Fidèle…
class PriceLevelsScreen extends StatelessWidget {
  const PriceLevelsScreen({super.key});

  Future<void> _edit(BuildContext context, [PriceLevel? level]) async {
    final result = await showDialog<(String, int)>(
      context: context,
      builder: (_) => _LevelDialog(level: level),
    );
    if (result == null || !context.mounted) return;
    try {
      await context.read<ShopRepository>().savePriceLevel(
        context.read<Session>().userId,
        id: level?.id,
        name: result.$1,
        minQty: result.$2,
      );
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tarifs')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context),
        icon: const Icon(Icons.add),
        label: const Text('Nouveau tarif'),
      ),
      body: Reloading<List<PriceLevel>>(
        load: (r, u) => r.priceLevels(u),
        builder: (context, levels) => ListView(
          padding: const EdgeInsets.only(bottom: 88),
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Chaque produit a un prix « Détail ». Ajoutez autant de tarifs que vous voulez '
                '(Demi-gros, Gros, Revendeur…), puis indiquez leur prix dans la fiche de chaque produit '
                '(menu ⋮ > Tarifs et conditionnements).\n\n'
                'Un tarif s\'applique quand vous le choisissez à la vente, quand il est attitré au client, '
                'ou tout seul à partir d\'une quantité (palier). Le client paie toujours le prix le plus avantageux.',
              ),
            ),
            const ListTile(
              leading: CircleAvatar(child: Icon(Icons.sell_outlined)),
              title: Text('Détail'),
              subtitle: Text('Prix de base de chaque produit (toujours présent)'),
            ),
            for (final l in levels)
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.local_offer_outlined)),
                title: Text(l.name),
                subtitle: Text(
                  l.minQty > 0
                      ? 'Palier proposé : dès ${Fmt.qtyUnit(l.minQty, 'unité')}'
                      : 'Appliqué au choix ou au client',
                ),
                onTap: () => _edit(context, l),
                trailing: IconButton(
                  tooltip: 'Supprimer',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    final ok = await confirm(
                      context,
                      'Supprimer « ${l.name} » ?',
                      'Les prix de ce tarif seront retirés des produits. Les ventes déjà faites ne changent pas.',
                      ok: 'Supprimer',
                      danger: true,
                    );
                    if (!ok || !context.mounted) return;
                    try {
                      await context.read<ShopRepository>().deletePriceLevel(context.read<Session>().userId, l.id);
                    } catch (e) {
                      if (context.mounted) showError(context, e);
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LevelDialog extends StatefulWidget {
  const _LevelDialog({this.level});
  final PriceLevel? level;

  @override
  State<_LevelDialog> createState() => _LevelDialogState();
}

class _LevelDialogState extends State<_LevelDialog> {
  late final _name = TextEditingController(text: widget.level?.name ?? '');
  late final _min = TextEditingController(text: '${widget.level?.minQty ?? 0}');
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _name.dispose();
    _min.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.level == null ? 'Nouveau tarif' : 'Modifier le tarif'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nom', hintText: 'Ex. Gros, Revendeur'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Obligatoire' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _min,
              keyboardType: TextInputType.number,
              inputFormatters: intInput,
              decoration: const InputDecoration(
                labelText: 'Palier proposé (quantité)',
                helperText: '0 = seulement si choisi.\nModifiable produit par produit.',
                helperMaxLines: 3,
              ),
              validator: (v) => requiredInt(v, field: 'Le palier'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, (_name.text.trim(), int.parse(_min.text.trim())));
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
