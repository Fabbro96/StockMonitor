import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/models/watchlist_item.dart';
import '../../shell/topbar.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/badges.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/page_content.dart';
import '../../widgets/range_bar.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/ticker_flag.dart';
import '../../widgets/toast.dart';
import '../stock_detail/market_editor_modal.dart' show showMarketEditor;
import '../stock_detail/stock_detail_modal.dart' show showStockDetail;
import 'watchlist_dialogs.dart';
import 'watchlist_providers.dart';

/// Larghezza minima della tabella: sopra questa soglia le colonne riempiono
/// la card, sotto compare lo scroll orizzontale (e sotto 900px si passa alle
/// card, parità con il breakpoint del frontend HTML).
const double _tableMinWidth = 1320;

/// Watchlist & Radar Mercati: stat cards, tabella/card dei titoli monitorati,
/// modal aggiunta/alert, filtro con debounce e rimozione con undo.
class WatchlistScreen extends ConsumerStatefulWidget {
  /// Crea la schermata Watchlist.
  const WatchlistScreen({super.key});

  @override
  ConsumerState<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends ConsumerState<WatchlistScreen> {
  late final TopbarActionsController _topbar;
  final TextEditingController _filterController = TextEditingController();
  Timer? _filterDebounce;
  bool _hasFilterText = false;

  @override
  void initState() {
    super.initState();
    _topbar = ref.read(topbarActionsProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted) return;
      _topbar.set(this, <Widget>[
        AppButton(
          label: '➕ Aggiungi Titolo al Radar',
          size: context.isCompact ? AppButtonSize.sm : AppButtonSize.md,
          onPressed: _openAddDialog,
        ),
      ]);
    });
  }

  @override
  void dispose() {
    _filterDebounce?.cancel();
    _filterController.dispose();
    _topbar.clear(this);
    super.dispose();
  }

  void _openAddDialog() => showWatchlistAddDialog(context);

  void _onFilterChanged(String value) {
    if (_hasFilterText != value.isNotEmpty) {
      setState(() => _hasFilterText = value.isNotEmpty);
    }
    _filterDebounce?.cancel();
    _filterDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      ref.read(watchlistFilterProvider.notifier).setQuery(value);
    });
  }

  void _clearFilter() {
    _filterDebounce?.cancel();
    _filterController.clear();
    if (_hasFilterText) setState(() => _hasFilterText = false);
    ref.read(watchlistFilterProvider.notifier).setQuery('');
  }

  /// Ricarica la lista dopo mutazioni esterne (scheda titolo, market editor).
  void _reloadList() =>
      unawaited(ref.read(watchlistProvider.notifier).reload());

  Future<void> _removeItem(WatchlistItem item) async {
    try {
      await ref.read(watchlistProvider.notifier).removeItem(item.id);
    } on ApiException catch (error) {
      if (!mounted) return;
      showAppToast(context, message: error.message, type: AppToastType.error);
      return;
    } catch (_) {
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Errore durante la rimozione',
        type: AppToastType.error,
      );
      return;
    }
    if (!mounted) return;
    showAppToast(
      context,
      message: '${item.ticker} rimosso dalla Watchlist',
      actionLabel: 'Annulla',
      onAction: () => unawaited(_restoreItem(item)),
    );
  }

  Future<void> _restoreItem(WatchlistItem item) async {
    try {
      await ref.read(watchlistProvider.notifier).restore(item);
    } on ApiException catch (error) {
      if (!mounted) return;
      showAppToast(context, message: error.message, type: AppToastType.error);
    } catch (_) {
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Errore durante il ripristino',
        type: AppToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Guardia array (fix bug #7): un payload non-lista diventa AsyncError e
    // viene notificato con un toast, senza crash né skeleton infinito.
    ref.listen<AsyncValue<List<WatchlistItem>>>(watchlistProvider, (
      AsyncValue<List<WatchlistItem>>? previous,
      AsyncValue<List<WatchlistItem>> next,
    ) {
      final Object? error = next.error;
      if (error == null || identical(previous?.error, error)) return;
      showAppToast(
        context,
        message: error is ApiException
            ? error.message
            : 'Errore nel caricamento della Watchlist',
        type: AppToastType.error,
      );
    });

    final AsyncValue<List<WatchlistItem>> asyncItems = ref.watch(
      watchlistProvider,
    );
    final List<WatchlistItem> filtered = ref.watch(filteredWatchlistProvider);
    final List<WatchlistItem> items =
        asyncItems.value ?? const <WatchlistItem>[];

    return PageContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _StatsGrid(
            stats: computeWatchlistStats(items),
            loading: asyncItems.isLoading && asyncItems.value == null,
          ),
          const SizedBox(height: AppSpacing.s14),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _buildCardHeader(context),
                const SizedBox(height: AppSpacing.s12),
                _buildContent(asyncItems, items, filtered),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardHeader(BuildContext context) {
    final Widget title = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text('🎯 Azioni Monitorate', style: AppText.cardTitle(context)),
        const SizedBox(width: AppSpacing.s8),
        Flexible(
          child: Text(
            '(Clicca su qualsiasi titolo per aprire la scheda tecnica completa)',
            style: AppText.caption(context),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    final Widget filter = TextField(
      controller: _filterController,
      onChanged: _onFilterChanged,
      textInputAction: TextInputAction.search,
      style: AppText.small(context),
      decoration: InputDecoration(
        hintText: 'Filtra ticker...',
        prefixIcon: const Icon(Icons.search, size: 16),
        suffixIcon: _hasFilterText
            ? IconButton(
                icon: const Icon(Icons.close, size: 15),
                tooltip: 'Pulisci filtro',
                onPressed: _clearFilter,
              )
            : null,
      ),
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              title,
              const SizedBox(height: AppSpacing.s10),
              filter,
            ],
          );
        }
        return Row(
          children: <Widget>[
            Expanded(child: title),
            const SizedBox(width: AppSpacing.s12),
            SizedBox(width: 230, child: filter),
          ],
        );
      },
    );
  }

  Widget _buildContent(
    AsyncValue<List<WatchlistItem>> asyncItems,
    List<WatchlistItem> items,
    List<WatchlistItem> filtered,
  ) {
    if (items.isEmpty) {
      if (asyncItems.isLoading) return _buildLoadingRows();
      if (asyncItems.hasError) return _buildErrorState();
      return _buildEmptyRadar();
    }
    if (filtered.isEmpty) return _buildEmptyFilter();
    return context.isDrawerLayout
        ? _buildCards(filtered)
        : _buildTable(filtered);
  }

  Widget _buildLoadingRows() {
    return const Column(
      children: <Widget>[SkeletonRow(), SkeletonRow(), SkeletonRow()],
    );
  }

  Widget _buildEmptyRadar() {
    return EmptyState(
      message: 'Nessun titolo nel radar.',
      actions: <Widget>[
        AppButton(
          label: '➕ Aggiungi Titolo al Radar',
          size: AppButtonSize.sm,
          onPressed: _openAddDialog,
        ),
      ],
    );
  }

  Widget _buildEmptyFilter() {
    return const EmptyState(
      message: 'Nessun risultato corrispondente al filtro.',
    );
  }

  Widget _buildErrorState() {
    return EmptyState(
      icon: const Icon(Icons.error_outline),
      message: 'Errore nel caricamento della Watchlist.',
      actions: <Widget>[
        AppButton(
          label: '↻ Riprova',
          variant: AppButtonVariant.ghost,
          size: AppButtonSize.sm,
          onPressed: () => ref.read(watchlistProvider.notifier).reload(),
        ),
      ],
    );
  }

  // --- Tabella (≥900px) ---------------------------------------------------

  Widget _buildTable(List<WatchlistItem> items) {
    final AppTokens t = context.tokens;
    final Table table = Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: <int, TableColumnWidth>{
        for (int i = 0; i < _columns.length; i++)
          i: _columns[i].width != null
              ? FixedColumnWidth(_columns[i].width!)
              : FlexColumnWidth(_columns[i].flex),
      },
      border: TableBorder(
        horizontalInside: BorderSide(color: t.borderSubtle),
        bottom: BorderSide(color: t.border),
      ),
      children: <TableRow>[
        TableRow(
          children: <Widget>[
            for (final _TableColumn column in _columns)
              _headerCell(context, column),
          ],
        ),
        for (final WatchlistItem item in items)
          TableRow(
            children: <Widget>[
              _tickerCell(context, item),
              _priceCell(context, item),
              _changeCell(context, item),
              _rangeCell(context, item),
              _rsiCell(context, item),
              _alertCell(context, item),
              _peCell(context, item),
              _dividendCell(context, item),
              _actionsCell(context, item),
            ],
          ),
      ],
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < _tableMinWidth) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: _tableMinWidth, child: table),
          );
        }
        return table;
      },
    );
  }

  Widget _headerCell(BuildContext context, _TableColumn column) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s10,
        vertical: AppSpacing.s8,
      ),
      child: Text(
        column.label.toUpperCase(),
        textAlign: column.align,
        style: AppText.tableHeader(context),
      ),
    );
  }

  Widget _tickerCell(BuildContext context, WatchlistItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s10,
        vertical: AppSpacing.s10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _marketButton(item),
          const SizedBox(width: AppSpacing.s8),
          Expanded(child: _tickerBlock(context, item)),
        ],
      ),
    );
  }

  Widget _priceCell(BuildContext context, WatchlistItem item) {
    return _numericCell(
      context,
      child: Text(
        formatCurrency(item.currentPrice, currency: _currencyOf(item)),
        textAlign: TextAlign.right,
        style: AppText.mono(context, size: 13.1, weight: FontWeight.w700),
      ),
    );
  }

  Widget _changeCell(BuildContext context, WatchlistItem item) {
    final AppTokens t = context.tokens;
    final bool isUp = item.changePercent >= 0;
    final String sign = isUp ? '+' : '';
    return _numericCell(
      context,
      child: Text(
        '$sign${formatCurrency(item.changeAbs, currency: _currencyOf(item))}'
        ' (${formatPercent(item.changePercent)})',
        textAlign: TextAlign.right,
        style: AppText.mono(
          context,
          size: 13.1,
          weight: FontWeight.w700,
          color: isUp ? t.successText : t.danger,
        ),
      ),
    );
  }

  Widget _rangeCell(BuildContext context, WatchlistItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s10,
        vertical: AppSpacing.s8,
      ),
      child: RangeBar(
        positionPercent: (item.fiftyTwoWeekPct ?? 50).clamp(0, 100).toDouble(),
        lowLabel: formatCurrency(
          item.fiftyTwoWeekLow,
          currency: _currencyOf(item),
        ),
        highLabel: formatCurrency(
          item.fiftyTwoWeekHigh,
          currency: _currencyOf(item),
        ),
        minWidth: 160,
      ),
    );
  }

  Widget _rsiCell(BuildContext context, WatchlistItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s6,
        vertical: AppSpacing.s8,
      ),
      child: Center(child: _rsiBadge(context, item)),
    );
  }

  Widget _alertCell(BuildContext context, WatchlistItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s6,
        vertical: AppSpacing.s8,
      ),
      child: Center(child: _alertWidget(context, item)),
    );
  }

  Widget _peCell(BuildContext context, WatchlistItem item) {
    return _numericCell(
      context,
      child: Text(
        item.peRatio == null ? '--' : item.peRatio!.toStringAsFixed(1),
        textAlign: TextAlign.right,
        style: AppText.mono(
          context,
          size: 12.2,
          weight: FontWeight.w600,
          color: context.tokens.textSecondary,
        ),
      ),
    );
  }

  Widget _dividendCell(BuildContext context, WatchlistItem item) {
    return _numericCell(
      context,
      child: Text(
        item.dividendYield == null
            ? '--'
            : '${item.dividendYield!.toStringAsFixed(2)}%',
        textAlign: TextAlign.right,
        style: AppText.mono(
          context,
          size: 12.2,
          weight: FontWeight.w600,
          color: context.tokens.successText,
        ),
      ),
    );
  }

  Widget _actionsCell(BuildContext context, WatchlistItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s6,
        vertical: AppSpacing.s6,
      ),
      child: Center(child: _quickActions(context, item)),
    );
  }

  Widget _numericCell(BuildContext context, {required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s10,
        vertical: AppSpacing.s10,
      ),
      child: child,
    );
  }

  // --- Card (sotto ~900px) ------------------------------------------------

  Widget _buildCards(List<WatchlistItem> items) {
    return Column(
      children: <Widget>[
        for (int i = 0; i < items.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: AppSpacing.s10),
          _buildCard(items[i]),
        ],
      ],
    );
  }

  Widget _buildCard(WatchlistItem item) {
    final AppTokens t = context.tokens;
    final bool isUp = item.changePercent >= 0;
    final String sign = isUp ? '+' : '';
    return AppCard(
      subtle: true,
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _marketButton(item),
              const SizedBox(width: AppSpacing.s8),
              Expanded(child: _tickerBlock(context, item)),
              const SizedBox(width: AppSpacing.s8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    formatCurrency(
                      item.currentPrice,
                      currency: _currencyOf(item),
                    ),
                    style: AppText.mono(
                      context,
                      size: 14.1,
                      weight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '$sign${formatCurrency(item.changeAbs, currency: _currencyOf(item))}'
                    ' (${formatPercent(item.changePercent)})',
                    style: AppText.mono(
                      context,
                      size: 12.2,
                      weight: FontWeight.w700,
                      color: isUp ? t.successText : t.danger,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s10),
          Row(
            children: <Widget>[
              Flexible(child: _rsiBadge(context, item)),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _alertWidget(context, item),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s10),
          RangeBar(
            positionPercent: (item.fiftyTwoWeekPct ?? 50)
                .clamp(0, 100)
                .toDouble(),
            lowLabel: formatCurrency(
              item.fiftyTwoWeekLow,
              currency: _currencyOf(item),
            ),
            highLabel: formatCurrency(
              item.fiftyTwoWeekHigh,
              currency: _currencyOf(item),
            ),
          ),
          const SizedBox(height: AppSpacing.s10),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.s18,
            runSpacing: AppSpacing.s8,
            children: <Widget>[
              _miniMetric(
                context,
                label: 'P/E',
                value: item.peRatio == null
                    ? '--'
                    : item.peRatio!.toStringAsFixed(1),
              ),
              _miniMetric(
                context,
                label: 'Div. Yield',
                value: item.dividendYield == null
                    ? '--'
                    : '${item.dividendYield!.toStringAsFixed(2)}%',
                valueColor: t.successText,
              ),
              _quickActions(context, item),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniMetric(
    BuildContext context, {
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: AppText.caption(context).copyWith(letterSpacing: 0.4),
        ),
        Text(
          value,
          style: AppText.mono(
            context,
            size: 12.8,
            weight: FontWeight.w700,
            color: valueColor ?? context.tokens.textPrimary,
          ),
        ),
      ],
    );
  }

  // --- Celle condivise ----------------------------------------------------

  /// Valuta del titolo con fallback EUR (il backend può ometterla).
  String _currencyOf(WatchlistItem item) => item.currency ?? 'EUR';

  Widget _tickerBlock(BuildContext context, WatchlistItem item) {
    final AppTokens t = context.tokens;
    final String name = item.name?.isNotEmpty == true
        ? item.name!
        : item.ticker;
    final String notes = item.notes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        InkWell(
          onTap: () =>
              showStockDetail(context, item.ticker, onChanged: _reloadList),
          borderRadius: BorderRadius.circular(AppRadii.small),
          child: Text(
            item.ticker,
            style: AppText.mono(
              context,
              size: 13.4,
              weight: FontWeight.w700,
              color: t.primary,
            ),
          ),
        ),
        Text(
          name,
          style: AppText.caption(context),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (notes.isNotEmpty)
          Tooltip(
            message: notes,
            child: Text(
              '📝 ${notes.length > 26 ? notes.substring(0, 26) : notes}',
              style: AppText.caption(context).copyWith(fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  Widget _marketButton(WatchlistItem item) {
    return AppIconButton(
      icon: Text(
        TickerFlags.forTicker(item.ticker, market: item.market),
        style: const TextStyle(fontSize: 14),
      ),
      size: 28,
      iconSize: 14,
      tooltip: 'Modifica mercato',
      semanticLabel: 'Modifica mercato di ${item.ticker}',
      onPressed: () => showMarketEditor(
        context,
        item.ticker,
        initialMarket: item.market,
        onSaved: (_) => _reloadList(),
      ),
    );
  }

  Widget _rsiBadge(BuildContext context, WatchlistItem item) {
    final String fullStatus = item.rsiStatus.isEmpty
        ? 'Neutro'
        : item.rsiStatus;
    final String shortStatus = fullStatus.split('(').first.trim().isEmpty
        ? fullStatus
        : fullStatus.split('(').first.trim();
    final String value = _formatRsi(item.rsi);
    return AppBadge(
      label: '$value · $shortStatus',
      tone: _rsiTone(item.rsiBadge),
      tooltip: 'RSI a 14 periodi: $value — $fullStatus',
    );
  }

  Widget _alertWidget(BuildContext context, WatchlistItem item) {
    final AppTokens t = context.tokens;
    Widget content;
    if (item.alertTriggered) {
      content = AppBadge(
        label: '🚨 Scattato!',
        tone: BadgeTone.danger,
        tooltip: 'Alert Scattato! Prezzo oltre la soglia',
      );
    } else if (item.alertAbove != null || item.alertBelow != null) {
      final List<String> lines = <String>[
        if (item.alertAbove != null)
          '▲ > ${formatCurrency(item.alertAbove, currency: _currencyOf(item))}',
        if (item.alertBelow != null)
          '▼ < ${formatCurrency(item.alertBelow, currency: _currencyOf(item))}',
      ];
      content = AppBadge(
        label: lines.join('\n'),
        tone: BadgeTone.warning,
        tooltip: 'Alert Attivo',
      );
    } else {
      content = Text(
        'Nessuno',
        style: AppText.caption(context).copyWith(fontSize: 11.8),
      );
    }

    return InkWell(
      onTap: () => showWatchlistAlertDialog(context, item),
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: Semantics(
        button: true,
        label: item.alertTriggered
            ? 'Alert scattato per ${item.ticker}'
            : 'Imposta alert di prezzo per ${item.ticker}',
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s2),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: t.textSecondary),
            child: content,
          ),
        ),
      ),
    );
  }

  Widget _quickActions(BuildContext context, WatchlistItem item) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _quickAction(
          emoji: '🔍',
          tooltip: 'Apri Scheda Completa',
          semanticLabel: 'Analisi e scheda completa per ${item.ticker}',
          onPressed: () =>
              showStockDetail(context, item.ticker, onChanged: _reloadList),
        ),
        const SizedBox(width: AppSpacing.s4),
        _quickAction(
          emoji: '🔔',
          tooltip: 'Imposta Alert Prezzo',
          semanticLabel: 'Imposta alert di prezzo per ${item.ticker}',
          onPressed: () => showWatchlistAlertDialog(context, item),
        ),
        const SizedBox(width: AppSpacing.s4),
        _quickAction(
          emoji: '💼',
          tooltip: 'Aggiungi alle Holding',
          semanticLabel: 'Aggiungi ${item.ticker} al portafoglio',
          onPressed: () =>
              context.go('/portfolio?add=${Uri.encodeComponent(item.ticker)}'),
        ),
        const SizedBox(width: AppSpacing.s4),
        _quickAction(
          emoji: '🗑️',
          tooltip: 'Rimuovi dal radar',
          semanticLabel: 'Rimuovi ${item.ticker} dalla watchlist',
          onPressed: () => unawaited(_removeItem(item)),
        ),
      ],
    );
  }

  Widget _quickAction({
    required String emoji,
    required String tooltip,
    required String semanticLabel,
    required VoidCallback onPressed,
  }) {
    return AppIconButton(
      icon: Text(emoji, style: const TextStyle(fontSize: 13)),
      size: 28,
      iconSize: 13,
      tooltip: tooltip,
      semanticLabel: semanticLabel,
      onPressed: onPressed,
    );
  }
}

/// Griglia responsive delle 4 stat card (4 colonne ≥900px, altrimenti 2).
class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats, required this.loading});

  final WatchlistStats stats;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final String count = loading ? '--' : '${stats.count}';
    final String gainers = loading ? '--' : '${stats.gainers}';
    final String losers = loading ? '--' : '${stats.losers}';
    final String alerts = loading ? '--' : '${stats.activeAlerts}';

    final List<Widget> cards = <Widget>[
      StatCard(
        label: 'Titoli nel Radar',
        value: count,
        valueColor: t.primary,
        description: 'Azioni ed ETF sotto osservazione',
      ),
      StatCard(
        label: 'In Rialzo Oggi',
        value: gainers,
        valueColor: t.successText,
        description: 'Titoli con variazione giornaliera positiva',
      ),
      StatCard(
        label: 'In Ribasso Oggi',
        value: losers,
        valueColor: t.danger,
        description: 'Titoli con variazione giornaliera negativa',
      ),
      StatCard(
        label: 'Alert Target Attivi',
        value: alerts,
        valueColor: t.warning,
        description: 'Soglie di prezzo monitorate',
      ),
    ];

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int columns = constraints.maxWidth >= 900 ? 4 : 2;
        const double gap = AppSpacing.s12;
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

