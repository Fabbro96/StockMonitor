import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Intestazione di sezione/card: titolo (`.card-title`), sottotitolo muted e
/// un trailing link o widget (es. `Tutti ➔`, `Apri Radar Completo ➔`).
///
/// Il margine inferiore di default (14px) coincide con `.card-header`.
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
  });

  /// Titolo (emoji inclusi, es. `🛡️ Metriche di Rischio & Performance`).
  final String title;

  /// Sottotitolo muted sotto il titolo.
  final String? subtitle;

  /// Widget a destra (ha precedenza su [trailingLabel]).
  final Widget? trailing;

  /// Testo del link a destra (es. `Tutti ➔`).
  final String? trailingLabel;

  /// Callback del link a destra.
  final VoidCallback? onTrailingTap;

  /// Icona mostrata dopo [trailingLabel].
  final IconData trailingIcon;

  /// Padding esterno; default `only(bottom: 14)`.
  final EdgeInsetsGeometry padding;

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

    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(title, style: AppText.cardTitle(context)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.s2),
                    child: Text(subtitle!, style: AppText.caption(context)),
                  ),
              ],
            ),
          ),
          if (trailingWidget != null) ...<Widget>[
            const SizedBox(width: AppSpacing.s12),
            DefaultTextStyle.merge(
              style: TextStyle(
                color: t.primary,
                fontSize: 13.1,
                fontWeight: FontWeight.w600,
                fontFamilyFallback: AppTokens.fontFallback,
              ),
              child: trailingWidget,
            ),
          ],
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

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final Widget link = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(widget.label),
        const SizedBox(width: AppSpacing.s4),
        Icon(
          widget.icon,
          size: 13,
          color: _hovered ? t.primarySolidHover : t.primary,
        ),
      ],
    );

    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(AppRadii.small),
      onHover: (bool value) => setState(() => _hovered = value),
      hoverColor: Colors.transparent,
      focusColor: context.tokens.primaryGlow,
      child: Semantics(
        button: true,
        child: DefaultTextStyle.merge(
          style: TextStyle(color: _hovered ? t.primarySolidHover : t.primary),
          child: link,
        ),
      ),
    );
  }
}
