import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/format.dart';
import '../data/models.dart';

/// Génération des rapports PDF (inventaire, bon de réapprovisionnement, rapport de période).
class PdfReports {
  /// La police PDF standard ne connaît pas les espaces fines insécables.
  static String _t(String s) => s.replaceAll(RegExp(r'[  ]'), ' ');
  static String _money(num v) => _t(Fmt.money(v));

  static Future<void> share(Uint8List bytes, String filename) =>
      Printing.sharePdf(bytes: bytes, filename: filename);

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

  static pw.Widget _kv(String k, String v) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(children: [
          pw.Expanded(child: pw.Text(_t(k))),
          pw.Text(_t(v), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        ]),
      );

  static Future<Uint8List> inventory(AppUser user, List<StockItem> items) {
    final doc = pw.Document(title: 'Inventaire', author: user.businessName);
    final total = items.fold<double>(0, (s, i) => s + i.stockValue);
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      build: (_) => [
        _header(user, 'Inventaire des stocks', 'Édité le ${Fmt.dateTime(DateTime.now())} — ${items.length} produit(s)'),
        _table(
          ['Réf.', 'Désignation', 'Catégorie', 'Unité', 'Seuil', 'Initial', 'Entrées', 'Sorties', 'Stock', 'CUMP', 'Valeur', 'Statut'],
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
                '${i.stock}',
                _money(i.cump),
                _money(i.stockValue),
                i.status.label,
              ]
          ],
          numeric: {4, 5, 6, 7, 8, 9, 10},
        ),
        pw.SizedBox(height: 10),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Valeur totale du stock : ${_money(total)}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
        ),
      ],
    ));
    return doc.save();
  }

  /// Liste des produits à réapprovisionner, utilisable comme bon de commande.
  static Future<Uint8List> reorder(AppUser user, List<StockItem> alerts) {
    final doc = pw.Document(title: 'Réapprovisionnement', author: user.businessName);
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (_) => [
        _header(user, 'Produits à réapprovisionner', 'Édité le ${Fmt.dateTime(DateTime.now())}'),
        if (alerts.isEmpty)
          pw.Text('Aucun produit en alerte : tous les stocks sont satisfaisants.')
        else
          _table(
            ['Réf.', 'Désignation', 'Stock', 'Seuil', 'Statut', 'Qté suggérée', 'Coût estimé'],
            [
              for (final i in alerts)
                [
                  i.product.reference,
                  i.product.name,
                  '${i.stock} ${i.product.unit}',
                  '${i.product.alertThreshold}',
                  i.status.label,
                  '${i.suggestedReorder}',
                  _money(i.suggestedReorder * i.cump),
                ]
            ],
            numeric: {2, 3, 5, 6},
          ),
        pw.SizedBox(height: 8),
        pw.Text('Quantité suggérée : de quoi remonter au double du seuil d\'alerte. Coût estimé au CUMP actuel.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      ],
    ));
    return doc.save();
  }

  static Future<Uint8List> periodReport(
    AppUser user, {
    required String periodLabel,
    required PeriodSummary summary,
    required List<ProductRanking> ranking,
    required List<Movement> movements,
  }) {
    final doc = pw.Document(title: 'Rapport $periodLabel', author: user.businessName);
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (_) => [
        _header(user, 'Rapport d\'activité — $periodLabel', 'Édité le ${Fmt.dateTime(DateTime.now())}'),
        _kv('Chiffre d\'affaires (${summary.salesCount} vente(s), ${summary.qtyOut} article(s))', _money(summary.salesAmount)),
        _kv('Bénéfice', _money(summary.profit)),
        _kv('Marge sur ventes', Fmt.percent(summary.marginRate)),
        _kv('Achats / entrées (${summary.qtyIn} article(s))', _money(summary.valueIn)),
        pw.SizedBox(height: 14),
        pw.Text('Classement des ventes', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        _table(
          ['#', 'Réf.', 'Produit', 'Qté', 'CA', 'Bénéfice'],
          [
            for (var k = 0; k < ranking.length; k++)
              ['${k + 1}', ranking[k].reference, ranking[k].name, '${ranking[k].quantity}', _money(ranking[k].amount), _money(ranking[k].profit)]
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
                m.cancelled ? 'ANNULÉE : ${m.cancelReason ?? ''}' : (m.partner ?? ''),
              ]
          ],
          numeric: {3, 4, 5},
        ),
      ],
    ));
    return doc.save();
  }
}
