import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/formatters.dart';
import '../../../core/models/dashboard.dart';
import '../../../core/models/portfolio.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/badges.dart';
import '../../../widgets/skeleton.dart';
import '../dashboard_providers.dart';

/// Selettore timeframe `7G/30G/90G/1A` (`.timeframe-group`): contenitore su
/// `surfaceHover` con segmento attivo su `surface` + testo primary.
class ChartTimeframeSelector extends StatelessWidget {
  /// Crea il selettore.
  const ChartTimeframeSelector({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  /// Timeframe attivo.
  final ChartTimeframe selected;

  /// Callback di selezione (persistenza a carico del chiamante).
  final ValueChanged<ChartTimeframe> onSelected;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: t.surfaceHover,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(AppRadii.input),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final ChartTimeframe timeframe in ChartTimeframe.values)
            _TimeframeButton(
              label: timeframe.label,
              selected: timeframe == selected,
              onPressed: () => onSelected(timeframe),
            ),
        ],
      ),
    );
  }
}

class _TimeframeButton extends StatefulWidget {
  const _TimeframeButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  State<_TimeframeButton> createState() => _TimeframeButtonState();
}

class _TimeframeButtonState extends State<_TimeframeButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool selected = widget.selected;
    final Color background = selected
        ? (t.brightness == Brightness.dark ? t.surfaceActive : t.surface)
        : Colors.transparent;
    final Color foreground =
        selected ? t.primary : (_hovered ? t.textPrimary : t.textSecondary);

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onPressed,
          onHover: (bool value) => setState(() => _hovered = value),
          borderRadius: BorderRadius.circular(AppRadii.small),
          hoverColor: Colors.transparent,
          focusColor: t.primaryGlow,
          child: AnimatedContainer(
            duration: AppMotion.effective(context, AppMotion.fast),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(AppRadii.small),
              boxShadow: selected ? t.shadowSm : null,
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                color: foreground,
                fontSize: 12.2,
                fontWeight: FontWeight.w600,
                height: 1.3,
                fontFamilyFallback: AppTokens.fontFallback,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Chip benchmark (`Solo Portafoglio` / `🇺🇸 S&P 500` / `🇮🇹 FTSE MIB` /
/// `Entrambi`) con swatch del colore della linea, come `.bench-chip`.
class ChartBenchmarkChips extends StatelessWidget {
  /// Crea i chip.
  const ChartBenchmarkChips({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  /// Benchmark attivo.
  final ChartBenchmark selected;

  /// Callback di selezione.
  final ValueChanged<ChartBenchmark> onSelected;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.s6,
      runSpacing: AppSpacing.s6,
      children: <Widget>[
        Text(
          'Benchmark:',
          style: TextStyle(
            color: t.textMuted,
            fontSize: 12.2,
            fontWeight: FontWeight.w400,
            fontFamilyFallback: AppTokens.fontFallback,
          ),
        ),
        for (final ChartBenchmark mode in ChartBenchmark.values)
          AppPill(
            label: mode.label,
            selected: mode == selected,
            icon: _Swatch(mode),
            onPressed: () => onSelected(mode),
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.mode);

  final ChartBenchmark mode;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final AppChartPalette chart = t.chart;
    final Decoration decoration = switch (mode) {
      ChartBenchmark.portfolio => BoxDecoration(color: t.primary, shape: BoxShape.circle),
      ChartBenchmark.sp500 => BoxDecoration(color: chart.benchmarkSp, shape: BoxShape.circle),
      ChartBenchmark.ftseMib => BoxDecoration(color: chart.benchmarkMib, shape: BoxShape.circle),
      ChartBenchmark.both => BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: <Color>[chart.benchmarkSp, chart.benchmarkMib],
          ),
        ),
    };
    return Container(width: 8, height: 8, decoration: decoration);
  }
}

/// Grafico andamento del portafoglio: area (default) oppure vista crescita %
/// con linee benchmark. Niente candele: il backend restituisce solo
/// `{date,value}` e sintetizzarle era un bug noto del vecchio frontend.
///
/// Con [loading] senza dati mostra uno skeleton; senza punti (o in errore al
/// primo load) mostra l'overlay `Nessun dato storico disponibile per il
/// periodo selezionato.`. Se un benchmark è richiesto ma i dati normalizzati
/// non sono disponibili (fetch fallita o vuota) resta la vista assoluta e
/// compare la nota `Benchmark non disponibili`. I colori arrivano da
/// [AppChartPalette].
class PortfolioChart extends StatelessWidget {
  /// Crea il grafico.
  const PortfolioChart({
    super.key,
    required this.data,
    required this.loading,
    required this.mode,
    required this.height,
  });

  /// Dati correnti; `null` = mai caricati.
  final DashboardChartData? data;

  /// True mentre il primo caricamento è in corso (skeleton).
  final bool loading;

  /// Benchmark attivo.
  final ChartBenchmark mode;

  /// Altezza dell'area grafico (340 desktop / 260 mobile).
  final double height;

  @override
  Widget build(BuildContext context) {
    if (loading && data == null) {
      return SkeletonBox(width: double.infinity, height: height, radius: AppRadii.input);
    }

    final _ChartSeries series = _buildSeries(data, mode);
    if (series.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s16),
            child: Text(
              'Nessun dato storico disponibile per il periodo selezionato.',
              textAlign: TextAlign.center,
              style: AppText.caption(context).copyWith(fontSize: 13.6),
            ),
          ),
        ),
      );
    }

    // Benchmark richiesto ma dati non disponibili (fetch fallita o vuota):
    // il grafico resta in vista assoluta e lo segnaliamo con una nota discreta,
    // senza toast d'errore.
    final bool benchmarkUnavailable =
        mode != ChartBenchmark.portfolio && !series.growth && series.main.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(height: height, child: LineChart(_buildChartData(context, series))),
        if (benchmarkUnavailable)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s6),
            child: Text(
              'Benchmark non disponibili',
              textAlign: TextAlign.right,
              style: AppText.caption(context),
            ),
          ),
      ],
    );
  }
}

