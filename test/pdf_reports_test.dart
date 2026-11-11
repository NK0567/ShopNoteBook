import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shopnotbook/core/period.dart';
import 'package:shopnotbook/data/models.dart';
import 'package:shopnotbook/services/pdf_reports.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    Intl.defaultLocale = 'fr_FR';
    await initializeDateFormatting('fr_FR');
  });

  final user = AppUser(
    id: 1,
    name: 'Boris',
    email: 'b@t.cm',
    businessName: 'Établissements Kalefack — Œufs & Cie',
    defaultAlertThreshold: 10,
    warningColor: 0xFFFF9800,
    criticalColor: 0xFFF44336,
    autoLockMinutes: 5,
    createdAt: DateTime(2026),
  );

  StockItem item(String name, {int initial = 10, int out = 0}) => StockItem(
    product: Product(
      id: 1,
      reference: 'R1',
      name: name,
      unit: 'unité',
      alertThreshold: 10,
      initialStock: initial,
      initialUnitCost: 1500,
      sellingPrice: 2500,
    ),
    categoryName: 'Épicerie',
    qtyIn: 0,
    valueIn: 0,
    qtyOut: out,
    salesAmount: out * 2500.0,
    profit: out * 1000.0,
  );

  test('inventaire et réapprovisionnement avec caractères spéciaux', () async {
    final items = [item('Riz parfumé 25 kg'), item('Œufs (plateau) « bio » → frais', out: 8), item('咖啡 café ☕')];
    expect((await PdfReports.inventory(user, items)).length, greaterThan(1000));
    expect((await PdfReports.reorder(user, items)).length, greaterThan(1000));
  });

  test('rapport de période personnalisée', () async {
    final p = Period.custom(DateTime(2026, 9, 1), DateTime(2026, 9, 30));
    final m = Movement(
      id: 1,
      number: 1,
      type: MovementType.sale,
      productId: 1,
      productReference: 'R1',
      productName: 'Savon « Lux » — 200 g',
      categoryName: null,
      unit: 'unité',
      date: DateTime(2026, 9, 2, 10),
      quantity: 2,
      unitPrice: 500,
      unitCost: 300,
      partner: 'Mme Ngo Bassa',
      cancelled: true,
      cancelReason: 'Erreur ⚠',
    );
    final bytes = await PdfReports.periodReport(
      user,
      periodLabel: p.label,
      summary: const PeriodSummary(qtyOut: 2, salesAmount: 1000, profit: 400, salesCount: 1),
      ranking: const [
        ProductRanking(productId: 1, reference: 'R1', name: 'Savon', quantity: 2, amount: 1000, profit: 400),
      ],
      movements: [m],
    );
    expect(bytes.length, greaterThan(1000));
  });
}
