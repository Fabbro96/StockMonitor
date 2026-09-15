import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/models/portfolio.dart';
import '../../shell/topbar.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_confirm_dialog.dart';
import '../../widgets/app_error_panel.dart';
import '../../widgets/app_segmented.dart';
import '../../widgets/badges.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/page_content.dart';
import '../../widgets/section_header.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/toast.dart';
import '../stock_detail/market_editor_modal.dart' show showMarketEditor;
import '../stock_detail/stock_detail_modal.dart' show showStockDetail;
import 'allocation_card.dart';
import 'dividends_section.dart';
import 'holding_dialog.dart';
import 'holdings_table.dart';
import 'portfolio_edits.dart';
import 'portfolio_modal.dart';
import 'portfolio_providers.dart';
import 'portfolio_table.dart';
import 'portfolio_tools_providers.dart';
import 'rebalancer_section.dart';
import 'tools/csv_tools.dart';
import 'transactions_section.dart';

/// Ancore in-page della pagina Portafoglio (scroll, nessuna rotta).
enum _PortfolioSection { positions, allocation, transactions, dividends, rebalancer }

extension on _PortfolioSection {
  /// Etichetta della voce nella barra delle ancore.
  String get label => switch (this) {
    _PortfolioSection.positions => 'Posizioni',
    _PortfolioSection.allocation => 'Allocazione',
    _PortfolioSection.transactions => 'Transazioni',
    _PortfolioSection.dividends => 'Dividendi',
    _PortfolioSection.rebalancer => 'Ribilanciatore',
  };

  /// Etichetta ridotta sotto 640px: cinque voci non ci stanno per esteso.
  String get compactLabel => switch (this) {
    _PortfolioSection.positions => 'Posizioni',
    _PortfolioSection.allocation => 'Allocaz.',
    _PortfolioSection.transactions => 'Transaz.',
    _PortfolioSection.dividends => 'Dividendi',
    _PortfolioSection.rebalancer => 'Ribilancio',
  };
}

/// Gestione Portafoglio: riepilogo, budget, holdings con inline edit,
/// allocazione e sezioni tools (transazioni, dividendi, rebalancer).
class PortfolioScreen extends ConsumerStatefulWidget {
  /// Crea la schermata Portafoglio.
  const PortfolioScreen({super.key});

