import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/amount_words.dart';
import '../core/format.dart';
import '../data/models.dart';

/// Génération des documents PDF : inventaire, réapprovisionnement, rapport de période,
/// reçu de caisse et relevé de crédit client.
class PdfReports {
  /// Police Roboto embarquée : la police PDF standard (Helvetica) ignore « Œ », « — », « → »...
  static Future<pw.ThemeData>? _themeFuture;

  static Future<pw.ThemeData> _theme() => _themeFuture ??= () async {
    try {
      final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
      final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
      return pw.ThemeData.withFont(base: regular, bold: bold);
    } catch (_) {
      // Échec du chargement : on réessaiera au prochain document au lieu de garder l'erreur.
      _themeFuture = null;
      rethrow;
    }
  }();

  static Future<pw.Document> _doc(String title, AppUser user) async =>
      pw.Document(title: title, author: user.businessName, theme: await _theme());

  /// Espaces fines insécables (séparateur de milliers) → espace simple, plus sûr à l'impression.
  static String _t(String s) => s.replaceAll(RegExp(r'[  ]'), ' ');
  static String _money(num v) => _t(Fmt.money(v));

  static Future<void> share(Uint8List bytes, String filename) => Printing.sharePdf(bytes: bytes, filename: filename);

  static pw.Widget _header(AppUser user, String title, String subtitle) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(_t(user.businessName), style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      pw.Text(_t(title), style: const pw.TextStyle(fontSize: 14)),
      pw.Text(_t(subtitle), style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
      pw.Divider(),
    ],
  );

  static pw.Widget _table(List<String> headers, List<List<String>> rows, {Set<int> numeric = const {}}) =>
      pw.TableHelper.fromTextArray(
        headers: headers.map(_t).toList(),
        data: rows.map((r) => r.map(_t).toList()).toList(),
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
        cellStyle: const pw.TextStyle(fontSize: 8.5),
        oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
        cellAlignments: {for (final i in numeric) i: pw.Alignment.centerRight},
      );

