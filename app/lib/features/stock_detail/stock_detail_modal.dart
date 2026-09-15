import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsRole;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
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
import '../../widgets/app_callout.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_delta.dart';
import '../../widgets/app_key_value.dart';
import '../../widgets/app_market_tag.dart';
import '../../widgets/app_segmented.dart';
import '../../widgets/badges.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/range_bar.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/stat_card.dart';
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

/// Etichette accessibili dei timeframe (tooltip del controllo segmentato).
const Map<String, String> _timeframeTooltips = <String, String>{
  '1G': 'Ultima giornata',
  '1S': 'Ultima settimana',
  '1M': 'Ultimo mese',
  '6M': 'Ultimi 6 mesi',
  '1A': 'Ultimo anno',
  '5A': 'Ultimi 5 anni',
};

/// Sezioni della scheda titolo (linguaggio Registro: icona Material, niente
/// emoji nei titoli).
enum _StockTab {
  /// Grafico, dati di mercato, indicatori e fondamentali.
  dettagli(label: 'Dettagli', icon: Icons.show_chart),

  /// Analisi Gemini on-demand.
  analisi(label: 'Analisi IA', icon: Icons.auto_awesome),

  /// Feed notizie del titolo (non ancora esposto dall'API).
  notizie(label: 'Notizie', icon: Icons.newspaper);

  const _StockTab({required this.label, required this.icon});

  /// Etichetta del segmento.
  final String label;

  /// Icona Material del segmento.
  final IconData icon;
}

/// Apre la scheda titolo (stock detail) di [ticker].
///
/// Contenitore adattivo del linguaggio Registro: dialogo centrato (max 720,
/// raggio 10, ombra ampia) sopra 640px, bottom sheet con maniglia e barra
/// azioni fissa sotto 640px. [onChanged] viene chiamato dopo mutazioni che
/// possono interessare la pagina chiamante (es. aggiunta in Watchlist).
Future<void> showStockDetail(
  BuildContext context,
  String ticker, {
  VoidCallback? onChanged,
}) {
  final String normalized = ticker.trim().toUpperCase();
  if (normalized.isEmpty) return Future<void>.value();

  final AppTokens t = context.tokens;
  if (context.isCompact) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: t.surface,
      barrierColor: t.scrim,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadii.sheet),
        ),
      ),
      builder: (BuildContext sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.88,
        ),
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
    barrierColor: t.scrim,
    builder: (BuildContext dialogContext) => Dialog(
      // La superficie (fondo, bordo, ombra ampia) è dipinta dal DecoratedBox:
      // il Material del Dialog resta trasparente per non sovrapporre ombre.
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.sheet),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(AppRadii.sheet),
          border: Border.all(color: t.border),
          boxShadow: t.shadowLg,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.sheet),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 720,
              maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.9,
            ),
            child: _StockDetailModal(
              ticker: normalized,
              onChanged: onChanged,
            ),
          ),
        ),
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

