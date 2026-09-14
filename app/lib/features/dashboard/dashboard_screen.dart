import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/portfolio_api.dart';
import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/models/advice.dart';
import '../../core/models/portfolio.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/badges.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/page_content.dart';
import '../../widgets/section_header.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/ticker_flag.dart';
import '../../widgets/toast.dart';
import '../stock_detail/stock_detail_modal.dart';
import 'dashboard_providers.dart';
import 'widgets/heatmap_grid.dart';
import 'widgets/holdings_section.dart';
import 'widgets/market_status.dart';
import 'widgets/portfolio_chart.dart';
import 'widgets/price_flash.dart';
import 'widgets/responsive_wrap.dart';

/// Dashboard principale, parità con `index.html`/`dashboard.js`:
/// stat cards, metriche di rischio, andamento storico con benchmark, analisi
/// macro IA, heatmap e prime 6 posizioni.
///
/// Caricamento: le sezioni primarie arrivano da [dashboardProvider] con errori
/// per-sezione (il render precedente resta); risk e chart hanno provider
/// dedicati. Auto-refresh ogni 180s solo ad app visibile (lifecycle observer),
/// refresh silente senza chart/risk e senza toast.
class DashboardScreen extends ConsumerStatefulWidget {
  /// Crea la dashboard.
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with WidgetsBindingObserver {
  static const Duration _refreshInterval = Duration(seconds: 180);

  Timer? _refreshTimer;
  bool _refreshing = false;
  bool _seeding = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startAutoRefresh();
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted) return;
      // Timeframe persistito (shared_preferences, chiave `dashboard_timeframe`).
      unawaited(ref.read(chartTimeframeProvider.notifier).load());
    });
  }

  @override
  void dispose() {
    _stopAutoRefresh();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _startAutoRefresh();
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _stopAutoRefresh();
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(_refreshInterval, (Timer _) => unawaited(_silentRefresh()));
  }

  void _stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  Future<void> _silentRefresh() async {
    if (_refreshing || !mounted) return;
    _refreshing = true;
    try {
      await ref.read(dashboardProvider.notifier).silentRefresh();
    } finally {
      _refreshing = false;
    }
  }

  void _reload() {
    unawaited(ref.read(dashboardProvider.notifier).reload());
  }

  Future<void> _seedDemo() async {
    if (_seeding) return;
    setState(() => _seeding = true);
    try {
      final Map<String, dynamic> result = await ref.read(portfolioApiProvider).seedDemo();
      if (!mounted) return;
      final String? message = result['message']?.toString();
      showAppToast(
        context,
        message: (message == null || message.isEmpty)
            ? 'Demo caricata con successo!'
            : message,
        type: AppToastType.success,
      );
      _reload();
    } on ApiException catch (error) {
      if (mounted) {
        showAppToast(context, message: error.message, type: AppToastType.error);
      }
    } catch (_) {
      if (mounted) {
        showAppToast(
          context,
          message: 'Errore nel caricamento della demo',
          type: AppToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  void _openStock(String ticker) {
    showStockDetail(context, ticker, onChanged: _reload);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<DashboardState>>(dashboardProvider,
        (AsyncValue<DashboardState>? previous, AsyncValue<DashboardState> next) {
      final DashboardState? nextState = next.value;
      if (nextState == null || nextState.failedSections.isEmpty) return;
      if (nextState.lastLoadSilent) return;
      if (previous?.value?.loadCount == nextState.loadCount) return;
      if (!mounted) return;
      showAppToast(
        context,
        message:
            'Dati non aggiornati (${nextState.failedSections.join(', ')}). Riprova più tardi.',
        type: AppToastType.error,
      );
    });

    final AsyncValue<DashboardState> dashboard = ref.watch(dashboardProvider);
    final DashboardState? state = dashboard.value;
    final bool initialLoading = dashboard.isLoading && state == null;
    final AsyncValue<RiskMetrics> risk = ref.watch(dashboardRiskProvider);
    final ChartTimeframe timeframe = ref.watch(chartTimeframeProvider);
    final ChartBenchmark benchmark = ref.watch(chartBenchmarkProvider);
    final AsyncValue<DashboardChartData> chart = ref.watch(dashboardChartProvider);
    final bool compact = context.isCompact;

    return AppLoaderOverlay(
      loading: _seeding,
      child: PageContent(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Align(
              alignment: Alignment.centerRight,
              child: MarketStatusView(status: state?.marketStatus),
            ),
            const SizedBox(height: AppSpacing.s12),
            _statsGrid(state, initialLoading),
            const SizedBox(height: AppSpacing.s18),
            _riskCard(risk),
            const SizedBox(height: AppSpacing.s14),
            _mainRow(state, initialLoading, chart, timeframe, benchmark, compact),
            const SizedBox(height: AppSpacing.s14),
            _heatmapCard(state, initialLoading),
            const SizedBox(height: AppSpacing.s14),
            _holdingsCard(state, initialLoading),
          ],
        ),
      ),
    );
  }

  // --- Stat cards ---------------------------------------------------------

  Widget _statsGrid(DashboardState? state, bool loading) {
    final AppTokens t = context.tokens;
    final PortfolioSummary? summary = state?.summary;
    final bool failed = !loading && summary == null;
    final Holding? gainer = summary?.topGainer;

    // Flash del valore su refresh silente (come `flashPriceChange` del
    // frontend per i tre stat monetari).
    Widget flashValue(String text, {required double value, required bool rising, Color? color}) {
      return PriceFlash(
        value: value,
        rising: rising,
        child: Text(
          text,
          style: AppText.statValue(context).copyWith(color: color),
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    return ResponsiveWrap(
      minItemWidth: 200,
      mobileColumns: 2,
      gap: AppSpacing.s12,
      children: <Widget>[
        StatCard(
          label: '💰 Valore Portafoglio',
          tooltip:
              'Controvalore complessivo di tutte le azioni possedute ai prezzi correnti di mercato.',
          description: 'Capitale totale attualmente investito',
          valueWidget: loading
              ? const SkeletonValue()
              : (failed
                  ? null
                  : flashValue(
                      formatCurrency(summary?.totalValue ?? 0),
                      value: summary?.totalValue ?? 0,
                      rising: (summary?.dailyPnl ?? 0) >= 0,
                      color: t.primary,
                    )),
          value: failed ? 'Dati non disponibili' : formatCurrency(summary?.totalValue ?? 0),
          valueColor: t.primary,
        ),
        StatCard(
          label: '📅 P&L Giornaliero',
          tooltip:
              'Variazione monetaria e percentuale registrata oggi rispetto alla chiusura precedente.',
          description: 'Rendimento nella seduta odierna',
          valueWidget: loading
              ? const SkeletonValue()
              : (failed
                  ? null
                  : flashValue(
                      '${formatCurrency(summary?.dailyPnl ?? 0)} (${formatPercent(summary?.dailyPnlPercent ?? 0)})',
                      value: summary?.dailyPnl ?? 0,
                      rising: (summary?.dailyPnl ?? 0) >= 0,
                      color: (summary?.dailyPnl ?? 0) >= 0 ? t.successText : t.danger,
                    )),
          value: failed
              ? 'Dati non disponibili'
              : '${formatCurrency(summary?.dailyPnl ?? 0)} (${formatPercent(summary?.dailyPnlPercent ?? 0)})',
          valueColor: failed
              ? null
              : ((summary?.dailyPnl ?? 0) >= 0 ? t.successText : t.danger),
        ),
        StatCard(
          label: '📊 P&L Totale',
          tooltip:
              'Rendimento complessivo calcolato tra il prezzo medio di carico e il prezzo attuale.',
          description: 'Guadagno o perdita complessiva',
          valueWidget: loading
              ? const SkeletonValue()
              : (failed
                  ? null
                  : flashValue(
                      '${formatCurrency(summary?.totalPnl ?? 0)} (${formatPercent(summary?.totalPnlPercent ?? 0)})',
                      value: summary?.totalPnl ?? 0,
                      rising: (summary?.totalPnl ?? 0) >= 0,
                      color: (summary?.totalPnl ?? 0) >= 0 ? t.successText : t.danger,
                    )),
          value: failed
              ? 'Dati non disponibili'
              : '${formatCurrency(summary?.totalPnl ?? 0)} (${formatPercent(summary?.totalPnlPercent ?? 0)})',
          valueColor: failed
              ? null
              : ((summary?.totalPnl ?? 0) >= 0 ? t.successText : t.danger),
        ),
        StatCard(
          label: '💵 Dividendi Stimati',
          tooltip:
              'Stima del flusso cedolare passivo annuo lordo generato dalle posizioni in portafoglio.',
          description: summary == null
              ? 'Yield Stimato: --%'
              : 'Yield Stimato: ${summary.estimatedDividendYield.toStringAsFixed(2)}%',
          valueWidget: loading ? const SkeletonValue() : null,
          value: failed
              ? 'Dati non disponibili'
              : '${formatCurrency(summary?.estimatedAnnualDividends ?? 0)}/anno',
          valueColor: t.successText,
        ),
        StatCard(
          label: '🏆 Top Performer',
          tooltip:
              'Il titolo con il maggior guadagno percentuale complessivo nel tuo portafoglio.',
          smallValue: true,
          valueWidget: loading ? const SkeletonValue() : null,
          value: gainer == null ? '--' : '${gainer.ticker} (${formatPercent(gainer.pnlPercent)})',
          valueColor: t.successText,
          description: gainer != null
              ? 'P&L Netto: ${formatCurrency(gainer.pnlAbsolute)}'
              : (loading ? 'Miglior posizione' : 'Nessuna posizione in utile'),
        ),
      ],
    );
  }

  // --- Metriche di rischio ------------------------------------------------

  Widget _riskCard(AsyncValue<RiskMetrics> risk) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SectionHeader(
            title: '🛡️ Metriche di Rischio & Performance',
            subtitle: 'Analisi quantitativa del portafoglio (orizzonte 180 giorni)',
          ),
          _riskBody(risk),
        ],
      ),
    );
  }

  Widget _riskBody(AsyncValue<RiskMetrics> risk) {
    final RiskMetrics? metrics = risk.value;

    if (metrics == null && risk.isLoading) {
      return const ResponsiveWrap(
        minItemWidth: 150,
        mobileColumns: 2,
        children: <Widget>[
          SkeletonStat(),
          SkeletonStat(),
          SkeletonStat(),
          SkeletonStat(),
        ],
      );
    }
    if (metrics == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
          child: Text('Metriche non disponibili al momento.', style: AppText.caption(context)),
        ),
      );
    }
    if (_isEmptyRisk(metrics)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
          child: Text(
            "Metriche calcolate dopo l'inserimento di posizioni storiche.",
            textAlign: TextAlign.center,
            style: AppText.caption(context),
          ),
        ),
      );
    }

    final AppTokens t = context.tokens;
    return ResponsiveWrap(
      minItemWidth: 150,
      mobileColumns: 2,
      children: <Widget>[
        _RiskMetricCard(
          label: 'Max Drawdown',
          value: formatPercent(metrics.maxDrawdownPct),
          description: 'Picco-minimo',
          color: t.danger,
        ),
        _RiskMetricCard(
          label: 'Volatilità Annua',
          value: '${metrics.annualizedVolatilityPct.toStringAsFixed(1)}%',
          description: 'Deviazione std',
          color: t.primary,
        ),
        _RiskMetricCard(
          label: 'Sharpe Ratio',
          value: metrics.sharpeRatio.toStringAsFixed(2),
          description: 'Rendimento / Rischio',
          color: metrics.sharpeRatio >= 1 ? t.successText : t.primary,
        ),
        _RiskMetricCard(
          label: 'Beta Pesato',
          value: metrics.weightedBeta.toStringAsFixed(2),
          description: 'Sensibilità mercato',
          color: t.primary,
        ),
      ],
    );
  }

  bool _isEmptyRisk(RiskMetrics metrics) {
    return metrics.daysAnalyzed == 0 &&
        metrics.maxDrawdownPct == 0 &&
        metrics.annualizedVolatilityPct == 0 &&
        metrics.sharpeRatio == 0 &&
        metrics.weightedBeta == 0;
  }

  // --- Chart + analisi IA -------------------------------------------------

  Widget _mainRow(
    DashboardState? state,
    bool loading,
    AsyncValue<DashboardChartData> chart,
    ChartTimeframe timeframe,
    ChartBenchmark benchmark,
    bool compact,
  ) {
    final Widget chartCard = _chartCard(chart, timeframe, benchmark, compact);
    final Widget adviceCard = _adviceCard(state, loading);

    if (context.isNarrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          chartCard,
          const SizedBox(height: AppSpacing.s12),
          adviceCard,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(flex: 2, child: chartCard),
        const SizedBox(width: AppSpacing.s14),
        Expanded(child: adviceCard),
      ],
    );
  }

  Widget _chartCard(
    AsyncValue<DashboardChartData> chart,
    ChartTimeframe timeframe,
    ChartBenchmark benchmark,
    bool compact,
  ) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            title: '📈 Andamento Storico del Portafoglio',
            subtitle: 'Crescita % a confronto con gli indici di mercato',
            trailing: ChartTimeframeSelector(
              selected: timeframe,
              onSelected: (ChartTimeframe value) =>
                  unawaited(ref.read(chartTimeframeProvider.notifier).select(value)),
            ),
          ),
          ChartBenchmarkChips(
            selected: benchmark,
            onSelected: (ChartBenchmark value) =>
                ref.read(chartBenchmarkProvider.notifier).select(value),
          ),
          const SizedBox(height: AppSpacing.s12),
          PortfolioChart(
            data: chart.value,
            loading: chart.isLoading && chart.value == null,
            mode: benchmark,
            height: compact ? 260 : 340,
          ),
        ],
      ),
    );
  }

  Widget _adviceCard(DashboardState? state, bool loading) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            title: '🧠 Analisi Macro IA',
            subtitle: 'Sintesi strategica Gemini 3.7 Flash',
            trailingLabel: 'Tutti',
            onTrailingTap: () => context.go('/advice'),
          ),
          _adviceBody(state, loading),
        ],
      ),
    );
  }

  Widget _adviceBody(DashboardState? state, bool loading) {
    final List<Advice>? advices = state?.advices;

    if (advices == null) {
      if (loading) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s16),
          child: Center(
            child: Text('Caricamento analisi...', style: AppText.caption(context)),
          ),
        );
      }
      if (state?.failedSections.contains('consigli') ?? false) {
        return const EmptyState(message: 'Dati non disponibili.');
      }
      return const EmptyState(
        message: 'Nessuna analisi recente. Generane una nella sezione Consigli.',
      );
    }
    if (advices.isEmpty) {
      return const EmptyState(
        message: 'Nessuna analisi recente. Generane una nella sezione Consigli.',
      );
    }

    final List<Advice> visible = advices.take(2).toList();
    return Column(
      children: <Widget>[
        for (var i = 0; i < visible.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: AppSpacing.s12),
          _AdviceCard(advice: visible[i]),
        ],
      ],
    );
  }

  // --- Heatmap e posizioni ------------------------------------------------

  Widget _heatmapCard(DashboardState? state, bool loading) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            title: '🌐 Heatmap di Mercato & Titoli Monitorati',
            subtitle: 'Panoramica visiva istantanea dei movimenti di prezzo odierni',
            trailing: AppButton(
              label: 'Apri Radar Completo ➔',
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.sm,
              onPressed: () => context.go('/watchlist'),
            ),
          ),
          HeatmapGrid(
            items: state?.heatmap,
            loading: loading,
            failed: state?.failedSections.contains('heatmap') ?? false,
            onOpenStock: _openStock,
            onSeedDemo: _seedDemo,
          ),
        ],
      ),
    );
  }

  Widget _holdingsCard(DashboardState? state, bool loading) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            title: '💼 Posizioni in Portafoglio',
            subtitle:
                "Clicca su qualsiasi ticker per consultare la scheda tecnica e l'analisi IA",
            trailing: AppButton(
              label: 'Gestisci Portafoglio ➔',
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.sm,
              onPressed: () => context.go('/portfolio'),
            ),
          ),
          HoldingsSection(
            holdings: state?.holdings,
            loading: loading,
            failed: state?.failedSections.contains('portafoglio') ?? false,
            onOpenStock: _openStock,
            onAddHolding: () => context.go('/portfolio?add='),
            onSeeAll: () => context.go('/portfolio'),
            onSeedDemo: _seedDemo,
          ),
        ],
      ),
    );
  }
}

