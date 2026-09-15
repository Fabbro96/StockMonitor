import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/portfolio_api.dart';
import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/models/advice.dart';
import '../../core/models/portfolio.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_error_panel.dart';
import '../../widgets/app_market_tag.dart';
import '../../widgets/app_segmented.dart';
import '../../widgets/badges.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/page_content.dart';
import '../../widgets/section_header.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/stat_card.dart';
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
/// striscia KPI, andamento storico con benchmark, analisi macro IA, metriche
/// di rischio compatte, heatmap e prime 6 posizioni.
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

  void _retryChart(ChartTimeframe timeframe) {
    ref.invalidate(performanceSeriesProvider(timeframe.days));
    ref.invalidate(benchmarksSeriesProvider(timeframe.days));
    ref.invalidate(dashboardChartProvider);
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
            _statusRow(state, initialLoading),
            const SizedBox(height: AppSpacing.s12),
            _statsStrip(state, initialLoading),
            const SizedBox(height: AppSpacing.s18),
            _mainRow(state, initialLoading, chart, timeframe, benchmark, compact),
            const SizedBox(height: AppSpacing.s14),
            _riskStrip(risk),
            const SizedBox(height: AppSpacing.s14),
            _heatmapCard(state, initialLoading),
            const SizedBox(height: AppSpacing.s14),
            _holdingsCard(state, initialLoading),
          ],
        ),
      ),
    );
  }

  // --- Riga di stato (aggiornamento + sessioni) ---------------------------

  Widget _statusRow(DashboardState? state, bool loading) {
    final AppTokens t = context.tokens;
    final DateTime? updated = state?.lastUpdated;
    final String label = updated != null
        ? 'Aggiornato alle ${DateFormat('HH:mm').format(updated)}'
        : (loading ? 'Aggiornamento in corso…' : 'In attesa del primo aggiornamento');
    final Widget caption =
        Text(label, style: AppText.caption(context).copyWith(color: t.textMuted));
    final Widget status = MarketStatusView(status: state?.marketStatus);

    // Su mobile le due informazioni vanno su righe separate: gli orari delle
    // sessioni non devono troncare.
    if (context.isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          caption,
          const SizedBox(height: AppSpacing.s6),
          status,
        ],
      );
    }

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.s12,
      runSpacing: AppSpacing.s6,
      children: <Widget>[caption, status],
    );
  }

  // --- Striscia KPI -------------------------------------------------------

  Widget _statsStrip(DashboardState? state, bool loading) {
    final AppTokens t = context.tokens;
    final bool compact = context.isCompact;
    final PortfolioSummary? summary = state?.summary;

    // Sezione fallita senza un render precedente: pannello d'errore incassato.
    if (!loading && summary == null) {
      return AppErrorPanel(
        message: 'Riepilogo del portafoglio non disponibile.',
        onRetry: _reload,
      );
    }

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
      minItemWidth: 220,
      mobileColumns: 2,
      gap: AppSpacing.s12,
      children: <Widget>[
        StatCard(
          label: 'Valore portafoglio',
          icon: const Icon(Icons.account_balance_wallet_outlined),
          tooltip:
              'Controvalore complessivo di tutte le azioni possedute ai prezzi correnti di mercato.',
          description: 'Capitale investito',
          valueWidget: loading
              ? const SkeletonValue()
              : (summary == null
                  ? null
                  : flashValue(
                      formatCurrency(summary.totalValue),
                      value: summary.totalValue,
                      rising: summary.dailyPnl >= 0,
                      color: t.primary,
                    )),
          value: summary == null ? 'Dati non disponibili' : formatCurrency(summary.totalValue),
          valueColor: t.primary,
        ),
        StatCard(
          label: 'P&L giornaliero',
          icon: const Icon(Icons.today_outlined),
          tooltip:
              'Variazione monetaria e percentuale registrata oggi rispetto alla chiusura precedente.',
          // Su mobile la riga delta/descrizione è stretta: il delta vince.
          description: compact ? null : 'Rendimento odierno',
          valueWidget: loading
              ? const SkeletonValue()
              : (summary == null
                  ? null
                  : flashValue(
                      formatCurrency(summary.dailyPnl),
                      value: summary.dailyPnl,
                      rising: summary.dailyPnl >= 0,
                    )),
          value: summary == null ? 'Dati non disponibili' : formatCurrency(summary.dailyPnl),
          delta: loading ? null : summary?.dailyPnlPercent,
          deltaLabel: '%',
        ),
        StatCard(
          label: 'P&L totale',
          icon: const Icon(Icons.trending_up),
          tooltip:
              'Rendimento complessivo calcolato tra il prezzo medio di carico e il prezzo attuale.',
          description: compact ? null : 'Risultato totale',
          valueWidget: loading
              ? const SkeletonValue()
              : (summary == null
                  ? null
                  : flashValue(
                      formatCurrency(summary.totalPnl),
                      value: summary.totalPnl,
                      rising: summary.totalPnl >= 0,
                    )),
          value: summary == null ? 'Dati non disponibili' : formatCurrency(summary.totalPnl),
          delta: loading ? null : summary?.totalPnlPercent,
          deltaLabel: '%',
        ),
        StatCard(
          label: 'Dividendi stimati',
          icon: const Icon(Icons.payments_outlined),
          tooltip:
              'Stima del flusso cedolare passivo annuo lordo generato dalle posizioni in portafoglio.',
          description: summary == null
              ? 'Yield stimato: --%'
              : '${compact ? 'Yield' : 'Yield stimato'}: ${_decimal(summary.estimatedDividendYield, 2)}%',
          valueWidget: loading ? const SkeletonValue() : null,
          // Su mobile il suffisso `/anno` non entra nel valore: la periodicità
          // resta nella descrizione.
          value: summary == null
              ? 'Dati non disponibili'
              : '${formatCurrency(summary.estimatedAnnualDividends)}${compact ? '' : '/anno'}',
          valueColor: t.successText,
        ),
        StatCard(
          label: 'Top performer',
          icon: const Icon(Icons.emoji_events_outlined),
          tooltip:
              'Il titolo con il maggior guadagno percentuale complessivo nel tuo portafoglio.',
          smallValue: true,
          valueWidget: loading ? const SkeletonValue() : null,
          value: gainer == null ? '--' : gainer.ticker,
          valueColor: t.successText,
          delta: (loading || gainer == null) ? null : gainer.pnlPercent,
          deltaLabel: '%',
          description: gainer == null
              ? (loading ? 'Miglior posizione' : 'Nessuna posizione in utile')
              : (compact ? null : 'P&L netto: ${formatCurrency(gainer.pnlAbsolute)}'),
        ),
      ],
    );
  }

  // --- Metriche di rischio (striscia incassata compatta) ------------------

  Widget _riskStrip(AsyncValue<RiskMetrics> risk) {
    final RiskMetrics? metrics = risk.value;
    final Widget body;

    if (metrics == null && risk.isLoading) {
      body = const ResponsiveWrap(
        minItemWidth: 150,
        mobileColumns: 2,
        children: <Widget>[
          SkeletonStat(),
          SkeletonStat(),
          SkeletonStat(),
          SkeletonStat(),
        ],
      );
    } else if (metrics == null) {
      body = AppErrorPanel(
        message: 'Metriche di rischio non disponibili.',
        onRetry: () => ref.invalidate(dashboardRiskProvider),
      );
    } else if (_isEmptyRisk(metrics)) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
        child: Text(
          "Metriche calcolate dopo l'inserimento di posizioni storiche.",
          textAlign: TextAlign.center,
          style: AppText.caption(context),
        ),
      );
    } else {
      final AppTokens t = context.tokens;
      body = ResponsiveWrap(
        minItemWidth: 150,
        mobileColumns: 2,
        children: <Widget>[
          _RiskTile(
            label: 'Max drawdown',
            value: formatPercent(metrics.maxDrawdownPct),
            description: 'Picco-minimo',
            color: t.danger,
          ),
          _RiskTile(
            label: 'Volatilità annua',
            value: '${_decimal(metrics.annualizedVolatilityPct, 1)}%',
            description: 'Deviazione std',
            color: t.textPrimary,
          ),
          _RiskTile(
            label: 'Sharpe ratio',
            value: _decimal(metrics.sharpeRatio, 2),
            description: 'Rendimento / rischio',
            color: metrics.sharpeRatio >= 1 ? t.successText : t.textPrimary,
          ),
          _RiskTile(
            label: 'Beta pesato',
            value: _decimal(metrics.weightedBeta, 2),
            description: 'Sensibilità mercato',
            color: t.textPrimary,
          ),
        ],
      );
    }

    return AppCard(
      subtle: true,
      dense: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SectionHeader(
            title: 'Rischio & performance',
            subtitle: 'Analisi quantitativa del portafoglio (orizzonte 180 giorni)',
            overline: 'Rischio',
            icon: Icons.shield_outlined,
            dense: true,
            padding: EdgeInsets.only(bottom: AppSpacing.s10),
          ),
          body,
        ],
      ),
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
    final bool narrow = context.isNarrow;

    final Widget selector = AppSegmented<ChartTimeframe>(
      segments: <AppSegment<ChartTimeframe>>[
        for (final ChartTimeframe value in ChartTimeframe.values)
          AppSegment<ChartTimeframe>(
            value: value,
            label: value.label,
            tooltip: 'Orizzonte di ${value.days} giorni',
          ),
      ],
      selected: timeframe,
      dense: true,
      expand: compact,
      semanticsLabel: 'Orizzonte del grafico',
      onSelected: (ChartTimeframe value) =>
          unawaited(ref.read(chartTimeframeProvider.notifier).select(value)),
    );

    final bool chartFailed = chart.value == null && chart.hasError;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            title: 'Andamento storico del portafoglio',
            subtitle: 'Crescita % a confronto con gli indici di mercato',
            overline: 'Portafoglio',
            icon: Icons.show_chart,
            padding: EdgeInsets.only(bottom: narrow ? AppSpacing.s10 : AppSpacing.s14),
            trailing: narrow ? null : selector,
          ),
          if (narrow) ...<Widget>[
            selector,
            const SizedBox(height: AppSpacing.s10),
          ],
          ChartBenchmarkChips(
            selected: benchmark,
            onSelected: (ChartBenchmark value) =>
                ref.read(chartBenchmarkProvider.notifier).select(value),
          ),
          const SizedBox(height: AppSpacing.s12),
          if (chartFailed)
            AppErrorPanel(
              message: 'Grafico non disponibile.',
              onRetry: () => _retryChart(timeframe),
            )
          else
            PortfolioChart(
              data: chart.value,
              loading: chart.isLoading && chart.value == null,
              mode: benchmark,
              height: compact ? 250 : 340,
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
            title: 'Analisi macro',
            subtitle: 'Sintesi strategica Gemini 3.8 Flash',
            overline: 'Analisi',
            icon: Icons.insights,
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
    final bool failed = state?.failedSections.contains('consigli') ?? false;

    if (advices == null) {
      if (loading) {
        return const Column(
          children: <Widget>[
            SkeletonCard(height: 96),
            SizedBox(height: AppSpacing.s12),
            SkeletonCard(height: 96),
          ],
        );
      }
      if (failed) {
        return AppErrorPanel(
          message: 'Analisi macro non disponibili.',
          onRetry: _reload,
        );
      }
      return EmptyState(
        title: 'Nessuna analisi recente',
        icon: const Icon(Icons.insights),
        message: 'Genera una nuova analisi macro dalla sezione Analisi.',
        actions: <Widget>[
          AppButton(
            label: 'Apri Analisi',
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
            onPressed: () => context.go('/advice'),
          ),
        ],
      );
    }
    if (advices.isEmpty) {
      return EmptyState(
        title: 'Nessuna analisi recente',
        icon: const Icon(Icons.insights),
        message: 'Genera una nuova analisi macro dalla sezione Analisi.',
        actions: <Widget>[
          AppButton(
            label: 'Apri Analisi',
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
            onPressed: () => context.go('/advice'),
          ),
        ],
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
            title: 'Heatmap di mercato',
            subtitle: 'Panoramica visiva dei movimenti di prezzo odierni',
            overline: 'Mercati',
            icon: Icons.grid_view,
            trailingLabel: 'Apri radar',
            onTrailingTap: () => context.go('/watchlist'),
          ),
          HeatmapGrid(
            items: state?.heatmap,
            loading: loading,
            failed: state?.failedSections.contains('heatmap') ?? false,
            onOpenStock: _openStock,
            onSeedDemo: _seedDemo,
            onRetry: _reload,
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
            title: 'Posizioni in portafoglio',
            subtitle: "Clicca su un ticker per la scheda tecnica e l'analisi IA",
            overline: 'Portafoglio',
            icon: Icons.business_center,
            trailingLabel: 'Gestisci',
            onTrailingTap: () => context.go('/portfolio'),
          ),
          HoldingsSection(
            holdings: state?.holdings,
            loading: loading,
            failed: state?.failedSections.contains('portafoglio') ?? false,
            onOpenStock: _openStock,
            onAddHolding: () => context.go('/portfolio?add='),
            onSeedDemo: _seedDemo,
            onRetry: _reload,
          ),
        ],
      ),
    );
  }
}

/// Formatta un decimale con la virgola italiana (`18.3` → `18,3`).
String _decimal(double value, int digits) =>
    value.toStringAsFixed(digits).replaceAll('.', ',');

/// Tile compatta delle metriche di rischio dentro la striscia incassata.
class _RiskTile extends StatelessWidget {
  const _RiskTile({
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label.toUpperCase(),
          style: AppText.micro(context).copyWith(fontSize: 10.5, color: t.textMuted),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: AppSpacing.s4),
        Text(value, style: AppText.mono(context, size: 17, weight: FontWeight.w700, color: color)),
        const SizedBox(height: AppSpacing.s2),
        Text(description, style: AppText.caption(context).copyWith(fontSize: 11)),
      ],
    );
  }
}

/// Card di un'analisi macro (`card card-subtle p-3`): tag mercato + titolo,
/// badge azione, `overview || strategy` clampata a 2 righe.
class _AdviceCard extends StatelessWidget {
  const _AdviceCard({required this.advice});

  final Advice advice;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final String market = (advice.market ?? '').toUpperCase();
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
                    AppMarketTag.forTicker('', market: market),
                    const SizedBox(width: AppSpacing.s6),
                    Flexible(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: t.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
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
