import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/shop_repository.dart';
import '../../services/session.dart';
import '../common.dart';
import '../sales/ticket_screen.dart';

/// Ligne d'historique. Disposition sur 2 lignes pour que le nom du produit,
/// la date et les montants restent lisibles sur un écran de téléphone.
class MovementTile extends StatelessWidget {
  const MovementTile({super.key, required this.movement, this.showProduct = true});
  final Movement movement;
  final bool showProduct;

  @override
  Widget build(BuildContext context) {
    final m = movement;
    final isSale = m.type == MovementType.sale;
    final isLoss = m.type == MovementType.loss;
    final theme = Theme.of(context);
    final color = m.cancelled
        ? theme.disabledColor
        : switch (m.type) {
            MovementType.sale => okColor,
            MovementType.entry => theme.colorScheme.primary,
            MovementType.loss => theme.colorScheme.error,
          };
    final strike = m.cancelled ? const TextStyle(decoration: TextDecoration.lineThrough) : const TextStyle();
    final small = theme.textTheme.bodySmall;

    return InkWell(
      onTap: () => showMovementDetails(context, m),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: color.withValues(alpha: 0.12),
              child: Icon(
                isLoss
                    ? Icons.remove_circle_outline
                    : isSale
                    ? Icons.arrow_upward
                    : Icons.arrow_downward,
                color: color,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          showProduct ? m.productName : '${m.type.label} ${m.code}',
                          style: theme.textTheme.bodyLarge!.merge(strike),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        Fmt.money(m.total),
                        style: TextStyle(fontWeight: FontWeight.bold, color: color).merge(strike),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          [
                            if (showProduct) m.code,
                            if (m.ticketNumber != null) 'T-${m.ticketNumber.toString().padLeft(4, '0')}',
                            Fmt.dateTime(m.date),
                            '${m.type == MovementType.entry ? '+' : '−'}${m.quantityLabel}',
                            if (isLoss && m.note != null) m.note!,
                          ].join(' · '),
                          style: small,
                        ),
                      ),
                      if (m.cancelled)
                        Text(
                          'ANNULÉE',
                          style: small?.copyWith(color: theme.colorScheme.error, fontWeight: FontWeight.bold),
                        )
                      else if (isSale)
                        Text('bénéf. ${Fmt.money(m.profit)}', style: small),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${m.type.label} ${m.code}', style: Theme.of(sheet).textTheme.titleLarge),
            if (m.cancelled) Text('Opération annulée', style: TextStyle(color: Theme.of(sheet).colorScheme.error)),
            const SizedBox(height: 12),
            _kv('Date', Fmt.dateTime(m.date)),
            _kv('Produit', '${m.productReference} — ${m.productName}'),
            _kv('Catégorie', m.categoryName ?? '-'),
            _kv('Quantité', m.quantityLabel),
            _kv(switch (m.type) {
              MovementType.sale => 'Prix de vente',
              MovementType.entry => 'Coût d\'achat',
              MovementType.loss => 'Valeur unitaire (CUMP)',
            }, m.displayPrice == m.unitPrice ? Fmt.money(m.unitPrice) : '${Fmt.money(m.displayPrice)} / ${m.packName}'),
            _kv('Total', Fmt.money(m.total)),
            if (isSale) _kv('CUMP à la vente', Fmt.money(m.unitCost)),
            if (isSale) _kv('Bénéfice', Fmt.money(m.profit)),
            if (m.partner != null) _kv(isSale ? 'Client' : 'Fournisseur', m.partner!),
            if (m.ticketId != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(sheet);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => TicketScreen(ticketId: m.ticketId!)));
                },
                icon: const Icon(Icons.receipt_long),
                label: Text('Voir le ticket T-${m.ticketNumber.toString().padLeft(4, '0')}'),
              ),
            ],
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
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(width: 130, child: Text(k)),
      Expanded(
        child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    ],
  ),
);

Future<void> _cancel(BuildContext context, Movement m) async {
  final qty = Fmt.qtyUnit(m.quantity, m.unit);
  final many = m.quantity > 1;
  final effect = m.type == MovementType.sale
      ? '$qty ${many ? 'reviendront' : 'reviendra'} en stock.'
      : '$qty ${many ? 'seront retirés' : 'sera retiré'} du stock.';
  final reason = await promptText(
    context,
    title: 'Annuler ${m.code} ?',
    message: '$effect L\'opération restera visible, barrée, dans l\'historique.',
    label: 'Motif (obligatoire)',
    hint: 'ex. erreur de saisie',
    ok: 'Annuler l\'opération',
    danger: true,
  );
  if (reason == null || !context.mounted) return;
  try {
    final refund = await context.read<ShopRepository>().cancelMovement(context.read<Session>().userId, m.id, reason);
    if (!context.mounted) return;
    if (refund >= 1) {
      // L'article avait déjà été payé : le commerçant doit rendre l'argent.
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          icon: const Icon(Icons.undo, size: 36),
          title: Text('${m.code} annulée'),
          content: Text('Rendez ${Fmt.money(refund)} au client.\nLe remboursement est noté sur son ticket.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('C\'est fait'))],
        ),
      );
    } else {
      showSuccess(context, '${m.code} annulée');
    }
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}
