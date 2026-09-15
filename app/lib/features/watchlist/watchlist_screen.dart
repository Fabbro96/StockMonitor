import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/models/watchlist_item.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_delta.dart';
import '../../widgets/app_error_panel.dart';
import '../../widgets/app_market_tag.dart';
import '../../widgets/app_segmented.dart';
import '../../widgets/badges.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/page_content.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/toast.dart';
import '../stock_detail/market_editor_modal.dart' show showMarketEditor;
import '../stock_detail/stock_detail_modal.dart' show showStockDetail;
import 'watchlist_dialogs.dart';
import 'watchlist_providers.dart';

/// Watchlist & Radar Mercati: striscia statistiche, toolbar (ricerca, filtro
/// mercato, aggiunta), tabella da 40px sopra i 640px e card compatte sotto.
/// Dialog di aggiunta/alert, filtro con debounce e rimozione con undo.
class WatchlistScreen extends ConsumerStatefulWidget {
  /// Crea la schermata Watchlist.
  const WatchlistScreen({super.key});

  @override
  ConsumerState<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends ConsumerState<WatchlistScreen> {
  final TextEditingController _filterController = TextEditingController();
  Timer? _filterDebounce;
  bool _hasFilterText = false;

  @override
  void dispose() {
    _filterDebounce?.cancel();
    _filterController.dispose();
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

  void _clearAllFilters() {
    _clearFilter();
    ref.read(watchlistMarketFilterProvider.notifier).select(null);
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
      message: '${item.ticker} rimosso da Mercati',
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

  /// Apre la scheda tecnica del titolo.
  void _openStock(WatchlistItem item) =>
      showStockDetail(context, item.ticker, onChanged: _reloadList);

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
            : 'Errore nel caricamento della sezione Mercati',
        type: AppToastType.error,
      );
    });

    final AsyncValue<List<WatchlistItem>> asyncItems = ref.watch(
      watchlistProvider,
    );
    final List<WatchlistItem> filtered = ref.watch(filteredWatchlistProvider);
    final List<WatchlistItem> items =
        asyncItems.value ?? const <WatchlistItem>[];
    final bool loading = asyncItems.isLoading && asyncItems.value == null;

    return PageContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _StatsRow(stats: computeWatchlistStats(items), loading: loading),
          const SizedBox(height: AppSpacing.s14),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _Toolbar(
                  filterController: _filterController,
                  hasFilterText: _hasFilterText,
                  onFilterChanged: _onFilterChanged,
                  onClearFilter: _clearFilter,
                  onAdd: _openAddDialog,
                ),
                const SizedBox(height: AppSpacing.s10),
                _ListCaption(
                  loading: loading,
                  total: items.length,
                  shown: filtered.length,
                ),
                const SizedBox(height: AppSpacing.s8),
                _buildContent(asyncItems, items, filtered),
              ],
            ),
          ),
        ],
      ),
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
    return context.isCompact
        ? _buildCards(filtered)
        : _WatchlistTable(
            items: filtered,
            onOpenStock: _openStock,
            onOpenAlert: (WatchlistItem item) => showWatchlistAlertDialog(context, item),
            onAddHolding: (WatchlistItem item) =>
                context.go('/portfolio?add=${Uri.encodeComponent(item.ticker)}'),
            onEditMarket: _editMarket,
            onRemove: (WatchlistItem item) => unawaited(_removeItem(item)),
          );
  }

  void _editMarket(WatchlistItem item) {
    showMarketEditor(
      context,
      item.ticker,
      initialMarket: item.market,
      onSaved: (_) => _reloadList(),
    );
  }

  Widget _buildLoadingRows() {
    return const Column(
      children: <Widget>[
        SkeletonRow(height: AppSizes.rowCompact),
        SkeletonRow(height: AppSizes.rowCompact),
        SkeletonRow(height: AppSizes.rowCompact),
      ],
    );
  }

  Widget _buildEmptyRadar() {
    return EmptyState(
      icon: const Icon(Icons.radar),
      title: 'Radar vuoto',
      message: 'Nessun titolo nel radar.',
      actions: <Widget>[
        AppButton(
          label: 'Aggiungi titolo',
          icon: const Icon(Icons.add),
          size: AppButtonSize.sm,
          onPressed: _openAddDialog,
        ),
      ],
    );
  }

  Widget _buildEmptyFilter() {
    return EmptyState(
      icon: const Icon(Icons.search_off),
      title: 'Nessun risultato',
      message: 'Nessun titolo corrisponde ai filtri attivi.',
      actions: <Widget>[
        AppButton(
          label: 'Azzera filtri',
          variant: AppButtonVariant.ghost,
          size: AppButtonSize.sm,
          onPressed: _clearAllFilters,
        ),
      ],
    );
  }

  Widget _buildErrorState() {
    return AppErrorPanel(
      message: 'Errore nel caricamento della sezione Mercati.',
      onRetry: () => ref.read(watchlistProvider.notifier).reload(),
    );
  }

  // --- Card (sotto 640px) -------------------------------------------------

  Widget _buildCards(List<WatchlistItem> items) {
    return Column(
      children: <Widget>[
        for (int i = 0; i < items.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: AppSpacing.s8),
          _CompactRow(
            key: ValueKey<int>(items[i].id),
            item: items[i],
            onOpenStock: _openStock,
            onOpenAlert: (WatchlistItem item) => showWatchlistAlertDialog(context, item),
            onAddHolding: (WatchlistItem item) =>
                context.go('/portfolio?add=${Uri.encodeComponent(item.ticker)}'),
            onEditMarket: _editMarket,
            onRemove: (WatchlistItem item) => unawaited(_removeItem(item)),
          ),
        ],
      ],
    );
  }
}

