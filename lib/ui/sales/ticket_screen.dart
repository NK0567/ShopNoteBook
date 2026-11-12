import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/shop_repository.dart';
import 'documents.dart';
import '../../services/session.dart';
import '../common.dart';
import '../operations/movement_tile.dart';

/// Couleur et libellé du solde d'un ticket.
(Color, String) ticketState(BuildContext context, Ticket t) {
  if (t.lineCount == 0) return (Theme.of(context).disabledColor, 'Annulé');
  if (t.isCredit) return (Theme.of(context).colorScheme.error, 'Reste ${Fmt.money(t.balance)}');
  if (t.balance <= -1) return (Theme.of(context).colorScheme.error, 'À rendre ${Fmt.money(-t.balance)}');
  return (okColor, 'Payé');
}

/// Liste des ventes (tickets de caisse) récentes.
class TicketsScreen extends StatefulWidget {
  const TicketsScreen({super.key});

  @override
  State<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends State<TicketsScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tickets de caisse')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              onChanged: (v) => setState(() => _q = v.trim()),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Client ou n° de ticket',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: Reloading<List<Ticket>>(
              deps: [_q],
              load: (repo, uid) => repo.tickets(uid, search: _q),
              builder: (context, list) => list.isEmpty
                  ? const EmptyState(icon: Icons.receipt_long, message: 'Aucun ticket.')
                  : ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) => TicketTile(ticket: list[i]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class TicketTile extends StatelessWidget {
  const TicketTile({super.key, required this.ticket});
  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    final (color, label) = ticketState(context, ticket);
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.receipt_long)),
      title: Text('${ticket.code}${ticket.client != null ? ' · ${ticket.client}' : ''}'),
      subtitle: Text('${Fmt.dateTime(ticket.date)} · ${Fmt.count(ticket.lineCount, 'article')}'),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(Fmt.money(ticket.total), style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TicketScreen(ticketId: ticket.id))),
    );
  }
}

/// Détail d'un ticket : articles, encaissements, solde, reçu.
class TicketScreen extends StatelessWidget {
  const TicketScreen({super.key, required this.ticketId});
  final int ticketId;

  @override
  Widget build(BuildContext context) {
    return Reloading<TicketDetail?>(
      load: (repo, uid) => repo.ticketDetail(uid, ticketId),
      builder: (context, d) {
        if (d == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(icon: Icons.search_off, message: 'Ticket introuvable'),
          );
        }
        final t = d.ticket;
        final (color, label) = ticketState(context, t);
        return Scaffold(
          appBar: AppBar(
            title: Text('Ticket ${t.code}'),
            actions: [
              IconButton(
                tooltip: 'Reçu, facture, bon de livraison',
                icon: const Icon(Icons.picture_as_pdf_outlined),
                onPressed: () => SalesDocuments.pick(context, d),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(Fmt.dateTime(t.date), style: Theme.of(context).textTheme.bodySmall),
              if (t.client != null) Text('Client : ${t.client}', style: Theme.of(context).textTheme.titleMedium),
              if (t.hasInvoice) Text('Facture ${t.invoiceCode} du ${Fmt.date(t.invoiceDate!)}'),
              if (t.note != null) Text(t.note!),
              const SizedBox(height: 12),
              KpiGrid(
                children: [
                  KpiCard(label: 'Total', value: Fmt.money(t.total), icon: Icons.receipt_long),
                  KpiCard(label: 'Encaissé', value: Fmt.money(t.paid), icon: Icons.payments_outlined, color: okColor),
                ],
              ),
              const SizedBox(height: 8),
              Card(
                color: color.withValues(alpha: 0.1),
                child: ListTile(
                  leading: Icon(t.isCredit ? Icons.schedule : Icons.check_circle, color: color),
                  title: Text(
                    label,
                    style: TextStyle(color: color, fontWeight: FontWeight.bold),
                  ),
                  trailing: t.isCredit
                      ? FilledButton(onPressed: () => _collect(context, t), child: const Text('Encaisser'))
                      : null,
                ),
              ),
              SectionTitle('Articles (${d.lines.length})'),
              Card(
                child: Column(children: [for (final m in d.lines) MovementTile(movement: m)]),
              ),
              SectionTitle('Encaissements (${d.payments.length})'),
              if (d.payments.isEmpty)
                const Text('Aucun encaissement : vente entièrement à crédit.')
              else
                Card(
                  child: Column(
                    children: [
                      for (final p in d.payments)
                        ListTile(
                          leading: Icon(
                            p.isRefund ? Icons.undo : Icons.payments_outlined,
                            color: p.cancelled ? Theme.of(context).disabledColor : null,
                          ),
                          title: Text(
                            p.isRefund ? 'Rendu au client' : p.method,
                            style: p.cancelled ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
                          ),
                          subtitle: Text(
                            [Fmt.dateTime(p.date), if (p.note != null) p.note!, if (p.cancelled) 'ANNULÉ'].join(' · '),
                          ),
                          trailing: Text(
                            Fmt.money(p.amount),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              decoration: p.cancelled ? TextDecoration.lineThrough : null,
                            ),
                          ),
                          onLongPress: p.cancelled || p.isRefund ? null : () => _cancelPayment(context, p),
                        ),
                    ],
                  ),
                ),
              if (d.payments.any((p) => !p.cancelled && !p.isRefund))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Appui long sur un encaissement pour l\'annuler (erreur de saisie).',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _collect(BuildContext context, Ticket t) async {
    final r = await showDialog<(double, String)>(
      context: context,
      builder: (_) => PaymentDialog(due: t.balance, title: 'Encaisser — ${t.code}'),
    );
    if (r == null || !context.mounted) return;
    try {
      await context.read<ShopRepository>().addPayment(context.read<Session>().userId, t.id, r.$1, method: r.$2);
      if (context.mounted) showSuccess(context, '${Fmt.money(r.$1)} encaissés');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _cancelPayment(BuildContext context, Payment p) async {
    final ok = await confirm(
      context,
      'Annuler cet encaissement ?',
      '${Fmt.money(p.amount)} (${p.method}) du ${Fmt.dateTime(p.date)}.\n'
          'Le montant sera de nouveau dû par le client.',
      ok: 'Annuler l\'encaissement',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await context.read<ShopRepository>().cancelPayment(context.read<Session>().userId, p.id);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}

/// Saisie d'un encaissement : montant (≤ dû) et mode de paiement.
class PaymentDialog extends StatefulWidget {
  const PaymentDialog({super.key, required this.due, required this.title});
  final double due;
  final String title;

  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<PaymentDialog> {
  late final _amount = TextEditingController(text: widget.due.round().toString());
  final _formKey = GlobalKey<FormState>();
  String _method = paymentMethods.first;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Montant dû : ${Fmt.money(widget.due)}'),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amount,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: intInput,
              decoration: const InputDecoration(labelText: 'Montant encaissé', suffixText: 'FCFA'),
              validator: (v) {
                final err = requiredAmount(v, allowZero: false);
                if (err != null) return err;
                if (Fmt.parseNumber(v)! > widget.due + 0.5) return 'Maximum ${Fmt.money(widget.due)}';
                return null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _method,
              decoration: const InputDecoration(labelText: 'Mode de paiement'),
              items: [for (final m in paymentMethods) DropdownMenuItem(value: m, child: Text(m))],
              onChanged: (v) => setState(() => _method = v ?? paymentMethods.first),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, (Fmt.parseNumber(_amount.text)!, _method));
            }
          },
          child: const Text('Encaisser'),
        ),
      ],
    );
  }
}
