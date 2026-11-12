import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/shop_repository.dart';
import '../../services/pdf_reports.dart';
import '../../services/session.dart';
import '../common.dart';

/// Édition des documents de vente (reçu, facture, bon de livraison, devis)
/// avec les coordonnées de la boutique et du client.
class SalesDocuments {
  static Future<(AppUser, ShopProfile, Client?)> _context(BuildContext context, String? clientName) async {
    final repo = context.read<ShopRepository>();
    final session = context.read<Session>();
    final profile = await repo.shopProfile(session.userId);
    final client = clientName == null ? null : await repo.clientByName(session.userId, clientName);
    return (session.user!, profile, client);
  }

  static Future<void> receipt(BuildContext context, TicketDetail d) async {
    try {
      final (user, profile, _) = await _context(context, null);
      await PdfReports.share(await PdfReports.receipt(user, d, profile: profile), 'recu-${d.ticket.code}.pdf');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  /// Facture A4. Le premier tirage attribue un numéro définitif (FAC-AAAA-NNNN).
  static Future<void> invoice(BuildContext context, TicketDetail d) async {
    final repo = context.read<ShopRepository>();
    final uid = context.read<Session>().userId;
    try {
      var detail = d;
      if (!d.ticket.hasInvoice) {
        final ok = await confirm(
          context,
          'Établir la facture ?',
          'Un numéro de facture définitif va être attribué à ce ticket. '
              'Il ne pourra plus être modifié ni réutilisé (numérotation continue exigée).',
          ok: 'Établir',
        );
        if (!ok) return;
        await repo.issueInvoice(uid, d.ticket.id);
        detail = (await repo.ticketDetail(uid, d.ticket.id))!;
      }
      if (!context.mounted) return;
      final (user, profile, client) = await _context(context, detail.ticket.client);
      if (!profile.isComplete && context.mounted) {
        showSuccess(context, 'Astuce : complétez adresse, téléphone et NIU dans Réglages > Ma boutique');
      }
      await PdfReports.share(
        await PdfReports.invoice(user, profile, detail, client: client),
        'facture-${detail.ticket.invoiceCode}.pdf',
      );
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  static Future<void> deliveryNote(BuildContext context, TicketDetail d) async {
    try {
      final (user, profile, client) = await _context(context, d.ticket.client);
      await PdfReports.share(
        await PdfReports.deliveryNote(user, profile, d, client: client),
        'bon-livraison-${d.ticket.code}.pdf',
      );
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  static Future<void> quote(BuildContext context, Quote q) async {
    try {
      final (user, profile, client) = await _context(context, q.client);
      await PdfReports.share(await PdfReports.quote(user, profile, q, client: client), 'devis-${q.code}.pdf');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  /// Menu « Documents » d'un ticket.
  static Future<void> pick(BuildContext context, TicketDetail d) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.receipt_outlined),
              title: const Text('Reçu de caisse'),
              subtitle: const Text('Ticket pour imprimante 58/80 mm'),
              onTap: () => Navigator.pop(c, 'receipt'),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(d.ticket.hasInvoice ? 'Facture ${d.ticket.invoiceCode}' : 'Facture A4'),
              subtitle: const Text('Avec NIU, TVA et montant en lettres'),
              onTap: () => Navigator.pop(c, 'invoice'),
            ),
            ListTile(
              leading: const Icon(Icons.local_shipping_outlined),
              title: const Text('Bon de livraison'),
              subtitle: const Text('Quantités sans prix, à signer par le client'),
              onTap: () => Navigator.pop(c, 'delivery'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case 'receipt':
        await receipt(context, d);
      case 'invoice':
        await invoice(context, d);
      case 'delivery':
        await deliveryNote(context, d);
    }
  }
}
