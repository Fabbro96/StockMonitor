import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/models/portfolio.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_card.dart';
import '../../widgets/badges.dart';
import 'portfolio_edits.dart';
import 'portfolio_providers.dart';

/// Diametro della donut (`.chart` allocation, 190×190).
const double _donutSize = 190;

/// Card "Allocazione": toggle Titoli/Mercati, donut e legenda (max 7 voci).
///
/// La vista Titoli usa i valori live delle modifiche inline pendenti
/// ([edits]); la vista Mercati usa `summary.market_allocation`.
class AllocationCard extends ConsumerWidget {
  /// Crea la card di allocazione.
  const AllocationCard({super.key, required this.edits});

  /// Modifiche inline pendenti (id holding → bozza).
  final Map<int, HoldingEdit> edits;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppTokens t = context.tokens;
    final AllocationView view = ref.watch(allocationViewProvider);
    final List<Holding> holdings =
        ref.watch(portfolioProvider).value ?? const <Holding>[];
    final PortfolioSummary? summary = ref.watch(portfolioSummaryProvider).value;

    final List<({String label, double value})> entries =
        view == AllocationView.market
        ? _marketEntries(summary)
        : _stockEntries(holdings, edits);
    final double total = entries.fold<double>(
      0,
      (double sum, ({String label, double value}) item) =>
          sum + (item.value.isFinite ? item.value : 0),
    );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text('Allocazione', style: AppText.cardTitle(context)),
              ),
              AppPill(
                label: 'Titoli',
                selected: view == AllocationView.stock,
                onPressed: () => ref
                    .read(allocationViewProvider.notifier)
                    .select(AllocationView.stock),
              ),
              const SizedBox(width: AppSpacing.s6),
              AppPill(
                label: 'Mercati',
                selected: view == AllocationView.market,
                onPressed: () => ref
                    .read(allocationViewProvider.notifier)
                    .select(AllocationView.market),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s16),
          Center(
            child: SizedBox(
              width: _donutSize,
              height: _donutSize,
              child: total > 0
                  ? _Donut(entries: entries, total: total, colors: t.chart.pie)
                  : CustomPaint(
                      painter: _DashedRingPainter(color: t.borderStrong),
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.s16),
          if (total <= 0)
            Center(child: Text('Nessun dato', style: AppText.caption(context)))
          else
            Column(
              children: <Widget>[
                for (int i = 0; i < entries.length && i < 7; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.s8),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: t.chart.pie[i % t.chart.pie.length],
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s8),
                        Expanded(
                          child: Text(
                            entries[i].label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.mono(
                              context,
                              size: 12,
                              weight: FontWeight.w700,
                              color: t.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s6),
                        Text(
                          formatPercent(entries[i].value / total * 100),
                          style: AppText.mono(
                            context,
                            size: 12,
                            weight: FontWeight.w500,
                            color: t.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  List<({String label, double value})> _stockEntries(
    List<Holding> holdings,
    Map<int, HoldingEdit> edits,
  ) {
    return <({String label, double value})>[
      for (final Holding holding in holdings)
        if (_stockValue(holding, edits) > 0)
          (label: holding.ticker, value: _stockValue(holding, edits)),
    ];
  }

  double _stockValue(Holding holding, Map<int, HoldingEdit> edits) {
    final HoldingEdit edit = holdingEditOf(holding, edits);
    if (edit.changed) return edit.totalValue;
    return holding.totalValue > 0 ? holding.totalValue : edit.totalValue;
  }

  List<({String label, double value})> _marketEntries(
    PortfolioSummary? summary,
  ) {
    const Map<String, String> labels = <String, String>{
      'IT': '🇮🇹 Italia',
      'US': '🇺🇸 USA',
      'EU': '🇪🇺 Europa',
    };
    final Map<String, double> allocation =
        summary?.marketAllocation ?? const <String, double>{};
    return <({String label, double value})>[
      for (final MapEntry<String, double> entry in allocation.entries)
        if (entry.value > 0)
          (label: labels[entry.key] ?? entry.key, value: entry.value),
    ];
  }
}

class _Donut extends StatelessWidget {
  const _Donut({
    required this.entries,
    required this.total,
    required this.colors,
  });

  final List<({String label, double value})> entries;
  final double total;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    const double outerRadius = _donutSize / 2 - 8; // 87
    const double innerRadius = outerRadius * 0.58; // ~50.5
    return PieChart(
      PieChartData(
        sections: <PieChartSectionData>[
          for (int i = 0; i < entries.length; i++)
            PieChartSectionData(
              value: entries[i].value,
              color: colors[i % colors.length],
              radius: outerRadius - innerRadius,
              showTitle: false,
            ),
        ],
        centerSpaceRadius: innerRadius,
        sectionsSpace: 0,
        startDegreeOffset: -90,
        pieTouchData: PieTouchData(enabled: false),
      ),
      duration: Duration.zero,
    );
  }
}

/// Anello tratteggiato placeholder (`.range-bar-track` style, legacy canvas).
class _DashedRingPainter extends CustomPainter {
  const _DashedRingPainter({required this.color});

  final Color color;

  static const double _strokeWidth = 8;
  static const double _dash = 6;
  static const double _gap = 6;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = math.max(0, (size.shortestSide - _strokeWidth) / 2);
    if (radius <= 0) return;
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth;
    final double step = (_dash + _gap) / radius;
    for (double angle = 0; angle < 2 * math.pi; angle += step) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        angle,
        _dash / radius,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRingPainter oldDelegate) =>
      oldDelegate.color != color;
}