/// Maniglia del bottom sheet: 36×4 su `track`, solo affordance di trascinamento.
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s8, bottom: AppSpacing.s2),
      child: Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: context.tokens.track,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
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

  /// Cache candele per timeframe API (`1d`, `1w`, ...): il cambio pill mostra
  /// subito l'ultimo dato noto (niente spinner) e rifresha in silenzio.
  /// Memoria trascurabile (6 serie al massimo per l'apertura del modal).
  final Map<String, List<Candle>> _candleCache = <String, List<Candle>>{};

  _StockTab _tab = _StockTab.dettagli;

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

  /// Carica le candele del timeframe selezionato con cache per-timeframe.
  ///
  /// Se il timeframe è già in cache lo mostra subito (niente spinner) e
  /// rifresha in silenzio; altrimenti mostra lo spinner. La generation guard
  /// scarta le risposte stale (cambio pill durante il fetch), come prima.
  Future<void> _loadCandles() async {
    final int generation = ++_chartGeneration;
    final String timeframe = _timeframes[_timeframe]!;
    final List<Candle>? cached = _candleCache[timeframe];
    if (cached != null) {
      setState(() {
        _candles = cached;
        _candlesLoading = false;
        _candlesFailed = false;
      });
    } else {
      setState(() {
        _candles = const <Candle>[];
        _candlesLoading = true;
        _candlesFailed = false;
      });
    }
    try {
      final List<Candle> data = await ref
          .read(stocksApiProvider)
          .candles(widget.ticker, timeframe);
      if (!mounted || generation != _chartGeneration) return;
      _candleCache[timeframe] = data;
      setState(() {
        _candles = data;
        _candlesLoading = false;
        _candlesFailed = false;
      });
    } catch (_) {
      if (!mounted || generation != _chartGeneration) return;
      setState(() {
        // Con un cached visibile non si entra in stato failed: resta il dato
        // precedente e il prossimo cambio pill riprova in silenzio.
        if (cached == null) {
          _candles = const <Candle>[];
          _candlesFailed = true;
        }
        _candlesLoading = false;
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
                  ? '${widget.ticker} è già in Mercati.'
                  : '${widget.ticker} aggiunto a Mercati!'),
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
        message: 'Errore durante il salvataggio in Mercati.',
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
    final bool compact = context.isCompact;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (compact) const _SheetHandle(),
        _buildHeader(context),
        _buildTabStrip(context),
        Flexible(
          child: Scrollbar(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Semantics(
                container: true,
                role: SemanticsRole.tabPanel,
                child: KeyedSubtree(
                  key: ValueKey<_StockTab>(_tab),
                  child: _buildTabPanel(context),
                ),
              ),
            ),
          ),
        ),
        if (compact) _buildStickyActions(context),
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
        : (_detailsLoading ? 'Caricamento dati…' : widget.ticker);
    final bool loaded = !_detailsLoading;
    final double? changePercent = details?.changePercent?.toDouble();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.borderSubtle)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
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
                    Text(
                      widget.ticker,
                      style: AppText.mono(
                        context,
                        size: 17,
                        weight: FontWeight.w700,
                      ),
                    ),
                    AppMarketTag.forTicker(
                      widget.ticker,
                      market: market,
                      tooltip: 'Mercato $market',
                    ),
                    if (_heldHolding != null)
                      const AppBadge(
                        label: 'IN PORTAFOGLIO',
                        tone: BadgeTone.success,
                        icon: Icon(Icons.work_outline),
                      ),
                    if (details?.stale == true)
                      const AppBadge(
                        label: 'CACHE',
                        tone: BadgeTone.warning,
                        tooltip:
                            'Prezzo non aggiornato: dato servito dalla cache.',
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s4),
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
              if (!loaded)
                const SkeletonBox(width: 88, height: 20)
              else
                Text(
                  _currencyText(details?.currentPrice),
                  style: AppText.mono(
                    context,
                    size: 19,
                    weight: FontWeight.w700,
                  ),
                ),
              const SizedBox(height: AppSpacing.s4),
              if (!loaded)
                const SkeletonBox(width: 64, height: 12)
              else if (changePercent != null)
                AppDelta(
                  value: changePercent,
                  suffix: '%',
                  size: 12.5,
                  semanticsLabel: 'Variazione odierna',
                )
              else
                Text(_dash, style: AppText.delta(context)),
            ],
          ),
          AppIconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Chiudi finestra',
            semanticLabel: 'Chiudi la scheda titolo',
            bordered: false,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabStrip(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool compact = context.isCompact;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: compact ? AppSpacing.s8 : AppSpacing.s10,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: AppSegmented<_StockTab>(
        expand: true,
        dense: compact,
        selected: _tab,
        semanticsLabel: 'Sezioni della scheda titolo',
        onSelected: (_StockTab value) => setState(() => _tab = value),
        segments: <AppSegment<_StockTab>>[
          for (final _StockTab tab in _StockTab.values)
            AppSegment<_StockTab>(
              value: tab,
              label: tab.label,
              icon: tab.icon,
            ),
        ],
      ),
    );
  }

  Widget _buildTabPanel(BuildContext context) {
    return switch (_tab) {
      _StockTab.dettagli => _buildDettagliTab(context),
      _StockTab.analisi => _buildAnalisiTab(context),
      _StockTab.notizie => _buildNotizieTab(context),
    };
  }

  // --- Tab 1: dettagli ----------------------------------------------------

  Widget _buildDettagliTab(BuildContext context) {
    final AppTokens t = context.tokens;
    final StockDetails? details = _details;
    final TechnicalIndicators? tech = details?.technical;
    final Holding? held = _heldHolding;
    final double? low = details?.fiftyTwoWeekLow;
    final double? high = details?.fiftyTwoWeekHigh;
    final num? rawPct = details?.fiftyTwoWeekPct;
    final double position = (rawPct == null || !rawPct.isFinite)
        ? 50
        : rawPct.toDouble().clamp(0, 100).toDouble();
    final double? dividendYield = details?.dividendYield;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (held != null) ...<Widget>[
          _HeldPositionCallout(holding: held),
          const SizedBox(height: AppSpacing.s12),
        ],
        _buildChartCard(context),
        if (!context.isCompact) ...<Widget>[
          const SizedBox(height: AppSpacing.s10),
          _buildActions(context),
        ],
        const SizedBox(height: AppSpacing.s12),
        if (_detailsLoading) ...<Widget>[
          const _AdaptiveSplit(
            left: SkeletonCard(height: 150),
            right: SkeletonCard(height: 150),
          ),
          const SizedBox(height: AppSpacing.s12),
          const _AdaptiveSplit(
            left: SkeletonCard(height: 176),
            right: SkeletonCard(height: 176),
          ),
        ] else ...<Widget>[
          _AdaptiveSplit(
            left: _InfoCard(
              title: 'Indicatori tecnici',
              icon: Icons.speed,
              children: <Widget>[
                AppKeyValue(
                  label: 'RSI (14)',
                  value: _numberText(tech?.rsi14),
                  trailing: AppBadge(
                    label: (tech?.rsiStatus?.isNotEmpty ?? false)
                        ? tech!.rsiStatus!
                        : 'Neutro',
                    tone: _rsiTone(tech?.rsiBadge),
                  ),
                ),
                AppKeyValue(
                  label: 'SMA 20',
                  value: _currencyText(tech?.sma20),
                ),
                AppKeyValue(
                  label: 'SMA 50',
                  value: _currencyText(tech?.sma50),
                ),
                AppKeyValue(
                  label: 'Trend',
                  value: (tech?.trend?.isNotEmpty ?? false)
                      ? tech!.trend!
                      : 'Neutro',
                  divider: false,
                  valueColor: t.primary,
                ),
              ],
            ),
            right: AppCard(
              dense: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const AppCardHeader(
                    title: 'Range 52 settimane',
                    icon: Icons.straighten,
                  ),
                  const SizedBox(height: AppSpacing.s10),
                  RangeBar(
                    positionPercent: position,
                    lowLabel: 'Min: ${_currencyText(low)}',
                    highLabel: 'Max: ${_currencyText(high)}',
                    showPosition: true,
                    minWidth: 180,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          _AdaptiveSplit(
            left: _InfoCard(
              title: 'Dati di mercato',
              icon: Icons.bar_chart,
              children: <Widget>[
                AppKeyValue(
                  label: 'Prezzo prec.',
                  value: _currencyText(details?.previousClose),
                ),
                AppKeyValue(
                  label: 'Variazione',
                  valueWidget: (details?.changePercent == null)
                      ? null
                      : AppDelta(
                          value: details!.changePercent!.toDouble(),
                          suffix: '%',
                          size: 13,
                          semanticsLabel: 'Variazione odierna',
                        ),
                ),
                AppKeyValue(
                  label: 'Min giorno',
                  value: _currencyText(details?.dayLow),
                ),
                AppKeyValue(
                  label: 'Max giorno',
                  value: _currencyText(details?.dayHigh),
                ),
                AppKeyValue(
                  label: 'Volume',
                  value: _compactText(details?.volume),
                ),
                AppKeyValue(
                  label: 'Volume medio',
                  value: _compactText(details?.avgVolume),
                  divider: false,
                ),
              ],
            ),
            right: _InfoCard(
              title: 'Fondamentali',
              icon: Icons.account_balance,
              children: <Widget>[
                AppKeyValue(
                  label: 'Capitalizzazione',
                  value: _compactText(details?.marketCap),
                ),
                AppKeyValue(
                  label: 'P/E (trailing)',
                  value: _numberText(details?.peRatio),
                ),
                AppKeyValue(
                  label: 'EPS',
                  value: _currencyText(details?.eps),
                ),
                AppKeyValue(
                  label: 'Beta',
                  value: _numberText(details?.beta),
                ),
                AppKeyValue(
                  label: 'Dividend yield',
                  value: dividendYield == null
                      ? '$_dash%'
                      : '${_numberText(dividendYield)}%',
                ),
                AppKeyValue(
                  label: 'Settore',
                  value: (details?.sector?.trim().isNotEmpty ?? false)
                      ? details!.sector!
                      : _dash,
                ),
                AppKeyValue(
                  label: 'Industria',
                  value: (details?.industry?.trim().isNotEmpty ?? false)
                      ? details!.industry!
                      : _dash,
                  divider: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          AppCard(
            dense: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const AppCardHeader(
                  title: 'Descrizione',
                  icon: Icons.notes,
                  dense: true,
                ),
                const SizedBox(height: AppSpacing.s8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 132),
                  child: SingleChildScrollView(
                    child: Text(
                      (details?.summary?.trim().isNotEmpty ?? false)
                          ? details!.summary!
                          : 'Nessuna descrizione disponibile.',
                      style: AppText.small(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Card del grafico: controlli, tela del chart e legenda.
  Widget _buildChartCard(BuildContext context) {
    final AppTokens t = context.tokens;
    final AppChartPalette palette = t.chart;
    final bool compact = context.isCompact;
    final double chartHeight = compact ? 240 : 320;
    final double volumeHeight = chartHeight * 0.22;
    // Il prezzo occupa l'altezza residua sopra il volume e il gap tra i due.
    final double priceHeight =
        chartHeight - volumeHeight - AppSpacing.s6;
    final bool intraday = _timeframe == '1G' || _timeframe == '1S';

    final Widget chart;
    if (_candlesLoading && _candles.isEmpty) {
      chart = const Center(child: AppSpinner());
    } else if (_candles.isEmpty) {
      chart = EmptyState(
        icon: const Icon(Icons.show_chart),
        message: _candlesFailed
            ? 'Dati non disponibili per questo intervallo.'
            : 'Nessun dato disponibile.',
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

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildTimeframeControls(context),
          const SizedBox(height: AppSpacing.s10),
          // Il grafico sta sulla superficie del pannello: le candele rialziste
          // "vuote" (`candleUpFill` = superficie) restano leggibili come
          // contorni anche senza colore.
          SizedBox(height: chartHeight, child: chart),
          const SizedBox(height: AppSpacing.s8),
          _buildChartLegend(context),
        ],
      ),
    );
  }

  Widget _buildTimeframeControls(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.s6,
      runSpacing: AppSpacing.s6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        for (final String label in _timeframes.keys)
          AppPill(
            label: label,
            selected: _timeframe == label,
            tooltip: _timeframeTooltips[label],
            onPressed: () {
              if (_timeframe == label) return;
              setState(() => _timeframe = label);
              _loadCandles();
            },
          ),
        const SizedBox(width: AppSpacing.s4),
        AppPill(
          label: 'Area',
          icon: const Icon(Icons.show_chart),
          selected: !_candleMode,
          onPressed: () => setState(() => _candleMode = false),
        ),
        AppPill(
          label: 'Candele',
          icon: const Icon(Icons.candlestick_chart),
          selected: _candleMode,
          onPressed: () => setState(() => _candleMode = true),
        ),
      ],
    );
  }

  Widget _buildChartLegend(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool hasAvg = (_heldHolding?.avgPurchasePrice ?? 0) > 0;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: AppSpacing.s12,
      runSpacing: AppSpacing.s4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        if (hasAvg)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _DashedSwatch(color: t.chart.breakeven),
              const SizedBox(width: AppSpacing.s6),
              Text(
                'Prezzo medio di carico',
                style: AppText.caption(context),
              ),
            ],
          ),
        Text('Volumi in basso', style: AppText.caption(context)),
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: AppSpacing.s8,
      runSpacing: AppSpacing.s8,
      children: <Widget>[
        AppButton(
          label: 'Salva in Mercati',
          icon: const Icon(Icons.bookmark_add_outlined),
          variant: AppButtonVariant.ghost,
          size: AppButtonSize.sm,
          loading: _addingToWatchlist,
          loadingLabel: 'Salvataggio…',
          onPressed: _addingToWatchlist ? null : _addToWatchlist,
        ),
        AppButton(
          label: 'Aggiungi al portafoglio',
          icon: const Icon(Icons.add),
          size: AppButtonSize.sm,
          onPressed: _addToPortfolio,
        ),
      ],
    );
  }

  /// Barra azioni fissa in fondo al bottom sheet (<640px).
  Widget _buildStickyActions(BuildContext context) {
    final AppTokens t = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: AppButton(
                  label: 'Mercati',
                  icon: const Icon(Icons.bookmark_add_outlined),
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.md,
                  loading: _addingToWatchlist,
                  loadingLabel: 'Salvataggio…',
                  tooltip: '${widget.ticker} in Mercati',
                  onPressed: _addingToWatchlist ? null : _addToWatchlist,
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: AppButton(
                  label: 'Portafoglio',
                  icon: const Icon(Icons.add),
                  size: AppButtonSize.md,
                  semanticLabel: 'Aggiungi ${widget.ticker} al portafoglio',
                  tooltip: 'Aggiungi al portafoglio',
                  onPressed: _addToPortfolio,
                ),
              ),
            ],
          ),
        ),
      ),
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

  // --- Tab 2: analisi IA --------------------------------------------------

  Widget _buildAnalisiTab(BuildContext context) {
    if (_aiResult != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildAiToolbar(context),
          const SizedBox(height: AppSpacing.s12),
          _AiResultView(
            analysis: _aiResult!,
            currency: _currency,
            holdingCurrency: _heldHolding?.currency ?? _currency,
          ),
        ],
      );
    }

    if (_aiLoading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: SkeletonLine(width: 190),
          ),
          SizedBox(height: AppSpacing.s14),
          SkeletonCard(height: 96),
          SizedBox(height: AppSpacing.s12),
          SkeletonCard(height: 170),
        ],
      );
    }

    if (_aiError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppCallout(
            tone: AppCalloutTone.danger,
            accent: true,
            icon: const Icon(Icons.error_outline),
            body:
                "Impossibile completare l'analisi per ${widget.ticker}: $_aiError",
            liveRegion: true,
          ),
          const SizedBox(height: AppSpacing.s10),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              label: 'Riprova',
              icon: const Icon(Icons.refresh),
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.sm,
              onPressed: _runAi,
            ),
          ),
        ],
      );
    }

    return EmptyState(
      icon: const Icon(Icons.auto_awesome),
      title: 'Analisi Gemini 3.8 Flash',
      message:
          'Interroga il modello su fondamentali, indicatori tecnici, '
          'catalizzatori e posizione in portafoglio.',
      actions: <Widget>[
        AppButton(
          label: 'Elabora analisi',
          icon: const Icon(Icons.auto_awesome),
          size: AppButtonSize.sm,
          onPressed: _runAi,
        ),
      ],
    );
  }

  Widget _buildAiToolbar(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            'Analisi Gemini 3.8 Flash',
            style: AppText.caption(context),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: AppSpacing.s10),
        AppButton(
          label: _aiAttempted ? 'Rielabora' : 'Elabora analisi',
          icon: const Icon(Icons.refresh),
          variant: AppButtonVariant.ghost,
          size: AppButtonSize.sm,
          loading: _aiLoading,
          loadingLabel: 'Analisi…',
          onPressed: _aiLoading ? null : _runAi,
        ),
      ],
    );
  }

  // --- Tab 3: notizie -----------------------------------------------------

  /// Il backend non espone (ancora) un feed notizie per il titolo: la sezione
  /// resta uno stato vuoto esplicito, senza inventare dati. Quando `news`
  /// arriverà nel deep dive basterà sostituire [EmptyState] con le righe
  /// `AppKeyValue` (titolo + tag fonte).
  Widget _buildNotizieTab(BuildContext context) {
    return const EmptyState(
      icon: Icon(Icons.newspaper),
      title: 'Notizie',
      message:
          'Il feed notizie non è ancora collegato a questo ambiente. '
          'Quando sarà disponibile, le notizie del titolo compariranno qui '
          'con la fonte.',
    );
  }
}

