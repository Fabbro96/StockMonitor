import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Card del design system: superficie, bordo 1px, raggio 10, padding responsive
/// (18 desktop / 14 sotto 640px). Come `.card` del CSS.
///
/// Varianti:
/// - [accent] → barra sinistra di 3px (`.card-accent`);
/// - [subtle] → sfondo `surfaceHover` (`.card-subtle`);
/// - [onTap] → card cliccabile con hover;
/// - [header] → intestazione con margine di 14px già applicato.
class AppCard extends StatelessWidget {
  /// Crea una card del design system.
  const AppCard({
    super.key,
    required this.child,
    this.header,
    this.padding,
    this.margin,
    this.accent = false,
    this.accentColor,
    this.subtle = false,
    this.onTap,
  });

  /// Contenuto della card.
  final Widget child;

  /// Intestazione opzionale (di norma un [AppCardHeader]) sopra il contenuto.
  final Widget? header;

  /// Padding interno; default `AppSpacing.cardPadding(width)`.
  final EdgeInsetsGeometry? padding;

  /// Margine esterno.
  final EdgeInsetsGeometry? margin;

  /// True = barra laterale sinistra di 3px (`.card-accent`).
  final bool accent;

  /// Colore della barra accent; default `primary`.
  final Color? accentColor;

  /// True = sfondo `surfaceHover` (`.card-subtle`).
  final bool subtle;

  /// Callback di tap: abilita hover e cursore.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final EdgeInsetsGeometry effectivePadding =
        padding ?? EdgeInsets.all(AppSpacing.cardPadding(context.windowWidth));

    Widget body = Padding(padding: effectivePadding, child: child);

    if (header != null) {
      body = Padding(
        padding: effectivePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            header!,
            const SizedBox(height: AppSpacing.s14),
            child,
          ],
        ),
      );
    }

    final BorderRadius radius = BorderRadius.circular(AppRadii.card);

    if (onTap != null) {
      body = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          hoverColor: t.surfaceHover,
          child: body,
        ),
      );
    }

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: subtle ? t.surfaceHover : t.surface,
        borderRadius: radius,
        border: Border.all(color: t.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: accent
          ? Stack(
              children: <Widget>[
                body,
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 3,
                  child: ColoredBox(color: accentColor ?? t.primary),
                ),
              ],
            )
          : body,
    );
  }
}

/// Intestazione di card: titolo (`.card-title`) e contenuto a destra opzionale.
class AppCardHeader extends StatelessWidget {
  /// Crea l'intestazione di una card.
  const AppCardHeader({super.key, required this.title, this.trailing});

  /// Titolo della card (testo semplice, emoji inclusi).
  final String title;

  /// Widget allineato a destra (link, badge, bottoni).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(child: Text(title, style: AppText.cardTitle(context))),
        if (trailing != null) ...<Widget>[
          const SizedBox(width: AppSpacing.s12),
          trailing!,
        ],
      ],
    );
  }
}
