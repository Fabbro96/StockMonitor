import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Riga etichetta/valore del linguaggio Registro: micro-etichetta a sinistra,
/// valore mono tabulare a destra, riga di separazione opzionale.
///
/// È il mattone delle schede di dettaglio (posizione, titolo, impostazioni):
/// ```dart
/// AppKeyValue(label: 'Prezzo medio', value: '42,18 €', mono: true)
/// ```
class AppKeyValue extends StatelessWidget {
  /// Crea una riga etichetta/valore.
  const AppKeyValue({
    super.key,
    required this.label,
    this.value,
    this.valueWidget,
    this.icon,
    this.trailing,
    this.dense = false,
    this.mono = true,
    this.divider = true,
    this.labelWidth,
    this.valueColor,
  });

  /// Etichetta (mostrata maiuscola con tracking).
  final String label;

  /// Valore testuale.
  final String? value;

  /// Valore personalizzato; ha precedenza su [value].
  final Widget? valueWidget;

  /// Icona Material opzionale prima dell'etichetta.
  final IconData? icon;

  /// Contenuto extra dopo il valore (badge, icona di stato).
  final Widget? trailing;

  /// True = spaziature ridotte.
  final bool dense;

  /// True = valore in mono tabulare (numeri).
  final bool mono;

  /// True = riga di separazione sotto la voce.
  final bool divider;

  /// Larghezza fissa dell'etichetta; `null` = flessibile.
  final double? labelWidth;

  /// Colore del valore (es. verde/rosso di profit).
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;

    final Widget labelWidget = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: AppSizes.iconXs, color: t.textFaint),
          const SizedBox(width: AppSpacing.s6),
        ],
        Flexible(child: Text(label.toUpperCase(), style: AppText.microFor(t), overflow: TextOverflow.ellipsis)),
      ],
    );

    final Widget valueWidget2 = valueWidget ??
        Text(
          value ?? '—',
          textAlign: TextAlign.right,
          overflow: TextOverflow.ellipsis,
          style: (mono ? AppText.deltaFor(t) : AppText.smallFor(t)).copyWith(color: valueColor),
        );

    return Container(
      padding: EdgeInsets.symmetric(vertical: dense ? 5 : 7),
      decoration: divider
          ? BoxDecoration(border: Border(bottom: BorderSide(color: t.borderSubtle)))
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          if (labelWidth != null)
            SizedBox(width: labelWidth, child: labelWidget)
          else
            Expanded(child: labelWidget),
          const SizedBox(width: AppSpacing.s12),
          Flexible(child: valueWidget2),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: AppSpacing.s8),
            trailing!,
          ],
        ],
      ),
    );
  }
}
