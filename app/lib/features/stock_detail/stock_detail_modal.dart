import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsRole;
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyEvent, KeyRepeatEvent, LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/advice_api.dart';
import '../../core/api/portfolio_api.dart';
import '../../core/api/stocks_api.dart';
import '../../core/api/watchlist_api.dart';
import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/models/advice.dart';
import '../../core/models/deep_dive.dart';
import '../../core/models/portfolio.dart';
import '../../core/models/stock.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/badges.dart';
import '../../widgets/range_bar.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/toast.dart';

/// Placeholder unico per i dati opzionali mancanti (mai `undefined`/crash).
const String _dash = '—';

/// Timeframe UI → parametro API (parità con le pill del vecchio modal).
const Map<String, String> _timeframes = <String, String>{
  '1G': '1d',
  '1S': '1w',
  '1M': '1m',
  '6M': '6m',
  '1A': '1y',
  '5A': '5y',
};

const List<String> _tabLabels = <String>[
  '📈 Grafico & Dati',
  '⚡ Indicatori Tecnici',
  '📊 Fondamentali',
  '🤖 Analisi AI Gemini',
];

/// Apre la scheda titolo (stock detail) di [ticker].
///
/// Contenitore adattivo: dialog centrato max-width 920 su desktop/web,
/// bottom-sheet quasi full-height su mobile (<640). [onChanged] viene chiamato
/// dopo mutazioni che possono interessare la pagina chiamante (es. aggiunta in
/// Watchlist).
Future<void> showStockDetail(
  BuildContext context,
  String ticker, {
  VoidCallback? onChanged,
}) {
  final String normalized = ticker.trim().toUpperCase();
  if (normalized.isEmpty) return Future<void>.value();

  final bool compact = context.isCompact;
  if (compact) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.tokens.surface,
      barrierColor: context.tokens.scrim,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadii.modal),
        ),
      ),
      builder: (BuildContext _) => FractionallySizedBox(
        heightFactor: 0.95,
        child: SafeArea(
          top: false,
          child: _EscapePop(
            child: _StockDetailModal(ticker: normalized, onChanged: onChanged),
          ),
        ),
      ),
    );
  }

  return showDialog<void>(
    context: context,
    barrierColor: context.tokens.scrim,
    builder: (BuildContext dialogContext) => Dialog(
      backgroundColor: context.tokens.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        side: BorderSide(color: context.tokens.border),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 920,
          maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.9,
        ),
        child: _StockDetailModal(ticker: normalized, onChanged: onChanged),
      ),
    ),
  );
}

/// Chiude il modal su `Esc` (il dialog lo fa già da solo, il bottom-sheet no).
class _EscapePop extends StatelessWidget {
  const _EscapePop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}

class _StockDetailModal extends ConsumerStatefulWidget {
  const _StockDetailModal({required this.ticker, this.onChanged});

  final String ticker;
  final VoidCallback? onChanged;

  @override
  ConsumerState<_StockDetailModal> createState() => _StockDetailModalState();
}

class _StockDetailModalState extends ConsumerState<_StockDetailModal> {
  StockDetails? _details;
  bool _detailsLoading = true;
  Holding? _holding;

  String _timeframe = '1M';
  bool _candleMode = false;
  List<Candle> _candles = const <Candle>[];
  bool _candlesLoading = true;
  bool _candlesFailed = false;
  int _chartGeneration = 0;

  int _tabIndex = 0;
  late final List<FocusNode> _tabFocusNodes = List<FocusNode>.generate(
    _tabLabels.length,
    (int index) => FocusNode(debugLabel: 'stock-tab-$index'),
  );

  bool _addingToWatchlist = false;

