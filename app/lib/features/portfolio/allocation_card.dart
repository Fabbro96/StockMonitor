import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/models/portfolio.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_key_value.dart';
import '../../widgets/app_progress_bar.dart';
import '../../widgets/app_segmented.dart';
import '../../widgets/section_header.dart';
import 'portfolio_edits.dart';
import 'portfolio_providers.dart';

/// Diametro della donut di allocazione (190×190).
const double _donutSize = 190;

/// Numero massimo di voci in legenda (oltre: nota "altri N titoli").
const int _maxLegendEntries = 7;

/// Card "Allocazione": toggle Titoli/Mercati, donut e legenda con barre di
/// ripartizione.
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
          SectionHeader(
            variant: SectionHeaderVariant.rule,
            icon: Icons.donut_large_outlined,
            overline: 'Portafoglio',
            title: 'Allocazione',
            subtitle: view == AllocationView.market
                ? 'Ripartizione del controvalore di mercato per mercato.'
                : 'Ripartizione del controvalore di mercato per titolo.',
            trailing: AppSegmented<AllocationView>(
              selected: view,
              dense: true,
              semanticsLabel: 'Vista allocazione',
              segments: const <AppSegment<AllocationView>>[
                AppSegment<AllocationView>(
                  value: AllocationView.stock,
                  label: 'Titoli',
                ),
                AppSegment<AllocationView>(
                  value: AllocationView.market,
                  label: 'Mercati',
                ),
              ],
              onSelected: (AllocationView value) => ref
                  .read(allocationViewProvider.notifier)
                  .select(value),
            ),
          ),
          const SizedBox(height: AppSpacing.s16),
          _AllocationBody(entries: entries, total: total),
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
      'IT': 'Italia',
      'US': 'Stati Uniti',
      'EU': 'Europa',
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

/// Corpo della card: donut e legenda, affiancati sopra i 620px.
class _AllocationBody extends StatelessWidget {
  const _AllocationBody({required this.entries, required this.total});

  final List<({String label, double value})> entries;
  final double total;

  @override
  Widget build(BuildContext context) {
    final Widget donut = _DonutArea(entries: entries, total: total);
    final Widget legend = _Legend(entries: entries, total: total);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Center(child: donut),
              const SizedBox(height: AppSpacing.s16),
              legend,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            donut,
            const SizedBox(width: AppSpacing.s20),
            Expanded(child: legend),
          ],
        );
      },
    );
  }
}

/// Donut (o anello tratteggiato quando non ci sono dati) con il totale al
/// centro.
class _DonutArea extends StatelessWidget {
  const _DonutArea({required this.entries, required this.total});

  final List<({String label, double value})> entries;
  final double total;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return SizedBox(
      width: _donutSize,
      height: _donutSize,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          if (total > 0)
            _Donut(entries: entries, total: total, colors: t.chart.pie)
          else
            CustomPaint(
              size: const Size.square(_donutSize),
              painter: _DashedRingPainter(color: t.borderStrong),
            ),
          IgnorePointer(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text('Totale', style: AppText.statLabel(context)),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  total > 0 ? formatCurrency(total) : '—',
                  style: AppText.mono(context, size: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Legenda: riga etichetta/percentuale con campione di tinta e barra.
class _Legend extends StatelessWidget {
  const _Legend({required this.entries, required this.total});

  final List<({String label, double value})> entries;
  final double total;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final int shown = math.min(entries.length, _maxLegendEntries);
    final int hidden = entries.length - shown;

    if (total <= 0) {
      return Text(
        'Nessun dato di allocazione disponibile.',
        style: AppText.caption(context),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < shown; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                AppKeyValue(
                  label: entries[i].label,
                  value: formatSharePercent(
                    entries[i].value / total * 100,
                  ),
                  divider: false,
                  dense: true,
                  trailing: _Swatch(
                    color: t.chart.pie[i % t.chart.pie.length],
                  ),
                ),
                const SizedBox(height: AppSpacing.s4),
                // Il valore resta leggibile anche in mono tabulare.
                AppProgressBar(
                  value: (entries[i].value / total).clamp(0, 1).toDouble(),
                  height: 5,
                  tone: AppProgressTone.neutral,
                  semanticsLabel:
                      '${entries[i].label}: '
                      '${formatSharePercent(entries[i].value / total * 100)}',
                ),
              ],
            ),
          ),
        if (hidden > 0)
          Text(
            'Altri $hidden titoli non mostrati.',
            style: AppText.caption(context),
          ),
      ],
    );
  }
}

/// Campione di tinta della legenda (quadrato 10×10, raggio 2).
class _Swatch extends StatelessWidget {
  const _Swatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadii.xs),
      ),
    );
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

/// Anello tratteggiato placeholder: stesso diametro e spessore della donut,
/// tinta `borderStrong`, tratteggio 3/5.
class _DashedRingPainter extends CustomPainter {
  const _DashedRingPainter({required this.color});

  final Color color;

  static const double _strokeWidth = 6;
  static const double _dash = 3;
  static const double _gap = 5;

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
    // Stesso punto di partenza della donut (-90°).
    for (double angle = -math.pi / 2; angle < 1.5 * math.pi; angle += step) {
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
