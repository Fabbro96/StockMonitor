import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Barra del range 52 settimane (`.range-bar-*`): track 6px, riempimento a
/// gradiente danger→warning→success al 55%, pin 4×12 nella posizione corrente.
///
/// [positionPercent] è la posizione già calcolata (0–100, fuori range viene
/// clampata). I label [lowLabel]/[highLabel] sono tipicamente i prezzi min/max
/// formattati; [showPosition] mostra anche `Posizione: N%`.
///
/// Per partire da prezzi grezzi usare [RangeBar.fromValues].
class RangeBar extends StatelessWidget {
  /// Crea una barra range con posizione percentuale esplicita.
  const RangeBar({
    super.key,
    required this.positionPercent,
    this.lowLabel,
    this.highLabel,
    this.showPosition = false,
    this.minWidth = 140,
  });

  /// Crea una barra range calcolando posizione e label dai valori.
  factory RangeBar.fromValues({
    Key? key,
    required double low,
    required double high,
    required double current,
    String Function(double value)? formatValue,
    bool showPosition = false,
    double minWidth = 140,
  }) {
    final double range = high - low;
    final double percent = range <= 0 ? 50 : ((current - low) / range * 100).clamp(0, 100).toDouble();
    final String Function(double) format = formatValue ?? (double value) => value.toStringAsFixed(2);
    return RangeBar(
      key: key,
      positionPercent: percent,
      lowLabel: format(low),
      highLabel: format(high),
      showPosition: showPosition,
      minWidth: minWidth,
    );
  }

  /// Posizione del pin in percentuale (0–100).
  final double positionPercent;

  /// Etichetta del minimo (sotto la barra, a sinistra).
  final String? lowLabel;

  /// Etichetta del massimo (sotto la barra, a destra).
  final String? highLabel;

  /// True = mostra la riga `Posizione: N%`.
  final bool showPosition;

  /// Larghezza minima del componente.
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final double percent = positionPercent.clamp(0, 100).toDouble();
    final bool hasLabels = lowLabel != null || highLabel != null;

    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: minWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            height: 14,
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double width = constraints.maxWidth;
                final double pinLeft = (width * percent / 100 - 2).clamp(0, width - 4).toDouble();
                return Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Positioned(
                      top: 4,
                      left: 0,
                      right: 0,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: t.surfaceHover,
                            border: Border.all(color: t.border),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: percent / 100,
                              heightFactor: 1,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: <Color>[t.danger, t.warning, t.success],
                                  ),
                                ),
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 1,
                      left: pinLeft,
                      child: Container(
                        width: 4,
                        height: 12,
                        decoration: BoxDecoration(
                          color: t.textPrimary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (hasLabels)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  if (lowLabel != null)
                    Flexible(
                      child: Text(
                        lowLabel!,
                        style: AppText.mono(context, size: 11.2, weight: FontWeight.w500, color: t.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  else
                    const SizedBox.shrink(),
                  if (highLabel != null)
                    Flexible(
                      child: Text(
                        highLabel!,
                        textAlign: TextAlign.right,
                        style: AppText.mono(context, size: 11.2, weight: FontWeight.w500, color: t.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  else
                    const SizedBox.shrink(),
                ],
              ),
            ),
          if (showPosition)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s4),
              child: Text(
                'Posizione: ${percent.round()}%',
                style: AppText.caption(context),
              ),
            ),
        ],
      ),
    );
  }
}
