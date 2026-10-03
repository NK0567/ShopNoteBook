import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/shop_repository.dart';
import '../../services/session.dart';
import '../common.dart';

class MovementTile extends StatelessWidget {
  const MovementTile({super.key, required this.movement, this.showProduct = true});
  final Movement movement;
  final bool showProduct;

  @override
  Widget build(BuildContext context) {
    final m = movement;
    final isSale = m.type == MovementType.sale;
    final color = m.cancelled ? Colors.grey : (isSale ? okColor : Theme.of(context).colorScheme.primary);
    final strike = m.cancelled ? const TextStyle(decoration: TextDecoration.lineThrough) : null;
    return ListTile(
      onTap: () => showMovementDetails(context, m),
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(isSale ? Icons.arrow_upward : Icons.arrow_downward, color: color),
      ),
      title: Text(
        showProduct ? m.productName : '${m.type.label} ${m.code}',
        style: strike,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          if (showProduct) m.code,
          Fmt.dateTime(m.date),
          '${isSale ? '-' : '+'}${m.quantity} × ${Fmt.money(m.unitPrice)}',
          if (m.cancelled) 'ANNULÉE',
        ].join(' · '),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(Fmt.money(m.total), style: TextStyle(fontWeight: FontWeight.bold, color: color).merge(strike)),
          if (isSale && !m.cancelled)
            Text('bénéf. ${Fmt.money(m.profit)}', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

Future<void> showMovementDetails(BuildContext context, Movement m) {
  final isSale = m.type == MovementType.sale;
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${m.type.label} ${m.code}', style: Theme.of(sheet).textTheme.titleLarge),
            const SizedBox(height: 12),
            _kv('Date', Fmt.dateTime(m.date)),
            _kv('Produit', '${m.productReference} — ${m.productName}'),
            _kv('Catégorie', m.categoryName ?? '-'),
            _kv('Quantité', '${m.quantity} ${m.unit}'),
            _kv(isSale ? 'Prix de vente' : 'Coût d\'achat', Fmt.money(m.unitPrice)),
            _kv('Total', Fmt.money(m.total)),
            if (isSale) _kv('CUMP au moment de la vente', Fmt.money(m.unitCost)),
            if (isSale) _kv('Bénéfice', Fmt.money(m.profit)),
            if (m.partner != null) _kv(isSale ? 'Client' : 'Fournisseur', m.partner!),
            if (m.note != null) _kv('Note', m.note!),
            if (m.cancelled) ...[
              const Divider(),
              _kv('Annulée le', m.cancelledAt == null ? '-' : Fmt.dateTime(m.cancelledAt!)),
              _kv('Motif', m.cancelReason ?? '-'),
            ] else ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Theme.of(sheet).colorScheme.error),
                onPressed: () async {
                  Navigator.pop(sheet);
                  await _cancel(context, m);
                },
                icon: const Icon(Icons.undo),
                label: const Text('Annuler cette opération'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

Widget _kv(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 170, child: Text(k)),
        Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600))),
      ]),
    );

Future<void> _cancel(BuildContext context, Movement m) async {
  final ctrl = TextEditingController();
  final reason = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Annuler ${m.code} ?'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(m.type == MovementType.sale
            ? 'Les ${m.quantity} ${m.unit} reviendront en stock. L\'opération restera visible, barrée, dans l\'historique.'
            : 'Les ${m.quantity} ${m.unit} seront retirés du stock. L\'opération restera visible, barrée, dans l\'historique.'),
        const SizedBox(height: 12),
        TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Motif (obligatoire)', hintText: 'ex. erreur de saisie'),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Retour')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error),
          onPressed: () => Navigator.pop(c, ctrl.text),
          child: const Text('Annuler l\'opération'),
        ),
      ],
    ),
  );
  ctrl.dispose();
  if (reason == null || !context.mounted) return;
  try {
    await context.read<ShopRepository>().cancelMovement(context.read<Session>().userId, m.id, reason);
    if (context.mounted) showSuccess(context, '${m.code} annulée');
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}
