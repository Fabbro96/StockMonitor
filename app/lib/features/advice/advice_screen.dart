import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/advice_api.dart';
import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/models/advice.dart';
import '../../core/models/dashboard.dart';
import '../../shell/topbar.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_callout.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_market_tag.dart';
import '../../widgets/app_segmented.dart';
import '../../widgets/badges.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/page_content.dart';
import '../../widgets/section_header.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/toast.dart';
import '../dashboard/widgets/market_status.dart';
import '../stock_detail/stock_detail_modal.dart';
import 'advice_card.dart';
import 'advice_dialogs.dart';
import 'advice_providers.dart';

/// Sezioni della pagina `Analisi` (nav interna ad ancore).
///
/// L'ordine riflette quello dei blocchi nella pagina: prima l'analisi
/// istantanea sul singolo titolo, poi la sezione macro (riassunto, guida,
/// filtri, archivio).
enum _AdviceView {
  /// Analisi istantanea su singolo titolo (input + report).
  singolo(label: 'Singolo titolo', icon: Icons.manage_search),

  /// Archivio macro: riassunto, guida, filtri e consigli raggruppati.
  macro(label: 'Macro', icon: Icons.public);

  const _AdviceView({required this.label, required this.icon});

  /// Etichetta del segmento.
  final String label;

  /// Icona Material del segmento.
  final IconData icon;
}

/// Schermata `Analisi & Consigli IA` (parità `advice.html`/`advice.js`).
///
/// Struttura: nav a segmenti (singolo titolo / macro) con azione di
/// generazione, analisi istantanea su singolo titolo, riassunto globale del
/// mercato, guida, filtri (giorno/mercato/azione + ricerca client-side),
/// archivio dei consigli raggruppato per data e paginazione `Carica Altri`.
/// La topbar porta i pallini di stato mercati.
class AdviceScreen extends ConsumerStatefulWidget {
  /// Crea la schermata Analisi.
  const AdviceScreen({super.key});

  @override
  ConsumerState<AdviceScreen> createState() => _AdviceScreenState();
}

class _AdviceScreenState extends ConsumerState<AdviceScreen> {
  late final TopbarActionsController _topbar;

  final TextEditingController _tickerController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  bool _analyzing = false;
  StockAnalysis? _analysis;
  String? _analysisError;
  bool _hasSearchText = false;
  final Set<int> _followBusy = <int>{};

  /// Sezione evidenziata nella nav: segue lo scroll (spy sulle ancore).
  _AdviceView _activeView = _AdviceView.singolo;

  /// Ancore di scroll delle due sezioni.
  final Map<_AdviceView, GlobalKey> _viewKeys = <_AdviceView, GlobalKey>{
    for (final _AdviceView view in _AdviceView.values) view: GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    _topbar = ref.read(topbarActionsProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted) return;
      _topbar.set(this, const <Widget>[_AdviceMarketStatusAction()]);
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _tickerController.dispose();
    _searchController.dispose();
    _topbar.clear(this);
    super.dispose();
  }

  // --- Navigazione interna -------------------------------------------------

  /// Scorre all'ancora della sezione [view] ed evidenzia il segmento.
  void _jumpTo(_AdviceView view) {
    setState(() => _activeView = view);
    final BuildContext? anchor = _viewKeys[view]?.currentContext;
    if (anchor == null) return;
    Scrollable.ensureVisible(
      anchor,
      alignment: 0,
      duration: AppMotion.effective(context, AppMotion.medium),
      curve: AppMotion.ease,
    );
  }

  /// Evidenzia la sezione con l'area visibile maggiore nel viewport
  /// ("table of contents" scroll-spy).
  bool _onScroll(ScrollNotification notification) {
    final RenderObject? viewport = notification.context?.findRenderObject();
    if (viewport is! RenderBox) return false;
    final double viewportTop = viewport.localToGlobal(Offset.zero).dy;
    final double viewportBottom = viewportTop + viewport.size.height;
    _AdviceView? current;
    double best = 0;
    for (final _AdviceView view in _AdviceView.values) {
      final RenderObject? anchor = _viewKeys[view]?.currentContext
          ?.findRenderObject();
      if (anchor is! RenderBox) continue;
      final double top = anchor.localToGlobal(Offset.zero).dy;
      final double bottom = top + anchor.size.height;
      final double visible =
          (bottom < viewportBottom ? bottom : viewportBottom) -
          (top > viewportTop ? top : viewportTop);
      if (visible > best) {
        best = visible;
        current = view;
      }
    }
    if (current != null && current != _activeView && mounted) {
      final _AdviceView next = current;
      setState(() => _activeView = next);
    }
    return false;
  }