  @override
  ConsumerState<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends ConsumerState<PortfolioScreen> {
  late final TopbarActionsController _topbar;

  /// Modifiche inline pendenti (id holding → bozza).
  final Map<int, HoldingEdit> _edits = <int, HoldingEdit>{};

  /// Contatore che invalida i controller di cella dopo annulla/salva.
  int _epoch = 0;

  /// Ultimo ticker gestito dal deep-link `?add=TICKER`.
  String? _handledAddTicker;

  /// Ultimo valore osservato del query param `add` (`null` = assente):
  /// serve a reagire ai cambi di query a rotta invariata (go_router riusa
  /// l'element di `/portfolio`).
  String? _lastAddQuery;

  /// Ultimo errore già notificato (dedupe tra holdings e riepilogo).
  String? _lastErrorToast;

  /// Chiave della barra di salvataggio: ne misura l'altezza reale per
  /// riservare spazio sotto il contenuto, senza coprire l'ultima riga.
  final GlobalKey _saveBarKey = GlobalKey();

  /// Altezza misurata della barra (0 finché non è stata disegnata).
  double _saveBarHeight = 0;

  /// Ancore in-page: chiavi delle sezioni impilate e voce attiva.
  final Map<_PortfolioSection, GlobalKey> _sectionKeys =
      <_PortfolioSection, GlobalKey>{
        for (final _PortfolioSection section in _PortfolioSection.values)
          section: GlobalKey(),
      };
  _PortfolioSection _activeSection = _PortfolioSection.positions;

  @override
  void initState() {
    super.initState();
    _topbar = ref.read(topbarActionsProvider.notifier);
    ref.read(allocationViewProvider.notifier).load();
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted) return;
      _topbar.set(this, _topbarActions());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `GoRouterState.of` registra una dipendenza dall'InheritedNotifier dello
    // state registry: il callback arriva a ogni navigazione, anche quando
    // cambia solo il query param sulla stessa rotta.
    final String? add = _addParamValue();
    if (add == _lastAddQuery) return;
    _lastAddQuery = add;
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      _handleAddParam();
    });
  }

  @override
  void dispose() {
    _topbar.clear(this);
    super.dispose();
  }

  List<Widget> _topbarActions() {
    // Su mobile i tre bottoni diventano icon-only: la topbar non ha wrap e i
    // label lunghi andrebbero in overflow (<640px).
    if (context.isCompact) {
      return <Widget>[
        AppIconButton(
          icon: const Icon(Icons.file_download_outlined),
          tooltip: 'Esporta CSV',
          semanticLabel: 'Esporta CSV',
          onPressed: _exportCsv,
        ),
        AppIconButton(
          icon: const Icon(Icons.file_upload_outlined),
          tooltip: 'Importa CSV',
          semanticLabel: 'Importa CSV',
          onPressed: _importCsv,
        ),
        AppIconButton(
          icon: const Icon(Icons.add),
          tooltip: 'Aggiungi holding',
          semanticLabel: 'Aggiungi holding',
          onPressed: _addHolding,
        ),
      ];
    }
    return <Widget>[
      AppButton(
        label: 'Esporta CSV',
        icon: const Icon(Icons.file_download_outlined),
        size: AppButtonSize.sm,
        onPressed: _exportCsv,
      ),
      AppButton(
        label: 'Importa CSV',
        icon: const Icon(Icons.file_upload_outlined),
        size: AppButtonSize.sm,
        onPressed: _importCsv,
      ),
      AppButton(
        label: 'Aggiungi holding',
        icon: const Icon(Icons.add),
        size: AppButtonSize.sm,
        onPressed: _addHolding,
      ),
    ];
  }

  // --- Deep link ?add=TICKER ----------------------------------------------

  /// Valore del param `add`: `null` = assente, `''` = presente ma vuoto
  /// (`?add=`, la dashboard ci naviga e apre il modal senza prefill).
  String? _addParamValue() =>
      GoRouterState.of(context).uri.queryParameters['add'];

  void _handleAddParam() {
    if (!mounted) return;
    final String? raw = _addParamValue();
    if (raw == null) {
      // Param consumato: riabilita la gestione per la prossima apertura.
      _handledAddTicker = null;
      return;
    }
    final String normalized = raw.trim().toUpperCase();
    if (_handledAddTicker == normalized) return;
    _handledAddTicker = normalized;
    unawaited(_openAddFromQuery(normalized));
  }

  Future<void> _openAddFromQuery(String ticker) async {
    // Consuma subito il query param (rotta invariata ma senza `add`): evita
    // riaperture su rebuild/refresh mentre il modal è aperto.
    if (mounted && _addParamValue() != null) {
      context.go('/portfolio');
    }
    await _addHolding(initialTicker: ticker);
  }

  // --- Ancore in-page -------------------------------------------------------

  /// Scorre alla sezione [section] senza toccare rotta o query.
  void _scrollTo(_PortfolioSection section) {
    setState(() => _activeSection = section);
    final BuildContext? target = _sectionKeys[section]?.currentContext;
    if (target == null) return;
    unawaited(
      Scrollable.ensureVisible(
        target,
        duration: AppMotion.effective(context, AppMotion.medium),
        curve: AppMotion.ease,
      ),
    );
  }

  // --- Azioni -------------------------------------------------------------

  Future<void> _exportCsv() async {
    // `Future.sync` assorbe sia `void` sia `Future<void>` (firma tools).
    await Future<void>.sync(() => exportPortfolioCsv(context));
  }

  Future<void> _importCsv() async {
    await Future<void>.sync(() => showImportPortfolioDialog(context));
    if (!mounted) return;
    await reloadPortfolio(ref);
  }

  Future<void> _addHolding({String initialTicker = ''}) async {
    final bool saved = await showAddHoldingDialog(
      context,
      initialTicker: initialTicker,
    );
    if (!mounted || !saved) return;
    _invalidateAggregates();
  }

  void _invalidateAggregates() {
    ref.invalidate(portfolioSummaryProvider);
    ref.invalidate(realizedPnlProvider);
    // Il calendario dividendi dipende dalle holdings: senza questa invalidazione
    // resterebbe vecchio dopo add/delete/undo/batch save (parità legacy).
    ref.invalidate(dividendsProvider);
  }

  void _reloadFromDetail() => unawaited(reloadPortfolio(ref));

  void _openTicker(Holding holding) => unawaited(
    showStockDetail(context, holding.ticker, onChanged: _reloadFromDetail),
  );

  void _openMarketEditor(Holding holding) => unawaited(
    showMarketEditor(
      context,
      holding.ticker,
      initialMarket: holding.market,
      onSaved: (_) => _reloadFromDetail(),
    ),
  );

  Future<void> _deleteHolding(Holding holding) async {
    try {
      await ref.read(portfolioProvider.notifier).remove(holding.id);
    } on ApiException catch (error) {
      if (!mounted) return;
      showAppToast(context, message: error.message, type: AppToastType.error);
      return;
    } catch (_) {
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Errore durante l\'eliminazione',
        type: AppToastType.error,
      );
      return;
    }
    if (!mounted) return;
    _invalidateAggregates();
    if (_edits.containsKey(holding.id)) {
      setState(() => _edits.remove(holding.id));
    }
    showAppToast(
      context,
      message: '${holding.ticker} eliminata con successo',
      type: AppToastType.info,
      actionLabel: 'Annulla',
      onAction: () => unawaited(_restoreHolding(holding)),
    );
  }

  Future<void> _restoreHolding(Holding holding) async {
    try {
      await ref.read(portfolioProvider.notifier).restore(holding);
      if (!mounted) return;
      _invalidateAggregates();
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

  Future<void> _seedDemo() async {
    try {
      final String message = await ref
          .read(portfolioProvider.notifier)
          .seedDemo();
      if (!mounted) return;
      _invalidateAggregates();
      showAppToast(context, message: message, type: AppToastType.success);
    } on ApiException catch (error) {
      if (!mounted) return;
      showAppToast(context, message: error.message, type: AppToastType.error);
    } catch (_) {
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Errore nel caricamento della demo',
        type: AppToastType.error,
      );
    }
  }

  // --- Inline edit / save bar ---------------------------------------------

  void _onEdit(Holding holding, {double? quantity, double? avgPrice}) {
    final HoldingEdit current = holdingEditOf(holding, _edits);
    final HoldingEdit next = current.copyWith(
      quantity: quantity,
      avgPrice: avgPrice,
    );
    setState(() {
      if (next.changed) {
        _edits[holding.id] = next;
      } else {
        _edits.remove(holding.id);
      }
    });
  }

  Future<void> _cancelEdits() async {
    final bool confirmed = await showAppConfirm(
      context,
      title: 'Annulla modifiche',
      message: 'Vuoi annullare tutte le modifiche non salvate?',
      confirmLabel: 'Sì, annulla',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _edits.clear();
      _epoch++;
    });
    showAppToast(
      context,
      message: 'Modifiche annullate',
      type: AppToastType.info,
    );
  }

  Future<void> _openConfirmSave() async {
    if (_edits.isEmpty) return;
    final bool hasInvalid = _edits.values.any(
      (HoldingEdit edit) => !(edit.quantity > 0) || !(edit.avgPrice > 0),
    );
    if (hasInvalid) {
      showAppToast(
        context,
        message:
            'La quantità e il prezzo devono essere maggiori di 0. '
            'Per rimuovere una posizione usa l\'icona Elimina.',
        type: AppToastType.error,
      );
      return;
    }
    await showPortfolioModal<void>(
      context,
      builder: (BuildContext _) => _ConfirmSaveDialog(
        edits: _edits.values.toList(growable: false),
        onSave: _performSave,
      ),
    );
  }

  Future<void> _performSave() async {
    final List<
      ({int id, double quantity, double avgPurchasePrice, String? notes})
    >
    updates =
        <({int id, double quantity, double avgPurchasePrice, String? notes})>[
          for (final HoldingEdit edit in _edits.values)
            (
              id: edit.holding.id,
              quantity: edit.quantity,
              avgPurchasePrice: edit.avgPrice,
              notes: edit.holding.notes,
            ),
        ];
    final int count = await ref
        .read(portfolioProvider.notifier)
        .batchUpdate(updates);
    if (!mounted) return;
    _invalidateAggregates();
    setState(() {
      _edits.clear();
      _epoch++;
    });
    showAppToast(
      context,
      message: 'Salvate $count posizioni con successo!',
      type: AppToastType.success,
    );
  }

  // --- Build --------------------------------------------------------------

  /// Notifica un errore una sola volta per messaggio (holdings + riepilogo
  /// possono fallire insieme con lo stesso testo).
  void _toastErrorOnce(AsyncValue<Object?> value, String fallback) {
    if (value.hasValue && !value.hasError) {
      _lastErrorToast = null;
      return;
    }
    final Object? error = value.error;
    if (error == null) return;
    final String message = error is ApiException ? error.message : fallback;
    if (message == _lastErrorToast) return;
    _lastErrorToast = message;
    showAppToast(context, message: message, type: AppToastType.error);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<Holding>>>(portfolioProvider, (
      AsyncValue<List<Holding>>? previous,
      AsyncValue<List<Holding>> next,
    ) {
      _toastErrorOnce(next, 'Errore nel caricamento del portafoglio');
    });
    ref.listen<AsyncValue<PortfolioSummary>>(portfolioSummaryProvider, (
      AsyncValue<PortfolioSummary>? previous,
      AsyncValue<PortfolioSummary> next,
    ) {
      _toastErrorOnce(next, 'Errore nel caricamento del riepilogo');
    });

    final AsyncValue<List<Holding>> holdingsAsync = ref.watch(
      portfolioProvider,
    );
    final PortfolioSummary? summary = ref.watch(portfolioSummaryProvider).value;
    final RealizedPnl? realized = ref.watch(realizedPnlProvider).value;
    final double? budget = ref.watch(portfolioBudgetProvider).value;
    final bool hasEdits = _edits.isNotEmpty;

    final double pagePadding = AppSpacing.pagePadding(context.windowWidth);
    final double baseBottomPadding = context.isCompact ? 28 : pagePadding;
    // Spazio sotto il contenuto quando la barra di salvataggio è agganciata in
    // basso: è l'altezza misurata della barra (breakpoint, testi e safe area
    // inclusi), così non può coprire l'ultima riga.
    final double saveBarSpace = hasEdits ? _saveBarHeight : 0;
    _measureSaveBar(hasEdits);

    return Stack(
      children: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _AnchorBar(
              selected: _activeSection,
              onSelected: _scrollTo,
            ),
            Expanded(
              child: PageContent(
                padding: EdgeInsets.fromLTRB(
                  pagePadding,
                  pagePadding,
                  pagePadding,
                  baseBottomPadding + saveBarSpace,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _SummaryGrid(
                      summary: summary,
                      realized: realized,
                      holdingsCount: holdingsAsync.value?.length,
                    ),
                    const SizedBox(height: AppSpacing.s14),
                    _BudgetCard(budget: budget, summary: summary),
                    const SizedBox(height: AppSpacing.s14),
                    _section(
                      _PortfolioSection.positions,
                      _buildPositionsSection(holdingsAsync),
                    ),
                    const SizedBox(height: AppSpacing.s20),
                    _section(
                      _PortfolioSection.allocation,
                      AllocationCard(edits: _edits),
                    ),
                    const SizedBox(height: AppSpacing.s20),
                    _section(
                      _PortfolioSection.transactions,
                      const TransactionsSection(),
                    ),
                    const SizedBox(height: AppSpacing.s20),
                    _section(
                      _PortfolioSection.dividends,
                      const DividendsSection(),
                    ),
                    const SizedBox(height: AppSpacing.s20),
                    _section(
                      _PortfolioSection.rebalancer,
                      const RebalancerSection(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (hasEdits)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: PortfolioSaveBar(
              key: _saveBarKey,
              count: _edits.length,
              onCancel: _cancelEdits,
              onSave: _openConfirmSave,
            ),
          ),
      ],
    );
  }

  /// Misura la barra di salvataggio dopo il layout e aggiorna il padding della
  /// pagina quando l'altezza cambia (evita di coprire il contenuto).
  void _measureSaveBar(bool visible) {
    if (!visible) return;
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted || _edits.isEmpty) return;
      final RenderObject? renderObject =
          _saveBarKey.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) return;
      final double height = renderObject.size.height;
      if ((height - _saveBarHeight).abs() <= 0.5) return;
      setState(() => _saveBarHeight = height);
    });
  }

  /// Avvolge [child] con la chiave dell'ancora [section].
  Widget _section(_PortfolioSection section, Widget child) =>
      KeyedSubtree(key: _sectionKeys[section], child: child);

  Widget _buildPositionsSection(AsyncValue<List<Holding>> holdingsAsync) {
    final List<Holding>? holdings = holdingsAsync.value;
    final Widget content;
    if (holdingsAsync.isLoading && holdings == null) {
      content = const PortfolioTableSkeleton();
    } else if (holdingsAsync.hasError && holdings == null) {
      content = AppErrorPanel(
        message: 'Errore nel caricamento del portafoglio',
        onRetry: () => ref.read(portfolioProvider.notifier).reload(),
      );
    } else if (holdings == null || holdings.isEmpty) {
      content = EmptyState(
        icon: const Icon(Icons.account_balance_wallet_outlined),
        title: 'Portafoglio vuoto',
        message: 'Nessun titolo nel portafoglio.',
        actions: <Widget>[
          AppButton(
            label: 'Aggiungi holding',
            icon: const Icon(Icons.add),
            size: AppButtonSize.sm,
            onPressed: _addHolding,
          ),
          AppButton(
            label: 'Inizializza demo',
            icon: const Icon(Icons.auto_awesome),
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
            onPressed: _seedDemo,
          ),
        ],
      );
    } else {
      content = HoldingsTable(
        holdings: holdings,
        edits: _edits,
        epoch: _epoch,
        onEdit: _onEdit,
        onDelete: (Holding holding) => unawaited(_deleteHolding(holding)),
        onOpenTicker: _openTicker,
        onEditMarket: _openMarketEditor,
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SectionHeader(
            variant: SectionHeaderVariant.rule,
            icon: Icons.account_balance_wallet_outlined,
            overline: 'Portafoglio',
            title: 'Posizioni',
            subtitle:
                'Modifica quantità e prezzo di carico direttamente nelle '
                'celle, poi salva. Clicca sul ticker per la scheda completa.',
            trailing: AppButton(
              label: 'Aggiungi',
              icon: const Icon(Icons.add),
              size: AppButtonSize.sm,
              onPressed: _addHolding,
            ),
          ),
          content,
        ],
      ),
    );
  }
}

