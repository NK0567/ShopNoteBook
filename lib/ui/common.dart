import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/stock_math.dart';
import '../data/shop_repository.dart';
import '../services/session.dart';

const okColor = Color(0xFF2E7D32);

/// Couleur d'un statut de stock, selon les couleurs choisies dans les réglages.
Color statusColor(BuildContext context, StockStatus s) {
  final user = context.read<Session>().user;
  if (s.isCritical) return Color(user?.criticalColor ?? 0xFFF44336);
  if (s == StockStatus.needed) return Color(user?.warningColor ?? 0xFFFF9800);
  return okColor;
}

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key, this.compact = false});
  final StockStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(context, status);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        compact
            ? switch (status) {
                StockStatus.unavailable => 'Rupture',
                StockStatus.urgent => 'Urgent',
                StockStatus.needed => 'À commander',
                StockStatus.ok => 'OK',
              }
            : status.label,
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }
}

class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color,
    this.subtitle,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Icon(icon, color: c, size: 20),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(label,
                      style: Theme.of(context).textTheme.labelMedium, overflow: TextOverflow.ellipsis),
                ),
              ]),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: c)),
              ),
              if (subtitle != null)
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

/// Grille de KPI : 2 colonnes sur téléphone, 4 sur grand écran.
class KpiGrid extends StatelessWidget {
  const KpiGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth > 700 ? 4 : 2;
      final w = (c.maxWidth - (cols - 1) * 8) / cols;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [for (final child in children) SizedBox(width: w, child: child)],
      );
    });
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message, this.action});
  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Row(children: [
          Expanded(
            child: Text(text,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

void showError(BuildContext context, Object e) {
  final msg = (e is BusinessException || e is AuthException) ? e.toString() : 'Erreur inattendue : $e';
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), backgroundColor: Theme.of(context).colorScheme.error));
}

void showSuccess(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), backgroundColor: okColor));
}

Future<bool> confirm(BuildContext context, String title, String message,
    {String ok = 'Confirmer', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Champs numériques : chiffres, espaces et séparateur décimal uniquement.
final List<TextInputFormatter> intInput = [FilteringTextInputFormatter.digitsOnly];
final List<TextInputFormatter> decimalInput = [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ,.]'))];

String? requiredInt(String? v, {int min = 0, String field = 'Ce champ'}) {
  final n = int.tryParse(v?.trim() ?? '');
  if (n == null) return '$field est obligatoire';
  if (n < min) return '$field doit être ≥ $min';
  return null;
}

String? requiredAmount(String? v, {bool allowZero = true}) {
  final n = Fmt.parseNumber(v);
  if (n == null) return 'Montant obligatoire';
  if (n < 0 || (!allowZero && n == 0)) return allowZero ? 'Montant invalide' : 'Doit être supérieur à 0';
  return null;
}

/// Construit un écran à partir de données chargées, rechargées automatiquement
/// après chaque modification enregistrée dans le dépôt.
class Reloading<T> extends StatefulWidget {
  const Reloading({super.key, required this.load, required this.builder, this.deps = const []});
  final Future<T> Function(ShopRepository repo, int userId) load;
  final Widget Function(BuildContext context, T data) builder;

  /// Paramètres (filtres) : un changement relance le chargement.
  final List<Object?> deps;

  @override
  State<Reloading<T>> createState() => _ReloadingState<T>();
}

class _ReloadingState<T> extends State<Reloading<T>> {
  Future<T>? _future;
  int _revision = -1;
  List<Object?> _deps = const [];
  T? _last;

  void _maybeReload(ShopRepository repo, int userId) {
    if (_future == null || repo.revision != _revision || !_sameDeps(widget.deps, _deps)) {
      _revision = repo.revision;
      _deps = List.of(widget.deps);
      _future = widget.load(repo, userId).then((v) => _last = v);
    }
  }

  static bool _sameDeps(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<ShopRepository>();
    final session = context.watch<Session>();
    if (!session.isLoggedIn) return const SizedBox.shrink();
    _maybeReload(repo, session.userId);
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return EmptyState(icon: Icons.error_outline, message: 'Erreur de chargement :\n${snap.error}');
        }
        final data = snap.data ?? _last;
        if (data == null) return const Center(child: CircularProgressIndicator());
        return widget.builder(context, data);
      },
    );
  }
}