// --- Toolbar ----------------------------------------------------------------

class _Toolbar extends ConsumerWidget {
  const _Toolbar({
    required this.filterController,
    required this.hasFilterText,
    required this.onFilterChanged,
    required this.onClearFilter,
    required this.onAdd,
  });

  final TextEditingController filterController;
  final bool hasFilterText;
  final ValueChanged<String> onFilterChanged;
  final VoidCallback onClearFilter;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? market = ref.watch(watchlistMarketFilterProvider);

    Widget search() => TextField(
          controller: filterController,
          onChanged: onFilterChanged,
          textInputAction: TextInputAction.search,
          style: AppText.small(context),
          decoration: InputDecoration(
            hintText: 'Filtra ticker...',
            prefixIcon: const Icon(Icons.search, size: 16),
            suffixIcon: hasFilterText
                ? IconButton(
                    icon: const Icon(Icons.close, size: 15),
                    tooltip: 'Pulisci filtro',
                    onPressed: onClearFilter,
                  )
                : null,
          ),
        );

    Widget marketFilter({bool expand = false}) => AppSegmented<String?>(
          segments: const <AppSegment<String?>>[
            AppSegment<String?>(value: null, label: 'Tutti'),
            AppSegment<String?>(value: 'IT', label: 'IT'),
            AppSegment<String?>(value: 'US', label: 'US'),
            AppSegment<String?>(value: 'EU', label: 'EU'),
          ],
          selected: market,
          dense: true,
          expand: expand,
          semanticsLabel: 'Filtro mercato',
          onSelected: (String? value) =>
              ref.read(watchlistMarketFilterProvider.notifier).select(value),
        );

    final Widget addButton = AppButton(
      label: 'Aggiungi',
      icon: const Icon(Icons.add),
      onPressed: onAdd,
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth >= 900) {
          return Row(
            children: <Widget>[
              SizedBox(width: 260, child: search()),
              const Spacer(),
              marketFilter(),
              const SizedBox(width: AppSpacing.s10),
              addButton,
            ],
          );
        }
        if (!context.isCompact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(child: search()),
                  const SizedBox(width: AppSpacing.s10),
                  addButton,
                ],
              ),
              const SizedBox(height: AppSpacing.s10),
              marketFilter(),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            search(),
            const SizedBox(height: AppSpacing.s10),
            Row(
              children: <Widget>[
                Expanded(child: marketFilter(expand: true)),
                const SizedBox(width: AppSpacing.s8),
                addButton,
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Riga di contesto sotto la toolbar: istruzioni e conteggio dei titoli.
class _ListCaption extends StatelessWidget {
  const _ListCaption({
    required this.loading,
    required this.total,
    required this.shown,
  });

  final bool loading;
  final int total;
  final int shown;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final String count = loading
        ? 'Caricamento…'
        : (shown == total ? '$total titoli' : '$shown di $total titoli');
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            'Clicca su un titolo per aprire la scheda tecnica completa.',
            style: AppText.caption(context),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: AppSpacing.s10),
        Text(
          count,
          style: AppText.caption(context).copyWith(color: t.textMuted),
        ),
      ],
    );
  }
}