/// Barra delle ancore in-page: resta fissa sopra il contenuto scrollabile e
/// porta alle sezioni impilate della pagina.
class _AnchorBar extends StatelessWidget {
  const _AnchorBar({required this.selected, required this.onSelected});

  final _PortfolioSection selected;
  final ValueChanged<_PortfolioSection> onSelected;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final double pagePadding = AppSpacing.pagePadding(context.windowWidth);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.s8),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppTokens.contentMaxWidth,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: pagePadding),
              child: AppSegmented<_PortfolioSection>(
                selected: selected,
                dense: true,
                semanticsLabel: 'Sezioni del portafoglio',
                segments: <AppSegment<_PortfolioSection>>[
                  for (final _PortfolioSection section
                      in _PortfolioSection.values)
                    AppSegment<_PortfolioSection>(
                      value: section,
                      label: context.isCompact
                          ? section.compactLabel
                          : section.label,
                      tooltip: section.label,
                    ),
                ],
                onSelected: onSelected,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --- Summary bar -----------------------------------------------------------

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({
    required this.summary,
    required this.realized,
    this.holdingsCount,
  });

  final PortfolioSummary? summary;
  final RealizedPnl? realized;
  final int? holdingsCount;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final double? totalPnl = summary?.totalPnl;
    final double? totalPnlPct = summary?.totalPnlPercent;
    final double? netRealized = realized?.netRealizedProfit;
    final double? dividends = summary?.estimatedAnnualDividends;
    final double? dividendYield = summary?.estimatedDividendYield;
    final Color? pnlColor = totalPnl == null
        ? null
        : (totalPnl >= 0 ? t.successText : t.danger);

    final List<Widget> cards = <Widget>[
      StatCard(
        label: 'Valore Attuale',
        icon: const Icon(Icons.account_balance_outlined),
        value: summary == null ? '--' : formatCurrency(summary!.totalValue),
        tooltip: 'Valore di mercato odierno di tutte le azioni possedute.',
        valueColor: t.primary,
      ),
      StatCard(
        label: 'Capitale Investito',
        icon: const Icon(Icons.savings_outlined),
        value: summary == null ? '--' : formatCurrency(summary!.totalInvested),
        tooltip: 'Somma totale spesa all\'acquisto delle posizioni.',
        valueColor: t.textSecondary,
      ),
      StatCard(
        label: 'P&L Totale',
        icon: const Icon(Icons.trending_up),
        iconColor: pnlColor,
        value: totalPnl == null ? '--' : formatCurrency(totalPnl),
        delta: totalPnlPct,
        deltaLabel: '%',
        tooltip:
            'Guadagno o perdita non realizzato rispetto al prezzo medio di '
            'carico.',
        valueColor: pnlColor,
      ),
      StatCard(
        label: 'P&L Realizzato',
        icon: const Icon(Icons.receipt_long_outlined),
        value: netRealized == null
            ? '--'
            : '${netRealized >= 0 ? '+' : '−'}${formatCurrency(netRealized.abs())}',
        tooltip:
            'Profitto o perdita netto incassato da vendite concluse e '
            'dividendi (al netto delle commissioni).',
        valueColor: netRealized == null
            ? null
            : (netRealized >= 0 ? t.successText : t.danger),
      ),
      StatCard(
        label: 'Dividendi Stimati',
        icon: const Icon(Icons.payments_outlined),
        value: dividends == null
            ? '--'
            : '${formatCurrency(dividends)}/anno '
                  '(${formatSharePercent(dividendYield ?? 0)})',
        tooltip:
            'Flusso cedolare annuo stimato lordo generato dalle posizioni in '
            'portafoglio.',
        valueColor: t.successText,
        smallValue: true,
      ),
      StatCard(
        label: 'Posizioni Attive',
        icon: const Icon(Icons.inventory_2_outlined),
        value: summary == null
            ? '${holdingsCount ?? 0}'
            : '${summary!.holdingsCount}',
        valueColor: t.primary,
      ),
    ];

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int columns = constraints.maxWidth >= 1100
            ? 3
            : (constraints.maxWidth >= AppBreakpoints.compact ? 3 : 2);
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

// --- Budget ----------------------------------------------------------------

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({required this.budget, required this.summary});

  final double? budget;
  final PortfolioSummary? summary;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final double? budgetValue = budget;
    final double totalValue = summary?.totalValue ?? 0;
    final double? deployedPct = budgetValue == null || budgetValue <= 0
        ? null
        : totalValue / budgetValue * 100;
    final double? remaining = budgetValue == null
        ? null
        : math.max(0, budgetValue - totalValue);

    final Widget titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'Capitale da investire (budget totale)'.toUpperCase(),
          style: AppText.statLabel(context),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: AppSpacing.s4),
        Text(
          budgetValue == null ? '--' : formatCurrency(budgetValue),
          style: AppText.mono(
            context,
            size: 19,
            weight: FontWeight.w700,
            color: t.primary,
          ),
        ),
      ],
    );

    final Widget secondary = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.s14,
      runSpacing: AppSpacing.s8,
      children: <Widget>[
        AppBadge(
          label: deployedPct == null
              ? 'Allocato: --%'
              : 'Allocato: ${formatSharePercent(deployedPct, decimals: 1)}',
          tone: deployedPct != null && deployedPct > 100
              ? BadgeTone.danger
              : BadgeTone.primary,
        ),
        Text.rich(
          TextSpan(
            text: 'Liquidità libera residua: ',
            children: <InlineSpan>[
              TextSpan(
                text: remaining == null
                    ? '--'
                    : formatCurrency(remaining),
                style: AppText.mono(
                  context,
                  size: 13,
                  weight: FontWeight.w700,
                  color: t.successText,
                ),
              ),
            ],
          ),
          style: AppText.caption(context),
        ),
        AppButton(
          label: 'Modifica budget',
          icon: const Icon(Icons.tune),
          variant: AppButtonVariant.ghost,
          size: AppButtonSize.xs,
          onPressed: () => context.go('/settings'),
        ),
      ],
    );

    final Widget icon = Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: t.surfaceSunken,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Icon(
        Icons.savings_outlined,
        size: AppSizes.iconSm,
        color: t.primary,
      ),
    );

    return AppCard(
      accent: true,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // Sotto ~480px il blocco titolo va a piena larghezza: il Row
          // a mainAxisSize.min dentro il Wrap non ha un vincolo finito e
          // overflowa con label lunghe.
          if (constraints.maxWidth < 480) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    icon,
                    const SizedBox(width: AppSpacing.s10),
                    Expanded(child: titleBlock),
                  ],
                ),
                const SizedBox(height: AppSpacing.s12),
                secondary,
              ],
            );
          }
          return Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.s16,
            runSpacing: AppSpacing.s10,
            children: <Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  icon,
                  const SizedBox(width: AppSpacing.s10),
                  titleBlock,
                ],
              ),
              secondary,
            ],
          );
        },
      ),
    );
  }
}