  // --- Azioni -------------------------------------------------------------

  Future<void> _analyzeTicker() async {
    final String ticker = _tickerController.text.trim().toUpperCase();
    if (ticker.isEmpty) {
      showAppToast(
        context,
        message: 'Inserisci un ticker valido da analizzare',
        type: AppToastType.error,
      );
      return;
    }
    if (_analyzing) return;

    setState(() {
      _analyzing = true;
      _analysis = null;
      _analysisError = null;
    });
    // F7: risolve la valuta in parallelo all'analisi AI; il risultato parte
    // con EUR e si aggiorna quando `details` risponde (nessun render bloccato).
    ref.read(adviceCurrencyProvider(ticker).future).ignore();
    try {
      final StockAnalysis result = await ref
          .read(adviceApiProvider)
          .analyzeStock(ticker);
      if (!mounted) return;
      setState(() => _analysis = result);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _analysisError = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _analysisError = 'Errore durante l\'analisi');
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Future<void> _toggleFollow(Advice advice) async {
    final int? id = advice.id;
    if (id == null || _followBusy.contains(id)) return;
    setState(() => _followBusy.add(id));
    try {
      final bool followed = await ref.read(adviceApiProvider).toggleFollow(id);
      if (!mounted) return;
      ref.read(adviceListProvider.notifier).setFollowed(id, followed);
      showAppToast(
        context,
        message: followed ? 'Segnato come letto' : 'Segnato come non letto',
        type: AppToastType.success,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      showAppToast(context, message: error.message, type: AppToastType.error);
    } catch (_) {
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Errore durante l\'aggiornamento dello stato',
        type: AppToastType.error,
      );
    } finally {
      if (mounted) setState(() => _followBusy.remove(id));
    }
  }

  Future<void> _loadMore() async {
    try {
      await ref.read(adviceListProvider.notifier).loadMore();
    } on ApiException catch (error) {
      if (!mounted) return;
      showAppToast(context, message: error.message, type: AppToastType.error);
    } catch (_) {
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Errore nel caricamento dei consigli',
        type: AppToastType.error,
      );
    }
  }

  void _openStock(String ticker) {
    if (ticker.isEmpty) return;
    unawaited(showStockDetail(context, ticker));
  }

  void _onSearchChanged(String value) {
    final bool hasText = value.isNotEmpty;
    if (hasText != _hasSearchText) {
      setState(() => _hasSearchText = hasText);
    }
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      ref.read(adviceFiltersProvider.notifier).setQuery(value);
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    if (_hasSearchText) setState(() => _hasSearchText = false);
    ref.read(adviceFiltersProvider.notifier).setQuery('');
  }

  void _resetFilters() {
    _clearSearch();
    ref.read(adviceFiltersProvider.notifier).reset();
  }

  Future<void> _pickDate() async {
    final String? selected = await showAdviceDatePicker(
      context,
      initialDate: ref.read(adviceFiltersProvider).date,
    );
    if (selected == null || !mounted) return;
    ref.read(adviceFiltersProvider.notifier).setDate(selected);
  }

  String get _today => dateToApi(DateTime.now());

  String get _yesterday =>
      dateToApi(DateTime.now().subtract(const Duration(days: 1)));

  String _displayDate(String isoDate) {
    final DateTime? parsed = parseServerDate(isoDate);
    return parsed == null ? isoDate : formatDate(parsed);
  }

  String _errorMessage(Object error, String fallback) =>
      error is ApiException ? error.message : fallback;

  List<Advice> _filterByQuery(List<Advice> items, String query) {
    final String q = query.trim().toUpperCase();
    if (q.isEmpty) return items;
    return items
        .where(
          (Advice advice) =>
              advice.title.toUpperCase().contains(q) ||
              (advice.overview ?? '').toUpperCase().contains(q) ||
              (advice.strategy ?? '').toUpperCase().contains(q) ||
              advice.stocksAnalysis.any(
                (AdviceStockAnalysis stock) =>
                    stock.ticker.toUpperCase().contains(q) ||
                    stock.name.toUpperCase().contains(q),
              ),
        )
        .toList(growable: false);
  }

