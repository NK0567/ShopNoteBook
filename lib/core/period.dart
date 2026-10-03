import 'format.dart';

/// Périodes d'analyse. `to` est exclusif.
enum PeriodKind {
  today('Aujourd\'hui'),
  week('7 derniers jours'),
  month('Ce mois'),
  lastMonth('Mois dernier'),
  year('Cette année'),
  all('Tout'),
  custom('Personnalisée');

  const PeriodKind(this.label);
  final String label;
}

class Period {
  final PeriodKind kind;
  final DateTime? from;
  final DateTime? to;

  const Period._(this.kind, this.from, this.to);

  factory Period.of(PeriodKind kind, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final tomorrow = today.add(const Duration(days: 1));
    switch (kind) {
      case PeriodKind.today:
        return Period._(kind, today, tomorrow);
      case PeriodKind.week:
        return Period._(kind, today.subtract(const Duration(days: 6)), tomorrow);
      case PeriodKind.month:
        return Period._(kind, DateTime(n.year, n.month), tomorrow);
      case PeriodKind.lastMonth:
        return Period._(kind, DateTime(n.year, n.month - 1), DateTime(n.year, n.month));
      case PeriodKind.year:
        return Period._(kind, DateTime(n.year), tomorrow);
      case PeriodKind.all:
      case PeriodKind.custom:
        return Period._(PeriodKind.all, null, null);
    }
  }

  /// Plage personnalisée, bornes incluses (jour entier).
  factory Period.custom(DateTime start, DateTime end) => Period._(
    PeriodKind.custom,
    DateTime(start.year, start.month, start.day),
    DateTime(end.year, end.month, end.day).add(const Duration(days: 1)),
  );

  String get label {
    if (kind == PeriodKind.custom && from != null && to != null) {
      return '${Fmt.date(from!)} → ${Fmt.date(to!.subtract(const Duration(days: 1)))}';
    }
    return kind.label;
  }
}