// --- Save bar --------------------------------------------------------------

/// Barra delle modifiche inline non salvate (`.save-bar`), agganciata in basso
/// dalla pagina.
///
/// Pubblica per i widget test (`border_paint_test.dart`): la striscia accent
/// superiore è clippata da [Stack] (un [Border] asimmetrico non è compatibile
/// con `borderRadius`).
class PortfolioSaveBar extends StatelessWidget {
  /// Crea la barra di salvataggio.
  const PortfolioSaveBar({
    super.key,
    required this.count,
    required this.onCancel,
    required this.onSave,
  });

  /// Numero di posizioni modificate.
  final int count;

  /// Callback di annullamento.
  final VoidCallback onCancel;

  /// Callback di salvataggio.
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final double pagePadding = AppSpacing.pagePadding(context.windowWidth);
    final String countLabel = count == 1
        ? 'Hai 1 posizione modificata.'
        : 'Hai $count posizioni modificate.';
    return Padding(
      padding: EdgeInsets.fromLTRB(
        pagePadding,
        0,
        pagePadding,
        context.isCompact ? AppSpacing.s12 : AppSpacing.s16,
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppTokens.contentMaxWidth,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: t.surface,
              border: Border.all(color: t.warningBorder),
              borderRadius: BorderRadius.circular(AppRadii.panel),
              boxShadow: t.shadowMd,
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s16,
                    vertical: AppSpacing.s12,
                  ),
                  child: LayoutBuilder(
                    builder:
                        (BuildContext context, BoxConstraints constraints) {
                          final Widget header = Row(
                            children: <Widget>[
                              Icon(
                                Icons.warning_amber,
                                size: AppSizes.iconLg,
                                color: t.warning,
                              ),
                              const SizedBox(width: AppSpacing.s12),
                              Flexible(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Text(
                                      'Modifiche al volo non salvate',
                                      style: AppText.button(context),
                                    ),
                                    const SizedBox(height: AppSpacing.s2),
                                    Text(
                                      '$countLabel Clicca "Salva Modifiche" '
                                      'per applicarle.',
                                      style: AppText.caption(context),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                          final Widget actions = Wrap(
                            spacing: AppSpacing.s8,
                            runSpacing: AppSpacing.s8,
                            children: <Widget>[
                              AppButton(
                                label: 'Annulla',
                                icon: const Icon(Icons.undo),
                                variant: AppButtonVariant.ghost,
                                size: AppButtonSize.sm,
                                onPressed: onCancel,
                              ),
                              AppButton(
                                label: 'Salva Modifiche',
                                icon: const Icon(Icons.save_outlined),
                                variant: AppButtonVariant.warning,
                                size: AppButtonSize.sm,
                                onPressed: onSave,
                              ),
                            ],
                          );
                          if (constraints.maxWidth < 720) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                header,
                                const SizedBox(height: AppSpacing.s10),
                                actions,
                              ],
                            );
                          }
                          return Row(
                            children: <Widget>[
                              Expanded(child: header),
                              const SizedBox(width: AppSpacing.s12),
                              actions,
                            ],
                          );
                        },
                  ),
                ),
                // Striscia accent superiore: un Border asimmetrico non è
                // compatibile con borderRadius (assert a ogni paint).
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: AppSizes.accentStrip,
                  child: ColoredBox(color: t.warning),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Conferma salvataggio ---------------------------------------------------

class _ConfirmSaveDialog extends StatefulWidget {
  const _ConfirmSaveDialog({required this.edits, required this.onSave});

  final List<HoldingEdit> edits;
  final Future<void> Function() onSave;

  @override
  State<_ConfirmSaveDialog> createState() => _ConfirmSaveDialogState();
}

class _ConfirmSaveDialogState extends State<_ConfirmSaveDialog> {
  bool _saving = false;

  Future<void> _confirm() async {
    setState(() => _saving = true);
    try {
      await widget.onSave();
      if (!mounted) return;
      Navigator.of(context).pop();
    } on ApiException catch (error) {
      if (!mounted) return;
      showAppToast(context, message: error.message, type: AppToastType.error);
      setState(() => _saving = false);
    } catch (_) {
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Errore durante il salvataggio',
        type: AppToastType.error,
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return PortfolioModalShell(
      title: 'Conferma salvataggio modifiche',
      onClose: _saving ? null : () => Navigator.of(context).pop(),
      actions: <Widget>[
        AppButton(
          label: 'Annulla',
          variant: AppButtonVariant.ghost,
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: 'Sì, conferma e salva',
          variant: AppButtonVariant.success,
          loading: _saving,
          loadingLabel: 'Salvataggio in corso...',
          onPressed: _saving ? null : _confirm,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Stai per aggiornare le seguenti posizioni nel database. '
            'Confermi l\'operazione?',
            style: AppText.small(context).copyWith(color: t.textSecondary),
          ),
          const SizedBox(height: AppSpacing.s12),
          Container(
            decoration: BoxDecoration(
              color: t.surfaceSunken,
              border: Border.all(color: t.border),
              borderRadius: BorderRadius.circular(AppRadii.control),
            ),
            child: Column(
              children: <Widget>[
                for (final HoldingEdit edit in widget.edits)
                  _ChangeItem(edit: edit),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Riga del riepilogo variazioni: `valore precedente → valore nuovo`.
class _ChangeItem extends StatelessWidget {
  const _ChangeItem({required this.edit});

  final HoldingEdit edit;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.borderSubtle)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Text(
              edit.holding.ticker,
              style: AppText.mono(
                context,
                size: 13,
                weight: FontWeight.w700,
                color: t.primary,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _ChangeValue(
                label: 'Q.tà',
                before: formatDraftNumber(edit.holding.quantity),
                after: formatDraftNumber(edit.quantity),
                increased: edit.quantity > edit.holding.quantity,
              ),
              const SizedBox(height: AppSpacing.s4),
              _ChangeValue(
                label: 'Prezzo',
                before: formatCurrency(
                  edit.holding.avgPurchasePrice,
                  currency: edit.holding.currency,
                ),
                after: formatCurrency(
                  edit.avgPrice,
                  currency: edit.holding.currency,
                ),
                increased: edit.avgPrice > edit.holding.avgPurchasePrice,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Coppia precedente → nuovo di una variazione.
class _ChangeValue extends StatelessWidget {
  const _ChangeValue({
    required this.label,
    required this.before,
    required this.after,
    required this.increased,
  });

  final String label;
  final String before;
  final String after;

  /// True se il valore nuovo è maggiore di quello precedente: solo in quel
  /// caso il "dopo" è dipinto in verde (`successText`).
  final bool increased;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label.toUpperCase(), style: AppText.microFor(t).copyWith(color: t.textFaint)),
        const SizedBox(width: AppSpacing.s8),
        Text(
          before,
          style: AppText.mono(context, size: 12, weight: FontWeight.w500)
              .copyWith(
                color: t.textMuted,
                decoration: TextDecoration.lineThrough,
              ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
          child: Icon(Icons.arrow_right_alt, size: AppSizes.iconSm, color: t.textMuted),
        ),
        Text(
          after,
          style: AppText.mono(
            context,
            size: 12,
            weight: FontWeight.w700,
            color: increased ? t.successText : t.textPrimary,
          ),
        ),
      ],
    );
  }
}
