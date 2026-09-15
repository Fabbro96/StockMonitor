import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'app_button.dart';

/// Pannello d'errore incassato del design system: fondo `dangerBg`, bordo
/// `dangerBorder`, icona `error_outline`, messaggio e azione `Riprova`
/// fantasma opzionale.
///
/// È lo stato di una sezione che fallisce senza un render precedente da
/// mantenere: la sezione resta al suo posto e si può ritentare senza ricaricare
/// la pagina. Il messaggio è breve, senza dettagli tecnici; quando compare
/// viene annunciato dagli screen reader (live region).
class AppErrorPanel extends StatelessWidget {
  /// Crea il pannello d'errore.
  const AppErrorPanel({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Riprova',
  });

  /// Messaggio mostrato (breve, senza dettagli tecnici).
  final String message;

  /// Callback dell'azione di ritentativo; `null` nasconde il bottone.
  final VoidCallback? onRetry;

  /// Etichetta dell'azione di ritentativo.
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s12,
          vertical: AppSpacing.s10,
        ),
        decoration: BoxDecoration(
          color: t.dangerBg,
          border: Border.all(color: t.dangerBorder),
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.error_outline, size: AppSizes.icon, color: t.danger),
            const SizedBox(width: AppSpacing.s8),
            Expanded(child: Text(message, style: AppText.caption(context))),
            if (onRetry != null) ...<Widget>[
              const SizedBox(width: AppSpacing.s10),
              AppButton(
                label: retryLabel,
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.sm,
                icon: const Icon(Icons.refresh),
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