// --- Reusable modal pieces -------------------------------------------------

/// Posizione detenuta, in testa alla sezione Dettagli: righe da registro
/// (quantità, carico medio, P&L) con striscia d'accento sul segno del P&L.
class _HeldPositionCallout extends StatelessWidget {
  const _HeldPositionCallout({required this.holding});

  final Holding holding;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool up = holding.pnlPercent >= 0;
    return AppCallout(
      accent: true,
      accentColor: up ? t.success : t.danger,
      padding: const EdgeInsets.all(AppSpacing.s10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.work_outline,
                size: AppSizes.iconSm,
                color: t.textSecondary,
              ),
              const SizedBox(width: AppSpacing.s6),
              Expanded(
                child: Text(
                  'Posizione in portafoglio',
                  style: AppText.microFor(t),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              AppDelta(
                value: holding.pnlPercent.toDouble(),
                suffix: '%',
                size: 12.5,
                semanticsLabel: 'P&L in percentuale',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s6),
          AppKeyValue(
            label: 'Quantità',
            value: NumberFormat('#,##0.####', 'it_IT').format(holding.quantity),
            dense: true,
          ),
          AppKeyValue(
            label: 'Carico medio',
            value: formatCurrency(
              holding.avgPurchasePrice,
              currency: holding.currency,
            ),
            dense: true,
          ),
          AppKeyValue(
            label: 'P&L',
            value: formatCurrency(
              holding.pnlAbsolute,
              currency: holding.currency,
            ),
            dense: false,
            valueColor: up ? t.successText : t.danger,
          ),
        ],
      ),
    );
  }
}

