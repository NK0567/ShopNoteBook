import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/period.dart';
import '../../data/models.dart';
import '../common.dart';
import '../sales/cart_screen.dart';
import '../sales/credits_screen.dart';
import '../sales/ticket_screen.dart';
import 'movement_form_screen.dart';
import 'movement_tile.dart';

/// Historique des entrées et sorties (feuilles "Entrée" et "Sortie").
class OperationsScreen extends StatefulWidget {
  const OperationsScreen({super.key});

  @override
  State<OperationsScreen> createState() => _OperationsScreenState();
}

class _OperationsScreenState extends State<OperationsScreen> {
  MovementType? _type;
  Period _period = Period.of(PeriodKind.month);
  bool _showCancelled = true;
  String _query = '';

  Future<void> _choosePeriod(PeriodKind kind) async {
    if (kind != PeriodKind.custom) {
      setState(() => _period = Period.of(kind));
      return;
    }
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      helpText: 'Période',
    );
    if (range != null) setState(() => _period = Period.custom(range.start, range.end));
  }

  void _go(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Opérations'),
        actions: [
          IconButton(
            tooltip: 'Tickets de caisse',
            icon: const Icon(Icons.receipt_long),
            onPressed: () => _go(const TicketsScreen()),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _go(const CartScreen()),
                    icon: const Icon(Icons.point_of_sale),
                    label: const Text('Vente'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => _go(const MovementFormScreen(type: MovementType.entry)),
                    icon: const Icon(Icons.add_shopping_cart),
                    label: const Text('Entrée'),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _go(const MovementFormScreen(type: MovementType.loss)),
                    icon: const Icon(Icons.remove_circle_outline),
                    label: const Text('Perte'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _go(const CreditsScreen()),
                    icon: const Icon(Icons.handshake_outlined),
                    label: const Text('Crédits'),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              onChanged: (v) => setState(() => _query = v.trim()),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Produit, référence, client, fournisseur',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<MovementType?>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 6)),
                    visualDensity: VisualDensity.compact,
                  ),
                  // Une seule ligne même en grand texte (sinon « Entrée/s »).
                  segments: [
                    for (final (value, label) in const [
                      (null, 'Tout'),
                      (MovementType.sale, 'Ventes'),
                      (MovementType.entry, 'Entrées'),
                      (MovementType.loss, 'Pertes'),
                    ])
                      ButtonSegment(
                        value: value,
                        label: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, softWrap: false)),
                      ),
                  ],
                  selected: {_type},
                  onSelectionChanged: (s) => setState(() => _type = s.first),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    PopupMenuButton<PeriodKind>(
                      tooltip: 'Période',
                      onSelected: _choosePeriod,
                      itemBuilder: (_) => [
                        for (final k in PeriodKind.values) PopupMenuItem(value: k, child: Text(k.label)),
                      ],
                      child: Chip(avatar: const Icon(Icons.date_range, size: 18), label: Text(_period.label)),
                    ),
                    FilterChip(
                      label: const Text('Afficher les annulées'),
                      selected: _showCancelled,
                      onSelected: (v) => setState(() => _showCancelled = v),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: Reloading<List<Movement>>(
              deps: [_type, _period.from, _period.to, _showCancelled, _query],
              load: (repo, uid) => repo.movements(
                uid,
                type: _type,
                from: _period.from,
                to: _period.to,
                includeCancelled: _showCancelled,
                search: _query,
                limit: 500,
              ),
              builder: (context, list) {
                if (list.isEmpty) {
                  return const EmptyState(icon: Icons.receipt_long, message: 'Aucune opération sur cette période.');
                }
                final active = list.where((m) => !m.cancelled);
                final sales = active.where((m) => m.type == MovementType.sale).fold<double>(0, (s, m) => s + m.total);
                final entries = active
                    .where((m) => m.type == MovementType.entry)
                    .fold<double>(0, (s, m) => s + m.total);
                final losses = active.fold<double>(0, (s, m) => s + m.lossValue);
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                      child: SizedBox(
                        width: double.infinity,
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 2,
                          children: [
                            Text(Fmt.count(list.length, 'opération'), style: Theme.of(context).textTheme.bodySmall),
                            if (_type == null || _type == MovementType.sale)
                              Text(
                                'Ventes : ${Fmt.money(sales)}',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            if (_type == null || _type == MovementType.entry)
                              Text(
                                'Entrées : ${Fmt.money(entries)}',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            if ((_type == null && losses > 0) || _type == MovementType.loss)
                              Text(
                                'Pertes : ${Fmt.money(losses)}',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const Divider(height: 1, indent: 64),
                        itemBuilder: (_, i) => MovementTile(movement: list[i]),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
