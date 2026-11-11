import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/session.dart';
import 'login_screen.dart';
import 'recovery_code_dialog.dart';

/// Réinitialisation du mot de passe avec le code de secours reçu à l'inscription.
/// Les données restant sur le téléphone, il n'y a pas d'e-mail de récupération.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.email = ''});
  final String email;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.email);
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    for (final c in [_email, _code, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final next = await context.read<Session>().resetPasswordWithCode(
        email: _email.text,
        code: _code.text,
        newPassword: _password.text,
      );
      if (!mounted) return;
      await showRecoveryCode(
        context,
        next,
        intro:
            'Mot de passe modifié. Votre ancien code de secours ne fonctionne plus : '
            'voici le nouveau. Notez-le sur papier.',
      );
      if (mounted) Navigator.pop(context, _email.text.trim().toLowerCase());
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Erreur : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      appBar: AppBar(title: const Text('Mot de passe oublié')),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Saisissez le code de secours qui vous a été donné à la création du compte '
              '(format ABCD-EFGH-JKLM), puis choisissez un nouveau mot de passe.',
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Email du compte', prefixIcon: Icon(Icons.email_outlined)),
              validator: Session.validateEmail,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Code de secours',
                hintText: 'ABCD-EFGH-JKLM',
                prefixIcon: Icon(Icons.key_outlined),
              ),
              validator: (v) =>
                  Session.normalizeRecoveryCode(v ?? '').length != 12 ? 'Le code comporte 12 caractères' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Nouveau mot de passe',
                helperText: '8 caractères minimum, avec lettres et chiffres',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: Session.validatePassword,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _confirm,
              obscureText: _obscure,
              onFieldSubmitted: (_) => _submit(),
              decoration: const InputDecoration(labelText: 'Confirmer', prefixIcon: Icon(Icons.lock)),
              validator: (v) => v != _password.text ? 'Les mots de passe ne correspondent pas' : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Changer le mot de passe'),
            ),
          ],
        ),
      ),
    );
  }
}
