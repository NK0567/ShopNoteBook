import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Affiche le code de secours une seule fois. Impossible de fermer sans confirmer
/// l'avoir noté : c'est la seule façon de récupérer un mot de passe oublié.
Future<void> showRecoveryCode(BuildContext context, String code, {String? intro}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _RecoveryCodeDialog(code: code, intro: intro),
);

class _RecoveryCodeDialog extends StatefulWidget {
  const _RecoveryCodeDialog({required this.code, this.intro});
  final String code;
  final String? intro;

  @override
  State<_RecoveryCodeDialog> createState() => _RecoveryCodeDialogState();
}

class _RecoveryCodeDialogState extends State<_RecoveryCodeDialog> {
  bool _noted = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      child: AlertDialog(
        icon: const Icon(Icons.key, size: 36),
        title: const Text('Votre code de secours'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.intro ??
                    'Si vous oubliez votre mot de passe, ce code est le SEUL moyen de récupérer votre boutique. '
                        'Écrivez-le sur papier et gardez-le en lieu sûr (pas dans le téléphone).',
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  widget.code,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: widget.code));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copié')));
                  }
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copier'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _noted,
                onChanged: (v) => setState(() => _noted = v ?? false),
                title: const Text('J\'ai noté ce code'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(onPressed: _noted ? () => Navigator.pop(context) : null, child: const Text('Continuer')),
        ],
      ),
    );
  }
}
