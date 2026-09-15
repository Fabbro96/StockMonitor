import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Variazione numerica firmata con freccia direzionale.
///
/// È il modo canonico di mostrare guadagni e perdite nel linguaggio Registro:
/// il colore da solo non basta (deuteranopia), quindi la freccia e il segno
/// `+`/`−` accompagnano sempre il numero, in mono tabulare.
///
/// ```dart
/// AppDelta(value: 1.24, suffix: '%')   // ▲ +1,24 %
/// AppDelta(value: -0.85, suffix: '%')  // ▼ −0,85 %
/// ```
class AppDelta extends StatelessWidget {
  /// Crea una variazione firmata.
  const AppDelta({
    super.key,
    required this.value,
    this.suffix,
    this.precision = 2,
    this.size = 13,
    this.showArrow = true,
    this.colorOverride,
    this.semanticsLabel,
  });

  /// Valore della variazione; `null` o `0` rendono il testo neutro.
  final double? value;

  /// Suffisso accodato al numero (es. `%`, `€`).
  final String? suffix;

  /// Decimali mostrati.
  final int precision;

  /// Taglia del testo e della freccia.
  final double size;

  /// True = freccia direzionale prima del numero.
  final bool showArrow;

  /// Colore esplicito (default: colore semantico della variazione).
  final Color? colorOverride;

  /// Etichetta accessibile; se assente viene costruita dal valore.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final double? v = value;
    final bool up = (v ?? 0) > 0;
    final bool down = (v ?? 0) < 0;
    final Color color = colorOverride ?? t.deltaText(v);

    final String number = _format((v ?? 0).abs(), precision);
    final String signed = '${up ? '+' : (down ? '−' : '')}$number${suffix == null ? '' : ' $suffix'}';

    final Widget arrow = Icon(
      up ? Icons.arrow_drop_up : Icons.arrow_drop_down,
      size: size * 1.35,
      color: color,
    );

    return Semantics(
      label: semanticsLabel ?? 'Variazione $signed',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (showArrow && (up || down))
              Padding(
                padding: const EdgeInsets.only(right: 1),
                child: arrow,
              ),
            Flexible(
              child: Text(
                signed,
                style: AppText.deltaFor(t).copyWith(fontSize: size, color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Formattazione italiana: virgola decimale, nessun separatore migliaia
  /// (le variazioni sono numeri compatti).
  static String _format(double value, int precision) {
    if (!value.isFinite) return '—';
    return value.toStringAsFixed(precision).replaceAll('.', ',');
  }
}