  bool _aiLoading = false;
  bool _aiAttempted = false;
  StockAnalysis? _aiResult;
  String? _aiError;
  int _aiGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadDetails();
    _loadCandles();
  }

  @override
  void dispose() {
    for (final FocusNode node in _tabFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  // --- Data loading -------------------------------------------------------

  /// Fetch parallelo details + holdings (per `isInPortfolio` e prezzo medio).
  ///
  /// Le due risposte falliscono in modo indipendente: details fallito → tutti
  /// i campi opzionali restano `null` e la UI mostra i placeholder `—`.
  Future<void> _loadDetails() async {
    final Future<StockDetails?> detailsFuture = _fetchDetails();
    final Future<List<Holding>?> holdingsFuture = _fetchHoldings();

    final StockDetails? details = await detailsFuture;
    final List<Holding>? holdings = await holdingsFuture;
    if (!mounted) return;

    Holding? held;
    if (holdings != null) {
      for (final Holding item in holdings) {
        if (item.ticker.toUpperCase() == widget.ticker) {
          held = item;
          break;
        }
      }
    }

    setState(() {
      _details = details ?? StockDetails(ticker: widget.ticker);
      _holding = held;
      _detailsLoading = false;
    });
  }

  Future<StockDetails?> _fetchDetails() async {
    try {
      return await ref.read(stocksApiProvider).details(widget.ticker);
    } catch (_) {
      return null;
    }
  }

  Future<List<Holding>?> _fetchHoldings() async {
    try {
      return await ref.read(portfolioApiProvider).holdings();
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadCandles() async {
    final int generation = ++_chartGeneration;
    final String timeframe = _timeframes[_timeframe]!;
    setState(() => _candlesLoading = true);
    try {
      final List<Candle> data = await ref
          .read(stocksApiProvider)
          .candles(widget.ticker, timeframe);
      if (!mounted || generation != _chartGeneration) return;
      setState(() {
        _candles = data;
        _candlesLoading = false;
        _candlesFailed = false;
      });
    } catch (_) {
      if (!mounted || generation != _chartGeneration) return;
      setState(() {
        _candles = const <Candle>[];
        _candlesLoading = false;
        _candlesFailed = true;
      });
    }
  }

  // --- Actions ------------------------------------------------------------

  Future<void> _addToWatchlist() async {
    if (_addingToWatchlist) return;
    setState(() => _addingToWatchlist = true);
    try {
      final result = await ref
          .read(watchlistApiProvider)
          .add(ticker: widget.ticker);
      if (!mounted) return;
      final bool exists = result.status == 'exists';
      showAppToast(
        context,
        message: result.message.isNotEmpty
            ? result.message
            : (exists
                  ? '${widget.ticker} è già nella Watchlist.'
                  : '${widget.ticker} aggiunto alla Watchlist!'),
        type: exists ? AppToastType.info : AppToastType.success,
      );
      widget.onChanged?.call();
    } on ApiException catch (error) {
      if (!mounted) return;
      showAppToast(context, message: error.message, type: AppToastType.error);
    } catch (_) {
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Errore durante il salvataggio in Watchlist.',
        type: AppToastType.error,
      );
    } finally {
      if (mounted) setState(() => _addingToWatchlist = false);
    }
  }

  void _addToPortfolio() {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go('/portfolio?add=${Uri.encodeComponent(widget.ticker)}');
  }

  Future<void> _runAi() async {
    final int generation = ++_aiGeneration;
    setState(() {
      _aiLoading = true;
      _aiAttempted = true;
      _aiError = null;
    });
    try {
      final result = await ref
          .read(adviceApiProvider)
          .analyzeStock(widget.ticker);
      if (!mounted || generation != _aiGeneration) return;
      setState(() {
        _aiResult = result;
        _aiLoading = false;
      });
    } on ApiException catch (error) {
      if (!mounted || generation != _aiGeneration) return;
      setState(() {
        _aiResult = null;
        _aiError = error.message;
        _aiLoading = false;
      });
    } catch (error) {
      if (!mounted || generation != _aiGeneration) return;
      setState(() {
        _aiResult = null;
        _aiError = error.toString();
        _aiLoading = false;
      });
    }
  }

  // --- Helpers ------------------------------------------------------------

  String get _currency => _details?.currency ?? _holding?.currency ?? 'EUR';

  Holding? get _heldHolding => _holding;

  String _currencyText(num? value) =>
      value == null ? _dash : formatCurrency(value, currency: _currency);

  String _compactText(num? value) =>
      value == null ? _dash : formatCompactNumber(value);

  String _numberText(num? value) =>
      value == null ? _dash : NumberFormat('#,##0.##', 'it_IT').format(value);

  // --- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _buildHeader(context),
        _buildTabBar(context),
        Flexible(
          child: Scrollbar(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              child: Semantics(
                container: true,
                role: SemanticsRole.tabPanel,
                child: KeyedSubtree(
                  key: ValueKey<int>(_tabIndex),
                  child: _buildTabPanel(context),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final AppTokens t = context.tokens;
    final StockDetails? details = _details;
    final String market = (_details?.market ?? _holding?.market ?? 'US')
        .toUpperCase();
    final String name = (details?.name?.trim().isNotEmpty ?? false)
        ? details!.name!
        : (_detailsLoading ? 'Caricamento dati...' : widget.ticker);

    final String price = _detailsLoading
        ? '--'
        : _currencyText(details?.currentPrice);

    final num? changeAbs = details?.changeAbs;
    final num? changePercent = details?.changePercent;
    final List<String> changeParts = <String>[
      if (changeAbs != null) _signedNumber(changeAbs),
      if (changePercent != null) '(${formatPercent(changePercent)})',
    ];
    final String changeText = changeParts.isEmpty
        ? _dash
        : changeParts.join(' ');
    final bool changeKnown = changeAbs != null || changePercent != null;
    final Color changeColor = !changeKnown
        ? t.textSecondary
        : ((changePercent ?? changeAbs ?? 0) >= 0 ? t.success : t.danger);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 10, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.borderSubtle)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _flagFor(market),
            style: const TextStyle(fontSize: 24, height: 1.1),
          ),
          const SizedBox(width: AppSpacing.s10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Wrap(
                  spacing: AppSpacing.s8,
                  runSpacing: AppSpacing.s4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    Text(widget.ticker, style: AppText.modalTitle(context)),
                    AppBadge(
                      label: market,
                      tone: market == 'IT' ? BadgeTone.success : BadgeTone.cyan,
                    ),
                    if (_heldHolding != null)
                      const AppBadge(
                        label: '💼 In Portafoglio',
                        tone: BadgeTone.success,
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  name,
                  style: AppText.caption(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                price,
                style: AppText.mono(context, size: 19, weight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.s2),
              Text(
                changeText,
                style: AppText.mono(
                  context,
                  size: 12,
                  weight: FontWeight.w700,
                  color: changeColor,
                ),
              ),
            ],
          ),
          AppIconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Chiudi finestra',
            semanticLabel: 'Chiudi finestra',
            bordered: false,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(BuildContext context) {
    final AppTokens t = context.tokens;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12),
        child: Semantics(
          container: true,
          role: SemanticsRole.tabBar,
          child: Row(
            children: <Widget>[
              for (int index = 0; index < _tabLabels.length; index++)
                _StockTabButton(
                  label: _tabLabels[index],
                  selected: _tabIndex == index,
                  focusNode: _tabFocusNodes[index],
                  onTap: () => setState(() => _tabIndex = index),
                  onKeyEvent: (KeyEvent event) => _onTabKey(index, event),
                ),
            ],
          ),
        ),
      ),
    );
  }

  KeyEventResult _onTabKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    int? next;
    if (key == LogicalKeyboardKey.arrowRight) {
      next = (index + 1) % _tabLabels.length;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      next = (index - 1 + _tabLabels.length) % _tabLabels.length;
    } else if (key == LogicalKeyboardKey.home) {
      next = 0;
    } else if (key == LogicalKeyboardKey.end) {
      next = _tabLabels.length - 1;
    }
    if (next == null) return KeyEventResult.ignored;
    setState(() => _tabIndex = next!);
    _tabFocusNodes[next].requestFocus();
    return KeyEventResult.handled;
  }

  Widget _buildTabPanel(BuildContext context) {
    return switch (_tabIndex) {
      0 => _buildChartTab(context),
      1 => _buildTechnicalsTab(context),
      2 => _buildFundamentalsTab(context),
      _ => _buildAiTab(context),
    };
  }

  // --- Tab 1: chart & data ------------------------------------------------

  Widget _buildChartTab(BuildContext context) {
    final AppTokens t = context.tokens;
    final AppChartPalette palette = t.chart;
    final double chartHeight = context.isCompact ? 240 : 320;
    final double volumeHeight = chartHeight * 0.22;
    // Il padding verticale del box (10 sopra + 4 sotto) va sottratto: le due
    // altezze interne più il gap devono entrare nello spazio utile, altrimenti
    // la Column interna overflowa di 14px.
    const double chartPaddingVertical = 10 + 4;
    final double priceHeight = chartHeight -
        volumeHeight -
        AppSpacing.s6 -
        chartPaddingVertical;
    final bool intraday = _timeframe == '1G' || _timeframe == '1S';

    final Widget chart;
    if (_candlesLoading && _candles.isEmpty) {
      chart = Center(child: AppSpinner());
    } else if (_candles.isEmpty) {
      chart = Center(
        child: Text(
          _candlesFailed
              ? 'Dati non disponibili per questo intervallo.'
              : 'Nessun dato disponibile.',
          style: AppText.caption(context),
        ),
      );
    } else {
      chart = _ChartView(
        candles: _candles,
        candleMode: _candleMode,
        avgPrice: _heldHolding?.avgPurchasePrice,
        palette: palette,
        intraday: intraday,
        priceHeight: priceHeight,
        volumeHeight: volumeHeight,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (context.isCompact)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _timeframeControls(context),
              const SizedBox(height: AppSpacing.s8),
              _chartActions(context),
            ],
          )
        else
          Row(
            children: <Widget>[
              Expanded(child: _timeframeControls(context)),
              const SizedBox(width: AppSpacing.s8),
              _chartActions(context),
            ],
          ),
        const SizedBox(height: AppSpacing.s12),
        SizedBox(
          height: chartHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: t.surfaceHover,
              borderRadius: BorderRadius.circular(AppRadii.heatmap),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 10, 10, 4),
              child: chart,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: AppSpacing.s12,
            runSpacing: AppSpacing.s4,
            children: <Widget>[
              if (_heldHolding != null)
                Text(
                  '🟠 Linea Tratteggiata: Prezzo Medio Carico Portafoglio',
                  style: AppText.caption(context),
                ),
              Text(
                'Volumi visualizzati in basso',
                style: AppText.caption(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _timeframeControls(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.s6,
      runSpacing: AppSpacing.s6,
      children: <Widget>[
        for (final String label in _timeframes.keys)
          AppPill(
            label: label,
            selected: _timeframe == label,
            onPressed: () {
              if (_timeframe == label) return;
              setState(() => _timeframe = label);
              _loadCandles();
            },
          ),
        const SizedBox(width: AppSpacing.s2),
        AppPill(
          label: '📈 Area',
          selected: !_candleMode,
          onPressed: () => setState(() => _candleMode = false),
        ),
        AppPill(
          label: '📊 Candele',
          selected: _candleMode,
          onPressed: () => setState(() => _candleMode = true),
        ),
      ],
    );
  }

  Widget _chartActions(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.s8,
      runSpacing: AppSpacing.s8,
      children: <Widget>[
        AppButton(
          label: '⭐ Salva in Watchlist',
          variant: AppButtonVariant.ghost,
          size: AppButtonSize.sm,
          loading: _addingToWatchlist,
          loadingLabel: 'Salvataggio...',
          onPressed: _addingToWatchlist ? null : _addToWatchlist,
        ),
        AppButton(
          label: '➕ Aggiungi al Portafoglio',
          variant: AppButtonVariant.primary,
          size: AppButtonSize.sm,
          onPressed: _addToPortfolio,
        ),
      ],
    );
  }

  // --- Tab 2: technicals --------------------------------------------------

  Widget _buildTechnicalsTab(BuildContext context) {
    final AppTokens t = context.tokens;
    final TechnicalIndicators? tech = _details?.technical;
    final double? low = _details?.fiftyTwoWeekLow;
    final double? high = _details?.fiftyTwoWeekHigh;
    final num? rawPct = _details?.fiftyTwoWeekPct;
    final double position = (rawPct == null || !rawPct.isFinite)
        ? 50
        : rawPct.toDouble().clamp(0, 100).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _MetricGrid(
          desktopColumns: 4,
          cards: <Widget>[
            _MetricCard(
              label: 'RSI (14 Periodi)',
              value: _numberText(tech?.rsi14),
              badge: AppBadge(
                label: (tech?.rsiStatus?.isNotEmpty ?? false)
                    ? tech!.rsiStatus!
                    : 'Neutro',
                tone: _rsiTone(tech?.rsiBadge),
              ),
            ),
            _MetricCard(
              label: 'Media Mobile 20 (SMA 20)',
              value: _currencyText(tech?.sma20),
              subtitle: 'Trend breve termine',
            ),
            _MetricCard(
              label: 'Media Mobile 50 (SMA 50)',
              value: _currencyText(tech?.sma50),
              subtitle: 'Trend medio termine',
            ),
            _MetricCard(
              label: 'Configurazione Trend',
              value: (tech?.trend?.isNotEmpty ?? false)
                  ? tech!.trend!
                  : 'Neutro',
              valueColor: t.primary,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s14),
        AppCard(
          subtle: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'RANGE 52 SETTIMANE',
                style: AppText.sectionLabel(context)
                    .copyWith(color: t.textMuted, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.s10),
              RangeBar(
                positionPercent: position,
                lowLabel: 'Min: ${_currencyText(low)}',
                highLabel: 'Max: ${_currencyText(high)}',
                showPosition: true,
                minWidth: 200,
              ),
            ],
          ),
        ),
      ],
    );
  }

  BadgeTone _rsiTone(String? badge) {
    return switch (badge) {
      'badge-buy' => BadgeTone.success,
      'badge-sell' => BadgeTone.danger,
      'badge-hold' => BadgeTone.warning,
      'badge-primary' => BadgeTone.primary,
      _ => BadgeTone.warning,
    };
  }

  // --- Tab 3: fundamentals ------------------------------------------------

  Widget _buildFundamentalsTab(BuildContext context) {
    final StockDetails? details = _details;
    final num? dividendYield = details?.dividendYield;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _MetricGrid(
          desktopColumns: 3,
          cards: <Widget>[
            _MetricCard(
              label: 'Capitalizzazione',
              value: _compactText(details?.marketCap),
            ),
            _MetricCard(
              label: 'P/E Ratio (Trailing)',
              value: _numberText(details?.peRatio),
            ),
            _MetricCard(
              label: 'EPS (Utile per Azione)',
              value: _currencyText(details?.eps),
            ),
            _MetricCard(
              label: 'Beta (Volatilità)',
              value: _numberText(details?.beta),
            ),
            _MetricCard(
              label: 'Dividend Yield',
              value: dividendYield == null
                  ? '$_dash%'
                  : '${_numberText(dividendYield)}%',
            ),
            _MetricCard(
              label: 'Volume Medio',
              value: _compactText(details?.avgVolume ?? details?.volume),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s14),
        AppCard(
          subtle: true,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 120),
            child: SingleChildScrollView(
              child: Text(
                (details?.summary?.trim().isNotEmpty ?? false)
                    ? details!.summary!
                    : 'Nessuna descrizione disponibile.',
                style: AppText.small(context),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --- Tab 4: AI analysis -------------------------------------------------

  Widget _buildAiTab(BuildContext context) {
    final AppTokens t = context.tokens;
    final Widget body;
    if (_aiLoading) {
      body = AppCard(
        subtle: true,
        child: const SizedBox(height: 140, child: Center(child: AppSpinner())),
      );
    } else if (_aiError != null) {
      body = StockDetailCallout(
        background: t.dangerBg,
        borderColor: t.dangerBorder,
        child: Text(
          "Impossibile completare l'analisi per ${widget.ticker}: $_aiError",
          textAlign: TextAlign.center,
          style: AppText.small(context).copyWith(color: t.danger),
        ),
      );
    } else if (_aiResult != null) {
      body = _AiResultView(
        analysis: _aiResult!,
        currency: _currency,
        holdingCurrency: _heldHolding?.currency ?? _currency,
      );
    } else {
      body = AppCard(
        subtle: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s24),
          child: Text(
            'Clicca "Elabora Analisi Ora" per interrogare l\'IA su '
            'fondamentali, indicatori tecnici, catalizzatori e posizione '
            'in portafoglio.',
            textAlign: TextAlign.center,
            style: AppText.caption(context),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '🧠 Analisi Istantanea Gemini 3.7 Flash',
                style: AppText.cardTitle(context).copyWith(color: t.primary),
              ),
            ),
            const SizedBox(width: AppSpacing.s10),
            AppButton(
              label: _aiAttempted
                  ? '⚡ Rielabora Analisi'
                  : '⚡ Elabora Analisi Ora',
              variant: AppButtonVariant.primary,
              size: AppButtonSize.sm,
              loading: _aiLoading,
              loadingLabel: 'Analisi in corso...',
              onPressed: _aiLoading ? null : _runAi,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s12),
        body,
      ],
    );
  }
}

// --- Reusable modal pieces -------------------------------------------------

class _StockTabButton extends StatefulWidget {
  const _StockTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.focusNode,
    this.onKeyEvent,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final KeyEventResult Function(KeyEvent event)? onKeyEvent;

  @override
  State<_StockTabButton> createState() => _StockTabButtonState();
}

class _StockTabButtonState extends State<_StockTabButton> {
  bool _focused = false;

  void _handleTap() {
    // Anche il click sposta il focus sulla tab (pattern roving tabindex).
    widget.focusNode?.requestFocus();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool selected = widget.selected;
    final Color foreground = selected ? t.primary : t.textSecondary;
    return Semantics(
      container: true,
      role: SemanticsRole.tab,
      selected: selected,
      button: true,
      child: Focus(
        focusNode: widget.focusNode,
        // Roving tabindex: solo la tab selezionata è raggiungibile con Tab.
        // Le altre restano focusabili via frecce/Home/End (requestFocus
        // programmatico, che skipTraversal non blocca).
        skipTraversal: !selected,
        onFocusChange: (bool value) => setState(() => _focused = value),
        onKeyEvent: (FocusNode _, KeyEvent event) =>
            widget.onKeyEvent?.call(event) ?? KeyEventResult.ignored,
        child: InkWell(
          onTap: _handleTap,
          // Il nodo di focus è quello esterno: l'InkWell non deve creare un
          // secondo tab stop.
          canRequestFocus: false,
          hoverColor: t.surfaceHover,
          borderRadius: BorderRadius.circular(AppRadii.small),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s12,
              vertical: AppSpacing.s10,
            ),
            decoration: BoxDecoration(
              color: _focused ? t.primaryGlow : null,
              border: Border(
                bottom: BorderSide(
                  color: selected ? t.primary : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Text(
              widget.label,
              style: AppText.button(context).copyWith(
                color: foreground,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.cards, this.desktopColumns = 4});

  final List<Widget> cards;
  final int desktopColumns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int columns = constraints.maxWidth >= 760 ? desktopColumns : 2;
        const double gap = AppSpacing.s10;
        final double itemWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (final Widget card in cards)
              SizedBox(width: itemWidth, child: card),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    this.subtitle,
    this.badge,
    this.valueColor,
  });

  final String label;
  final String value;
  final String? subtitle;
  final Widget? badge;
  final Color? valueColor;

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
            style: AppText.sectionLabel(context).copyWith(color: t.textMuted),
          ),
          const SizedBox(height: AppSpacing.s6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.mono(
              context,
              size: 18,
              weight: FontWeight.w700,
              color: valueColor,
            ),
          ),
          if (badge != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s8),
              child: badge,
            ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s4),
              child: Text(subtitle!, style: AppText.caption(context)),
            ),
        ],
      ),
    );
  }
}

/// Callout della scheda titolo (`.callout`, `.callout-accent`, `.callout-*`).
///
/// Pubblica per i widget test (`border_paint_test.dart`): l'accent sinistro è
/// una striscia clippata su [Stack] (un [Border] asimmetrico non è compatibile
/// con `borderRadius`).
class StockDetailCallout extends StatelessWidget {
  const StockDetailCallout({
    super.key,
    required this.child,
    required this.background,
    required this.borderColor,
    this.accentColor,
  });

  final Widget child;
  final Color background;
  final Color borderColor;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    if (accentColor == null) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.s10),
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(AppRadii.input),
        ),
        child: child,
      );
    }
    // Accent sinistro come striscia clippata su Stack: un Border con lati di
    // colori diversi non è compatibile con borderRadius (assert a ogni paint).
    return Container(
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(AppRadii.input),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: <Widget>[
          Padding(padding: const EdgeInsets.all(AppSpacing.s10), child: child),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 3,
            child: ColoredBox(color: accentColor!),
          ),
        ],
      ),
    );
  }
}