  static pw.Widget _kv(String k, String v, {double size = 11, bool bold = true}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Text(_t(k), style: pw.TextStyle(fontSize: size)),
        ),
        pw.SizedBox(width: 8),
        pw.Text(
          _t(v),
          style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : null),
        ),
      ],
    ),
  );

  static Future<Uint8List> inventory(AppUser user, List<StockItem> items) async {
    final doc = await _doc('Inventaire', user);
    final total = items.fold<double>(0, (s, i) => s + i.stockValue);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (_) => [
          _header(
            user,
            'Inventaire des stocks',
            'Édité le ${Fmt.dateTime(DateTime.now())} — ${Fmt.count(items.length, 'produit')}',
          ),
          _table(
            [
              'Réf.',
              'Désignation',
              'Catégorie',
              'Unité',
              'Seuil',
              'Initial',
              'Entrées',
              'Sorties',
              'Pertes',
              'Stock',
              'CUMP',
              'Valeur',
              'Statut',
            ],
            [
              for (final i in items)
                [
                  i.product.reference,
                  i.product.name,
                  i.categoryName ?? '-',
                  i.product.unit,
                  '${i.product.alertThreshold}',
                  '${i.product.initialStock}',
                  '${i.qtyIn}',
                  '${i.qtyOut}',
                  '${i.qtyLoss}',
                  '${i.stock}',
                  _money(i.cump),
                  _money(i.stockValue),
                  i.status.label,
                ],
            ],
            numeric: {4, 5, 6, 7, 8, 9, 10, 11},
          ),
          pw.SizedBox(height: 10),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Valeur totale du stock : ${_money(total)}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
    return doc.save();
  }

  /// Liste des produits à réapprovisionner, utilisable comme bon de commande.
  static Future<Uint8List> reorder(AppUser user, List<StockItem> alerts) async {
    final doc = await _doc('Réapprovisionnement', user);
    final total = alerts.fold<double>(0, (s, i) => s + i.suggestedReorder * i.cump);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (_) => [
          _header(user, 'Produits à réapprovisionner', 'Édité le ${Fmt.dateTime(DateTime.now())}'),
          if (alerts.isEmpty)
            pw.Text('Aucun produit en alerte : tous les stocks sont satisfaisants.')
          else ...[
            _table(
              ['Réf.', 'Désignation', 'Stock', 'Seuil', 'Statut', 'Qté suggérée', 'Coût estimé'],
              [
                for (final i in alerts)
                  [
                    i.product.reference,
                    i.product.name,
                    Fmt.qtyUnit(i.stock, i.product.unit),
                    '${i.product.alertThreshold}',
                    i.status.label,
                    '${i.suggestedReorder}',
                    _money(i.suggestedReorder * i.cump),
                  ],
              ],
              numeric: {2, 3, 5, 6},
            ),
            pw.SizedBox(height: 8),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text('Budget estimé : ${_money(total)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ),
          ],
          pw.SizedBox(height: 8),
          pw.Text(
            'Quantité suggérée : de quoi remonter au double du seuil d\'alerte. Coût estimé au CUMP actuel.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ),
    );
    return doc.save();
  }

  static Future<Uint8List> periodReport(
    AppUser user, {
    required String periodLabel,
    required PeriodSummary summary,
    required List<ProductRanking> ranking,
    required List<Movement> movements,
  }) async {
    final doc = await _doc('Rapport $periodLabel', user);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (_) => [
          _header(user, 'Rapport d\'activité — $periodLabel', 'Édité le ${Fmt.dateTime(DateTime.now())}'),
          _kv(
            'Chiffre d\'affaires (${Fmt.count(summary.salesCount, 'vente')}, ${Fmt.count(summary.qtyOut, 'article')})',
            _money(summary.salesAmount),
          ),
          _kv('Bénéfice sur ventes', _money(summary.profit)),
          _kv('Marge sur ventes', Fmt.percent(summary.marginRate)),
          _kv('Pertes (${Fmt.count(summary.qtyLoss, 'article')})', '- ${_money(summary.valueLoss)}'),
          _kv('Bénéfice net', _money(summary.netProfit)),
          _kv('Argent encaissé', _money(summary.cashIn)),
          _kv('Achats / entrées (${Fmt.count(summary.qtyIn, 'article')})', _money(summary.valueIn)),
          pw.SizedBox(height: 14),
          pw.Text('Classement des ventes', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          _table(
            ['#', 'Réf.', 'Produit', 'Qté', 'CA', 'Bénéfice'],
            [
              for (var k = 0; k < ranking.length; k++)
                [
                  '${k + 1}',
                  ranking[k].reference,
                  ranking[k].name,
                  '${ranking[k].quantity}',
                  _money(ranking[k].amount),
                  _money(ranking[k].profit),
                ],
            ],
            numeric: {3, 4, 5},
          ),
          pw.SizedBox(height: 14),
          pw.Text('Détail des opérations', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          _table(
            ['N°', 'Date', 'Produit', 'Qté', 'Prix unit.', 'Total', 'Note'],
            [
              for (final m in movements)
                [
                  m.code,
                  Fmt.dateTime(m.date),
                  m.productName,
                  '${m.quantity}',
                  _money(m.unitPrice),
                  _money(m.total),
                  m.cancelled ? 'ANNULÉE : ${m.cancelReason ?? ''}' : (m.partner ?? m.note ?? ''),
                ],
            ],
            numeric: {3, 4, 5},
          ),
        ],
      ),
    );
    return doc.save();
  }

  /// Reçu de caisse au format ticket (rouleau 58 ou 80 mm), lisible aussi à l'écran.
  static Future<Uint8List> receipt(AppUser user, TicketDetail detail, {ShopProfile profile = const ShopProfile()}) async {
    final doc = await _doc('Reçu ${detail.ticket.code}', user);
    final t = detail.ticket;
    final lines = detail.lines.where((l) => !l.cancelled).toList();
    final payments = detail.payments.where((p) => !p.cancelled).toList();
    const small = pw.TextStyle(fontSize: 8);
    final narrow = profile.receiptWidth == 58;
    doc.addPage(
      pw.Page(
        pageFormat: narrow ? PdfPageFormat.roll57 : PdfPageFormat.roll80,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              _t(user.businessName),
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: narrow ? 10 : 12, fontWeight: pw.FontWeight.bold),
            ),
            for (final h in profile.headerLines) pw.Text(_t(h), textAlign: pw.TextAlign.center, style: small),
            pw.SizedBox(height: 4),
            pw.Text('Reçu ${t.code}', textAlign: pw.TextAlign.center),
            if (t.hasInvoice) pw.Text('Facture ${t.invoiceCode}', textAlign: pw.TextAlign.center, style: small),
            pw.Text(Fmt.dateTime(t.date), textAlign: pw.TextAlign.center, style: small),
            if (t.client != null) pw.Text(_t('Client : ${t.client}'), textAlign: pw.TextAlign.center, style: small),
            pw.Divider(),
            for (final l in lines) ...[
              pw.Text(_t(l.productName), style: const pw.TextStyle(fontSize: 9)),
              _kv(
                '  ${_t(l.quantityLabel)} × ${_money(l.displayPrice)}',
                _money(l.total),
                size: 9,
                bold: false,
              ),
            ],
            if (profile.vatEnabled) ...[
              pw.Divider(),
              _kv('Dont TVA ${Fmt.number(profile.vatRate)} %', _money(Vat.taxPart(t.total, profile.vatRate)), size: 8, bold: false),
            ],
            pw.Divider(),
            _kv('TOTAL', _money(t.total), size: 12),
            for (final p in payments)
              _kv(
                p.isRefund ? 'Rendu (${Fmt.date(p.date)})' : '${p.method} (${Fmt.date(p.date)})',
                _money(p.amount),
                size: 9,
                bold: false,
              ),
            if (t.balance >= 1) _kv('RESTE À PAYER', _money(t.balance), size: 11),
            if (t.balance <= -1) _kv('À RENDRE AU CLIENT', _money(-t.balance), size: 11),
            if (t.balance.abs() < 1 && t.total > 0) pw.Text('Payé — merci !', textAlign: pw.TextAlign.center),
            pw.SizedBox(height: 8),
            pw.Text(_t(profile.invoiceFooter ?? 'Merci de votre visite'), textAlign: pw.TextAlign.center, style: small),
          ],
        ),
      ),
    );
    return doc.save();
  }

  /// Relevé des crédits d'un client (tickets non soldés).
  static Future<Uint8List> clientStatement(AppUser user, String client, List<Ticket> tickets) async {
    final doc = await _doc('Relevé $client', user);
    final due = tickets.fold<double>(0, (s, t) => s + t.balance);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (_) => [
          _header(user, 'Relevé de compte — $client', 'Édité le ${Fmt.dateTime(DateTime.now())}'),
          _table(
            ['Ticket', 'Date', 'Montant', 'Payé', 'Reste'],
            [
              for (final t in tickets) [t.code, Fmt.date(t.date), _money(t.total), _money(t.paid), _money(t.balance)],
            ],
            numeric: {2, 3, 4},
          ),
          pw.SizedBox(height: 10),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Total restant dû : ${_money(due)}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
    return doc.save();
  }

  // ======================================================================
  // Documents commerciaux A4 : facture, bon de livraison, devis
  // ======================================================================

  /// Facture A4 (le ticket doit avoir reçu un numéro de facture).
  static Future<Uint8List> invoice(
    AppUser user,
    ShopProfile profile,
    TicketDetail detail, {
    Client? client,
  }) async {
    final t = detail.ticket;
    final lines = detail.lines.where((l) => !l.cancelled).toList();
    return _salesDocument(
      user: user,
      profile: profile,
      title: 'FACTURE',
      number: t.invoiceCode ?? t.code,
      date: t.invoiceDate ?? t.date,
      extraRefs: ['Ticket ${t.code} du ${Fmt.date(t.date)}'],
      clientName: t.client,
      client: client,
      rows: [
        for (final l in lines)
          _DocLine(l.productReference, l.productName, l.quantityLabel, l.displayPrice, l.total),
      ],
      total: t.total,
      paid: t.paid,
      wordsPrefix: 'Arrêtée la présente facture à la somme de',
    );
  }

  /// Bon de livraison : quantités sans les prix, avec signatures.
  static Future<Uint8List> deliveryNote(
    AppUser user,
    ShopProfile profile,
    TicketDetail detail, {
    Client? client,
  }) async {
    final t = detail.ticket;
    final lines = detail.lines.where((l) => !l.cancelled).toList();
    return _salesDocument(
      user: user,
      profile: profile,
      title: 'BON DE LIVRAISON',
      number: 'BL-${t.number.toString().padLeft(4, '0')}',
      date: DateTime.now(),
      extraRefs: [
        'Ticket ${t.code} du ${Fmt.date(t.date)}',
        if (t.hasInvoice) 'Facture ${t.invoiceCode}',
      ],
      clientName: t.client,
      client: client,
      rows: [for (final l in lines) _DocLine(l.productReference, l.productName, l.quantityLabel, 0, 0)],
      withPrices: false,
      signatures: const ['Livré par', 'Reçu par (nom et signature du client)'],
    );
  }

  /// Devis / facture pro forma.
  static Future<Uint8List> quote(AppUser user, ShopProfile profile, Quote q, {Client? client}) async {
    return _salesDocument(
      user: user,
      profile: profile,
      title: 'DEVIS / FACTURE PRO FORMA',
      number: q.code,
      date: q.date,
      extraRefs: [if (q.validUntil != null) 'Valable jusqu\'au ${Fmt.date(q.validUntil!)}'],
      clientName: q.client,
      client: client,
      rows: [for (final l in q.lines) _DocLine(l.reference, l.productName, l.quantityLabel, l.displayPrice, l.total)],
      total: q.total,
      wordsPrefix: 'Arrêté le présent devis à la somme de',
      note: 'Ce devis n\'est pas une facture. Prix sous réserve de disponibilité du stock.',
    );
  }

  static Future<Uint8List> _salesDocument({
    required AppUser user,
    required ShopProfile profile,
    required String title,
    required String number,
    required DateTime date,
    List<String> extraRefs = const [],
    String? clientName,
    Client? client,
    required List<_DocLine> rows,
    bool withPrices = true,
    double total = 0,
    double? paid,
    String? wordsPrefix,
    String? note,
    List<String> signatures = const ['Le vendeur'],
  }) async {
    final doc = await _doc('$title $number', user);
    const grey = PdfColors.grey700;
    final vat = profile.vatEnabled && withPrices;
    final ht = Vat.excludingTax(total, profile.vatRate);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 40),
        footer: (ctx) => pw.Column(
          children: [
            if ((profile.invoiceFooter ?? '').isNotEmpty)
              pw.Text(_t(profile.invoiceFooter!), textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 8, color: grey)),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text('Page ${ctx.pageNumber}/${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: grey)),
            ),
          ],
        ),
        build: (_) => [
          // En-tête : boutique à gauche, type et numéro du document à droite.
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(_t(user.businessName), style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                    for (final h in profile.headerLines) pw.Text(_t(h), style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.blueGrey800, width: 1.2)),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(_t(title), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                    pw.Text('N° $number', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                    pw.Text('Date : ${Fmt.date(date)}', style: const pw.TextStyle(fontSize: 9)),
                    for (final r in extraRefs) pw.Text(_t(r), style: const pw.TextStyle(fontSize: 8, color: grey)),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          // Client.
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(8),
            decoration: const pw.BoxDecoration(color: PdfColors.grey100),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Client', style: const pw.TextStyle(fontSize: 8, color: grey)),
                pw.Text(_t(clientName ?? 'Client comptant'), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                if ((client?.address ?? '').isNotEmpty) pw.Text(_t(client!.address!), style: const pw.TextStyle(fontSize: 9)),
                if ((client?.phone ?? '').isNotEmpty) pw.Text(_t('Tél. ${client!.phone}'), style: const pw.TextStyle(fontSize: 9)),
                if ((client?.niu ?? '').isNotEmpty) pw.Text(_t('NIU : ${client!.niu}'), style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
          ),
          pw.SizedBox(height: 14),
          _table(
            withPrices
                ? ['Réf.', 'Désignation', 'Quantité', vat ? 'P.U. TTC' : 'Prix unitaire', vat ? 'Montant TTC' : 'Montant']
                : ['Réf.', 'Désignation', 'Quantité', 'Contrôle'],
            [
              for (final r in rows)
                withPrices
                    ? [r.reference, r.name, r.quantity, _money(r.unitPrice), _money(r.total)]
                    : [r.reference, r.name, r.quantity, ''],
            ],
            numeric: withPrices ? {2, 3, 4} : {2},
          ),
          if (withPrices) ...[
            pw.SizedBox(height: 10),
            pw.Row(
              children: [
                pw.Spacer(),
                pw.SizedBox(
                  width: 230,
                  child: pw.Column(
                    children: [
                      if (vat) ...[
                        _kv('Total HT', _money(ht), size: 10, bold: false),
                        _kv('TVA ${Fmt.number(profile.vatRate)} %', _money(total - ht), size: 10, bold: false),
                      ],
                      pw.Divider(height: 6),
                      _kv(vat ? 'Total TTC' : 'Total', _money(total), size: 13),
                      if (paid != null) ...[
                        _kv('Déjà payé', _money(paid), size: 10, bold: false),
                        if (total - paid >= 1) _kv('Reste à payer', _money(total - paid), size: 11),
                        if (total - paid < 1) _kv('Statut', 'Payée', size: 10),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (wordsPrefix != null) ...[
              pw.SizedBox(height: 12),
              pw.Text(
                _t('$wordsPrefix : ${AmountWords.francs(total)}.'),
                style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic),
              ),
            ],
          ],
          if (note != null) ...[
            pw.SizedBox(height: 8),
            pw.Text(_t(note), style: const pw.TextStyle(fontSize: 8, color: grey)),
          ],
          pw.SizedBox(height: 28),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              for (final s in signatures)
                pw.Container(
                  width: 200,
                  height: 70,
                  padding: const pw.EdgeInsets.all(6),
                  decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey500, width: 0.5)),
                  child: pw.Text(_t(s), style: const pw.TextStyle(fontSize: 8, color: grey)),
                ),
            ],
          ),
        ],
      ),
    );
    return doc.save();
  }
}

class _DocLine {
  final String reference;
  final String name;
  final String quantity;
  final double unitPrice;
  final double total;
  const _DocLine(this.reference, this.name, this.quantity, this.unitPrice, this.total);
}