  // --- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<AdviceListState>>(adviceListProvider, (
      AsyncValue<AdviceListState>? previous,
      AsyncValue<AdviceListState> next,
    ) {
      final Object? error = next.error;
      if (error == null || identical(previous?.error, error)) return;
      if (!mounted) return;
      showAppToast(
        context,
        message: _errorMessage(error, 'Errore nel caricamento dei consigli'),
        type: AppToastType.error,
      );
    });

    final AdviceFilters filters = ref.watch(adviceFiltersProvider);
    final AsyncValue<AdviceListState> listAsync = ref.watch(adviceListProvider);
    final AsyncValue<List<Advice>> latestAsync = ref.watch(
      adviceLatestProvider,
    );
    final bool generating = ref.watch(adviceGenerationProvider);

    final AdviceListState? listState = listAsync.value;
    final List<Advice> items = listState?.items ?? const <Advice>[];
    final List<Advice> filtered = _filterByQuery(items, filters.query);
    final bool firstLoading = listAsync.isLoading && listState == null;
    final bool firstError = listAsync.hasError && listState == null;
    final bool refreshing = listAsync.isLoading && listState != null;

    return Column(
      children: <Widget>[
        _buildViewNav(),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: PageContent(
              padding: _bodyPadding(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  KeyedSubtree(
                    key: _viewKeys[_AdviceView.singolo],
                    child: _buildSingleStockCard(),
                  ),
                  const SizedBox(height: AppSpacing.s18),
                  Column(
                    key: _viewKeys[_AdviceView.macro],
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _buildMarketSummaryCard(filters, latestAsync),
                      const SizedBox(height: AppSpacing.s14),
                      _buildLegendCard(),
                      const SizedBox(height: AppSpacing.s14),
                      _buildFiltersCard(filters),
                      const SizedBox(height: AppSpacing.s14),
                      AppLoaderOverlay(
                        loading: generating || refreshing,
                        borderRadius: BorderRadius.circular(AppRadii.card),
                        child: _buildListSection(
                          listAsync,
                          filtered,
                          firstLoading,
                          firstError,
                        ),
                      ),
                      if (listState?.hasMore ?? false) ...<Widget>[
                        const SizedBox(height: AppSpacing.s18),
                        Center(
                          child: AppButton(
                            label: 'Carica Altri',
                            variant: AppButtonVariant.ghost,
                            loading: listState?.loadingMore ?? false,
                            loadingLabel: 'Caricamento...',
                            onPressed: _loadMore,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Nav interna pinnata: segmenti (singolo / macro) e generazione macro.
  Widget _buildViewNav() {
    final double pagePadding = AppSpacing.pagePadding(context.windowWidth);
    final bool compact = context.isCompact;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppTokens.contentMaxWidth),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            pagePadding,
            pagePadding,
            pagePadding,
            AppSpacing.s12,
          ),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final Widget segmented = AppSegmented<_AdviceView>(
                segments: <AppSegment<_AdviceView>>[
                  for (final _AdviceView view in _AdviceView.values)
                    AppSegment<_AdviceView>(
                      value: view,
                      label: view.label,
                      icon: view.icon,
                      tooltip: view == _AdviceView.singolo
                          ? 'Analisi istantanea su singolo titolo'
                          : 'Archivio macro e riassunto di mercato',
                    ),
                ],
                selected: _activeView,
                dense: compact,
                expand: compact,
                semanticsLabel: 'Sezioni analisi',
                onSelected: _jumpTo,
              );
              final Widget generate = const _AdviceGenerateButton();
              if (constraints.maxWidth < AppBreakpoints.compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    segmented,
                    const SizedBox(height: AppSpacing.s10),
                    generate,
                  ],
                );
              }
              return Row(
                children: <Widget>[
                  segmented,
                  const Spacer(),
                  generate,
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  EdgeInsets _bodyPadding() {
    final double pagePadding = AppSpacing.pagePadding(context.windowWidth);
    return EdgeInsets.fromLTRB(
      pagePadding,
      0,
      pagePadding,
      context.isCompact ? 28 : pagePadding,
    );
  }

  // --- Analisi singolo titolo --------------------------------------------

  Widget _buildSingleStockCard() {
    return AppCard(
      accent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SectionHeader(
            variant: SectionHeaderVariant.rule,
            overline: 'Analisi',
            icon: Icons.bolt_outlined,
            title: 'Analisi istantanea su singolo titolo',
            subtitle:
                'Report approfondito con Gemini 3.8 Flash: target price, '
                'stop loss, RSI, SMA e catalizzatori.',
          ),
          _buildTickerInput(),
          if (_analyzing) ...<Widget>[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.s22),
              child: Center(child: AppSpinner()),
            ),
          ] else if (_analysisError != null) ...<Widget>[
            AppCallout(
              tone: AppCalloutTone.danger,
              accent: true,
              icon: const Icon(Icons.error_outline),
              body: 'Errore analisi: $_analysisError',
              liveRegion: true,
            ),
          ] else if (_analysis != null) ...<Widget>[
            _buildSingleResult(_analysis!),
          ],
        ],
      ),
    );
  }

  Widget _buildTickerInput() {
    final Widget field = TextField(
      controller: _tickerController,
      textInputAction: TextInputAction.search,
      textCapitalization: TextCapitalization.characters,
      onSubmitted: (_) => _analyzeTicker(),
      style: AppText.small(context),
      decoration: const InputDecoration(
        hintText: 'Inserisci ticker (es. NVDA, AAPL, ENEL.MI, RACE.MI)...',
        prefixIcon: Icon(Icons.search, size: 16),
      ),
    );
    final Widget button = AppButton(
      label: 'Analizza titolo con IA',
      icon: const Icon(Icons.auto_awesome),
      loading: _analyzing,
      loadingLabel: 'Analisi in corso...',
      onPressed: _analyzing ? null : _analyzeTicker,
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              field,
              const SizedBox(height: AppSpacing.s10),
              button,
            ],
          );
        }
        return Row(
          children: <Widget>[
            Expanded(child: field),
            const SizedBox(width: AppSpacing.s10),
            button,
          ],
        );
      },
    );
  }

  Widget _buildSingleResult(StockAnalysis analysis) {
    final AppTokens t = context.tokens;
    final String actionLabel = (analysis.actionLabel ?? '').trim().isNotEmpty
        ? analysis.actionLabel!.trim()
        : analysis.action;
    final String? confidence = analysis.confidence?.trim();
    final String? timeframe = analysis.timeframe?.trim();
    final double? upside = analysis.upsidePotentialPct;
    // F7: valuta risolta dai details (fallback EUR finché non arriva).
    final String currency =
        ref.watch(adviceCurrencyProvider(analysis.ticker)).value ?? 'EUR';

    final List<InlineSpan> metaSpans = <InlineSpan>[
      if (confidence != null && confidence.isNotEmpty) ...<InlineSpan>[
        const TextSpan(text: 'Confidenza: '),
        TextSpan(
          text: confidence,
          style: TextStyle(color: t.primary, fontWeight: FontWeight.w700),
        ),
      ],
      if (confidence != null &&
          confidence.isNotEmpty &&
          timeframe != null &&
          timeframe.isNotEmpty)
        const TextSpan(text: ' • '),
      if (timeframe != null && timeframe.isNotEmpty) ...<InlineSpan>[
        const TextSpan(text: 'Orizzonte: '),
        TextSpan(
          text: timeframe,
          style: TextStyle(color: t.primary, fontWeight: FontWeight.w700),
        ),
      ],
    ];

    final Widget metrics = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Widget target = _metricBox(
          icon: Icons.track_changes,
          label: 'Target price stimato',
          value: formatCurrency(analysis.targetPrice, currency: currency),
          valueColor: t.primary,
          trailing: upside == null ? null : '(${formatPercent(upside)})',
          trailingColor: (upside ?? 0) >= 0 ? t.successText : t.danger,
        );
        final Widget stop = _metricBox(
          icon: Icons.shield_outlined,
          label: 'Stop loss prudenziale',
          value: (analysis.stopLoss ?? 0) > 0
              ? formatCurrency(analysis.stopLoss, currency: currency)
              : '--',
          valueColor: t.danger,
        );
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              target,
              const SizedBox(height: AppSpacing.s8),
              stop,
            ],
          );
        }
        // `IntrinsicHeight` perché la Row vive in una Column scrollabile
        // (altezza non limitata): senza, `stretch` chiederebbe altezza infinita.
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: target),
              const SizedBox(width: AppSpacing.s8),
              Expanded(child: stop),
            ],
          ),
        );
      },
    );

    final Widget bullBear = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Widget bull = _bulletCallout(
          icon: Icons.trending_up,
          title: 'Bull case & catalizzatori',
          text: analysis.bullCase,
          success: true,
        );
        final Widget bear = _bulletCallout(
          icon: Icons.trending_down,
          title: 'Bear case & rischi',
          text: analysis.bearCase,
          success: false,
        );
        if (constraints.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              bull,
              const SizedBox(height: AppSpacing.s8),
              bear,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: bull),
            const SizedBox(width: AppSpacing.s8),
            Expanded(child: bear),
          ],
        );
      },
    );

    final String? strategy = analysis.operationalStrategy?.trim();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s14),
      child: AppCallout(
        accent: true,
        accentColor: t.primary,
        accentWidth: 3,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Wrap(
              spacing: AppSpacing.s10,
              runSpacing: AppSpacing.s6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text(
                  analysis.ticker,
                  style: AppText.mono(
                    context,
                    size: 20,
                    weight: FontWeight.w700,
                    color: t.primary,
                  ),
                ),
                AppMarketTag.forTicker(analysis.ticker),
                if (analysis.name.trim().isNotEmpty)
                  Text(
                    analysis.name.trim(),
                    style: AppText.small(context)
                        .copyWith(color: t.textSecondary),
                  ),
                if (actionLabel.isNotEmpty)
                  AppBadge(
                    label: actionLabel,
                    tone: actionToneFor(analysis.action),
                  ),
              ],
            ),
            if (metaSpans.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.s6),
              Text.rich(
                TextSpan(style: AppText.caption(context), children: metaSpans),
              ),
            ],
            const SizedBox(height: AppSpacing.s12),
            metrics,
            if ((analysis.summary ?? '').trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.s12),
              Text(analysis.summary!.trim(), style: AppText.body(context)),
            ],
            const SizedBox(height: AppSpacing.s12),
            bullBear,
            const SizedBox(height: AppSpacing.s12),
            Container(
              padding: const EdgeInsets.only(top: AppSpacing.s10),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: t.border)),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.s10,
                runSpacing: AppSpacing.s8,
                children: <Widget>[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.lightbulb_outline,
                        size: AppSizes.iconSm,
                        color: t.textMuted,
                      ),
                      const SizedBox(width: AppSpacing.s6),
                      Flexible(
                        child: Text.rich(
                          TextSpan(
                            style: AppText.caption(context)
                                .copyWith(color: t.textSecondary),
                            children: <InlineSpan>[
                              const TextSpan(
                                text: 'Strategia: ',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              TextSpan(
                                text: (strategy == null || strategy.isEmpty)
                                    ? '--'
                                    : strategy,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  AppButton(
                    label: 'Apri scheda completa',
                    icon: const Icon(Icons.arrow_outward),
                    variant: AppButtonVariant.ghost,
                    size: AppButtonSize.sm,
                    onPressed: () => _openStock(analysis.ticker),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricBox({
    required IconData icon,
    required String label,
    required String value,
    required Color valueColor,
    String? trailing,
    Color? trailingColor,
  }) {
    final AppTokens t = context.tokens;
    return AppCallout(
      padding: const EdgeInsets.all(AppSpacing.s10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: AppSizes.iconXs, color: t.textMuted),
              const SizedBox(width: AppSpacing.s6),
              Expanded(child: Text(label, style: AppText.caption(context))),
            ],
          ),
          const SizedBox(height: AppSpacing.s4),
          Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  text: value,
                  style: AppText.mono(
                    context,
                    size: 17.6,
                    weight: FontWeight.w700,
                    color: valueColor,
                  ),
                ),
                if (trailing != null)
                  TextSpan(
                    text: ' $trailing',
                    style: AppText.caption(context).copyWith(
                      color: trailingColor ?? t.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bulletCallout({
    required IconData icon,
    required String title,
    required String? text,
    required bool success,
  }) {
    final String body = (text ?? '').trim().isEmpty ? '--' : text!.trim();
    return AppCallout(
      tone: success ? AppCalloutTone.success : AppCalloutTone.danger,
      accent: true,
      icon: Icon(icon),
      title: title,
      body: body,
      padding: const EdgeInsets.all(AppSpacing.s10),
    );
  }

  // --- Riassunto globale e legenda ----------------------------------------

  Widget _buildMarketSummaryCard(
    AdviceFilters filters,
    AsyncValue<List<Advice>> latestAsync,
  ) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SectionHeader(
            variant: SectionHeaderVariant.rule,
            overline: 'Sintesi',
            title: 'Riassunto globale del mercato',
            subtitle: 'Ultimi 7 giorni • Gemini 3.8 Flash',
          ),
          Text(
            _marketSummaryText(filters, latestAsync),
            style: AppText.body(context)
                .copyWith(color: context.tokens.textSecondary),
          ),
        ],
      ),
    );
  }

  String _marketSummaryText(
    AdviceFilters filters,
    AsyncValue<List<Advice>> latestAsync,
  ) {
    if (filters.date.isNotEmpty) {
      return 'Analisi storiche registrate per la giornata del '
          '${_displayDate(filters.date)}.';
    }
    final Advice? latest = _latestWithText(latestAsync.value);
    if (latest != null) {
      final String? overview = latest.overview?.trim();
      if (overview != null && overview.isNotEmpty) return overview;
      return latest.strategy!.trim();
    }
    if (latestAsync.isLoading) return 'Caricamento in corso...';
    return 'Visualizzazione dei report strategici generati nell\'ultima '
        'settimana, suddivisi per Borsa Italiana (Piazza Affari) e '
        'Borsa Americana (Wall Street).';
  }

  Advice? _latestWithText(List<Advice>? items) {
    if (items == null) return null;
    for (final Advice advice in items) {
      if ((advice.overview ?? '').trim().isNotEmpty ||
          (advice.strategy ?? '').trim().isNotEmpty) {
        return advice;
      }
    }
    return null;
  }

  Widget _buildLegendCard() {
    final List<_LegendItem> items = <_LegendItem>[
      const _LegendItem(
        icon: Icons.track_changes,
        title: 'Target price',
        body: "Prezzo obiettivo stimato per il titolo in base all'analisi "
            'fondamentale e tecnica recente.',
      ),
      const _LegendItem(
        icon: Icons.shield_outlined,
        title: 'Livello di confidenza',
        body: "Grado di affidabilità del segnale (Bassa / Media / Alta) "
            "calcolato dall'IA.",
      ),
      const _LegendItem(
        icon: Icons.schedule,
        title: 'Timeframe (orizzonte)',
        body: 'Orizzonte temporale della strategia: Breve Termine (giorni) o '
            'Medio/Lungo Termine (settimane/mesi).',
      ),
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SectionHeader(
            variant: SectionHeaderVariant.rule,
            overline: 'Guida',
            title: 'Come interpretare le analisi',
            subtitle: 'Le metriche dei report macro spiegate in breve',
          ),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool threeColumns = constraints.maxWidth >= 720;
              final double itemWidth = threeColumns
                  ? (constraints.maxWidth - AppSpacing.s12 * 2) / 3
                  : constraints.maxWidth;
              return Wrap(
                spacing: AppSpacing.s12,
                runSpacing: AppSpacing.s12,
                children: <Widget>[
                  for (final _LegendItem item in items)
                    SizedBox(
                      width: itemWidth,
                      child: _legendItem(context, item),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _legendItem(BuildContext context, _LegendItem item) {
    final AppTokens t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(item.icon, size: AppSizes.iconSm, color: t.primary),
            const SizedBox(width: AppSpacing.s6),
            Expanded(
              child: Text(
                item.title,
                style: AppText.formLabel(context)
                    .copyWith(color: t.primary, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s4),
        Text(
          item.body,
          style: AppText.caption(context).copyWith(color: t.textSecondary),
        ),
      ],
    );
  }

  // --- Filtri --------------------------------------------------------------

  Widget _buildFiltersCard(AdviceFilters filters) {
    final bool isToday = filters.date == _today;
    final bool isYesterday = filters.date == _yesterday;
    final bool isCustom = filters.date.isNotEmpty && !isToday && !isYesterday;

    final Widget dayFilter = _filterField(
      Icons.calendar_month_outlined,
      'Filtra per giorno',
      Wrap(
        spacing: AppSpacing.s8,
        runSpacing: AppSpacing.s8,
        children: <Widget>[
          AppPill(
            label: 'Oggi',
            selected: isToday,
            onPressed: () =>
                ref.read(adviceFiltersProvider.notifier).setDate(_today),
          ),
          AppPill(
            label: 'Ieri',
            selected: isYesterday,
            onPressed: () =>
                ref.read(adviceFiltersProvider.notifier).setDate(_yesterday),
          ),
          AppPill(
            label: isCustom ? _displayDate(filters.date) : 'Scegli giorno',
            icon: const Icon(Icons.calendar_month_outlined),
            selected: isCustom,
            onPressed: _pickDate,
          ),
        ],
      ),
    );

    final Widget marketFilter = _filterField(
      Icons.public,
      'Mercato',
      DropdownButtonFormField<String>(
        key: ValueKey<String>('advice-market-${filters.market}'),
        initialValue: filters.market,
        isExpanded: true,
        items: const <DropdownMenuItem<String>>[
          DropdownMenuItem<String>(value: '', child: Text('Tutti i mercati')),
          DropdownMenuItem<String>(
            value: 'IT',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                AppMarketTag(code: 'IT', tone: BadgeTone.primary),
                SizedBox(width: AppSpacing.s6),
                Flexible(child: Text('Borsa Italiana')),
              ],
            ),
          ),
          DropdownMenuItem<String>(
            value: 'US',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                AppMarketTag(code: 'US'),
                SizedBox(width: AppSpacing.s6),
                Flexible(child: Text('Borsa Americana')),
              ],
            ),
          ),
        ],
        onChanged: (String? value) =>
            ref.read(adviceFiltersProvider.notifier).setMarket(value ?? ''),
      ),
    );

    final Widget actionFilter = _filterField(
      Icons.track_changes,
      'Azione generale',
      DropdownButtonFormField<String>(
        key: ValueKey<String>('advice-action-${filters.action}'),
        initialValue: filters.action,
        isExpanded: true,
        items: const <DropdownMenuItem<String>>[
          DropdownMenuItem<String>(value: '', child: Text('Tutte le azioni')),
          DropdownMenuItem<String>(
            value: 'ACCUMULO',
            child: Text('Accumulo / Buy'),
          ),
          DropdownMenuItem<String>(
            value: 'MANTENIMENTO',
            child: Text('Mantenimento / Hold'),
          ),
          DropdownMenuItem<String>(
            value: 'PRESA_PROFITTO',
            child: Text('Presa profitto / Sell'),
          ),
        ],
        onChanged: (String? value) =>
            ref.read(adviceFiltersProvider.notifier).setAction(value ?? ''),
      ),
    );

    final Widget searchFilter = _filterField(
      Icons.search,
      'Cerca ticker nei blocchi',
      TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        textInputAction: TextInputAction.search,
        style: AppText.small(context),
        decoration: InputDecoration(
          hintText: 'Es. ENEL, AAPL, NVDA, LDO...',
          prefixIcon: const Icon(Icons.search, size: 16),
          suffixIcon: _hasSearchText
              ? IconButton(
                  icon: const Icon(Icons.close, size: 15),
                  tooltip: 'Pulisci filtro',
                  onPressed: _clearSearch,
                )
              : null,
        ),
      ),
    );

    final Widget resetButton = AppButton(
      label: 'Mostra tutta la settimana',
      icon: const Icon(Icons.restart_alt),
      variant: AppButtonVariant.ghost,
      size: AppButtonSize.sm,
      onPressed: _resetFilters,
    );

    return AppCard(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // Sotto 560px il bottone di reset non sta accanto al titolo: scende
          // a piè di card, a larghezza piena.
          final bool headerTrailing = constraints.maxWidth >= 560;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SectionHeader(
                variant: SectionHeaderVariant.rule,
                overline: 'Archivio',
                title: 'Filtra le analisi',
                subtitle: 'Giorno, mercato, azione e ricerca testuale',
                trailing: headerTrailing ? resetButton : null,
              ),
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  if (constraints.maxWidth < 820) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        dayFilter,
                        const SizedBox(height: AppSpacing.s12),
                        marketFilter,
                        const SizedBox(height: AppSpacing.s12),
                        actionFilter,
                        const SizedBox(height: AppSpacing.s12),
                        searchFilter,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Flexible(child: dayFilter),
                      const SizedBox(width: AppSpacing.s16),
                      SizedBox(width: 200, child: marketFilter),
                      const SizedBox(width: AppSpacing.s16),
                      SizedBox(width: 220, child: actionFilter),
                      const SizedBox(width: AppSpacing.s16),
                      Expanded(child: searchFilter),
                    ],
                  );
                },
              ),
              if (!headerTrailing) ...<Widget>[
                const SizedBox(height: AppSpacing.s14),
                Align(alignment: Alignment.centerLeft, child: resetButton),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _filterField(IconData icon, String label, Widget child) {
    final AppTokens t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, size: AppSizes.iconXs, color: t.textFaint),
            const SizedBox(width: AppSpacing.s6),
            Expanded(child: Text(label, style: AppText.formLabel(context))),
          ],
        ),
        const SizedBox(height: AppSpacing.s6),
        child,
      ],
    );
  }

  // --- Lista consigli ------------------------------------------------------

  Widget _buildListSection(
    AsyncValue<AdviceListState> asyncState,
    List<Advice> filtered,
    bool firstLoading,
    bool firstError,
  ) {
    if (firstLoading) {
      return const Column(
        children: <Widget>[
          SkeletonCard(),
          SizedBox(height: AppSpacing.s14),
          SkeletonCard(),
          SizedBox(height: AppSpacing.s14),
          SkeletonCard(),
        ],
      );
    }
    if (firstError) {
      return AppCard(
        child: EmptyState(
          icon: const Icon(Icons.error_outline),
          message: _errorMessage(
            asyncState.error!,
            'Errore nel caricamento dei consigli',
          ),
          actions: <Widget>[
            AppButton(
              label: 'Riprova',
              icon: const Icon(Icons.refresh),
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.sm,
              onPressed: () => ref.invalidate(adviceListProvider),
            ),
          ],
        ),
      );
    }
    if (filtered.isEmpty) {
      return AppCard(
        child: EmptyState(
          icon: const Icon(Icons.search_off),
          title: 'Nessun risultato',
          message:
              'Nessuna analisi strategica trovata per i criteri selezionati. '
              'Usa il pulsante "Genera Analisi Macro Ora" o seleziona '
              'un\'altra data.',
        ),
      );
    }

    final AdviceListState? state = asyncState.value;
    final List<(String, List<Advice>)> groups = _groupByDay(filtered);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int g = 0; g < groups.length; g++) ...<Widget>[
          if (g > 0) const SizedBox(height: AppSpacing.s22),
          SectionHeader(
            variant: SectionHeaderVariant.rule,
            overline: 'Archivio',
            title: groups[g].$1,
            trailing: AppBadge(
              label: '${groups[g].$2.length} analisi',
              tone: BadgeTone.neutral,
            ),
          ),
          for (int i = 0; i < groups[g].$2.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: AppSpacing.s14),
            AdviceCard(
              advice: groups[g].$2[i],
              followed:
                  state?.isFollowed(groups[g].$2[i]) ??
                  groups[g].$2[i].followed,
              followBusy: _followBusy.contains(groups[g].$2[i].id),
              onToggleFollow: () => _toggleFollow(groups[g].$2[i]),
              onOpenStock: _openStock,
            ),
          ],
        ],
      ],
    );
  }

  /// Raggruppa l'archivio per giorno di elaborazione, in ordine di arrivo.
  List<(String, List<Advice>)> _groupByDay(List<Advice> items) {
    final Map<String, List<Advice>> grouped = <String, List<Advice>>{};
    for (final Advice advice in items) {
      final String key = advice.timestamp == null
          ? 'Senza data'
          : formatDate(advice.timestamp);
      grouped.putIfAbsent(key, () => <Advice>[]).add(advice);
    }
    return grouped.entries
        .map((MapEntry<String, List<Advice>> entry) => (entry.key, entry.value))
        .toList(growable: false);
  }
}

