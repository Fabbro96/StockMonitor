import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Varianti colore di [AppButton].
enum AppButtonVariant {
  /// Blu pieno: azioni principali (`.btn-primary`).
  primary,

  /// Superficie con bordo: azioni secondarie (`.btn-ghost`).
  ghost,

  /// Verde pieno (`.btn-success`).
  success,

  /// Ambra piena (`.btn-warning`).
  warning,

  /// Rosso pieno per azioni distruttive (estensione del DS).
  danger,
}

/// Taglie di [AppButton]: [md] `.btn`, [sm] `.btn-sm`, [xs] `.btn-xs`.
enum AppButtonSize { md, sm, xs }

/// Bottone del design system con varianti e taglie del CSS, stato disabled
/// neutro (non sbiadito), scala 0.98 alla pressione, spinner integrato.
///
/// Con [expand] occupa tutta la larghezza (es. bottone Accedi).
class AppButton extends StatefulWidget {
  /// Crea un bottone.
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.md,
    this.icon,
    this.loading = false,
    this.loadingLabel,
    this.expand = false,
    this.tooltip,
    this.semanticLabel,
  });

  /// Testo del bottone.
  final String label;

  /// Callback; `null` disabilita il bottone.
  final VoidCallback? onPressed;

  /// Variante colore.
  final AppButtonVariant variant;

  /// Taglia.
  final AppButtonSize size;

  /// Icona opzionale a sinistra del testo.
  final Widget? icon;

  /// True = spinner + [loadingLabel] (o [label]) e bottone disabilitato.
  final bool loading;

  /// Testo durante il caricamento (es. `Verifica in corso...`).
  final String? loadingLabel;

  /// True = larghezza piena.
  final bool expand;

  /// Tooltip opzionale.
  final String? tooltip;

  /// Etichetta per screen reader, se diversa dal testo visibile.
  final String? semanticLabel;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool enabled = widget.onPressed != null && !widget.loading;

    final EdgeInsets padding = switch (widget.size) {
      AppButtonSize.md => const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      AppButtonSize.sm => const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      AppButtonSize.xs => const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    };
    final double fontSize = switch (widget.size) {
      AppButtonSize.md => 13.8,
      AppButtonSize.sm => 12.5,
      AppButtonSize.xs => 11.8,
    };

    final _ButtonPalette palette = _paletteFor(t, widget.variant);
    final Color background = enabled
        ? (_hovered || _pressed ? palette.hoverBackground : palette.background)
        : t.surfaceActive;
    final Color foreground = enabled
        ? (_hovered ? palette.hoverForeground : palette.foreground)
        : t.textMuted;
    final Color border = enabled ? (_hovered ? palette.hoverBorder : palette.border) : t.border;

    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (widget.loading)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
            ),
          )
        else if (widget.icon != null)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: IconTheme.merge(
              data: IconThemeData(color: foreground, size: 15),
              child: widget.icon!,
            ),
          ),
        Flexible(
          child: Text(
            widget.loading ? (widget.loadingLabel ?? widget.label) : widget.label,
            style: AppText.button(context).copyWith(fontSize: fontSize, color: foreground),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    Widget button = AnimatedContainer(
      duration: AppMotion.effective(context, AppMotion.fast),
      curve: AppMotion.ease,
      padding: padding,
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(AppRadii.input),
        boxShadow: _focused && enabled
            ? <BoxShadow>[
                BoxShadow(color: t.primaryGlow, blurRadius: 0, spreadRadius: 2),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? widget.onPressed : null,
          canRequestFocus: enabled,
          onHover: (bool value) => setState(() => _hovered = value),
          onHighlightChanged: (bool value) => setState(() => _pressed = value),
          onFocusChange: (bool value) => setState(() => _focused = value),
          borderRadius: BorderRadius.circular(AppRadii.input),
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          child: content,
        ),
      ),
    );

    button = AnimatedScale(
      scale: _pressed && enabled ? 0.98 : 1,
      duration: AppMotion.effective(context, AppMotion.fast),
      curve: AppMotion.ease,
      child: button,
    );

    if (widget.expand) {
      button = SizedBox(width: double.infinity, child: button);
    }

    final String? tooltip = widget.tooltip;
    if (tooltip != null) {
      button = Tooltip(message: tooltip, child: button);
    }

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: button,
    );
  }
}

