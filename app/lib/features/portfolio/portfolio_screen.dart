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
import '../../widgets/badges.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/page_content.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/toast.dart';
import '../stock_detail/market_editor_modal.dart' show showMarketEditor;
import '../stock_detail/stock_detail_modal.dart' show showStockDetail;
import 'allocation_card.dart';
import 'dividends_section.dart';
import 'holding_dialog.dart';
import 'holdings_table.dart';
import 'portfolio_edits.dart';
import 'portfolio_providers.dart';
import 'portfolio_tools_providers.dart';
import 'rebalancer_section.dart';
import 'tools/csv_tools.dart';
import 'transactions_section.dart';

/// Gestione Portafoglio: riepilogo, budget, holdings con inline edit,
/// allocazione e sezioni tools (rebalancer, dividendi, ledger).
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
          icon: const Text('📥', style: TextStyle(fontSize: 14)),
          tooltip: 'Esporta CSV',
          semanticLabel: 'Esporta CSV',
          onPressed: _exportCsv,
        ),
        AppIconButton(
          icon: const Text('📤', style: TextStyle(fontSize: 14)),
          tooltip: 'Importa CSV',
          semanticLabel: 'Importa CSV',
          onPressed: _importCsv,
        ),
        AppIconButton(
          icon: const Text('➕', style: TextStyle(fontSize: 14)),
          tooltip: 'Aggiungi Holding',
          semanticLabel: 'Aggiungi Holding',
          onPressed: _addHolding,
        ),
      ];
    }
    return <Widget>[
      AppButton(
        label: '📥 Esporta CSV',
        size: AppButtonSize.sm,
        onPressed: _exportCsv,
      ),
      AppButton(
        label: '📤 Importa CSV',
        size: AppButtonSize.sm,
        onPressed: _importCsv,
      ),
      AppButton(
        label: '➕ Aggiungi Holding',
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
    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierColor: context.tokens.scrim,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Annulla modifiche'),
        content: const Text('Vuoi annullare tutte le modifiche non salvate?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sì, annulla'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
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
            'Per rimuovere una posizione usa 🗑️.',
        type: AppToastType.error,
      );
      return;
    }
    await showDialog<void>(
      context: context,
      barrierColor: context.tokens.scrim,
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

    return Column(
      children: <Widget>[
        if (_edits.isNotEmpty)
          PortfolioSaveBar(
            count: _edits.length,
            onCancel: _cancelEdits,
            onSave: _openConfirmSave,
          ),
        Expanded(
          child: PageContent(
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
                _buildHoldingsArea(context, holdingsAsync),
                const SizedBox(height: AppSpacing.s20),
                const RebalancerSection(),
                const SizedBox(height: AppSpacing.s20),
                const DividendsSection(),
                const SizedBox(height: AppSpacing.s20),
                const TransactionsSection(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHoldingsArea(
    BuildContext context,
    AsyncValue<List<Holding>> holdingsAsync,
  ) {
    final List<Holding>? holdings = holdingsAsync.value;
    final Widget tableContent;
    if (holdingsAsync.isLoading && holdings == null) {
      tableContent = const Column(
        children: <Widget>[SkeletonRow(), SkeletonRow(), SkeletonRow()],
      );
    } else if (holdingsAsync.hasError && holdings == null) {
      tableContent = EmptyState(
        icon: const Icon(Icons.error_outline),
        message: 'Dati non disponibili.',
        actions: <Widget>[
          AppButton(
            label: '↻ Riprova',
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
            onPressed: () => ref.read(portfolioProvider.notifier).reload(),
          ),
        ],
      );
    } else if (holdings == null || holdings.isEmpty) {
      tableContent = EmptyState(
        message: 'Nessun titolo nel portafoglio.',
        actions: <Widget>[
          AppButton(
            label: '➕ Aggiungi Holding',
            size: AppButtonSize.sm,
            onPressed: _addHolding,
          ),
          AppButton(
            label: '🚀 Inizializza Demo',
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
            onPressed: _seedDemo,
          ),
        ],
      );
    } else {
      tableContent = HoldingsTable(
        holdings: holdings,
        edits: _edits,
        epoch: _epoch,
        onEdit: _onEdit,
        onDelete: (Holding holding) => unawaited(_deleteHolding(holding)),
        onOpenTicker: _openTicker,
        onEditMarket: _openMarketEditor,
      );
    }

    final Widget tableCard = AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text.rich(
            TextSpan(
              text: '💡 ',
              children: <InlineSpan>[
                TextSpan(
                  text:
                      'Modifica Quantità e Prezzo Acquisto direttamente nelle '
                      'caselle e clicca "Salva Modifiche". Clicca sui ticker '
                      'per il deep-dive.',
                  style: AppText.caption(context).copyWith(
                    fontStyle: FontStyle.italic,
                    color: context.tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          tableContent,
        ],
      ),
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth >= AppBreakpoints.narrow) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: tableCard),
              const SizedBox(width: AppSpacing.s14),
              SizedBox(width: 310, child: AllocationCard(edits: _edits)),
            ],
          );
        }
        return Column(
          children: <Widget>[
            tableCard,
            const SizedBox(height: AppSpacing.s14),
            AllocationCard(edits: _edits),
          ],
        );
      },
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

    final List<Widget> cards = <Widget>[
      StatCard(
        label: 'Valore Attuale',
        value: summary == null ? '--' : formatCurrency(summary!.totalValue),
        tooltip: 'Valore di mercato odierno di tutte le azioni possedute.',
        valueColor: t.primary,
      ),
      StatCard(
        label: 'Capitale Investito',
        value: summary == null ? '--' : formatCurrency(summary!.totalInvested),
        tooltip: 'Somma totale spesa all\'acquisto delle posizioni.',
        valueColor: t.textSecondary,
      ),
      StatCard(
        label: 'P&L Totale',
        value: totalPnl == null
            ? '--'
            : '${formatCurrency(totalPnl)} (${formatPercent(totalPnlPct)})',
        tooltip:
            'Guadagno o perdita non realizzato rispetto al prezzo medio di '
            'carico.',
        valueColor: totalPnl == null
            ? null
            : (totalPnl >= 0 ? t.success : t.danger),
        smallValue: true,
      ),
      StatCard(
        label: 'P&L Realizzato',
        value: netRealized == null
            ? '--'
            : '${netRealized >= 0 ? '+' : ''}${formatCurrency(netRealized)}',
        tooltip:
            'Profitto o perdita netto incassato da vendite concluse e '
            'dividendi (al netto delle commissioni).',
        valueColor: netRealized == null
            ? null
            : (netRealized >= 0 ? t.success : t.danger),
      ),
      StatCard(
        label: 'Dividendi Stimati',
        value: dividends == null
            ? '--'
            : '${formatCurrency(dividends)}/anno '
                  '(${(dividendYield ?? 0).toStringAsFixed(2)}%)',
        tooltip:
            'Flusso cedolare annuo stimato lordo generato dalle posizioni in '
            'portafoglio.',
        valueColor: t.success,
        smallValue: true,
      ),
      StatCard(
        label: 'Posizioni Attive',
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
          'CAPITALE DA INVESTIRE (BUDGET TOTALE)',
          style: AppText.sectionLabel(context).copyWith(color: t.textMuted),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: AppSpacing.s2),
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
              : 'Allocato: ${deployedPct.toStringAsFixed(1)}%',
          tone: deployedPct != null && deployedPct > 100
              ? BadgeTone.danger
              : BadgeTone.primary,
        ),
        Text.rich(
          TextSpan(
            text: 'Liquidità Libera Residua: ',
            children: <InlineSpan>[
              TextSpan(
                text: remaining == null
                    ? '--'
                    : formatCurrency(remaining),
                style: AppText.mono(
                  context,
                  size: 13,
                  weight: FontWeight.w700,
                  color: t.success,
                ),
              ),
            ],
          ),
          style: AppText.caption(context),
        ),
        AppButton(
          label: '⚙️ Modifica Budget',
          variant: AppButtonVariant.ghost,
          size: AppButtonSize.xs,
          onPressed: () => context.go('/settings'),
        ),
      ],
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
                    const Text('💶', style: TextStyle(fontSize: 20)),
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
                  const Text('💶', style: TextStyle(fontSize: 20)),
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

/// Barra sticky delle modifiche inline non salvate (`.save-bar`).
///
/// Pubblica per i widget test (`border_paint_test.dart`): la striscia warning
/// sinistra è una strip clippata su [Stack] (un [Border] asimmetrico non è
/// compatibile con `borderRadius`).
class PortfolioSaveBar extends StatelessWidget {
  const PortfolioSaveBar({
    super.key,
    required this.count,
    required this.onCancel,
    required this.onSave,
  });

  final int count;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final double pagePadding = AppSpacing.pagePadding(context.windowWidth);
    final String countLabel = count == 1
        ? 'Hai 1 posizione modificata.'
        : 'Hai $count posizioni modificate.';
    return Padding(
      padding: EdgeInsets.fromLTRB(pagePadding, AppSpacing.s10, pagePadding, 0),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppTokens.contentMaxWidth,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: t.surface,
              border: Border.all(color: t.warningBorder),
              borderRadius: BorderRadius.circular(AppRadii.card),
              boxShadow: t.shadowSm,
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
                              const Text('⚠️', style: TextStyle(fontSize: 18)),
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
                                label: '↩️ Annulla',
                                variant: AppButtonVariant.ghost,
                                size: AppButtonSize.sm,
                                onPressed: onCancel,
                              ),
                              AppButton(
                                label: '💾 Salva Modifiche',
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
                // Striscia warning sinistra: un Border asimmetrico non è
                // compatibile con borderRadius (assert a ogni paint).
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 3,
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
    return Dialog(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        side: BorderSide(color: t.border),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '⚠️ Conferma Salvataggio Modifiche',
                      style: AppText.modalTitle(context),
                    ),
                  ),
                  AppIconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Chiudi',
                    semanticLabel: 'Chiudi',
                    bordered: false,
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s12),
              Text(
                'Stai per aggiornare le seguenti posizioni nel database. '
                'Confermi l\'operazione?',
                style: AppText.small(context).copyWith(color: t.textSecondary),
              ),
              const SizedBox(height: AppSpacing.s12),
              Container(
                decoration: BoxDecoration(
                  color: t.surfaceHover,
                  border: Border.all(color: t.border),
                  borderRadius: BorderRadius.circular(AppRadii.input),
                ),
                child: Column(
                  children: <Widget>[
                    for (final HoldingEdit edit in widget.edits)
                      _ChangeItem(edit: edit),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.s20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  AppButton(
                    label: 'Annulla',
                    variant: AppButtonVariant.ghost,
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  AppButton(
                    label: '✅ Sì, Conferma e Salva',
                    variant: AppButtonVariant.success,
                    loading: _saving,
                    loadingLabel: 'Salvataggio in corso...',
                    onPressed: _saving ? null : _confirm,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChangeItem extends StatelessWidget {
  const _ChangeItem({required this.edit});

  final HoldingEdit edit;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Padding(
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
              Text.rich(
                TextSpan(
                  text: 'Q.tà: ',
                  children: <InlineSpan>[
                    TextSpan(
                      text: formatDraftNumber(edit.holding.quantity),
                      style: TextStyle(
                        color: t.textMuted,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    const TextSpan(text: ' ➔ '),
                    TextSpan(
                      text: formatDraftNumber(edit.quantity),
                      style: TextStyle(
                        color: t.success,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                style: AppText.mono(context, size: 12),
              ),
              const SizedBox(height: AppSpacing.s2),
              Text.rich(
                TextSpan(
                  text: 'Prz: ',
                  children: <InlineSpan>[
                    TextSpan(
                      text: formatCurrency(
                        edit.holding.avgPurchasePrice,
                        currency: edit.holding.currency,
                      ),
                      style: TextStyle(
                        color: t.textMuted,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    const TextSpan(text: ' ➔ '),
                    TextSpan(
                      text: formatCurrency(
                        edit.avgPrice,
                        currency: edit.holding.currency,
                      ),
                      style: TextStyle(
                        color: t.success,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                style: AppText.mono(context, size: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