class _ChartSeries {
  const _ChartSeries({
    required this.main,
    required this.sp,
    required this.mib,
    required this.growth,
    required this.hasDates,
  });

  final List<FlSpot> main;
  final List<FlSpot> sp;
  final List<FlSpot> mib;
  final bool growth;
  final bool hasDates;

  bool get isEmpty => main.isEmpty && sp.isEmpty && mib.isEmpty;
}

_ChartSeries _buildSeries(DashboardChartData? data, ChartBenchmark mode) {
  const _ChartSeries empty = _ChartSeries(
    main: <FlSpot>[],
    sp: <FlSpot>[],
    mib: <FlSpot>[],
    growth: false,
    hasDates: false,
  );
  if (data == null) return empty;

  final BenchmarksResult? benchmarks = data.benchmarks;
  final List<PricePoint> performance = data.performance.data;
  final List<GrowthPoint> growthPoints = benchmarks?.portfolio ?? const <GrowthPoint>[];
  // Come il frontend: senza dati portfolio normalizzati si resta sulla vista
  // assoluta (niente benchmark su scale diverse).
  final bool growth = mode != ChartBenchmark.portfolio && growthPoints.isNotEmpty;

  final List<FlSpot> main = growth
      ? _spots<GrowthPoint>(growthPoints, (GrowthPoint p) => p.date, (GrowthPoint p) => p.growthPct)
      : _spots<PricePoint>(performance, (PricePoint p) => p.date, (PricePoint p) => p.value);
  final bool hasDates = growth
      ? growthPoints.every((GrowthPoint p) => p.date != null)
      : performance.every((PricePoint p) => p.date != null);

  final bool showSp = growth && (mode == ChartBenchmark.sp500 || mode == ChartBenchmark.both);
  final bool showMib = growth && (mode == ChartBenchmark.ftseMib || mode == ChartBenchmark.both);

  return _ChartSeries(
    main: main,
    sp: showSp
        ? _spots<GrowthPoint>(
            benchmarks?.benchmarks['^GSPC']?.data ?? const <GrowthPoint>[],
            (GrowthPoint p) => p.date,
            (GrowthPoint p) => p.growthPct,
          )
        : const <FlSpot>[],
    mib: showMib
        ? _spots<GrowthPoint>(
            benchmarks?.benchmarks['FTSEMIB.MI']?.data ?? const <GrowthPoint>[],
            (GrowthPoint p) => p.date,
            (GrowthPoint p) => p.growthPct,
          )
        : const <FlSpot>[],
    growth: growth,
    hasDates: hasDates && main.isNotEmpty,
  );
}

List<FlSpot> _spots<T>(
  List<T> points,
  DateTime? Function(T) dateOf,
  double Function(T) valueOf,
) {
  final bool allDates = points.isNotEmpty && points.every((T p) => dateOf(p) != null);
  return <FlSpot>[
    for (var i = 0; i < points.length; i++)
      FlSpot(
        allDates ? dateOf(points[i])!.millisecondsSinceEpoch.toDouble() : i.toDouble(),
        valueOf(points[i]),
      ),
  ];
}