/// Bottone quadrato con sola icona (34×34 di default), bordo opzionale:
/// usato da topbar (tema), sidebar (logout), toast (chiudi).
class AppIconButton extends StatefulWidget {
  /// Crea un bottone icona.
  const AppIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.semanticLabel,
    this.size = 34,
    this.iconSize = 18,
    this.bordered = true,
    this.danger = false,
    this.selected = false,
    this.backgroundColor,
  });

  /// Icona (di norma un [Icon]).
  final Widget icon;

  /// Callback; `null` disabilita il bottone.
  final VoidCallback? onPressed;

  /// Tooltip e, se [semanticLabel] è null, etichetta accessibile.
  final String? tooltip;

  /// Etichetta per screen reader.
  final String? semanticLabel;

  /// Lato del bottone.
  final double size;

  /// Dimensione dell'icona.
  final double iconSize;

  /// True = bordo e raggio come `.icon-btn`/`.theme-toggle-btn`.
  final bool bordered;

  /// True = hover in rosso (`#btnLogout:hover`).
  final bool danger;

  /// True = stato selezionato (sfondo `primaryGlow`, testo `primary`).
  final bool selected;

  /// Sfondo esplicito; default trasparente (o `surface` se [bordered]).
  final Color? backgroundColor;

  @override
  State<AppIconButton> createState() => _AppIconButtonState();
}

class _AppIconButtonState extends State<AppIconButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool enabled = widget.onPressed != null;

    final Color foreground = !enabled
        ? t.textMuted
        : widget.selected
            ? t.primary
            : _hovered || _focused
                ? (widget.danger ? t.danger : t.primary)
                : t.textSecondary;
    final Color background = widget.backgroundColor ??
        (widget.selected ? t.primaryGlow : (widget.bordered ? t.surface : Colors.transparent));
    final Color borderColor = widget.selected
        ? t.primary
        : _hovered || _focused
            ? (widget.danger ? t.danger : t.primary)
            : (widget.bordered ? t.border : Colors.transparent);

    Widget button = AnimatedContainer(
      duration: AppMotion.effective(context, AppMotion.fast),
      curve: AppMotion.ease,
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: _hovered && !widget.selected && widget.backgroundColor == null
            ? t.surfaceHover
            : background,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(AppRadii.input),
        boxShadow: _focused && enabled
            ? <BoxShadow>[
                BoxShadow(color: t.primaryGlow, blurRadius: 0, spreadRadius: 2),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? widget.onPressed : null,
          canRequestFocus: enabled,
          onHover: (bool value) => setState(() => _hovered = value),
          onFocusChange: (bool value) => setState(() => _focused = value),
          borderRadius: BorderRadius.circular(AppRadii.input),
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          child: IconTheme.merge(
            data: IconThemeData(color: foreground, size: widget.iconSize),
            child: Center(child: widget.icon),
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }

    return Semantics(
      button: true,
      enabled: enabled,
      selected: widget.selected,
      label: widget.semanticLabel ?? widget.tooltip,
      child: button,
    );
  }
}

class _ButtonPalette {
  const _ButtonPalette({
    required this.background,
    required this.hoverBackground,
    required this.foreground,
    required this.hoverForeground,
    required this.border,
    required this.hoverBorder,
  });

  final Color background;
  final Color hoverBackground;
  final Color foreground;
  final Color hoverForeground;
  final Color border;
  final Color hoverBorder;
}

_ButtonPalette _paletteFor(AppTokens t, AppButtonVariant variant) {
  switch (variant) {
    case AppButtonVariant.primary:
      return _ButtonPalette(
        background: t.primarySolid,
        hoverBackground: t.primarySolidHover,
        foreground: t.onPrimarySolid,
        hoverForeground: t.onPrimarySolid,
        border: t.primarySolid,
        hoverBorder: t.primarySolidHover,
      );
    case AppButtonVariant.ghost:
      return _ButtonPalette(
        background: t.surface,
        hoverBackground: t.surfaceHover,
        foreground: t.textSecondary,
        hoverForeground: t.primary,
        border: t.border,
        hoverBorder: t.primary,
      );
    case AppButtonVariant.success:
      return _ButtonPalette(
        background: t.success,
        hoverBackground: _shift(t, t.success),
        foreground: t.onSuccessSolid,
        hoverForeground: t.onSuccessSolid,
        border: t.success,
        hoverBorder: _shift(t, t.success),
      );
    case AppButtonVariant.warning:
      return _ButtonPalette(
        background: t.warning,
        hoverBackground: _shift(t, t.warning),
        foreground: t.onWarningSolid,
        hoverForeground: t.onWarningSolid,
        border: t.warning,
        hoverBorder: _shift(t, t.warning),
      );
    case AppButtonVariant.danger:
      final Color foreground = t.brightness == Brightness.dark
          ? const Color(0xFF2A0A0D)
          : t.onPrimarySolid;
      return _ButtonPalette(
        background: t.danger,
        hoverBackground: _shift(t, t.danger),
        foreground: foreground,
        hoverForeground: foreground,
        border: t.danger,
        hoverBorder: _shift(t, t.danger),
      );
  }
}

/// Schiarisce leggermente nel tema scuro, scurisce nel tema chiaro.
Color _shift(AppTokens t, Color base) {
  return Color.alphaBlend(
    (t.brightness == Brightness.dark ? Colors.white : Colors.black).withValues(alpha: 0.08),
    base,
  );
}
