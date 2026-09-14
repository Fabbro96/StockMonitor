import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/app_button.dart';
import '../widgets/badges.dart';

/// Mostra il dialog delle scorciatoie da tastiera
/// (`⌨️ Scorciatoie da Tastiera`).
///
/// Si chiude con `esc`, tap sul backdrop, la X o il bottone `Ho capito`.
/// Sotto 640px compare come bottom-sheet (radius 12 in alto), come i modali
/// del frontend.
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
        ? const BorderRadius.vertical(top: Radius.circular(AppRadii.modal))
        : BorderRadius.circular(AppRadii.card);

    return Semantics(
      namesRoute: true,
      label: '⌨️ Scorciatoie da Tastiera',
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
              constraints: const BoxConstraints(maxWidth: 560),
              child: Container(
                decoration: BoxDecoration(
                  color: t.surface,
                  border: Border.all(color: t.border),
                  borderRadius: radius,
                  boxShadow: t.shadowLg,
                ),
                clipBehavior: Clip.antiAlias,
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _header(context, t),
                    const SizedBox(height: AppSpacing.s16),
                    Text(
                      'Naviga e gestisci il tuo portafoglio ad alta velocità '
                      'con questi comandi globali:',
                      style: AppText.caption(context),
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    _ShortcutRow(
                      action: 'Apri Command Palette / Cerca',
                      keys: <Widget>[
                        const AppKbd('Ctrl'),
                        _separator(t, ' + '),
                        const AppKbd('K'),
                        _separator(t, ' / '),
                        const AppKbd('/'),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    const _ShortcutRow(
                      action: 'Apri questa Guida',
                      keys: <Widget>[AppKbd('?')],
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    const _ShortcutRow(
                      action: 'Chiudi Finestre e Modal',
                      keys: <Widget>[AppKbd('Esc')],
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
          Expanded(
            child: Text(
              '⌨️ Scorciatoie da Tastiera',
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
            bordered: false,
            danger: true,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  Widget _separator(AppTokens t, String text) {
    return Text(
      text,
      style: TextStyle(
        color: t.textMuted,
        fontSize: 11.8,
        height: 1.4,
        fontFamily: AppTokens.monoFontFamily,
        fontFamilyFallback: AppTokens.monoFontFallback,
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.action, required this.keys});

  final String action;
  final List<Widget> keys;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: t.surfaceHover,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(AppRadii.input),
      ),
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
            spacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: keys,
          ),
        ],
      ),
    );
  }
}
