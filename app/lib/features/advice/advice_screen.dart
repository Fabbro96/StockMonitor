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
import '../../widgets/app_card.dart';
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

/// Schermata `🧠 Analisi & Consigli IA` (parità `advice.html`/`advice.js`).
///
/// Struttura: analisi istantanea su singolo titolo, riassunto globale del
/// mercato, legenda, filtri (giorno/mercato/azione + ricerca client-side),
/// lista consigli con tabella priorità e follow, paginazione `Carica Altri`.
/// La topbar porta pallini di stato mercati e `Genera Analisi Macro Ora`.
class AdviceScreen extends ConsumerStatefulWidget {
  /// Crea la schermata Consigli.
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

    return PageContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Azione primaria in alto a destra (il legacy la teneva in topbar;
          // qui resta nel contenuto per non comprimere la topbar condivisa).
          const Align(
            alignment: Alignment.centerRight,
            child: _AdviceGenerateButton(),
          ),
          const SizedBox(height: AppSpacing.s14),
          _buildSingleStockCard(),
          const SizedBox(height: AppSpacing.s14),
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
            title: '⚡ Analisi Istantanea su Singolo Titolo (Gemini 3.7 Flash)',
            subtitle: "Interroga l'IA per un report approfondito con Target Price, RSI, SMA e catalizzatori",
          ),
          _buildTickerInput(),
          if (_analyzing) ...<Widget>[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.s22),
              child: Center(child: AppSpinner()),
            ),
          ] else if (_analysisError != null) ...<Widget>[
            AdviceCallout(
              background: context.tokens.dangerBg,
              borderColor: context.tokens.dangerBorder,
              accent: context.tokens.danger,
              child: Text(
                'Errore analisi: $_analysisError',
                textAlign: TextAlign.center,
                style: AppText.small(context)
                    .copyWith(color: context.tokens.danger),
              ),
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
      label: 'Analizza Titolo con IA ➔',
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
          label: '🎯 Target Price Stimato',
          value: formatCurrency(analysis.targetPrice, currency: currency),
          valueColor: t.primary,
          trailing: upside == null ? null : '(${formatPercent(upside)})',
          trailingColor: (upside ?? 0) >= 0 ? t.successText : t.danger,
        );
        final Widget stop = _metricBox(
          label: '🛡️ Stop Loss Prudenziale',
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
          title: '🟢 Bull Case & Catalizzatori',
          text: analysis.bullCase,
          success: true,
        );
        final Widget bear = _bulletCallout(
          title: '🔴 Bear Case & Rischi',
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
      child: AdviceCallout(
        accent: t.primary,
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
                  Text.rich(
                    TextSpan(
                      style: AppText.caption(context)
                          .copyWith(color: t.textSecondary),
                      children: <InlineSpan>[
                        const TextSpan(text: '💡 '),
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
                  AppButton(
                    label: 'Apri Scheda Completa ➔',
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
    required String label,
    required String value,
    required Color valueColor,
    String? trailing,
    Color? trailingColor,
  }) {
    final AppTokens t = context.tokens;
    return AdviceCallout(
      padding: const EdgeInsets.all(AppSpacing.s10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: AppText.caption(context)),
          const SizedBox(height: AppSpacing.s2),
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
    required String title,
    required String? text,
    required bool success,
  }) {
    final AppTokens t = context.tokens;
    final String body = (text ?? '').trim().isEmpty ? '--' : text!.trim();
    return AdviceCallout(
      background: success ? t.successBg : t.dangerBg,
      borderColor: success ? t.successBorder : t.dangerBorder,
      accent: success ? t.success : t.danger,
      padding: const EdgeInsets.all(AppSpacing.s10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: AppText.small(context).copyWith(
              color: success ? t.successText : t.danger,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(
            body,
            style: AppText.captionFor(t).copyWith(color: t.textSecondary),
          ),
        ],
      ),
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
          SectionHeader(
            title: '🌐 Riassunto Globale del Mercato',
            subtitle: 'Ultimi 7 Giorni • Gemini 3.7 Flash',
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
        title: '🎯 Target Price',
        body: "Prezzo obiettivo stimato per il titolo in base all'analisi fondamentale e tecnica recente.",
      ),
      const _LegendItem(
        title: '🛡️ Livello di Confidenza',
        body: "Grado di affidabilità del segnale (Bassa / Media / Alta) calcolato dall'IA.",
      ),
      const _LegendItem(
        title: '⏳ Timeframe (Orizzonte)',
        body:
            'Orizzonte temporale della strategia: Breve Termine (giorni) o '
            'Medio/Lungo Termine (settimane/mesi).',
      ),
    ];

    return AppCard(
      accent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Text('💡', style: TextStyle(fontSize: 15.2)),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Text(
                  'Come interpretare le analisi macro',
                  style: AppText.small(context)
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s10),
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
        Text(
          item.title,
          style: AppText.small(context)
              .copyWith(color: t.primary, fontWeight: FontWeight.w700),
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
    final AppTokens t = context.tokens;
    final bool isToday = filters.date == _today;
    final bool isYesterday = filters.date == _yesterday;
    final bool isCustom = filters.date.isNotEmpty && !isToday && !isYesterday;

    final Widget dayFilter = _filterField(
      '📅 Filtra per Giorno',
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
            label: isCustom
                ? '📅 ${_displayDate(filters.date)}'
                : 'Scegli giorno 📅',
            selected: isCustom,
            onPressed: _pickDate,
          ),
        ],
      ),
    );

    final Widget marketFilter = _filterField(
      '🏛️ Mercato',
      DropdownButtonFormField<String>(
        key: ValueKey<String>('advice-market-${filters.market}'),
        initialValue: filters.market,
        isExpanded: true,
        items: const <DropdownMenuItem<String>>[
          DropdownMenuItem<String>(value: '', child: Text('Tutti i Mercati')),
          DropdownMenuItem<String>(
            value: 'IT',
            child: Text('🇮🇹 Borsa Italiana'),
          ),
          DropdownMenuItem<String>(
            value: 'US',
            child: Text('🇺🇸 Borsa Americana'),
          ),
        ],
        onChanged: (String? value) =>
            ref.read(adviceFiltersProvider.notifier).setMarket(value ?? ''),
      ),
    );

    final Widget actionFilter = _filterField(
      '🎯 Azione Generale',
      DropdownButtonFormField<String>(
        key: ValueKey<String>('advice-action-${filters.action}'),
        initialValue: filters.action,
        isExpanded: true,
        items: const <DropdownMenuItem<String>>[
          DropdownMenuItem<String>(value: '', child: Text('Tutte le Azioni')),
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
            child: Text('Presa Profitto / Sell'),
          ),
        ],
        onChanged: (String? value) =>
            ref.read(adviceFiltersProvider.notifier).setAction(value ?? ''),
      ),
    );

    final Widget searchFilter = _filterField(
      '🔎 Cerca Ticker nei Blocchi',
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

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.s10,
            runSpacing: AppSpacing.s8,
            children: <Widget>[
              Text(
                '🔍 Filtra Analisi di Mercato',
                style: AppText.small(context)
                    .copyWith(color: t.primary, fontWeight: FontWeight.w700),
              ),
              AppButton(
                label: '↺ Mostra Tutta la Settimana',
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.sm,
                onPressed: _resetFilters,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s14),
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
        ],
      ),
    );
  }

  Widget _filterField(String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: AppText.formLabel(context)),
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
          message: _errorMessage(
            asyncState.error!,
            'Errore nel caricamento dei consigli',
          ),
          actions: <Widget>[
            AppButton(
              label: 'Riprova',
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
          message:
              'Nessuna analisi strategica trovata per i criteri selezionati. '
              'Usa il pulsante "Genera Analisi Macro Ora" o seleziona '
              'un\'altra data.',
        ),
      );
    }

    final AdviceListState? state = asyncState.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < filtered.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: AppSpacing.s14),
          AdviceCard(
            advice: filtered[i],
            followed: state?.isFollowed(filtered[i]) ?? filtered[i].followed,
            followBusy: _followBusy.contains(filtered[i].id),
            onToggleFollow: () => _toggleFollow(filtered[i]),
            onOpenStock: _openStock,
          ),
        ],
      ],
    );
  }
}

/// Voce della legenda "Come interpretare le analisi macro".
class _LegendItem {
  const _LegendItem({required this.title, required this.body});

  final String title;
  final String body;
}

/// Pallini di stato mercati in topbar (riuso del widget dashboard).
///
/// Sotto 1024px forza il layout compatto (pallini + tooltip, senza label):
/// tra 900 e 1024 la topbar con la sidebar aperta è troppo stretta per le
/// label accanto a ricerca/help/tema.
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

/// Bottone `Genera Analisi Macro Ora` sopra le card, con loading e toast.
class _AdviceGenerateButton extends ConsumerWidget {
  const _AdviceGenerateButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool generating = ref.watch(adviceGenerationProvider);
    return AppButton(
      label: 'Genera Analisi Macro Ora',
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
