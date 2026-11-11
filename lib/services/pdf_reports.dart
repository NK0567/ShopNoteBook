import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

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

  /// Reçu de caisse au format ticket (rouleau 80 mm), lisible aussi à l'écran.
  static Future<Uint8List> receipt(AppUser user, TicketDetail detail) async {
    final doc = await _doc('Reçu ${detail.ticket.code}', user);
    final t = detail.ticket;
    final lines = detail.lines.where((l) => !l.cancelled).toList();
    final payments = detail.payments.where((p) => !p.cancelled).toList();
    const small = pw.TextStyle(fontSize: 8);
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              _t(user.businessName),
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text('Reçu ${t.code}', textAlign: pw.TextAlign.center),
            pw.Text(Fmt.dateTime(t.date), textAlign: pw.TextAlign.center, style: small),
            if (t.client != null) pw.Text(_t('Client : ${t.client}'), textAlign: pw.TextAlign.center, style: small),
            pw.Divider(),
            for (final l in lines) ...[
              pw.Text(_t(l.productName), style: const pw.TextStyle(fontSize: 9)),
              _kv('  ${l.quantity} × ${_money(l.unitPrice)}', _money(l.total), size: 9, bold: false),
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
            pw.Text('Merci de votre visite', textAlign: pw.TextAlign.center, style: small),
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
}