LineChartData _buildChartData(BuildContext context, _ChartSeries series) {
  final AppTokens t = context.tokens;
  final AppChartPalette chart = t.chart;

  final List<FlSpot> all = <FlSpot>[...series.main, ...series.sp, ...series.mib];
  final double minX = all.map((FlSpot s) => s.x).reduce(math.min);
  final double maxX = all.map((FlSpot s) => s.x).reduce(math.max);
  final double minY = all.map((FlSpot s) => s.y).reduce(math.min);
  final double maxY = all.map((FlSpot s) => s.y).reduce(math.max);
  final double rangeY = (maxY - minY).abs();
  final double padY = rangeY < 1e-9 ? (maxY.abs() * 0.05 + 1) : rangeY * 0.08;
  final double yInterval = _niceInterval(rangeY + padY * 2);
  final double xRange = maxX - minX;
  final double xInterval = xRange > 0 ? xRange / 3 : 0;
  final bool dateLabels = series.hasDates && xInterval > 0;
  // Con un anno di storico le etichette mensili restano leggibili.
  final bool monthly = xRange > 120 * Duration.millisecondsPerDay;

  TextStyle axisStyle() => TextStyle(
        color: chart.text,
        fontSize: 10.9,
        fontWeight: FontWeight.w400,
        fontFamilyFallback: AppTokens.fontFallback,
      );

  return LineChartData(
    minX: minX,
    maxX: maxX,
    minY: minY - padY,
    maxY: maxY + padY,
    lineBarsData: <LineChartBarData>[
      LineChartBarData(
        spots: series.main,
        color: chart.line,
        barWidth: 2,
        isCurved: false,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(
          show: !series.growth && series.main.isNotEmpty,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[chart.top, chart.bottom],
          ),
        ),
      ),
      if (series.sp.isNotEmpty)
        LineChartBarData(
          spots: series.sp,
          color: chart.benchmarkSp,
          barWidth: 2,
          dotData: const FlDotData(show: false),
        ),
      if (series.mib.isNotEmpty)
        LineChartBarData(
          spots: series.mib,
          color: chart.benchmarkMib,
          barWidth: 2,
          dotData: const FlDotData(show: false),
        ),
    ],
    titlesData: FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: dateLabels,
          reservedSize: 26,
          interval: dateLabels ? xInterval : null,
          minIncluded: false,
          getTitlesWidget: (double value, TitleMeta meta) {
            final DateTime date = DateTime.fromMillisecondsSinceEpoch(value.round());
            return SideTitleWidget(
              meta: meta,
              space: 6,
              child: Text(
                DateFormat(monthly ? 'MM/yy' : 'dd/MM').format(date),
                style: axisStyle(),
              ),
            );
          },
        ),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 54,
          interval: yInterval,
          getTitlesWidget: (double value, TitleMeta meta) {
            final String label = series.growth
                ? '${value.toStringAsFixed(1)}%'
                : (value.abs() < 1e-9 ? '0' : formatCompactNumber(value));
            return SideTitleWidget(
              meta: meta,
              space: 6,
              child: Text(label, style: axisStyle()),
            );
          },
        ),
      ),
    ),
    gridData: FlGridData(
      show: true,
      drawVerticalLine: dateLabels,
      horizontalInterval: yInterval,
      verticalInterval: dateLabels ? xInterval : null,
      getDrawingHorizontalLine: (double value) => FlLine(color: chart.grid, strokeWidth: 1),
      getDrawingVerticalLine: (double value) => FlLine(color: chart.grid, strokeWidth: 1),
    ),
    borderData: FlBorderData(show: false),
    lineTouchData: LineTouchData(
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (LineBarSpot spot) => t.surface,
        tooltipBorder: BorderSide(color: t.border),
        tooltipBorderRadius: BorderRadius.circular(AppRadii.input),
        tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        getTooltipItems: (List<LineBarSpot> spots) => <LineTooltipItem>[
          for (final LineBarSpot spot in spots)
            LineTooltipItem(
              _tooltipText(series, spot),
              AppText.mono(
                context,
                size: 11.5,
                weight: FontWeight.w600,
                color: _lineColor(chart, spot.barIndex),
              ),
            ),
        ],
      ),
    ),
  );
}

String _tooltipText(_ChartSeries series, LineBarSpot spot) {
  const List<String> labels = <String>['Portafoglio', 'S&P 500', 'FTSE MIB'];
  final String label = spot.barIndex < labels.length ? labels[spot.barIndex] : 'Serie';
  final String value = series.growth ? formatPercent(spot.y) : formatCurrency(spot.y);
  if (!series.hasDates) return '$label: $value';
  final DateTime date = DateTime.fromMillisecondsSinceEpoch(spot.x.round());
  return '$label: $value\n${formatDate(date)}';
}

Color _lineColor(AppChartPalette chart, int barIndex) {
  return switch (barIndex) {
    1 => chart.benchmarkSp,
    2 => chart.benchmarkMib,
    _ => chart.line,
  };
}

/// Passo "bello" (1/2/5 × 10^n) per le tacche dell'asse Y.
double _niceInterval(double range) {
  if (range <= 0) return 1;
  final double rough = range / 4;
  final double magnitude = math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
  final double residual = rough / magnitude;
  final double step = residual >= 5 ? 5 : (residual >= 2 ? 2 : 1);
  return step * magnitude;
}
