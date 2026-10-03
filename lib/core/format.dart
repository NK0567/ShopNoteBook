import 'package:intl/intl.dart';

/// Formatage centralisé (montants en FCFA, dates, quantités).
class Fmt {
  static final _money = NumberFormat.decimalPattern('fr_FR');
  static final _date = DateFormat('dd/MM/yyyy');
  static final _dateTime = DateFormat('dd/MM/yyyy HH:mm');

  /// Le FCFA n'a pas de centimes : on arrondit à l'unité.
  static String money(num value) => '${_money.format(value.round())} FCFA';

  static String number(num value) => _money.format(value);

  static String qty(num value) =>
      value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(2);

  static String percent(double value) => '${value.toStringAsFixed(1)} %';

  static String date(DateTime d) => _date.format(d);

  static String dateTime(DateTime d) => _dateTime.format(d);

  /// Analyse une saisie utilisateur ("1 500", "1500,5") en nombre.
  static double? parseNumber(String? input) {
    if (input == null) return null;
    final cleaned = input.replaceAll(RegExp(r'[\s  ]'), '').replaceAll(',', '.');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }
}
