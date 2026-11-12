import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/shop_repository.dart';
import '../../services/session.dart';
import '../common.dart';
import 'cart_screen.dart';
import 'documents.dart';
import 'ticket_screen.dart';

/// Devis / factures pro forma : liste, PDF, transformation en vente.
class QuotesScreen extends StatefulWidget {
  const QuotesScreen({super.key});

  @override
  State<QuotesScreen> createState() => _QuotesScreenState();
}

class _QuotesScreenState extends State<QuotesScreen> {
  QuoteStatus? _status = QuoteStatus.open;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Devis')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartScreen())),
        icon: const Icon(Icons.add),
        label: const Text('Nouveau devis'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SegmentedButton<QuoteStatus?>(
              showSelectedIcon: false,
              segments: [
                for (final (v, l) in const [
                  (QuoteStatus.open, 'En attente'),
                  (QuoteStatus.converted, 'Vendus'),
                  (null, 'Tous'),
                ])
                  ButtonSegment(
                    value: v,
                    label: FittedBox(fit: BoxFit.scaleDown, child: Text(l, maxLines: 1, softWrap: false)),
                  ),
              ],
              selected: {_status},
              onSelectionChanged: (s) => setState(() => _status = s.first),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Pour faire un devis : préparez le panier comme une vente, puis « Enregistrer en devis ».',
              style: TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: Reloading<List<Quote>>(
              deps: [_status],
              load: (r, u) => r.quotes(u, status: _status),
              builder: (context, quotes) {
                if (quotes.isEmpty) {
                  return const EmptyState(icon: Icons.request_quote_outlined, message: 'Aucun devis.');
                }
                final now = DateTime.now();
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: quotes.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final q = quotes[i];
                    final expired = q.status == QuoteStatus.open && q.isExpired(now);
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.request_quote_outlined)),
                      title: Text('${q.code} · ${q.client ?? 'Sans client'}'),
                      subtitle: Text(
                        [
                          Fmt.date(q.date),
                          Fmt.count(q.lines.length, 'article'),
                          if (expired) 'EXPIRÉ' else q.status.label,
                        ].join(' · '),
                      ),
                      trailing: Text(Fmt.money(q.total), style: const TextStyle(fontWeight: FontWeight.bold)),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => QuoteScreen(quoteId: q.id))),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class QuoteScreen extends StatelessWidget {
  const QuoteScreen({super.key, required this.quoteId});
  final int quoteId;

  @override
  Widget build(BuildContext context) {
    return Reloading<Quote?>(
      load: (r, u) => r.quote(u, quoteId),
      builder: (context, q) {
        if (q == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(icon: Icons.search_off, message: 'Devis introuvable'),
          );
        }
        final open = q.status == QuoteStatus.open;
        final expired = open && q.isExpired(DateTime.now());
        return Scaffold(
          appBar: AppBar(
            title: Text('Devis ${q.code}'),
            actions: [
              IconButton(
                tooltip: 'PDF du devis',
                icon: const Icon(Icons.picture_as_pdf_outlined),
                onPressed: () => SalesDocuments.quote(context, q),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Établi le ${Fmt.date(q.date)}', style: Theme.of(context).textTheme.bodySmall),
              if (q.validUntil != null)
                Text(
                  'Valable jusqu\'au ${Fmt.date(q.validUntil!)}${expired ? ' — EXPIRÉ' : ''}',
                  style: expired ? TextStyle(color: Theme.of(context).colorScheme.error) : null,
                ),
              if (q.client != null) Text('Client : ${q.client}', style: Theme.of(context).textTheme.titleMedium),
              if (q.note != null) Text(q.note!),
              const SizedBox(height: 8),
              Chip(label: Text(q.status.label)),
              SectionTitle('Articles (${q.lines.length})'),
              Card(
                child: Column(
                  children: [
                    for (final l in q.lines)
                      ListTile(
                        title: Text(l.productName),
                        subtitle: Text('${l.quantityLabel} × ${Fmt.money(l.displayPrice)}'),
                        trailing: Text(Fmt.money(l.total), style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    const Divider(height: 1),
                    ListTile(
                      title: const Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
                      trailing: Text(Fmt.money(q.total), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (open) ...[
                FilledButton.icon(
                  onPressed: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => CartScreen(quote: q)),
                  ),
                  icon: const Icon(Icons.point_of_sale),
                  label: const Text('Transformer en vente'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await confirm(context, 'Annuler le devis ${q.code} ?', 'Il restera visible dans « Tous ».',
                        ok: 'Annuler le devis', danger: true);
                    if (!ok || !context.mounted) return;
                    try {
                      await context.read<ShopRepository>().cancelQuote(context.read<Session>().userId, q.id);
                    } catch (e) {
                      if (context.mounted) showError(context, e);
                    }
                  },
                  icon: const Icon(Icons.block),
                  label: const Text('Annuler le devis'),
                ),
              ],
              if (q.ticketId != null)
                FilledButton.tonalIcon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => TicketScreen(ticketId: q.ticketId!)),
                  ),
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('Voir la vente'),
                ),
            ],
          ),
        );
      },
    );
  }
}
