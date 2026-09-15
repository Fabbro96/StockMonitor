import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Tinte disponibili per [AppBadge].
enum BadgeTone {
  /// Verde: buy, guadagno, successo.
  success,

  /// Rosso: sell, perdita, errore.
  danger,

  /// Ambra: hold, alert, rischio.
  warning,

  /// Ciano informativo: mercati non italiani, dati ausiliari.
  cyan,

  /// Accento: stato informativo neutro.
  primary,

  /// Viola: admin.
  purple,

  /// Neutro: superfici e testi secondari.
  neutral,
}

/// Tag di stato del design system: geometria squadrata (raggio 3), mono
/// maiuscolo, 11px/600. Le tinte semantiche descrivono solo il significato del
/// dato, mai la marca.
///
/// Costruttori rapidi: [AppBadge.buy], [AppBadge.sell], [AppBadge.hold],
/// [AppBadge.cyan], [AppBadge.primary], [AppBadge.admin], più la factory
/// [AppBadge.trade] per le stringhe di lato (`BUY`/`SELL`/`HOLD`).
class AppBadge extends StatelessWidget {
  /// Crea un badge generico.
  const AppBadge({
    super.key,
    required this.label,
    this.tone = BadgeTone.neutral,
    this.icon,
    this.tooltip,
  });

  /// Badge verde `BUY`.
  const AppBadge.buy({super.key, this.icon, this.tooltip})
      : label = 'BUY',
        tone = BadgeTone.success;

  /// Badge rosso `SELL`.
  const AppBadge.sell({super.key, this.icon, this.tooltip})
      : label = 'SELL',
        tone = BadgeTone.danger;

  /// Badge ambra `HOLD`.
  const AppBadge.hold({super.key, this.icon, this.tooltip})
      : label = 'HOLD',
        tone = BadgeTone.warning;

  /// Badge ciano, di norma per mercati non italiani.
  const AppBadge.cyan({super.key, required this.label, this.icon, this.tooltip})
      : tone = BadgeTone.cyan;

  /// Badge di accento.
  const AppBadge.primary({super.key, required this.label, this.icon, this.tooltip})
      : tone = BadgeTone.primary;

  /// Badge viola admin.
  const AppBadge.admin({super.key, required this.label, this.icon, this.tooltip})
      : tone = BadgeTone.purple;

  /// Testo del badge.
  final String label;

  /// Tinta.
  final BadgeTone tone;

  /// Icona opzionale a sinistra (Material, non emoji).
  final Widget? icon;

  /// Tooltip opzionale.
  final String? tooltip;

  /// Badge per un lato di trade: `BUY` → verde, `SELL` → rosso, altro → ambra.
  factory AppBadge.trade(String side) {
    return switch (side.toUpperCase()) {
      'BUY' => const AppBadge.buy(),
      'SELL' => const AppBadge.sell(),
      _ => const AppBadge.hold(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final (Color background, Color border, Color foreground) = switch (tone) {
      BadgeTone.success => (t.successBg, t.successBorder, t.successText),
      BadgeTone.danger => (t.dangerBg, t.dangerBorder, t.danger),
      BadgeTone.warning => (t.warningBg, t.warningBorder, t.warning),
      BadgeTone.cyan => (t.primaryGlow, t.primary, t.cyan),
      BadgeTone.primary => (t.primaryGlow, t.primary, t.primary),
      BadgeTone.purple => (t.purpleBg, t.purple, t.purple),
      BadgeTone.neutral => (t.surfaceSunken, t.border, t.textSecondary),
    };

    final int labelLines = '\n'.allMatches(label).length + 1;

    Widget badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(AppRadii.tag),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            IconTheme.merge(
              data: IconThemeData(color: foreground, size: 11),
              child: icon!,
            ),
            const SizedBox(width: AppSpacing.s4),
          ],
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                height: 1.35,
                fontFamilyFallback: AppTokens.fontFallback,
              ),
              maxLines: labelLines,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

    if (tooltip != null) {
      badge = Tooltip(message: tooltip!, child: badge);
    }
    return badge;
  }
}