class _AdaptiveSplit extends StatelessWidget {
  const _AdaptiveSplit({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              left,
              const SizedBox(height: AppSpacing.s10),
              right,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: left),
            const SizedBox(width: AppSpacing.s10),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}

class _AiResultView extends StatelessWidget {
  const _AiResultView({
    required this.analysis,
    required this.currency,
    required this.holdingCurrency,
  });

  final StockAnalysis analysis;
  final String currency;
  final String holdingCurrency;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final HoldingContext? holding = analysis.holdingContext;
    final double? upside = analysis.upsidePotentialPct;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AppBadge(
              label: _actionLabel(analysis),
              tone: _actionTone(analysis.action),
            ),
            const Spacer(),
            Text.rich(
              TextSpan(
                text: 'Confidenza: ',
                children: <InlineSpan>[
                  TextSpan(
                    text: (analysis.confidence?.isNotEmpty ?? false)
                        ? analysis.confidence!
                        : 'MEDIA',
                    style: TextStyle(
                      color: t.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const TextSpan(text: ' • Orizzonte: '),
                  TextSpan(
                    text: (analysis.timeframe?.isNotEmpty ?? false)
                        ? analysis.timeframe!
                        : 'Medio Termine',
                    style: TextStyle(
                      color: t.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              textAlign: TextAlign.right,
              style: AppText.caption(context),
            ),
          ],
        ),
        if (holding != null) ...<Widget>[
          const SizedBox(height: AppSpacing.s10),
          StockDetailCallout(
            background: t.primaryGlow,
            borderColor: t.primary,
            accentColor: t.primary,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '💼 Posizione nel tuo Portafoglio',
                  style: AppText.caption(context)
                      .copyWith(color: t.primary, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppSpacing.s4),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: AppSpacing.s12,
                  runSpacing: AppSpacing.s4,
                  children: <Widget>[
                    Text.rich(
                      TextSpan(
                        text: 'Possiedi: ',
                        children: <InlineSpan>[
                          TextSpan(
                            text: NumberFormat(
                              '#,##0.##',
                              'it_IT',
                            ).format(holding.quantity),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const TextSpan(text: ' azioni a carico '),
                          TextSpan(
                            text: formatCurrency(
                              holding.avgPurchasePrice,
                              currency: holdingCurrency,
                            ),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      style: AppText.mono(context, size: 12),
                    ),
                    Text(
                      'P&L: ${formatCurrency(holding.currentPnlAbs, currency: holdingCurrency)} '
                      '(${formatPercent(holding.currentPnlPct)})',
                      style: AppText.mono(
                        context,
                        size: 12,
                        weight: FontWeight.w700,
                        color: holding.currentPnlPct >= 0
                            ? t.success
                            : t.danger,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.s10),
        _AdaptiveSplit(
          left: StockDetailCallout(
            background: t.surfaceHover,
            borderColor: t.border,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '🎯 Target Price Stimato',
                  style: AppText.caption(context),
                ),
                const SizedBox(height: AppSpacing.s4),
                Text.rich(
                  TextSpan(
                    text: formatCurrency(
                      analysis.targetPrice,
                      currency: currency,
                    ),
                    children: <InlineSpan>[
                      if (upside != null)
                        TextSpan(
                          text: ' (${formatPercent(upside)})',
                          style: TextStyle(
                            fontSize: 12,
                            color: upside > 0 ? t.success : t.danger,
                          ),
                        ),
                    ],
                  ),
                  style: AppText.mono(
                    context,
                    size: 17,
                    weight: FontWeight.w700,
                    color: t.primary,
                  ),
                ),
              ],
            ),
          ),
          right: StockDetailCallout(
            background: t.surfaceHover,
            borderColor: t.border,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '🛡️ Stop Loss Consigliato',
                  style: AppText.caption(context),
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  formatCurrency(analysis.stopLoss, currency: currency),
                  style: AppText.mono(
                    context,
                    size: 17,
                    weight: FontWeight.w700,
                    color: t.danger,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s10),
        Text(
          (analysis.summary?.isNotEmpty ?? false) ? analysis.summary! : _dash,
          style: AppText.small(context),
        ),
        const SizedBox(height: AppSpacing.s10),
        _AdaptiveSplit(
          left: StockDetailCallout(
            background: t.successBg,
            borderColor: t.successBorder,
            child: _CaseText(
              title: '🟢 Bull Case & Punti di Forza',
              body: (analysis.bullCase?.isNotEmpty ?? false)
                  ? analysis.bullCase!
                  : _dash,
              titleColor: t.success,
            ),
          ),
          right: StockDetailCallout(
            background: t.dangerBg,
            borderColor: t.dangerBorder,
            child: _CaseText(
              title: '🔴 Bear Case & Rischi Chiave',
              body: (analysis.bearCase?.isNotEmpty ?? false)
                  ? analysis.bearCase!
                  : _dash,
              titleColor: t.danger,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s10),
        StockDetailCallout(
          background: t.surfaceHover,
          borderColor: t.border,
          child: _CaseText(
            title: '💡 Strategia Operativa Suggerita',
            body: (analysis.operationalStrategy?.isNotEmpty ?? false)
                ? analysis.operationalStrategy!
                : _dash,
            titleColor: t.primary,
          ),
        ),
      ],
    );
  }

  static String _actionLabel(StockAnalysis analysis) {
    if (analysis.actionLabel?.isNotEmpty ?? false) return analysis.actionLabel!;
    if (analysis.action.isNotEmpty) return analysis.action;
    return 'HOLD';
  }

  static BadgeTone _actionTone(String action) {
    return switch (action.toUpperCase()) {
      'ACCUMULO' || 'BUY' => BadgeTone.success,
      'PRESA_PROFITTO' || 'SELL' => BadgeTone.danger,
      _ => BadgeTone.warning,
    };
  }
}

class _CaseText extends StatelessWidget {
  const _CaseText({
    required this.title,
    required this.body,
    required this.titleColor,
  });

  final String title;
  final String body;
  final Color titleColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          title,
          style: AppText.caption(context)
              .copyWith(color: titleColor, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.s4),
        Text(body, style: AppText.small(context)),
      ],
    );
  }
}

// --- Chart -----------------------------------------------------------------

class _ChartPoint {
  const _ChartPoint({
    required this.x,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
    required this.up,
  });

  final double x;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;
  final bool up;
}

class _ChartData {
  const _ChartData({
    required this.points,
    required this.labels,
    required this.minY,
    required this.maxY,
    required this.maxVolume,
  });

  final List<_ChartPoint> points;
  final List<String> labels;
  final double minY;
  final double maxY;
  final double maxVolume;

  /// Costruisce il view-model: le chiavi possono essere opzionali (fallback
  /// offline) quindi si scartano solo le candele senza prezzo finale.
  static _ChartData? build(
    List<Candle> candles, {
    required bool intraday,
    double? avgPrice,
  }) {
    final List<_ChartPoint> points = <_ChartPoint>[];
    final List<String> labels = <String>[];
    for (final Candle candle in candles) {
      final double? close = candle.close ?? candle.value;
      if (close == null || !close.isFinite) continue;
      final double open = candle.open ?? close;
      final double high = candle.high ?? math.max(open, close);
      final double low = candle.low ?? math.min(open, close);
      points.add(
        _ChartPoint(
          x: points.length.toDouble(),
          open: open,
          high: high,
          low: low,
          close: close,
          volume: (candle.volume ?? 0).toDouble(),
          up: close >= open,
        ),
      );
      labels.add(_formatCandleTime(candle.time, intraday: intraday));
    }
    if (points.isEmpty) return null;

    double minY = double.infinity;
    double maxY = -double.infinity;
    double maxVolume = 0;
    for (final _ChartPoint point in points) {
      minY = math.min(minY, point.low);
      maxY = math.max(maxY, point.high);
      maxVolume = math.max(maxVolume, point.volume);
    }
    if (avgPrice != null && avgPrice.isFinite) {
      minY = math.min(minY, avgPrice);
      maxY = math.max(maxY, avgPrice);
    }
    double span = maxY - minY;
    if (span <= 0) {
      span = maxY.abs() * 0.02;
      if (span <= 0) span = 1;
    }
    final double padding = span * 0.06;
    return _ChartData(
      points: points,
      labels: labels,
      minY: minY - padding,
      maxY: maxY + padding,
      maxVolume: maxVolume,
    );
  }
}

class _ChartView extends StatelessWidget {
  const _ChartView({
    required this.candles,
    required this.candleMode,
    required this.avgPrice,
    required this.palette,
    required this.intraday,
    required this.priceHeight,
    required this.volumeHeight,
  });

  final List<Candle> candles;
  final bool candleMode;
  final double? avgPrice;
  final AppChartPalette palette;
  final bool intraday;
  final double priceHeight;
  final double volumeHeight;

  @override
  Widget build(BuildContext context) {
    final _ChartData? data = _ChartData.build(
      candles,
      intraday: intraday,
      avgPrice: avgPrice,
    );
    if (data == null) {
      return Center(
        child: Text(
          'Nessun dato disponibile.',
          style: AppText.caption(context),
        ),
      );
    }
    // Un unico campionamento per prezzo e volumi: i due grafici devono
    // condividere gli stessi indici per restare allineati.
    final List<_ChartPoint> view = _samplePoints(
      data.points,
      candleMode ? 220 : 500,
    );
    final List<String> labels = <String>[
      for (final _ChartPoint point in view)
        data.labels[point.x.round().clamp(0, data.labels.length - 1)],
    ];
    final double maxX = view.length <= 1 ? 1 : (view.length - 1).toDouble();

    return Column(
      children: <Widget>[
        SizedBox(
          height: priceHeight,
          child: candleMode
              ? _CandlestickView(
                  data: data,
                  view: view,
                  maxX: maxX,
                  palette: palette,
                )
              : _AreaView(
                  data: data,
                  view: view,
                  maxX: maxX,
                  palette: palette,
                  avgPrice: avgPrice,
                ),
        ),
        const SizedBox(height: AppSpacing.s6),
        SizedBox(
          height: volumeHeight,
          child: _VolumeView(
            data: data,
            view: view,
            labels: labels,
            maxX: maxX,
            palette: palette,
          ),
        ),
      ],
    );
  }
}

class _AreaView extends StatelessWidget {
  const _AreaView({
    required this.data,
    required this.view,
    required this.maxX,
    required this.palette,
    required this.avgPrice,
  });

  final _ChartData data;
  final List<_ChartPoint> view;
  final double maxX;
  final AppChartPalette palette;
  final double? avgPrice;

  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX,
        minY: data.minY,
        maxY: data.maxY,
        gridData: _gridData(palette, data),
        borderData: FlBorderData(show: false),
        titlesData: _titlesData(context, palette: palette),
        lineTouchData: const LineTouchData(enabled: true),
        lineBarsData: <LineChartBarData>[
          LineChartBarData(
            spots: <FlSpot>[
              for (int i = 0; i < view.length; i++)
                FlSpot(i.toDouble(), view[i].close),
            ],
            isCurved: false,
            barWidth: 2,
            color: palette.line,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[palette.top, palette.bottom],
              ),
            ),
          ),
          if (avgPrice != null && avgPrice!.isFinite)
            LineChartBarData(
              spots: <FlSpot>[FlSpot(0, avgPrice!), FlSpot(maxX, avgPrice!)],
              isCurved: false,
              barWidth: 2,
              color: palette.breakeven,
              dashArray: const <int>[6, 4],
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: false),
            ),
        ],
      ),
      duration: Duration.zero,
    );
  }
}

class _CandlestickView extends StatelessWidget {
  const _CandlestickView({
    required this.data,
    required this.view,
    required this.maxX,
    required this.palette,
  });

