import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/shop_repository.dart';
import '../../services/session.dart';
import '../common.dart';

const _palette = <int>[
  0xFFFF9800, // orange
  0xFFFFC107, // ambre
  0xFFF44336, // rouge
  0xFFD32F2F, // rouge foncé
  0xFFE91E63, // rose
  0xFF9C27B0, // violet
  0xFF795548, // marron
  0xFF607D8B, // gris bleu
];

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final user = session.user!;
    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.store)),
            title: Text(user.businessName),
            subtitle: Text('${user.name} · ${user.email}'),
            trailing: const Icon(Icons.edit),
            onTap: () => _editProfile(context, user),
          ),
          const Divider(),
          _header(context, 'Stock'),
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: const Text('Seuil d\'alerte par défaut'),
            subtitle: Text('${user.defaultAlertThreshold} — proposé à la création d\'un produit'),
            onTap: () => _editThreshold(context, user),
          ),
          ListTile(
            leading: Icon(Icons.circle, color: Color(user.warningColor)),
            title: const Text('Couleur « Approvisionnement nécessaire »'),
            onTap: () => _pickColor(context, user, warning: true),
          ),
          ListTile(
            leading: Icon(Icons.circle, color: Color(user.criticalColor)),
            title: const Text('Couleur « Urgent / Rupture »'),
            onTap: () => _pickColor(context, user, warning: false),
          ),
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('Catégories'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoriesScreen())),
          ),
          const Divider(),
          _header(context, 'Sécurité'),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Verrouillage automatique'),
            subtitle: Text(user.autoLockMinutes == 0 ? 'Désactivé' : 'Après ${user.autoLockMinutes} min d\'inactivité'),
            onTap: () => _pickAutoLock(context, user),
          ),
          ListTile(
            leading: const Icon(Icons.password),
            title: const Text('Changer le mot de passe'),
            onTap: () => _changePassword(context),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Journal d\'activité'),
            subtitle: const Text('Connexions, modifications, annulations'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AuditScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Verrouiller maintenant'),
            onTap: session.lock,
          ),
          ListTile(
            leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
            title: Text('Se déconnecter', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            onTap: () async {
              if (await confirm(context, 'Déconnexion', 'Voulez-vous vous déconnecter ?', ok: 'Se déconnecter')) {
                session.logout();
              }
            },
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('ShopBook 2.0'),
            subtitle: Text('Données stockées uniquement sur cet appareil.'),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(t,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );

  Future<void> _save(BuildContext context, AppUser updated, [String? msg]) async {
    try {
      await context.read<Session>().updateSettings(updated);
      if (context.mounted) showSuccess(context, msg ?? 'Réglages enregistrés');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _editProfile(BuildContext context, AppUser user) async {
    final name = TextEditingController(text: user.name);
    final business = TextEditingController(text: user.businessName);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Profil'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Votre nom')),
          const SizedBox(height: 12),
          TextField(controller: business, decoration: const InputDecoration(labelText: 'Nom de la boutique')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await _save(context, user.copyWith(name: name.text.trim(), businessName: business.text.trim()));
    }
    name.dispose();
    business.dispose();
  }

  Future<void> _editThreshold(BuildContext context, AppUser user) async {
    final ctrl = TextEditingController(text: '${user.defaultAlertThreshold}');
    final v = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Seuil d\'alerte par défaut'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          inputFormatters: intInput,
          autofocus: true,
          decoration: const InputDecoration(
            helperText: 'Sous 50 % du seuil : urgent ; sous le seuil : à commander',
            helperMaxLines: 2,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, int.tryParse(ctrl.text)), child: const Text('OK')),
        ],
      ),
    );
    ctrl.dispose();
    if (v != null && context.mounted) await _save(context, user.copyWith(defaultAlertThreshold: v));
  }

  Future<void> _pickColor(BuildContext context, AppUser user, {required bool warning}) async {
    final c = await showDialog<int>(
      context: context,
      builder: (d) => SimpleDialog(
        title: Text(warning ? 'Couleur « à commander »' : 'Couleur « urgent »'),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 12, runSpacing: 12, children: [
              for (final p in _palette)
                InkWell(
                  onTap: () => Navigator.pop(d, p),
                  customBorder: const CircleBorder(),
                  child: CircleAvatar(
                    backgroundColor: Color(p),
                    child: p == (warning ? user.warningColor : user.criticalColor)
                        ? const Icon(Icons.check, color: Colors.white)
                        : null,
                  ),
                ),
            ]),
          ),
        ],
      ),
    );
    if (c == null || !context.mounted) return;
    await _save(context, warning ? user.copyWith(warningColor: c) : user.copyWith(criticalColor: c));
  }

  Future<void> _pickAutoLock(BuildContext context, AppUser user) async {
    final v = await showDialog<int>(
      context: context,
      builder: (d) => SimpleDialog(
        title: const Text('Verrouillage automatique'),
        children: [
          for (final m in [1, 5, 15, 30, 0])
            ListTile(
              title: Text(m == 0 ? 'Désactivé' : 'Après $m min'),
              trailing: m == user.autoLockMinutes ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(d, m),
            ),
        ],
      ),
    );
    if (v != null && context.mounted) await _save(context, user.copyWith(autoLockMinutes: v));
  }

  Future<void> _changePassword(BuildContext context) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => const _ChangePasswordDialog());
    if (ok == true && context.mounted) showSuccess(context, 'Mot de passe modifié');
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<Session>().changePassword(_current.text, _next.text);
      if (mounted) Navigator.pop(context, true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Changer le mot de passe'),
      content: Form(
        key: _formKey,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(
            controller: _current,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Mot de passe actuel'),
            validator: (v) => (v == null || v.isEmpty) ? 'Obligatoire' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _next,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Nouveau mot de passe'),
            validator: Session.validatePassword,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _confirm,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Confirmer'),
            validator: (v) => v != _next.text ? 'Ne correspond pas' : null,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
        FilledButton(onPressed: _busy ? null : _submit, child: const Text('Valider')),
      ],
    );
  }
}

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  Future<String?> _ask(BuildContext context, String title, [String initial = '']) async {
    final ctrl = TextEditingController(text: initial);
    final v = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('OK')),
        ],
      ),
    );
    ctrl.dispose();
    return v;
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ShopRepository>();
    final uid = context.read<Session>().userId;
    Future<void> run(Future<void> Function() action) async {
      try {
        await action();
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Catégories')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Ajouter',
        onPressed: () async {
          final name = await _ask(context, 'Nouvelle catégorie');
          if (name != null) await run(() => repo.addCategory(uid, name));
        },
        child: const Icon(Icons.add),
      ),
      body: Reloading<(List<Category>, List<StockItem>)>(
        load: (r, u) async => (await r.categories(u), await r.inventory(u, includeArchived: true)),
        builder: (context, data) {
          final (cats, items) = data;
          if (cats.isEmpty) {
            return const EmptyState(icon: Icons.category_outlined, message: 'Aucune catégorie.');
          }
          return ListView(children: [
            for (final c in cats)
              ListTile(
                title: Text(c.name),
                subtitle: Text('${items.where((i) => i.product.categoryId == c.id).length} produit(s)'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: 'Renommer',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () async {
                      final name = await _ask(context, 'Renommer', c.name);
                      if (name != null) await run(() => repo.renameCategory(uid, c.id, name));
                    },
                  ),
                  IconButton(
                    tooltip: 'Supprimer',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final ok = await confirm(context, 'Supprimer « ${c.name} » ?',
                          'Les produits de cette catégorie passeront en « Sans catégorie ».',
                          ok: 'Supprimer', danger: true);
                      if (ok) await run(() => repo.deleteCategory(uid, c.id));
                    },
                  ),
                ]),
              ),
          ]);
        },
      ),
    );
  }
}

class AuditScreen extends StatelessWidget {
  const AuditScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Journal d\'activité')),
      body: Reloading<List<AuditEntry>>(
        load: (r, u) => r.auditLog(u),
        builder: (context, list) => list.isEmpty
            ? const EmptyState(icon: Icons.history, message: 'Journal vide')
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) => ListTile(
                  dense: true,
                  title: Text(list[i].details),
                  subtitle: Text('${list[i].action} · ${Fmt.dateTime(list[i].date)}'),
                ),
              ),
      ),
    );
  }
}