/// Voce della guida "Come interpretare le analisi".
class _LegendItem {
  const _LegendItem({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

/// Pallini di stato mercati in topbar (riuso del widget dashboard).
///
/// Sotto 1024px forza il layout compatto (pallini + orari, senza label):
/// tra 900 e 1024 la topbar con la sidebar aperta è troppo stretta per le
/// label accanto a ricerca/help/tema.
///
/// Nota: [MarketStatusView] sceglie il layout leggendo la larghezza del
/// MediaQuery, non i vincoli locali; finché il widget vive in un'altra lane
/// questo wrapper è l'unico punto per forzare la variante compatta.
class _AdviceMarketStatusAction extends ConsumerWidget {
  const _AdviceMarketStatusAction();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final MarketStatusInfo? status = ref
        .watch(adviceMarketStatusProvider)
        .value;
    final Widget view = MarketStatusView(status: status);
    if (!context.isNarrow) return view;
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        size: Size(
          AppBreakpoints.compact - 1,
          MediaQuery.sizeOf(context).height,
        ),
      ),
      child: view,
    );
  }
}

/// Bottone `Genera Analisi Macro Ora` con loading e toast.
class _AdviceGenerateButton extends ConsumerWidget {
  const _AdviceGenerateButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool generating = ref.watch(adviceGenerationProvider);
    return AppButton(
      label: 'Genera Analisi Macro Ora',
      icon: const Icon(Icons.auto_awesome),
      loading: generating,
      loadingLabel: 'Generazione...',
      onPressed: () => _generate(context, ref),
    );
  }

  Future<void> _generate(BuildContext context, WidgetRef ref) async {
    final String? error = await ref
        .read(adviceGenerationProvider.notifier)
        .generate();
    if (!context.mounted) return;
    if (error != null) {
      showAppToast(context, message: error, type: AppToastType.error);
      return;
    }
    showAppToast(
      context,
      message: 'Analisi per Borsa Italiana e Americana generata con successo!',
      type: AppToastType.success,
    );
  }
}