  final _ChartData data;
  final List<_ChartPoint> view;
  final double maxX;
  final AppChartPalette palette;

  @override
  Widget build(BuildContext context) {
    return CandlestickChart(
      CandlestickChartData(
        minX: 0,
        maxX: maxX,
        minY: data.minY,
        maxY: data.maxY,
        gridData: _gridData(palette, data),
        borderData: FlBorderData(show: false),
        titlesData: _titlesData(context, palette: palette),
        candlestickPainter: DefaultCandlestickPainter(
          candlestickStyleProvider: (CandlestickSpot spot, int _) {
            final Color color = spot.isUp ? palette.up : palette.down;
            return CandlestickStyle(
              lineColor: color,
              lineWidth: 1.2,
              bodyStrokeColor: color,
              bodyStrokeWidth: 0,
              bodyFillColor: color,
              bodyWidth: 4,
              bodyRadius: 1,
            );
          },
        ),
        candlestickSpots: <CandlestickSpot>[
          for (int i = 0; i < view.length; i++)
            CandlestickSpot(
              x: i.toDouble(),
              open: view[i].open,
              high: view[i].high,
              low: view[i].low,
              close: view[i].close,
            ),
        ],
      ),
      duration: Duration.zero,
    );
  }
}

class _VolumeView extends StatelessWidget {
  const _VolumeView({
    required this.data,
    required this.view,
    required this.labels,
    required this.maxX,
    required this.palette,
  });