/// Chip selezionabile (filtri, timeframe, benchmark): bordo 1px, raggio 3,
/// 12.5px/500. Selezionata = fondo `primaryGlow` + bordo e testo d'accento.
/// Con [squared] = false usa il raggio pill per i contatori.
class AppPill extends StatefulWidget {
  /// Crea un chip.
  const AppPill({
    super.key,
    required this.label,
    this.selected = false,
    this.onPressed,
    this.icon,
    this.tooltip,
    this.squared = true,
  });

  /// Testo del chip.
  final String label;

  /// True = stato attivo.
  final bool selected;

  /// Callback di tap; `null` rende il chip non interattivo.
  final VoidCallback? onPressed;

  /// Icona opzionale a sinistra (Material, non emoji).
  final Widget? icon;

  /// Tooltip opzionale.
  final String? tooltip;

  /// True = raggio squadrato (3), false = raggio pill (999).
  final bool squared;

  @override
  State<AppPill> createState() => _AppPillState();
}

class _AppPillState extends State<AppPill> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool enabled = widget.onPressed != null;
    final BorderRadius radius =
        BorderRadius.circular(widget.squared ? AppRadii.tag : AppRadii.pill);

    final Color background = widget.selected
        ? t.primaryGlow
        : (_hovered && enabled ? t.surfaceHover : t.surface);
    final Color border = widget.selected || _focused
        ? t.primary
        : (_hovered && enabled ? t.borderStrong : t.border);
    final Color foreground = widget.selected
        ? t.primary
        : (_hovered || _focused ? t.textPrimary : t.textSecondary);

    Widget pill = AnimatedContainer(
      duration: AppMotion.effective(context, AppMotion.fast),
      curve: AppMotion.ease,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
        borderRadius: radius,
        boxShadow: _focused && enabled
            ? <BoxShadow>[
                BoxShadow(color: t.focusRing, blurRadius: 0, spreadRadius: 2),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onPressed,
          canRequestFocus: enabled,
          onHover: (bool value) => setState(() => _hovered = value),
          onFocusChange: (bool value) => setState(() => _focused = value),
          borderRadius: radius,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (widget.icon != null) ...<Widget>[
                IconTheme.merge(
                  data: IconThemeData(color: foreground, size: AppSizes.iconXs),
                  child: widget.icon!,
                ),
                const SizedBox(width: AppSpacing.s6),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 12.5,
                    fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w500,
                    height: 1.3,
                    fontFamilyFallback: AppTokens.fontFallback,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      pill = Tooltip(message: widget.tooltip!, child: pill);
    }
    return Semantics(
      button: enabled,
      selected: widget.selected,
      child: pill,
    );
  }
}

/// Badge tastiera: monocromo, bordo 1px, raggio 2, font mono 10.5px.
class AppKbd extends StatelessWidget {
  /// Crea un badge tastiera.
  const AppKbd(this.label, {super.key});

  /// Testo del tasto (es. `Ctrl K`).
  final String label;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: t.surfaceSunken,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(AppRadii.xs),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: t.textMuted,
          fontSize: 10.5,
          fontWeight: FontWeight.w500,
          height: 1.5,
          fontFamily: AppTokens.monoFontFamily,
          fontFamilyFallback: AppTokens.monoFontFallback,
        ),
      ),
    );
  }
}

/// Pallino di stato: verde = aperto, rosso = chiuso, grigio = sconosciuto.
/// Sempre accompagnato da un'etichetta accessibile.
class AppStatusDot extends StatelessWidget {
  /// Crea un pallino di stato.
  const AppStatusDot({super.key, required this.open, this.size = 7, this.statusLabel});

  /// True = aperto, false = chiuso, null = stato sconosciuto.
  final bool? open;

  /// Diametro del pallino.
  final double size;

  /// Etichetta accessibile opzionale.
  final String? statusLabel;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final Color color = switch (open) {
      true => t.success,
      false => t.danger,
      null => t.textMuted,
    };
    return Semantics(
      label: statusLabel,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(color: color.withValues(alpha: 0.28), blurRadius: 0, spreadRadius: 3),
          ],
        ),
      ),
    );
  }
}
