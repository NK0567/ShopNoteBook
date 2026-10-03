import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/session.dart';
import 'login_screen.dart';

/// Écran affiché après une période d'inactivité.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (_password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<Session>().unlock(_password.text);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      _password.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<Session>();
    final user = session.user;
    return AuthScaffold(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppLogo(subtitle: user?.businessName ?? ''),
        const SizedBox(height: 24),
        Text('Application verrouillée', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text('Saisissez le mot de passe de ${user?.email ?? ''}',
            textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 24),
        TextField(
          controller: _password,
          obscureText: true,
          autofocus: true,
          onSubmitted: (_) => _unlock(),
          decoration: const InputDecoration(labelText: 'Mot de passe', prefixIcon: Icon(Icons.lock_outline)),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _busy ? null : _unlock,
          icon: const Icon(Icons.lock_open),
          label: const Text('Déverrouiller'),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: _busy ? null : session.logout, child: const Text('Changer de compte')),
      ]),
    );
  }
}