/// Formatta un indicatore tipo RSI senza decimali inutili (`50`, `52.4`).
String _formatRsi(double value) {
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();
}

/// Mappatura `badge-*` RSI → tinta del badge DS.
BadgeTone _rsiTone(String badge) {
  return switch (badge) {
    'badge-buy' => BadgeTone.success,
    'badge-sell' => BadgeTone.danger,
    _ => BadgeTone.warning,
  };
}

/// Specifica di colonna della tabella azioni monitorate.
class _TableColumn {
  const _TableColumn(
    this.label, {
    this.flex = 1,
    this.width,
    this.align = TextAlign.left,
  });

  final String label;
  final double flex;
  final double? width;
  final TextAlign align;
}

const List<_TableColumn> _columns = <_TableColumn>[
  _TableColumn('Ticker & Titolo', flex: 1),
  _TableColumn('Prezzo Live', width: 112, align: TextAlign.right),
  _TableColumn('Variazione Oggi', width: 195, align: TextAlign.right),
  _TableColumn('Range 52 Settimane', width: 180),
  _TableColumn('RSI (14)', width: 150, align: TextAlign.center),
  _TableColumn('Alert Target', width: 150, align: TextAlign.center),
  _TableColumn('P/E', width: 68, align: TextAlign.right),
  _TableColumn('Div. Yield', width: 90, align: TextAlign.right),
  _TableColumn('Azioni Rapide', width: 152, align: TextAlign.center),
];
