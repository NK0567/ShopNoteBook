import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/shop_repository.dart';
import '../../services/pdf_reports.dart';
import '../../services/session.dart';
import '../common.dart';
import 'ticket_screen.dart';

/// Le carnet de crédit : ce que chaque client doit encore.
class CreditsScreen extends StatelessWidget {
  const CreditsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crédits clients')),
      body: Reloading<List<ClientDebt>>(
        load: (repo, uid) => repo.clientDebts(uid),
        builder: (context, debts) {
          if (debts.isEmpty) {
            return const EmptyState(
              icon: Icons.handshake_outlined,
              message: 'Aucun crédit en cours.\nLes ventes non payées en totalité apparaîtront ici.',
            );
          }
          final total = debts.fold<double>(0, (s, d) => s + d.balance);
          final now = DateTime.now();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              KpiGrid(
                children: [
                  KpiCard(
                    label: 'Total des crédits',
                    value: Fmt.money(total),
                    icon: Icons.schedule,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  KpiCard(label: 'Clients concernés', value: '${debts.length}', icon: Icons.people_outline),
                ],
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    for (final d in debts)
                      ListTile(
                        leading: CircleAvatar(child: Text(d.client.characters.first.toUpperCase())),
                        title: Text(d.client),
                        subtitle: Text(
                          '${Fmt.count(d.ticketCount, 'ticket')} · depuis ${_age(now.difference(d.oldest))}',
                        ),
                        trailing: Text(
                          Fmt.money(d.balance),
                          style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.error),
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => ClientCreditScreen(client: d.client)),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _age(Duration d) {
    if (d.inDays >= 60) return '${d.inDays ~/ 30} mois';
    if (d.inDays >= 1) return Fmt.count(d.inDays, 'jour');
    return 'aujourd\'hui';
  }
}

/// Crédits d'un client : tickets non soldés, remboursement, relevé.
class ClientCreditScreen extends StatelessWidget {
  const ClientCreditScreen({super.key, required this.client});
  final String client;

  @override
  Widget build(BuildContext context) {
    return Reloading<List<Ticket>>(
      load: (repo, uid) => repo.openTickets(uid, client: client),
      builder: (context, tickets) {
        final due = tickets.fold<double>(0, (s, t) => s + t.balance);
        return Scaffold(
          appBar: AppBar(
            title: Text(client),
            actions: [
              if (tickets.isNotEmpty)
                IconButton(
                  tooltip: 'Relevé PDF',
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  onPressed: () => _statement(context, tickets),
                ),
            ],
          ),
          body: tickets.isEmpty
              ? const EmptyState(icon: Icons.check_circle_outline, message: 'Ce client ne doit plus rien.')
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text('Reste à payer'),
                            Text(
                              Fmt.money(due),
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: () => _collect(context, due),
                              icon: const Icon(Icons.payments_outlined),
                              label: const Text('Encaisser un remboursement'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Le montant encaissé solde d\'abord les tickets les plus anciens.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    SectionTitle('Tickets non soldés (${tickets.length})'),
                    Card(
                      child: Column(children: [for (final t in tickets) TicketTile(ticket: t)]),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _collect(BuildContext context, double due) async {
    final r = await showDialog<(double, String)>(
      context: context,
      builder: (_) => PaymentDialog(due: due, title: 'Remboursement — $client'),
    );
    if (r == null || !context.mounted) return;
    try {
      await context.read<ShopRepository>().payClientDebt(context.read<Session>().userId, client, r.$1, method: r.$2);
      if (context.mounted) showSuccess(context, '${Fmt.money(r.$1)} encaissés de $client');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _statement(BuildContext context, List<Ticket> tickets) async {
    try {
      final user = context.read<Session>().user!;
      await PdfReports.share(await PdfReports.clientStatement(user, client, tickets), 'releve-$client.pdf');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}
