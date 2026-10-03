import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shopnotbook/core/format.dart';

String _plain(String s) => s.replaceAll(RegExp(r'[  ]'), ' ');

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  test('pluriels des unités', () {
    expect(Fmt.plural(1, 'unité'), 'unité');
    expect(Fmt.plural(0, 'unité'), 'unité');
    expect(Fmt.plural(18, 'unité'), 'unités');
    expect(Fmt.plural(3, 'sac de riz'), 'sacs de riz');
    expect(Fmt.plural(2, 'kg'), 'kg');
    expect(Fmt.plural(2, 'colis'), 'colis');
    expect(Fmt.plural(2, 'carton'), 'cartons');
    expect(Fmt.plural(2, 'seau'), 'seaux');
    expect(Fmt.plural(2, '1unité'), '1unité');
    expect(Fmt.qtyUnit(1500, 'pièce'), _plainAware('1 500 pièces'));
  });

  test('montants et pourcentages à la française', () {
    expect(_plain(Fmt.money(1250000)), '1 250 000 FCFA');
    expect(_plain(Fmt.money(403.49)), '403 FCFA');
    expect(Fmt.percent(28), '28,0 %');
  });

  test('saisie de montants', () {
    expect(Fmt.parseNumber('1 500'), 1500);
    expect(Fmt.parseNumber(''), isNull);
    expect(Fmt.parseNumber('abc'), isNull);
  });
}

Matcher _plainAware(String expected) => predicate<String>((s) => _plain(s) == expected, expected);
