import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/models/user.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_button.dart';
import '../../widgets/toast.dart';
import 'settings_providers.dart';

/// Apre il dialog "Reimposta password" per [user] (azione admin).
Future<void> showResetPasswordDialog(BuildContext context, AuthUser user) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) => ResetPasswordDialog(user: user),
  );
}

/// Dialog admin di reset password: nuova password (min 8 caratteri) e conferma.
class ResetPasswordDialog extends ConsumerStatefulWidget {
  /// Crea il dialog per [user].
  const ResetPasswordDialog({super.key, required this.user});

  /// Utente di cui reimpostare la password.
  final AuthUser user;

  @override
  ConsumerState<ResetPasswordDialog> createState() =>
      _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends ConsumerState<ResetPasswordDialog> {
  final TextEditingController _passwordController = TextEditingController();

  bool _showPassword = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _error = 'Inserisci la nuova password');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = 'La password deve contenere almeno 8 caratteri');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(usersProvider.notifier)
          .resetPassword(widget.user.id, password);
      if (!mounted) return;
      showAppToast(
        context,
        message:
            'Password di "${widget.user.username}" reimpostata con successo!',
        type: AppToastType.success,
      );
      Navigator.of(context).pop();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error.message;
      });
      showAppToast(context, message: error.message, type: AppToastType.error);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Errore durante la reimpostazione della password';
      });
      showAppToast(
        context,
        message: 'Errore durante la reimpostazione della password',
        type: AppToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return AlertDialog(
      title: Text(
        'Reimposta password di ${widget.user.username}',
        style: AppText.modalTitle(context),
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'L\'utente potrà accedere con la nuova password.',
              style: AppText.caption(context),
            ),
            const SizedBox(height: AppSpacing.s12),
            Text(
              'Nuova Password (min. 8 car.)',
              style: AppText.formLabel(context),
            ),
            const SizedBox(height: AppSpacing.s6),
            TextField(
              controller: _passwordController,
              autofocus: true,
              obscureText: !_showPassword,
              autofillHints: const <String>[AutofillHints.newPassword],
              textInputAction: TextInputAction.done,
              onSubmitted: (String _) => _submit(),
              decoration: InputDecoration(
                hintText: '••••••••',
                errorText: _error,
                suffixIcon: IconButton(
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                  tooltip: _showPassword
                      ? 'Nascondi password'
                      : 'Mostra password',
                  icon: Icon(
                    _showPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 17,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              'L\'operazione non può essere annullata.',
              style: TextStyle(
                color: t.textMuted,
                fontSize: 11.8,
                height: 1.4,
                fontFamilyFallback: AppTokens.fontFallback,
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        AppButton(
          label: 'Annulla',
          variant: AppButtonVariant.ghost,
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: 'Reimposta',
          icon: const Icon(Icons.key_outlined),
          loading: _submitting,
          onPressed: _submit,
        ),
      ],
    );
  }
}
