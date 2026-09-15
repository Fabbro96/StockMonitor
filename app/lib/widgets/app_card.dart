import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Varianti di superficie di [AppCard].
enum AppCardVariant {
  /// Pannello standard: `surface` + bordo 1px (default).
  panel,

  /// Pannello incassato: `surfaceSunken`, per well e blocchi interni.
  inset,

  /// Pannello senza fondo né bordo: solo contenuto, per composizioni libere.
  flush,

  /// Pannello sollevato: `surfaceRaised` + ombra piccola, per contenuti in
  /// evidenza.
  raised,
}

/// Pannello del design system: bordo 1px, raggio 6, padding responsive
/// (16 desktop / 12 sotto 640px). Nel linguaggio Registro i pannelli sono
/// piatti: l'ombra è riservata ai livelli flottanti o a [AppCardVariant.raised].
///
/// Varianti:
/// - [accent] → striscia sinistra di 2px ([accentColor], default `primary`);
/// - [subtle] → fondo `surfaceSunken` (alias storico di [AppCardVariant.inset]);
/// - [onTap] → card cliccabile con hover e focus visibili;
/// - [header] → intestazione con margine di 12px già applicato.
class AppCard extends StatefulWidget {
  /// Crea un pannello del design system.
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
    this.variant = AppCardVariant.panel,
    this.bordered = true,
    this.dense = false,
  });

  /// Pannello trasparente senza bordo: il contenuto definisce la struttura.
  const AppCard.flush({
    super.key,
    required this.child,
    this.header,
    this.padding,
    this.margin,
    this.onTap,
    this.dense = false,
  })  : accent = false,
        accentColor = null,
        subtle = false,
        variant = AppCardVariant.flush,
        bordered = false;

  /// Pannello sollevato con ombra piccola.
  const AppCard.raised({
    super.key,
    required this.child,
    this.header,
    this.padding,
    this.margin,
    this.onTap,
    this.dense = false,
  })  : accent = false,
        accentColor = null,
        subtle = false,
        variant = AppCardVariant.raised,
        bordered = true;

  /// Contenuto della card.
  final Widget child;

  /// Intestazione opzionale (di norma un [AppCardHeader]) sopra il contenuto.
  final Widget? header;

  /// Padding interno; default `AppSpacing.cardPadding(width)`.
  final EdgeInsetsGeometry? padding;

  /// Margine esterno.
  final EdgeInsetsGeometry? margin;

  /// True = striscia laterale sinistra di 2px.
  final bool accent;

  /// Colore della striscia accent; default `primary`.
  final Color? accentColor;

  /// True = fondo `surfaceSunken` (alias di [AppCardVariant.inset]).
  final bool subtle;

  /// Callback di tap: abilita hover, focus e cursore.
  final VoidCallback? onTap;

  /// Variante di superficie.
  final AppCardVariant variant;

  /// True = bordo 1px attorno al pannello.
  final bool bordered;

  /// True = padding ridotto (12px fissi).
  final bool dense;

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool interactive = widget.onTap != null;
    final AppCardVariant variant = widget.subtle ? AppCardVariant.inset : widget.variant;

    final double pad = widget.dense ? AppSpacing.s12 : AppSpacing.cardPadding(context.windowWidth);
    final EdgeInsetsGeometry effectivePadding = widget.padding ?? EdgeInsets.all(pad);

    Widget body = Padding(padding: effectivePadding, child: widget.child);

    if (widget.header != null) {
      body = Padding(
        padding: effectivePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            widget.header!,
            const SizedBox(height: AppSpacing.s12),
            widget.child,
          ],
        ),
      );
    }

    final BorderRadius radius = BorderRadius.circular(AppRadii.card);

    if (interactive) {
      body = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: radius,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          onHover: (bool value) => setState(() => _hovered = value),
          onFocusChange: (bool value) => setState(() => _focused = value),
          child: body,
        ),
      );
    }

    final Color background = switch (variant) {
      AppCardVariant.panel => t.surface,
      AppCardVariant.inset => t.surfaceSunken,
      AppCardVariant.flush => Colors.transparent,
      AppCardVariant.raised => t.surfaceRaised,
    };

    final Color borderColor = switch (variant) {
      AppCardVariant.flush => Colors.transparent,
      _ when _focused => t.primary,
      _ when interactive && _hovered => t.borderStrong,
      _ => widget.bordered ? t.border : Colors.transparent,
    };

    return AnimatedContainer(
      duration: AppMotion.effective(context, AppMotion.fast),
      curve: AppMotion.ease,
      margin: widget.margin,
      decoration: BoxDecoration(
        color: interactive && _hovered && variant == AppCardVariant.panel
            ? t.surfaceHover
            : background,
        borderRadius: radius,
        border: Border.all(color: borderColor),
        boxShadow: _shadowFor(t, variant, interactive),
      ),
      clipBehavior: Clip.antiAlias,
      child: widget.accent
          ? Stack(
              children: <Widget>[
                body,
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: AppSizes.accentStrip,
                  child: ColoredBox(color: widget.accentColor ?? t.primary),
                ),
              ],
            )
          : body,
    );
  }

  List<BoxShadow>? _shadowFor(AppTokens t, AppCardVariant variant, bool interactive) {
    if (variant == AppCardVariant.raised) return t.shadowSm;
    if (interactive && _hovered) return t.shadowSm;
    return null;
  }
}

/// Intestazione di pannello: icona opzionale, titolo (`.card-title`),
/// sottotitolo muted e contenuto a destra opzionale.
class AppCardHeader extends StatelessWidget {
  /// Crea l'intestazione di un pannello.
  const AppCardHeader({
    super.key,
    required this.title,
    this.trailing,
    this.icon,
    this.subtitle,
    this.dense = false,
  });

  /// Titolo della card (testo semplice, senza emoji: usare [icon]).
  final String title;

  /// Widget allineato a destra (link, badge, bottoni).
  final Widget? trailing;

  /// Icona Material a sinistra del titolo (sostituisce le emoji di sezione).
  final IconData? icon;

  /// Sottotitolo muted sotto il titolo.
  final String? subtitle;

  /// True = nasconde il sottotitolo (intestazioni compatte).
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;

    final Widget titleRow = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: AppSizes.icon, color: t.textSecondary),
          const SizedBox(width: AppSpacing.s8),
        ],
        Expanded(
          child: Text(
            title,
            style: AppText.cardTitle(context),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null) ...<Widget>[
          const SizedBox(width: AppSpacing.s12),
          trailing!,
        ],
      ],
    );

    if (subtitle == null) return titleRow;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        titleRow,
        if (!dense)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s2),
            child: Text(subtitle!, style: AppText.caption(context)),
          ),
      ],
    );
  }
}
