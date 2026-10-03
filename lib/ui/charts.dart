import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/format.dart';
import '../data/models.dart';

const chartPalette = [
  Color(0xFF1565C0),
  Color(0xFF2E7D32),
  Color(0xFFEF6C00),
  Color(0xFF6A1B9A),
  Color(0xFF00838F),
  Color(0xFFC62828),
  Color(0xFF9E9D24),
  Color(0xFF4E342E),
];

/// Camembert par catégorie (feuille "Tableau de bord" des classeurs) avec légende.
class CategoryPie extends StatelessWidget {
  const CategoryPie({super.key, required this.shares, this.maxSlices = 6});
  final List<CategoryShare> shares;
  final int maxSlices;

  List<CategoryShare> get _grouped {
    if (shares.length <= maxSlices) return shares;
    final head = shares.take(maxSlices - 1).toList();
    final rest = shares.skip(maxSlices - 1).fold<double>(0, (s, e) => s + e.value);
    return [...head, CategoryShare('Autres', rest)];
  }

  @override
  Widget build(BuildContext context) {
    final data = _grouped.where((s) => s.value > 0).toList();
    final total = data.fold<double>(0, (s, e) => s + e.value);
    if (data.isEmpty || total <= 0) {
      return const SizedBox(height: 80, child: Center(child: Text('Pas encore de données')));
    }
    return Column(
      children: [
        SizedBox(
          width: 150,
          height: 150,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 28,
              sections: [
                for (var i = 0; i < data.length; i++)
                  PieChartSectionData(
                    value: data[i].value,
                    color: chartPalette[i % chartPalette.length],
                    radius: 40,
                    title: data[i].value / total >= 0.08 ? '${(data[i].value / total * 100).round()} %' : '',
                    titleStyle: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < data.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Container(width: 10, height: 10, color: chartPalette[i % chartPalette.length]),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(data[i].category)),
                const SizedBox(width: 8),
                Text(
                  '${Fmt.money(data[i].value)} (${(data[i].value / total * 100).round()} %)',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Histogramme des ventes journalières.
class DailyBars extends StatelessWidget {
  const DailyBars({super.key, required this.days, required this.values});
  final List<DateTime> days;
  final Map<DateTime, double> values;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final maxY = days.map((d) => values[d] ?? 0).fold<double>(0, (a, b) => a > b ? a : b);
    final dayFmt = DateFormat('E', 'fr_FR');
    return SizedBox(
      height: 160,
      child: BarChart(
        BarChartData(
          maxY: maxY <= 0 ? 1 : maxY * 1.15,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                '${Fmt.date(days[group.x])}\n${Fmt.money(rod.toY)}',
                const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= days.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(dayFmt.format(days[i]), style: const TextStyle(fontSize: 11)),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < days.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: values[days[i]] ?? 0,
                    color: color,
                    width: 18,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