// --- Tabella (≥640px) -------------------------------------------------------

/// Specifica di colonna della tabella titoli monitorati.
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

class _WatchlistTable extends StatelessWidget {
  const _WatchlistTable({
    required this.items,
    required this.onOpenStock,
    required this.onOpenAlert,
    required this.onAddHolding,
    required this.onEditMarket,
    required this.onRemove,
  });

  final List<WatchlistItem> items;
  final ValueChanged<WatchlistItem> onOpenStock;
  final ValueChanged<WatchlistItem> onOpenAlert;
  final ValueChanged<WatchlistItem> onAddHolding;
  final ValueChanged<WatchlistItem> onEditMarket;
  final ValueChanged<WatchlistItem> onRemove;

  @override
  Widget build(BuildContext context) {
    final bool narrow = context.windowWidth < AppBreakpoints.drawer;
    final List<_TableColumn> columns = <_TableColumn>[
      const _TableColumn('Titolo', flex: 3),
      const _TableColumn('Prezzo', width: 104, align: TextAlign.right),
      const _TableColumn('Δ%', width: 84, align: TextAlign.right),
      if (!narrow) const _TableColumn('RSI (14)', width: 86, align: TextAlign.center),
      if (!narrow) const _TableColumn('Alert', width: 112, align: TextAlign.center),
      _TableColumn(narrow ? '' : 'Azioni', width: narrow ? 44 : 128, align: TextAlign.right),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.control),
      child: Column(
        children: <Widget>[
          _HeaderRow(columns: columns),
          for (final WatchlistItem item in items)
            _WatchlistRow(
              key: ValueKey<int>(item.id),
              item: item,
              columns: columns,
              narrow: narrow,
              onOpenStock: onOpenStock,
              onOpenAlert: onOpenAlert,
              onAddHolding: onAddHolding,
              onEditMarket: onEditMarket,
              onRemove: onRemove,
            ),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.columns});

  final List<_TableColumn> columns;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Container(
      height: AppSizes.tableHeader,
      color: t.surfaceSunken,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s10),
      child: Row(
        children: <Widget>[
          for (final _TableColumn column in columns)
            if (column.width != null)
              SizedBox(
                width: column.width,
                child: Text(
                  column.label.toUpperCase(),
                  textAlign: column.align,
                  style: AppText.tableHeader(context),
                ),
              )
            else
              Expanded(
                flex: column.flex.round(),
                child: Text(
                  column.label.toUpperCase(),
                  textAlign: column.align,
                  style: AppText.tableHeader(context),
                ),
              ),
        ],
      ),
    );
  }
}

class _WatchlistRow extends StatefulWidget {
  const _WatchlistRow({
    super.key,
    required this.item,
    required this.columns,
    required this.narrow,
    required this.onOpenStock,
    required this.onOpenAlert,
    required this.onAddHolding,
    required this.onEditMarket,
    required this.onRemove,
  });

  final WatchlistItem item;
  final List<_TableColumn> columns;
  final bool narrow;
  final ValueChanged<WatchlistItem> onOpenStock;
  final ValueChanged<WatchlistItem> onOpenAlert;
  final ValueChanged<WatchlistItem> onAddHolding;
  final ValueChanged<WatchlistItem> onEditMarket;
  final ValueChanged<WatchlistItem> onRemove;

  @override
  State<_WatchlistRow> createState() => _WatchlistRowState();
}

