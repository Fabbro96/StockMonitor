import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Varianti di [SectionHeader].
enum SectionHeaderVariant {
  /// Titolo + sottotitolo (default).
  plain,

  /// Intestazione "ledger": overline sopra il titolo e riga di separazione
  /// sotto, per scandire le sezioni di una pagina lunga.
  rule,
}

/// Intestazione di sezione/pannello: icona, titolo, sottotitolo muted e un
/// trailing link o widget (es. `Tutti`, `Apri Radar`).
///
/// Nel linguaggio Registro il titolo non contiene più emoji: l'icona si passa
/// con [icon]. Con [variant] = [SectionHeaderVariant.rule] la sezione è
/// scandita da overline + riga, lo stile delle pagine lunghe.
class SectionHeader extends StatelessWidget {
  /// Crea un'intestazione di sezione.
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.trailingLabel,
    this.onTrailingTap,
    this.trailingIcon = Icons.arrow_forward,
    this.padding = const EdgeInsets.only(bottom: AppSpacing.s14),
    this.icon,
    this.overline,
    this.variant = SectionHeaderVariant.plain,
    this.dense = false,
  });

  /// Titolo (testo semplice, senza emoji: usare [icon]).
  final String title;

  /// Sottotitolo muted sotto il titolo.
  final String? subtitle;

  /// Widget a destra (ha precedenza su [trailingLabel]).
  final Widget? trailing;

  /// Testo del link a destra (es. `Tutti`).
  final String? trailingLabel;

  /// Callback del link a destra.
  final VoidCallback? onTrailingTap;

  /// Icona mostrata dopo [trailingLabel].
  final IconData trailingIcon;

  /// Padding esterno; default `only(bottom: 14)`.
  final EdgeInsetsGeometry padding;

  /// Icona Material a sinistra del titolo.
  final IconData? icon;

  /// Micro-etichetta maiuscola sopra il titolo (di norma con [variant] rule).
  final String? overline;

  /// Variante tipografica.
  final SectionHeaderVariant variant;

  /// True = titolo e spaziature ridotte.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;

    Widget? trailingWidget = trailing;
    if (trailingWidget == null && trailingLabel != null) {
      trailingWidget = _TrailingLink(
        label: trailingLabel!,
        icon: trailingIcon,
        onTap: onTrailingTap,
      );
    }

    final Widget titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (overline != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s4),
            child: Text(overline!, style: AppText.micro(context)),
          ),
        Row(
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: AppSizes.icon, color: t.textSecondary),
              const SizedBox(width: AppSpacing.s8),
            ],
            Flexible(
              child: Text(
                title,
                style: dense
                    ? AppText.cardTitle(context).copyWith(fontSize: 13.5)
                    : AppText.cardTitle(context),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s2),
            child: Text(subtitle!, style: AppText.caption(context)),
          ),
      ],
    );

    final Widget header = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(child: titleBlock),
        if (trailingWidget != null) ...<Widget>[
          const SizedBox(width: AppSpacing.s12),
          DefaultTextStyle.merge(
            style: TextStyle(
              color: t.primary,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              fontFamilyFallback: AppTokens.fontFallback,
            ),
            child: trailingWidget,
          ),
        ],
      ],
    );

    if (variant == SectionHeaderVariant.plain) {
      return Padding(padding: padding, child: header);
    }

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          header,
          const SizedBox(height: AppSpacing.s8),
          Container(height: AppSizes.rule, color: t.border),
        ],
      ),
    );
  }
}

class _TrailingLink extends StatefulWidget {
  const _TrailingLink({required this.label, required this.icon, this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  State<_TrailingLink> createState() => _TrailingLinkState();
}

class _TrailingLinkState extends State<_TrailingLink> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final Color color = _hovered || _focused ? t.primarySolidHover : t.primary;
    final Widget link = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(widget.label),
        const SizedBox(width: AppSpacing.s4),
        Icon(widget.icon, size: AppSizes.iconSm, color: color),
      ],
    );

    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(AppRadii.xs),
      onHover: (bool value) => setState(() => _hovered = value),
      onFocusChange: (bool value) => setState(() => _focused = value),
      hoverColor: Colors.transparent,
      focusColor: t.primaryGlow,
      child: Semantics(
        button: true,
        child: DefaultTextStyle.merge(
          style: TextStyle(color: color),
          child: link,
        ),
      ),
    );
  }
}
