import 'package:flutter_test/flutter_test.dart';
import 'package:shopnotbook/core/period.dart';
import 'package:shopnotbook/core/stock_math.dart';

void main() {
  group('CUMP (formule de "ma boutique.xlsm")', () {
    test('reproduit le calcul du classeur : (7000 + 24069) / (14 + 63)', () {
      final cump = StockMath.cump(initialStock: 14, initialUnitCost: 500, qtyIn: 63, valueIn: 24069);
      expect(cump, closeTo(403.49, 0.01));
    });

    test('sans stock ni entrée, retombe sur le coût initial (pas de division par zéro)', () {
      expect(StockMath.cump(initialStock: 0, initialUnitCost: 250, qtyIn: 0, valueIn: 0), 250);
    });
  });

  group('Statut de stock (version "MODIF UN PLUS" + rupture)', () {
    test('seuils', () {
      expect(StockMath.status(0, 10), StockStatus.unavailable);
      expect(StockMath.status(-3, 10), StockStatus.unavailable);
      expect(StockMath.status(4, 10), StockStatus.urgent);
      expect(StockMath.status(5, 10), StockStatus.needed);
      expect(StockMath.status(9, 10), StockStatus.needed);
      expect(StockMath.status(10, 10), StockStatus.ok);
      expect(StockMath.status(1, 0), StockStatus.ok);
    });
  });

  test('bénéfice et marge d\'une vente', () {
    expect(StockMath.saleProfit(3, 900, 600), 900);
    expect(StockMath.marginRate(1000, 750), 25);
    expect(StockMath.marginRate(0, 750), 0);
  });

  test('périodes : bornes de fin exclusives', () {
    final now = DateTime(2026, 3, 15, 10, 30);
    final today = Period.of(PeriodKind.today, now: now);
    expect(today.from, DateTime(2026, 3, 15));
    expect(today.to, DateTime(2026, 3, 16));
    final last = Period.of(PeriodKind.lastMonth, now: DateTime(2026, 1, 10));
    expect(last.from, DateTime(2025, 12));
    expect(last.to, DateTime(2026, 1));
    final custom = Period.custom(DateTime(2026, 2, 1), DateTime(2026, 2, 28));
    expect(custom.to, DateTime(2026, 3, 1));
  });
}