  final _ChartData data;
  final List<_ChartPoint> view;
  final List<String> labels;
  final double maxX;
  final AppChartPalette palette;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double leftReserve = 56;
        final double plotWidth = math.max(
          40,
          constraints.maxWidth - leftReserve,
        );
        final double barWidth = view.isEmpty
            ? 1
            : (plotWidth / view.length * 0.7).clamp(1.0, 12.0);
        final double interval = maxX <= 4 ? 1 : (maxX / 4).ceilToDouble();
        return BarChart(
          BarChartData(
            minY: 0,
            maxY: data.maxVolume <= 0 ? 1 : data.maxVolume * 1.15,
            alignment: BarChartAlignment.spaceBetween,
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            barTouchData: BarTouchData(enabled: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: const AxisTitles(
                sideTitles: SideTitles(
                  showTitles: false,
                  reservedSize: leftReserve,
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 22,
                  interval: interval,
                  getTitlesWidget: (double value, TitleMeta meta) {
                    final int index = value.round();
                    if (index < 0 || index >= labels.length) {
                      return const SizedBox.shrink();
                    }
                    final String label = labels[index];
                    if (label.isEmpty) return const SizedBox.shrink();
                    return SideTitleWidget(
                      meta: meta,
                      child: Text(
                        label,
                        style: TextStyle(color: palette.text, fontSize: 10.5),
                      ),
                    );
                  },
                ),
              ),
            ),
            barGroups: <BarChartGroupData>[
              for (int i = 0; i < view.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: <BarChartRodData>[
                    BarChartRodData(
                      toY: view[i].volume,
                      width: barWidth,
                      color: view[i].volume <= 0
                          ? Colors.transparent
                          : (view[i].up
                                ? palette.volumeUp
                                : palette.volumeDown),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ],
                ),
            ],
          ),
          duration: Duration.zero,
        );
      },
    );
  }
}

