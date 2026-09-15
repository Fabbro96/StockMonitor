import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Barra del range 52 settimane: track 5px su `surfaceSunken`, riempimento a
/// gradiente danger→warning→success, pin 3×11 nella posizione corrente.
///
/// [positionPercent] è la posizione già calcolata (0–100, fuori range viene
/// clampata). I label [lowLabel]/[highLabel] sono tipicamente i prezzi min/max
/// formattati; [showPosition] mostra anche `Posizione: N%`.
///
/// Per posizioni già calcolate usare direttamente il costruttore.
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
            height: 13,
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double width = constraints.maxWidth;
                final double pinLeft = (width * percent / 100 - 1.5).clamp(0, width - 3).toDouble();
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
                          height: 5,
                          decoration: BoxDecoration(
                            color: t.surfaceSunken,
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
                        width: 3,
                        height: 11,
                        decoration: BoxDecoration(
                          color: t.textPrimary,
                          border: Border.all(color: t.surface),
                          borderRadius: BorderRadius.circular(1.5),
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
                        style: AppText.mono(context, size: 11, weight: FontWeight.w500, color: t.textMuted),
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
                        style: AppText.mono(context, size: 11, weight: FontWeight.w500, color: t.textMuted),
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