/// Card compatta delle metriche di rischio (`card-subtle p-3` del frontend).
class _RiskMetricCard extends StatelessWidget {
  const _RiskMetricCard({
    required this.label,
    required this.value,
    required this.description,
    required this.color,
  });

  final String label;
  final String value;
  final String description;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return AppCard(
      subtle: true,
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              color: t.textMuted,
              fontSize: 12.2,
              fontWeight: FontWeight.w400,
              fontFamilyFallback: AppTokens.fontFallback,
            ),
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(value, style: AppText.mono(context, size: 16.8, weight: FontWeight.w700, color: color)),
          const SizedBox(height: AppSpacing.s2),
          Text(description, style: AppText.caption(context).copyWith(fontSize: 10.9)),
        ],
      ),
    );
  }
}

/// Card di un'analisi macro (`card card-subtle p-3`): bandiera + titolo,
/// badge azione, `overview || strategy` clampata a 2 righe.
class _AdviceCard extends StatelessWidget {
  const _AdviceCard({required this.advice});

  final Advice advice;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final String market = (advice.market ?? '').toUpperCase();
    final String flag = market == 'IT'
        ? TickerFlags.italy
        : (market == 'EU' ? TickerFlags.europe : TickerFlags.unitedStates);
    final String action = (advice.action ?? 'HOLD').toUpperCase();
    final BadgeTone tone = action.contains('ACCUMULO') || action.contains('BUY')
        ? BadgeTone.success
        : (action.contains('PROFITTO') || action.contains('SELL')
            ? BadgeTone.danger
            : BadgeTone.warning);
    final String title = advice.title.isNotEmpty
        ? advice.title
        : (market == 'IT' ? 'Borsa Italiana' : 'Wall Street');
    final String description =
        advice.overview ?? advice.strategy ?? 'Nessuna descrizione disponibile.';

    return AppCard(
      subtle: true,
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Row(
                  children: <Widget>[
                    Text(flag, style: const TextStyle(fontSize: 13, height: 1.2)),
                    const SizedBox(width: AppSpacing.s6),
                    Flexible(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: t.primary,
                          fontSize: 13.1,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                          fontFamilyFallback: AppTokens.fontFallback,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              AppBadge(label: action, tone: tone),
            ],
          ),
          const SizedBox(height: AppSpacing.s6),
          Text(
            description,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 12.2,
              fontWeight: FontWeight.w400,
              height: 1.6,
              fontFamilyFallback: AppTokens.fontFallback,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