// --- Chart helpers ---------------------------------------------------------

List<_ChartPoint> _samplePoints(List<_ChartPoint> points, int maxPoints) {
  if (points.length <= maxPoints) return points;
  final int step = (points.length / maxPoints).ceil();
  final List<_ChartPoint> sampled = <_ChartPoint>[];
  for (int i = 0; i < points.length; i += step) {
    sampled.add(points[i]);
  }
  if (sampled.last.x != points.last.x) sampled.add(points.last);
  return sampled;
}

FlGridData _gridData(AppChartPalette palette, _ChartData data) {
  final double interval = math.max((data.maxY - data.minY) / 4, 0.0001);
  return FlGridData(
    show: true,
    drawVerticalLine: false,
    horizontalInterval: interval,
    getDrawingHorizontalLine: (double _) =>
        FlLine(color: palette.grid, strokeWidth: 1),
  );
}

FlTitlesData _titlesData(
  BuildContext context, {
  required AppChartPalette palette,
}) {
  return FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    bottomTitles: const AxisTitles(
      sideTitles: SideTitles(showTitles: false, reservedSize: 22),
    ),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 56,
        getTitlesWidget: (double value, TitleMeta meta) => SideTitleWidget(
          meta: meta,
          child: Text(
            _axisPrice(value),
            style: TextStyle(color: palette.text, fontSize: 10.5),
          ),
        ),
      ),
    ),
  );
}

