import 'package:intl/intl.dart';

/// Formatage centralisé (montants en FCFA, dates, quantités, pluriels).
class Fmt {
  static final _money = NumberFormat.decimalPattern('fr_FR');
  static final _percent = NumberFormat('0.0', 'fr_FR');
  static final _date = DateFormat('dd/MM/yyyy');
  static final _dateTime = DateFormat('dd/MM/yyyy HH:mm');

  /// Le FCFA n'a pas de centimes : on arrondit à l'unité.
  static String money(num value) => '${_money.format(value.round())} FCFA';

  static String number(num value) => _money.format(value);

  /// "28,0 %" (virgule décimale française).
  static String percent(double value) => '${_percent.format(value)} %';

  static String date(DateTime d) => _date.format(d);

  static String dateTime(DateTime d) => _dateTime.format(d);

  /// Unités abrégées qui ne prennent jamais de "s".
  static const _invariable = {'kg', 'g', 'mg', 't', 'l', 'cl', 'ml', 'm', 'cm', 'mm', 'm2', 'm3', 'pce', 'pcs'};

  /// Accorde un mot au pluriel : "1 unité", "18 unités", "3 sacs de riz", "2 kg".
  static String plural(num count, String word) {
    final w = word.trim();
    if (count.abs() < 2 || w.isEmpty) return w;
    final parts = w.split(' ');
    final first = parts.first;
    final lower = first.toLowerCase();
    final invariable =
        _invariable.contains(lower.replaceAll('.', '')) ||
        RegExp(r'[sxz]$').hasMatch(lower) ||
        RegExp(r'\d').hasMatch(lower) ||
        lower.endsWith('.');
    if (invariable) return w;
    final pluralFirst = RegExp(r'(au|eu)$').hasMatch(lower)
        ? '${first}x'
        : lower.endsWith('al') && lower != 'bal'
        ? '${first.substring(0, first.length - 2)}aux'
        : '${first}s';
    return [pluralFirst, ...parts.skip(1)].join(' ');
  }

  /// "18 unités", "1 carton".
  /// Espace insécable : le nombre et l'unité ne sont jamais séparés en fin de ligne.
  static String qtyUnit(num count, String unit) => '${_money.format(count)}\u00A0${plural(count, unit)}';

  /// "3 ventes", "1 vente".
  static String count(num count, String word) => '${_money.format(count)}\u00A0${plural(count, word)}';

  /// Analyse une saisie utilisateur ("1 500", "1500,5") en nombre.
  static double? parseNumber(String? input) {
    if (input == null) return null;
    final cleaned = input.replaceAll(RegExp(r'[\s  ]'), '').replaceAll(',', '.');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }
}
