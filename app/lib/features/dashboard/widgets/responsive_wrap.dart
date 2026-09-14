import 'package:flutter/material.dart';

import '../../../theme/tokens.dart';

/// Griglia responsive in stile `.stat-grid`/`.risk-grid`/`.heatmap-grid`:
/// auto-fit con larghezza minima per item, oppure numero di colonne fisso
/// sotto i 640px (dove il CSS passa a 2 colonne o a tile più larghe).
///
/// Gli item occupano sempre tutta la larghezza disponibile divisa per il
/// numero di colonne, come `1fr` del CSS (l'ultima riga non viene stirata).
class ResponsiveWrap extends StatelessWidget {
  /// Crea la griglia.
  const ResponsiveWrap({
    super.key,
    required this.children,
    required this.minItemWidth,
    this.mobileMinItemWidth,
    this.mobileColumns,
    this.gap = 10,
    this.mobileGap,
  });

  /// Contenuto della griglia.
  final List<Widget> children;

  /// Larghezza minima di un item sopra i 640px.
  final double minItemWidth;

  /// Larghezza minima sotto i 640px; default [minItemWidth].
  final double? mobileMinItemWidth;

  /// Se valorizzato, sotto i 640px usa questo numero di colonne (es. 2 per
  /// `.stat-grid`/`.risk-grid`); altrimenti continua l'auto-fit.
  final int? mobileColumns;

  /// Gap tra item sopra i 640px.
  final double gap;

  /// Gap tra item sotto i 640px; default [gap].
  final double? mobileGap;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compact = context.isCompact;
        final double effectiveGap = compact ? (mobileGap ?? gap) : gap;
        final double minWidth =
            compact ? (mobileMinItemWidth ?? minItemWidth) : minItemWidth;

        int columns = ((constraints.maxWidth + effectiveGap) /
                (minWidth + effectiveGap))
            .floor();
        if (compact && mobileColumns != null) columns = mobileColumns!;
        columns = columns.clamp(1, children.length);

        final double itemWidth =
            (constraints.maxWidth - effectiveGap * (columns - 1)) / columns;

        return Wrap(
          spacing: effectiveGap,
          runSpacing: effectiveGap,
          children: <Widget>[
            for (final Widget child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}