String _axisPrice(double value) {
  if (value.abs() >= 10000) {
    return NumberFormat.compact(locale: 'it_IT').format(value);
  }
  return NumberFormat('#,##0.00', 'it_IT').format(value);
}

String _formatCandleTime(dynamic raw, {required bool intraday}) {
  final DateTime? time = _parseCandleTime(raw);
  if (time == null) return '';
  return intraday
      ? DateFormat('HH:mm').format(time)
      : DateFormat('dd/MM').format(time);
}

DateTime? _parseCandleTime(dynamic raw) {
  if (raw is int) {
    final int millis = raw > 1000000000000 ? raw : raw * 1000;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }
  if (raw is double && raw.isFinite) {
    final int value = raw.round();
    final int millis = value > 1000000000000 ? value : value * 1000;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }
  if (raw is String) {
    final DateTime? parsed = DateTime.tryParse(raw);
    if (parsed != null) return parsed;
    final int? epoch = int.tryParse(raw);
    if (epoch != null) {
      final int millis = epoch > 1000000000000 ? epoch : epoch * 1000;
      return DateTime.fromMillisecondsSinceEpoch(millis);
    }
  }
  return null;
}

String _flagFor(String market) {
  return switch (market) {
    'IT' => '🇮🇹',
    'EU' => '🇪🇺',
    _ => '🇺🇸',
  };
}

String _signedNumber(num value) {
  final String formatted = NumberFormat('#,##0.00', 'it_IT').format(value);
  return value > 0 ? '+$formatted' : formatted;
}
