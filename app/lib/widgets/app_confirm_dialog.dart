import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'app_button.dart';

/// Dialog di conferma del design system: titolo, messaggio e due azioni
/// (`Annulla` + conferma). Con [destructive] la conferma è rossa.
///
/// Il widget non si chiude da solo: le azioni fanno `pop(false)` /
/// `pop(true)`, così resta usabile sia con [showAppConfirm] sia con un
/// `showDialog` diretto. Da tastiera `Esc` e il tap sul backdrop valgono
/// annullamento (`null` → `false`).
class AppConfirmDialog extends StatelessWidget {
  /// Crea un dialog di conferma.
  const AppConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmLabel = 'Conferma',
    this.cancelLabel = 'Annulla',
    this.destructive = false,
  });

  /// Titolo del dialog.
  final String title;

  /// Messaggio (testo semplice, una domanda chiara).
  final String message;

  /// Etichetta dell'azione di conferma.
  final String confirmLabel;

  /// Etichetta dell'azione di annullamento.
  final String cancelLabel;

  /// True = conferma in rosso (azione distruttiva).
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title, style: AppText.modalTitle(context)),
      content: Text(message, style: AppText.body(context)),
      actions: <Widget>[
        AppButton(
          label: cancelLabel,
          variant: AppButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: confirmLabel,
          variant: destructive
              ? AppButtonVariant.danger
              : AppButtonVariant.primary,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}

/// Mostra [AppConfirmDialog] e restituisce `true` solo quando l'utente
/// conferma; `false` per annullamento o chiusura con `Esc`/backdrop.
Future<bool> showAppConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Conferma',
  String cancelLabel = 'Annulla',
  bool destructive = false,
}) async {
  final bool? confirmed = await showDialog<bool>(
    context: context,
    barrierColor: context.tokens.scrim,
    builder: (BuildContext _) => AppConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      destructive: destructive,
    ),
  );
  return confirmed ?? false;
}