class _WatchlistRowState extends State<_WatchlistRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final WatchlistItem item = widget.item;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onOpenStock(item),
        child: AnimatedContainer(
          duration: AppMotion.effective(context, AppMotion.fast),
          curve: AppMotion.ease,
          height: AppSizes.rowCompact,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s10),
          decoration: BoxDecoration(
            color: _hovered ? t.surfaceHover : Colors.transparent,
            border: Border(bottom: BorderSide(color: t.borderSubtle)),
          ),
          child: Row(
            children: <Widget>[
              Expanded(flex: 3, child: _ticker(context, item)),
              SizedBox(width: 104, child: _price(context, item)),
              SizedBox(width: 84, child: _change(context, item)),
              if (!widget.narrow) SizedBox(width: 86, child: _rsi(context, item)),
              if (!widget.narrow) SizedBox(width: 112, child: _alert(context, item)),
              SizedBox(
                width: widget.narrow ? 44 : 128,
                child: widget.narrow
                    ? Align(
                        alignment: Alignment.centerRight,
                        child: _OverflowMenu(item: item, onSelected: _onMenu),
                      )
                    : _ActionsReveal(
                        hovered: _hovered,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: <Widget>[
                            _action(
                              icon: Icons.arrow_outward,
                              tooltip: 'Apri scheda completa',
                              semanticLabel: 'Analisi e scheda completa per ${item.ticker}',
                              onPressed: () => widget.onOpenStock(item),
                            ),
                            _action(
                              icon: _hasAlert(item)
                                  ? Icons.notifications_active
                                  : Icons.notifications_none,
                              tooltip: 'Imposta alert di prezzo',
                              semanticLabel: 'Imposta alert di prezzo per ${item.ticker}',
                              active: _hasAlert(item),
                              onPressed: () => widget.onOpenAlert(item),
                            ),
                            _action(
                              icon: Icons.business_center_outlined,
                              tooltip: 'Aggiungi alle holding',
                              semanticLabel: 'Aggiungi ${item.ticker} al portafoglio',
                              onPressed: () => widget.onAddHolding(item),
                            ),
                            _action(
                              icon: Icons.delete_outline,
                              tooltip: 'Rimuovi dal radar',
                              semanticLabel: 'Rimuovi ${item.ticker} da Mercati',
                              danger: true,
                              onPressed: () => widget.onRemove(item),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onMenu(_RowAction action) {
    final WatchlistItem item = widget.item;
    switch (action) {
      case _RowAction.open:
        widget.onOpenStock(item);
      case _RowAction.alert:
        widget.onOpenAlert(item);
      case _RowAction.holding:
        widget.onAddHolding(item);
      case _RowAction.market:
        widget.onEditMarket(item);
      case _RowAction.remove:
        widget.onRemove(item);
    }
  }

  Widget _action({
    required IconData icon,
    required String tooltip,
    required String semanticLabel,
    required VoidCallback onPressed,
    bool danger = false,
    bool active = false,
  }) {
    // Niente padding tra le azioni: l'area sensibile da 32px è già il
    // distanziatore (la colonna "Azioni" è larga esattamente 4 × 32).
    return AppIconButton(
      icon: Icon(icon),
      size: AppSizes.iconButtonSm,
      iconSize: AppSizes.iconSm,
      minTargetSize: AppSizes.touchTarget,
      tooltip: tooltip,
      semanticLabel: semanticLabel,
      danger: danger,
      selected: active,
      onPressed: onPressed,
    );
  }

  Widget _ticker(BuildContext context, WatchlistItem item) {
    final AppTokens t = context.tokens;
    final String name = item.name?.isNotEmpty == true ? item.name! : item.ticker;
    final String notes = item.notes;
    return Row(
      children: <Widget>[
        _MarketTagButton(item: item, onPressed: () => widget.onEditMarket(item)),
        const SizedBox(width: AppSpacing.s6),
        InkWell(
          onTap: () => widget.onOpenStock(item),
          borderRadius: BorderRadius.circular(AppRadii.small),
          child: Text(
            item.ticker,
            style: AppText.mono(context, size: 13, weight: FontWeight.w700, color: t.primary),
          ),
        ),
        const SizedBox(width: AppSpacing.s6),
        Expanded(
          child: Tooltip(
            message: notes.isEmpty ? name : '$name\n$notes',
            child: Text(
              name,
              style: AppText.caption(context).copyWith(color: t.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }

  Widget _price(BuildContext context, WatchlistItem item) {
    return Text(
      formatCurrency(item.currentPrice, currency: _currencyOf(item)),
      textAlign: TextAlign.right,
      style: AppText.tableCellNum(context).copyWith(fontWeight: FontWeight.w600),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _change(BuildContext context, WatchlistItem item) {
    return Align(
      alignment: Alignment.centerRight,
      child: AppDelta(value: item.changePercent, suffix: '%', size: 12.5),
    );
  }

  Widget _rsi(BuildContext context, WatchlistItem item) {
    final AppTokens t = context.tokens;
    final String fullStatus = item.rsiStatus.isEmpty ? 'Neutro' : item.rsiStatus;
    final String value = _formatRsi(item.rsi);
    return Tooltip(
      message: 'RSI a 14 periodi: $value — $fullStatus',
      child: Text(
        value,
        textAlign: TextAlign.center,
        style: AppText.tableCellNum(context).copyWith(
          color: _rsiToneColor(t, item.rsiBadge),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _alert(BuildContext context, WatchlistItem item) {
    return Center(
      child: _AlertAffordance(
        item: item,
        onPressed: () => widget.onOpenAlert(item),
      ),
    );
  }
}

/// Tag di mercato cliccabile: apre l'editor del mercato di quotazione.
class _MarketTagButton extends StatelessWidget {
  const _MarketTagButton({required this.item, required this.onPressed});

  final WatchlistItem item;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Modifica mercato',
      child: Semantics(
        button: true,
        label: 'Modifica mercato di ${item.ticker}',
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadii.tag),
          child: AppMarketTag.forTicker(item.ticker, market: item.market),
        ),
      ),
    );
  }
}

// --- Azioni di riga ---------------------------------------------------------

/// Reveal delle azioni al passaggio del mouse o al focus da tastiera.
class _ActionsReveal extends StatefulWidget {
  const _ActionsReveal({required this.hovered, required this.child});

  final bool hovered;
  final Widget child;

  @override
  State<_ActionsReveal> createState() => _ActionsRevealState();
}

class _ActionsRevealState extends State<_ActionsReveal> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      onFocusChange: (bool value) => setState(() => _focused = value),
      child: AnimatedOpacity(
        duration: AppMotion.effective(context, AppMotion.fast),
        curve: AppMotion.ease,
        opacity: (widget.hovered || _focused) ? 1 : 0,
        child: widget.child,
      ),
    );
  }
}

enum _RowAction { open, alert, holding, market, remove }

/// Menu di overflow della riga: dati secondari e azioni complete.
class _OverflowMenu extends StatelessWidget {
  const _OverflowMenu({required this.item, required this.onSelected});

  final WatchlistItem item;
  final ValueChanged<_RowAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return PopupMenuButton<_RowAction>(
      tooltip: 'Altre azioni',
      icon: Icon(Icons.more_horiz, size: AppSizes.icon, color: t.textSecondary),
      padding: EdgeInsets.zero,
      splashRadius: 16,
      // Più spazio del default (280) per i dati secondari in mono tabulare.
      constraints: const BoxConstraints(minWidth: 224, maxWidth: 320),
      onSelected: onSelected,
      itemBuilder: (BuildContext context) => <PopupMenuEntry<_RowAction>>[
        PopupMenuItem<_RowAction>(
          enabled: false,
          height: 30,
          child: Text('Dati secondari', style: AppText.micro(context)),
        ),
        PopupMenuItem<_RowAction>(
          enabled: false,
          height: 30,
          child: _MenuDatum(
            label: 'RSI (14)',
            value: '${_formatRsi(item.rsi)} · ${_shortRsiStatus(item.rsiStatus)}',
          ),
        ),
        // Niente RangeBar nel menu: il popup misura i discendenti in
        // larghezza intrinseca e il `LayoutBuilder` interno alla barra non è
        // compatibile. I due valori restano leggibili in mono tabulare.
        PopupMenuItem<_RowAction>(
          enabled: false,
          height: 30,
          child: _MenuDatum(label: 'Range 52s', value: _rangeLabel(item)),
        ),
        PopupMenuItem<_RowAction>(
          enabled: false,
          height: 30,
          child: _MenuDatum(
            label: 'Posizione 52s',
            value: (item.fiftyTwoWeekHigh ?? 0) <= 0
                ? '—'
                : '${(item.fiftyTwoWeekPct ?? 50).round()}%',
          ),
        ),
        PopupMenuItem<_RowAction>(
          enabled: false,
          height: 30,
          child: _MenuDatum(
            label: 'P/E',
            value: item.peRatio == null ? '—' : item.peRatio!.toStringAsFixed(1),
          ),
        ),
        PopupMenuItem<_RowAction>(
          enabled: false,
          height: 30,
          child: _MenuDatum(
            label: 'Div. yield',
            value: item.dividendYield == null
                ? '—'
                : '${item.dividendYield!.toStringAsFixed(2)}%',
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<_RowAction>(
          value: _RowAction.open,
          height: 38,
          child: _MenuAction(icon: Icons.arrow_outward, label: 'Apri scheda completa'),
        ),
        const PopupMenuItem<_RowAction>(
          value: _RowAction.alert,
          height: 38,
          child: _MenuAction(icon: Icons.notifications_none, label: 'Imposta alert di prezzo'),
        ),
        const PopupMenuItem<_RowAction>(
          value: _RowAction.holding,
          height: 38,
          child: _MenuAction(icon: Icons.business_center_outlined, label: 'Aggiungi alle holding'),
        ),
        const PopupMenuItem<_RowAction>(
          value: _RowAction.market,
          height: 38,
          child: _MenuAction(icon: Icons.public, label: 'Correggi mercato'),
        ),
        const PopupMenuItem<_RowAction>(
          value: _RowAction.remove,
          height: 38,
          child: _MenuAction(icon: Icons.delete_outline, label: 'Rimuovi dal radar', danger: true),
        ),
      ],
    );
  }

  /// Etichetta compatta del range 52 settimane (`8,00 € – 30,00 €`).
  String _rangeLabel(WatchlistItem item) {
    final double low = item.fiftyTwoWeekLow ?? 0;
    final double high = item.fiftyTwoWeekHigh ?? 0;
    if (low <= 0 && high <= 0) return '—';
    return '${formatCurrency(low, currency: _currencyOf(item))} – '
        '${formatCurrency(high, currency: _currencyOf(item))}';
  }
}

class _MenuDatum extends StatelessWidget {
  const _MenuDatum({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label.toUpperCase(),
            style: AppText.micro(context),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: AppSpacing.s10),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: AppText.mono(context, size: 12, weight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _MenuAction extends StatelessWidget {
  const _MenuAction({
    required this.icon,
    required this.label,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final Color color = danger ? t.danger : t.textSecondary;
    return Row(
      children: <Widget>[
        Icon(icon, size: AppSizes.iconSm, color: color),
        const SizedBox(width: AppSpacing.s10),
        Expanded(
          child: Text(
            label,
            style: AppText.small(context).copyWith(color: danger ? t.danger : null),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// --- Riga compatta (<640px) -------------------------------------------------

class _CompactRow extends StatelessWidget {
  const _CompactRow({
    super.key,
    required this.item,
    required this.onOpenStock,
    required this.onOpenAlert,
    required this.onAddHolding,
    required this.onEditMarket,
    required this.onRemove,
  });

  final WatchlistItem item;
  final ValueChanged<WatchlistItem> onOpenStock;
  final ValueChanged<WatchlistItem> onOpenAlert;
  final ValueChanged<WatchlistItem> onAddHolding;
  final ValueChanged<WatchlistItem> onEditMarket;
  final ValueChanged<WatchlistItem> onRemove;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final String name = item.name?.isNotEmpty == true ? item.name! : item.ticker;

    return AppCard(
      onTap: () => onOpenStock(item),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12, vertical: AppSpacing.s10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              _MarketTagButton(item: item, onPressed: () => onEditMarket(item)),
              const SizedBox(width: AppSpacing.s6),
              Expanded(
                child: Text(
                  item.ticker,
                  style: AppText.mono(context, size: 13.5, weight: FontWeight.w700, color: t.primary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AppDelta(value: item.changePercent, suffix: '%', size: 12.5),
            ],
          ),
          const SizedBox(height: AppSpacing.s2),
          Row(
            children: <Widget>[
              Expanded(
                child: Tooltip(
                  message: item.notes.isEmpty ? name : '$name\n${item.notes}',
                  child: Text(
                    name,
                    style: AppText.caption(context).copyWith(color: t.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Text(
                formatCurrency(item.currentPrice, currency: _currencyOf(item)),
                style: AppText.mono(context, size: 13, weight: FontWeight.w600),
              ),
              const SizedBox(width: AppSpacing.s2),
              _OverflowMenu(
                item: item,
                onSelected: (_RowAction action) => switch (action) {
                  _RowAction.open => onOpenStock(item),
                  _RowAction.alert => onOpenAlert(item),
                  _RowAction.holding => onAddHolding(item),
                  _RowAction.market => onEditMarket(item),
                  _RowAction.remove => onRemove(item),
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// --- Striscia statistiche ---------------------------------------------------

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats, required this.loading});

  final WatchlistStats stats;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;

    final List<Widget> tiles = <Widget>[
      _StatTile(
        label: 'Titoli monitorati',
        value: loading ? '--' : '${stats.count}',
        description: 'Azioni ed ETF sotto osservazione',
        color: t.primary,
      ),
      _StatTile(
        label: 'In rialzo oggi',
        value: loading ? '--' : '${stats.gainers}',
        description: loading ? 'Variazione giornaliera positiva' : '${stats.losers} in ribasso oggi',
        color: t.successText,
      ),
      _StatTile(
        label: 'Alert attivi',
        value: loading ? '--' : '${stats.activeAlerts}',
        description: 'Soglie di prezzo monitorate',
        color: t.warning,
      ),
    ];

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int columns = constraints.maxWidth >= 560 ? 3 : 2;
        const double gap = AppSpacing.s12;
        final double itemWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (final Widget tile in tiles) SizedBox(width: itemWidth, child: tile),
          ],
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
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
    return AppCard(
      subtle: true,
      dense: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label.toUpperCase(),
            style: AppText.statLabel(context),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(value, style: AppText.statValueSm(context).copyWith(color: color)),
          const SizedBox(height: AppSpacing.s2),
          Text(
            description,
            style: AppText.statDesc(context),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// --- Celle condivise --------------------------------------------------------

/// Valuta del titolo con fallback EUR (il backend può ometterla).
String _currencyOf(WatchlistItem item) => item.currency ?? 'EUR';

/// Formatta un indicatore tipo RSI senza decimali inutili (`50`, `52.4`).
String _formatRsi(double value) {
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();
}

/// Etichetta breve dello stato RSI (`Neutro`, `Ipercomprato`...).
String _shortRsiStatus(String status) {
  final String full = status.isEmpty ? 'Neutro' : status;
  final String short = full.split('(').first.trim();
  return short.isEmpty ? full : short;
}

/// Colore del valore RSI in base alla banda (`badge-buy`/`badge-sell`).
Color _rsiToneColor(AppTokens t, String badge) {
  return switch (badge) {
    'badge-buy' => t.successText,
    'badge-sell' => t.danger,
    _ => t.warning,
  };
}

bool _hasAlert(WatchlistItem item) =>
    item.alertAbove != null || item.alertBelow != null || item.alertTriggered;

/// Badge/icona alert con tooltip; il tap apre il dialog delle soglie.
class _AlertAffordance extends StatelessWidget {
  const _AlertAffordance({required this.item, required this.onPressed});

  final WatchlistItem item;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final Widget content;
    final String tooltip;
    if (item.alertTriggered) {
      content = const AppBadge(
        label: 'Scattato',
        tone: BadgeTone.danger,
        icon: Icon(Icons.notifications_active),
      );
      tooltip = 'Alert scattato: prezzo oltre la soglia';
    } else if (item.alertAbove != null || item.alertBelow != null) {
      final List<String> lines = <String>[
        if (item.alertAbove != null)
          '> ${formatCurrency(item.alertAbove, currency: _currencyOf(item))}',
        if (item.alertBelow != null)
          '< ${formatCurrency(item.alertBelow, currency: _currencyOf(item))}',
      ];
      content = AppBadge(label: lines.join('\n'), tone: BadgeTone.warning);
      tooltip = 'Alert attivi: soglie di prezzo monitorate';
    } else {
      content = Icon(Icons.notifications_none, size: AppSizes.icon, color: t.textFaint);
      tooltip = 'Nessun alert impostato';
    }

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadii.tag),
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
      ),
    );
  }
}