/// Pannello informativo a righe etichetta/valore (dati, fondamentali).
class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      dense: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AppCardHeader(title: title, icon: icon),
          const SizedBox(height: AppSpacing.s8),
          ...children,
        ],
      ),
    );
  }
}

/// Spezza i contenuti in due colonne sopra 560px, altrimenti li impila.
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

// --- AI result --------------------------------------------------------------

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
    final String? verdict = analysis.technicalVerdict;

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
            const SizedBox(width: AppSpacing.s10),
            Expanded(
              child: Text(
                'Confidenza: ${(analysis.confidence?.isNotEmpty ?? false) ? analysis.confidence! : 'MEDIA'}'
                ' · Orizzonte: ${(analysis.timeframe?.isNotEmpty ?? false) ? analysis.timeframe! : 'Medio termine'}',
                textAlign: TextAlign.right,
                style: AppText.caption(context),
              ),
            ),
          ],
        ),
        if (holding != null) ...<Widget>[
          const SizedBox(height: AppSpacing.s12),
          AppCallout(
            tone: AppCalloutTone.info,
            accent: true,
            padding: const EdgeInsets.all(AppSpacing.s10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.work_outline,
                      size: AppSizes.iconSm,
                      color: t.primary,
                    ),
                    const SizedBox(width: AppSpacing.s6),
                    Expanded(
                      child: Text(
                        'Posizione nel tuo portafoglio',
                        style: AppText.microFor(t).copyWith(color: t.primary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s8),
                    AppDelta(
                      value: holding.currentPnlPct,
                      suffix: '%',
                      size: 12.5,
                      semanticsLabel: 'P&L della posizione',
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s6),
                AppKeyValue(
                  label: 'Azioni',
                  value: NumberFormat('#,##0.####', 'it_IT').format(
                    holding.quantity,
                  ),
                  dense: true,
                ),
                AppKeyValue(
                  label: 'Carico medio',
                  value: formatCurrency(
                    holding.avgPurchasePrice,
                    currency: holdingCurrency,
                  ),
                  dense: true,
                ),
                AppKeyValue(
                  label: 'P&L',
                  value: formatCurrency(
                    holding.currentPnlAbs,
                    currency: holdingCurrency,
                  ),
                  dense: false,
                  valueColor: holding.currentPnlPct >= 0
                      ? t.successText
                      : t.danger,
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.s12),
        _AdaptiveSplit(
          left: StatCard(
            label: 'Target price',
            value: formatCurrency(analysis.targetPrice, currency: currency),
            delta: upside,
            deltaLabel: '%',
            smallValue: true,
            icon: const Icon(Icons.flag_outlined),
            tooltip: 'Prezzo obiettivo stimato dal modello',
          ),
          right: StatCard(
            label: 'Stop loss consigliato',
            value: formatCurrency(analysis.stopLoss, currency: currency),
            smallValue: true,
            valueColor: t.danger,
            icon: const Icon(Icons.shield_outlined),
            tooltip: 'Livello di uscita per limitare le perdite',
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        _AiSection(
          title: 'Sintesi',
          icon: Icons.notes,
          body: analysis.summary,
        ),
        const SizedBox(height: AppSpacing.s10),
        _AdaptiveSplit(
          left: AppCard(
            accent: true,
            accentColor: t.success,
            child: _CaseBlock(
              title: 'Bull case e punti di forza',
              body: analysis.bullCase,
              titleColor: t.success,
            ),
          ),
          right: AppCard(
            accent: true,
            accentColor: t.danger,
            child: _CaseBlock(
              title: 'Bear case e rischi',
              body: analysis.bearCase,
              titleColor: t.danger,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s10),
        _AiSection(
          title: 'Strategia operativa',
          icon: Icons.route,
          body: analysis.operationalStrategy,
        ),
        if (verdict != null && verdict.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.s10),
          _AiSection(
            title: 'Verdetto tecnico',
            icon: Icons.speed,
            body: verdict,
          ),
        ],
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

/// Blocco di testo dell'analisi IA dentro un [AppCard] intitolato.
class _AiSection extends StatelessWidget {
  const _AiSection({
    required this.title,
    required this.icon,
    required this.body,
  });

  final String title;
  final IconData icon;
  final String? body;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      dense: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AppCardHeader(title: title, icon: icon, dense: true),
          const SizedBox(height: AppSpacing.s8),
          Text(
            (body?.trim().isNotEmpty ?? false) ? body! : _dash,
            style: AppText.small(context),
          ),
        ],
      ),
    );
  }
}

class _CaseBlock extends StatelessWidget {
  const _CaseBlock({
    required this.title,
    required this.body,
    required this.titleColor,
  });

  final String title;
  final String? body;
  final Color titleColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          title.toUpperCase(),
          style: AppText.micro(context).copyWith(color: titleColor),
        ),
        const SizedBox(height: AppSpacing.s6),
        Text(
          (body?.trim().isNotEmpty ?? false) ? body! : _dash,
          style: AppText.small(context),
        ),
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
      return const EmptyState(
        icon: Icon(Icons.show_chart),
        message: 'Nessun dato disponibile.',
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
                  avgPrice: avgPrice,
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
    final AppTokens t = context.tokens;
    final TextStyle tooltipStyle = AppText.mono(
      context,
      size: 11,
      color: t.textInverse,
    );
    final LineChartBarData priceBar = LineChartBarData(
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
    );
    final double? avg = avgPrice;
    final LineChartBarData? avgBar = (avg == null || !avg.isFinite)
        ? null
        : LineChartBarData(
            spots: <FlSpot>[FlSpot(0, avg), FlSpot(maxX, avg)],
            isCurved: false,
            barWidth: 1.5,
            color: palette.breakeven,
            dashArray: const <int>[6, 4],
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: false),
          );

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX,
        minY: data.minY,
        maxY: data.maxY,
        gridData: _gridData(palette),
        borderData: FlBorderData(show: false),
        titlesData: _titlesData(context, palette: palette),
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (LineBarSpot _) => t.surfaceInverse,
            tooltipBorderRadius: BorderRadius.circular(AppRadii.control),
            getTooltipItems: (List<LineBarSpot> spots) => <LineTooltipItem?>[
              for (final LineBarSpot spot in spots)
                LineTooltipItem(_axisPrice(spot.y), tooltipStyle),
            ],
          ),
          // Mirino tratteggiato sul punto toccato (colore `crosshair`).
          getTouchedSpotIndicator:
              (LineChartBarData bar, List<int> indexes) {
                if (!identical(bar, priceBar)) {
                  return const <TouchedSpotIndicatorData>[];
                }
                return <TouchedSpotIndicatorData>[
                  for (final int _ in indexes)
                    TouchedSpotIndicatorData(
                      FlLine(
                        color: palette.crosshair,
                        strokeWidth: 1,
                        dashArray: const <int>[4, 3],
                      ),
                      FlDotData(
                        show: true,
                        getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                          radius: 2.5,
                          color: palette.line,
                          strokeColor: palette.line,
                          strokeWidth: 1,
                        ),
                      ),
                    ),
                ];
              },
        ),
        lineBarsData: <LineChartBarData>[
          priceBar,
          ?avgBar,
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
    required this.avgPrice,
  });

  final _ChartData data;
  final List<_ChartPoint> view;
  final double maxX;
  final AppChartPalette palette;
  final double? avgPrice;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final TextStyle tooltipStyle = AppText.mono(
      context,
      size: 11,
      color: t.textInverse,
    );

    final Widget chart = CandlestickChart(
      CandlestickChartData(
        minX: 0,
        maxX: maxX,
        minY: data.minY,
        maxY: data.maxY,
        gridData: _gridData(palette),
        borderData: FlBorderData(show: false),
        titlesData: _titlesData(context, palette: palette),
        candlestickPainter: DefaultCandlestickPainter(
          // Rialziste vuote (contorno, corpo = superficie), ribassiste piene:
          // la direzione resta leggibile anche senza colore.
          candlestickStyleProvider: (CandlestickSpot spot, int _) {
            if (spot.isUp) {
              return CandlestickStyle(
                lineColor: palette.candleUpStroke,
                lineWidth: 1.2,
                bodyStrokeColor: palette.candleUpStroke,
                bodyStrokeWidth: 1,
                bodyFillColor: palette.candleUpFill,
                bodyWidth: 4,
                bodyRadius: 0.5,
              );
            }
            return CandlestickStyle(
              lineColor: palette.candleDownStroke,
              lineWidth: 1.2,
              bodyStrokeColor: palette.candleDownStroke,
              bodyStrokeWidth: 0,
              bodyFillColor: palette.candleDownFill,
              bodyWidth: 4,
              bodyRadius: 0.5,
            );
          },
        ),
        candlestickTouchData: CandlestickTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: CandlestickTouchTooltipData(
            getTooltipColor: (CandlestickSpot _) => t.surfaceInverse,
            tooltipBorderRadius: BorderRadius.circular(AppRadii.control),
            getTooltipItems:
                (FlCandlestickPainter painter, CandlestickSpot spot, int _) =>
                    CandlestickTooltipItem(
                      'A ${_axisPrice(spot.open)} · C ${_axisPrice(spot.close)}',
                      textStyle: tooltipStyle,
                    ),
          ),
        ),
        // Mirino tratteggiato (colore `crosshair`) su entrambi gli assi.
        touchedPointIndicator: AxisSpotIndicator(
          painter: AxisLinesIndicatorPainter(
            verticalLineProvider: (double x) => VerticalLine(
              x: x,
              color: palette.crosshair,
              strokeWidth: 1,
              dashArray: const <int>[4, 3],
            ),
            horizontalLineProvider: (double y) => HorizontalLine(
              y: y,
              color: palette.crosshair,
              strokeWidth: 1,
              dashArray: const <int>[4, 3],
            ),
          ),
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

    final double? avg = avgPrice;
    if (avg == null || !avg.isFinite) return chart;
    // Linea tratteggiata del prezzo medio di carico sopra le candele: overlay
    // senza tocchi, con gli stessi assi del chart sottostante per allinearsi.
    return Stack(
      children: <Widget>[
        chart,
        Positioned.fill(
          child: IgnorePointer(
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: maxX,
                minY: data.minY,
                maxY: data.maxY,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: _titlesData(context, palette: palette),
                lineTouchData: const LineTouchData(enabled: false),
                lineBarsData: <LineChartBarData>[
                  LineChartBarData(
                    spots: <FlSpot>[FlSpot(0, avg), FlSpot(maxX, avg)],
                    isCurved: false,
                    barWidth: 1.5,
                    color: palette.breakeven,
                    dashArray: const <int>[6, 4],
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: false),
                  ),
                ],
              ),
              duration: Duration.zero,
            ),
          ),
        ),
      ],
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
                        style: AppText.mono(
                          context,
                          size: 10.5,
                          weight: FontWeight.w500,
                          color: palette.text,
                        ),
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

/// Campione tratteggiato di legenda (riga di 18px nel colore della serie).
class _DashedSwatch extends StatelessWidget {
  const _DashedSwatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(18, 8),
      painter: _DashedSwatchPainter(color: color),
    );
  }
}

class _DashedSwatchPainter extends CustomPainter {
  const _DashedSwatchPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    const double dash = 4;
    const double gap = 3;
    double x = 0;
    final double y = size.height / 2;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, y),
        Offset(math.min(x + dash, size.width), y),
        paint,
      );
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_DashedSwatchPainter oldDelegate) =>
      oldDelegate.color != color;
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

FlGridData _gridData(AppChartPalette palette) {
  return FlGridData(
    show: true,
    drawVerticalLine: false,
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
            style: AppText.mono(
              context,
              size: 10.5,
              weight: FontWeight.w500,
              color: palette.text,
            ),
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
