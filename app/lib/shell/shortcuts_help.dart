import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/app_button.dart';
import '../widgets/badges.dart';

/// Mostra il dialog delle scorciatoie da tastiera
/// (`Scorciatoie da Tastiera`).
///
/// Pannello in stile registro: intestazione con icona, elenco a righe nude
/// separate da hairline e tasti in [AppKbd]. Si chiude con `esc`, tap sul
/// backdrop, la X o il bottone `Ho capito`. Sotto 640px compare come
/// bottom-sheet con raggio 10 in alto.
Future<void> showShortcutsHelp(BuildContext context) {
  final AppTokens t = context.tokens;
  final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: t.scrim,
    barrierLabel: 'Chiudi scorciatoie da tastiera',
    transitionDuration: reduceMotion ? Duration.zero : AppMotion.overlay,
    pageBuilder: (
      BuildContext dialogContext,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
    ) => const _ShortcutsHelpDialog(),
    transitionBuilder:
        (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
          Widget child,
        ) {
          if (reduceMotion) return child;
          final Animation<double> curved = CurvedAnimation(
            parent: animation,
            curve: AppMotion.ease,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.02),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
  );
}

class _ShortcutsHelpDialog extends StatelessWidget {
  const _ShortcutsHelpDialog();

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool compact = context.isCompact;

    final BorderRadius radius = compact
        ? const BorderRadius.vertical(top: Radius.circular(AppRadii.sheet))
        : BorderRadius.circular(AppRadii.sheet);

    return Semantics(
      namesRoute: true,
      label: 'Scorciatoie da Tastiera',
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.of(context).maybePop(),
        },
        child: Align(
          alignment: compact ? Alignment.bottomCenter : Alignment.center,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Container(
                decoration: BoxDecoration(
                  color: t.surfaceRaised,
                  border: Border.all(color: t.border),
                  borderRadius: radius,
                  boxShadow: t.shadowLg,
                ),
                clipBehavior: Clip.antiAlias,
                // `Material` non solo per l'inchiostro: senza di esso i testi
                // di un dialog fuori dallo Scaffold ereditano lo stile di
                // fallback (mono, decorazioni di debug) invece del tema.
                child: Material(
                  type: MaterialType.transparency,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _header(context, t),
                        const SizedBox(height: AppSpacing.s14),
                        Text(
                          'Naviga e gestisci il tuo portafoglio ad alta velocità '
                          'con questi comandi globali:',
                          style: AppText.caption(context),
                        ),
                        const SizedBox(height: AppSpacing.s14),
                        const _ShortcutRow(
                          action: 'Apri Command Palette / Cerca',
                          keys: <Widget>[
                            AppKbd('Ctrl'),
                            AppKbd('K'),
                            AppKbd('/'),
                          ],
                        ),
                        const _ShortcutRow(
                          action: 'Apri questa Guida',
                          keys: <Widget>[AppKbd('?')],
                        ),
                        const _ShortcutRow(
                          action: 'Chiudi Finestre e Modal',
                          keys: <Widget>[AppKbd('Esc')],
                          divider: false,
                        ),
                        const SizedBox(height: AppSpacing.s16),
                        Align(
                          alignment: Alignment.centerRight,
                          child: AppButton(
                            label: 'Ho capito',
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, AppTokens t) {
    return Container(
      padding: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.keyboard_outlined,
            size: AppSizes.iconLg,
            color: t.textSecondary,
          ),
          const SizedBox(width: AppSpacing.s8),
          Expanded(
            child: Text(
              'Scorciatoie da Tastiera',
              style: AppText.modalTitle(context),
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          AppIconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Chiudi',
            semanticLabel: 'Chiudi',
            size: 30,
            iconSize: 17,
            danger: true,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

/// Riga del registro scorciatoie: azione a sinistra, tasti a destra,
/// separata dalla successiva da una hairline.
class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({
    required this.action,
    required this.keys,
    this.divider = true,
  });

  final String action;
  final List<Widget> keys;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: divider
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: t.borderSubtle)),
            )
          : null,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              action,
              style: AppText.small(context)
                  .copyWith(fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: AppSpacing.s10),
          Wrap(
            spacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: keys,
          ),
        ],
      ),
    );
  }
}
