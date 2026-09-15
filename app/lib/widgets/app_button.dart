import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Varianti colore di [AppButton].
enum AppButtonVariant {
  /// Accento pieno: azioni principali.
  primary,

  /// Bordo 1px su superficie: azioni secondarie.
  ghost,

  /// Testo senza bordo: azioni terziarie e link (hover `surfaceHover`).
  quiet,

  /// Verde pieno: conferme di guadagno.
  success,

  /// Ambra piena: attenzioni.
  warning,

  /// Rosso pieno per azioni distruttive.
  danger,
}

/// Taglie di [AppButton]: [lg], [md], [sm], [xs].
enum AppButtonSize { lg, md, sm, xs }

/// Bottone del design system: geometria squadrata (raggio 4), niente ombre,
/// anello di focus visibile da tastiera, spinner integrato, scala 0.98 alla
/// pressione.
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
      AppButtonSize.lg => const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
      AppButtonSize.md => const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      AppButtonSize.sm => const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      AppButtonSize.xs => const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    };
    final double fontSize = switch (widget.size) {
      AppButtonSize.lg => 13.5,
      AppButtonSize.md => 13,
      AppButtonSize.sm => 12.5,
      AppButtonSize.xs => 11.5,
    };
    final double minHeight = switch (widget.size) {
      AppButtonSize.lg => AppSizes.controlLg,
      AppButtonSize.md => AppSizes.control,
      AppButtonSize.sm => AppSizes.controlSm,
      AppButtonSize.xs => AppSizes.controlXs,
    };

    final _ButtonPalette palette = _paletteFor(t, widget.variant);
    final bool highlight = _hovered || _focused;
    final Color background = enabled
        ? (_pressed ? palette.pressedBackground : (highlight ? palette.hoverBackground : palette.background))
        : palette.disabledBackground(t);
    final Color foreground = enabled
        ? (highlight ? palette.hoverForeground : palette.foreground)
        : t.textMuted;
    final Color border = enabled
        ? (highlight ? palette.hoverBorder : palette.border)
        : t.borderSubtle;

    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (widget.loading)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
            ),
          )
        else if (widget.icon != null)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: IconTheme.merge(
              data: IconThemeData(color: foreground, size: AppSizes.iconSm),
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
      constraints: BoxConstraints(minHeight: minHeight),
      padding: padding,
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(AppRadii.input),
        boxShadow: _focused && enabled
            ? <BoxShadow>[
                BoxShadow(color: t.focusRing, blurRadius: 0, spreadRadius: 2),
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

/// Bottone quadrato con sola icona: topbar (tema, scorciatoie), sidebar
/// (logout), toast (chiudi). Default 32×32, bordo opzionale.
class AppIconButton extends StatefulWidget {
  /// Crea un bottone icona.
  const AppIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.semanticLabel,
    this.size = AppSizes.iconButton,
    this.iconSize = AppSizes.icon,
    this.bordered = false,
    this.danger = false,
    this.selected = false,
    this.backgroundColor,
    this.minTargetSize,
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

  /// True = bordo 1px visibile a riposo.
  final bool bordered;

  /// True = hover in rosso (azioni distruttive).
  final bool danger;

  /// True = stato selezionato (fondo `primaryGlow`, testo `primary`).
  final bool selected;

  /// Sfondo esplicito; default trasparente (o `surface` se [bordered]).
  final Color? backgroundColor;

  /// Lato minimo dell'area interattiva; con un valore maggiore di [size] il
  /// riquadro sensibile cresce senza ingrandire il bottone visibile (azioni in
  /// riga tabella: target ≥ [AppSizes.touchTarget] senza cambiare l'altezza
  /// della riga).
  final double? minTargetSize;

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
            : (_hovered || _focused)
                ? (widget.danger ? t.danger : t.primary)
                : t.textSecondary;
    final Color background = widget.backgroundColor ??
        (widget.selected
            ? t.primaryGlow
            : (_hovered && enabled ? t.surfaceHover : (widget.bordered ? t.surface : Colors.transparent)));
    final Color borderColor = widget.selected
        ? t.primary
        : (_hovered || _focused) && enabled
            ? (widget.danger ? t.danger : t.primary)
            : (widget.bordered ? t.border : Colors.transparent);

    // Il bottone visibile resta [size]; l'area sensibile può crescere fino a
    // [minTargetSize] senza toccare l'altezza della riga che lo ospita.
    final double target = (widget.minTargetSize ?? 0) > widget.size
        ? widget.minTargetSize!
        : widget.size;

    Widget button = SizedBox(
      width: target,
      height: target,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? widget.onPressed : null,
          canRequestFocus: enabled,
          onHover: (bool value) => setState(() => _hovered = value),
          onFocusChange: (bool value) => setState(() => _focused = value),
          borderRadius: BorderRadius.circular(AppRadii.control),
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          child: Center(
            child: AnimatedContainer(
              duration: AppMotion.effective(context, AppMotion.fast),
              curve: AppMotion.ease,
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: background,
                border: Border.all(color: borderColor),
                borderRadius: BorderRadius.circular(AppRadii.control),
                boxShadow: _focused && enabled
                    ? <BoxShadow>[
                        BoxShadow(color: t.focusRing, blurRadius: 0, spreadRadius: 2),
                      ]
                    : null,
              ),
              child: IconTheme.merge(
                data: IconThemeData(color: foreground, size: widget.iconSize),
                child: Center(child: widget.icon),
              ),
            ),
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
    required this.pressedBackground,
    required this.foreground,
    required this.hoverForeground,
    required this.border,
    required this.hoverBorder,
  });

  final Color background;
  final Color hoverBackground;
  final Color pressedBackground;
  final Color foreground;
  final Color hoverForeground;
  final Color border;
  final Color hoverBorder;

  /// Fondo dello stato disabilitato (neutro, mai "sbiadito" sull'accento).
  Color disabledBackground(AppTokens t) =>
      background == Colors.transparent ? Colors.transparent : t.surfaceActive;
}

_ButtonPalette _paletteFor(AppTokens t, AppButtonVariant variant) {
  switch (variant) {
    case AppButtonVariant.primary:
      return _ButtonPalette(
        background: t.primarySolid,
        hoverBackground: t.primarySolidHover,
        pressedBackground: t.primarySolidHover,
        foreground: t.onPrimarySolid,
        hoverForeground: t.onPrimarySolid,
        border: t.primarySolid,
        hoverBorder: t.primarySolidHover,
      );
    case AppButtonVariant.ghost:
      return _ButtonPalette(
        background: t.surface,
        hoverBackground: t.surfaceHover,
        pressedBackground: t.surfaceActive,
        foreground: t.textPrimary,
        hoverForeground: t.primary,
        border: t.border,
        hoverBorder: t.primary,
      );
    case AppButtonVariant.quiet:
      return _ButtonPalette(
        background: Colors.transparent,
        hoverBackground: t.surfaceHover,
        pressedBackground: t.surfaceActive,
        foreground: t.textSecondary,
        hoverForeground: t.primary,
        border: Colors.transparent,
        hoverBorder: Colors.transparent,
      );
    case AppButtonVariant.success:
      return _ButtonPalette(
        background: t.success,
        hoverBackground: _shift(t, t.success),
        pressedBackground: _shift(t, t.success, 0.14),
        foreground: t.onSuccessSolid,
        hoverForeground: t.onSuccessSolid,
        border: t.success,
        hoverBorder: _shift(t, t.success),
      );
    case AppButtonVariant.warning:
      return _ButtonPalette(
        background: t.warning,
        hoverBackground: _shift(t, t.warning),
        pressedBackground: _shift(t, t.warning, 0.14),
        foreground: t.onWarningSolid,
        hoverForeground: t.onWarningSolid,
        border: t.warning,
        hoverBorder: _shift(t, t.warning),
      );
    case AppButtonVariant.danger:
      return _ButtonPalette(
        background: t.danger,
        hoverBackground: _shift(t, t.danger),
        pressedBackground: _shift(t, t.danger, 0.14),
        foreground: t.onDangerSolid,
        hoverForeground: t.onDangerSolid,
        border: t.danger,
        hoverBorder: _shift(t, t.danger),
      );
  }
}

/// Schiarisce leggermente nel tema scuro, scurisce nel tema chiaro.
Color _shift(AppTokens t, Color base, [double amount = 0.08]) {
  return Color.alphaBlend(
    (t.isDark ? Colors.white : Colors.black).withValues(alpha: amount),
    base,
  );
}
