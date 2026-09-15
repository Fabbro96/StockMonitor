import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/portfolio_api.dart';
import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/models/portfolio.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_confirm_dialog.dart';
import '../../widgets/app_error_panel.dart';
import '../../widgets/app_market_tag.dart';
import '../../widgets/app_progress_bar.dart';
import '../../widgets/badges.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/section_header.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/stepper_input.dart';
import '../../widgets/toast.dart';
import '../stock_detail/stock_detail_modal.dart' show showStockDetail;
import 'portfolio_edits.dart' show formatDraftNumber, formatSharePercent;
import 'portfolio_table.dart';
import 'portfolio_tools_providers.dart';

/// Etichette degli scope del Rebalancer (legacy `SCOPE_LABELS`).
const Map<String, String> _scopeLabels = <String, String>{
  'MARKET': 'Mercato',
  'TICKERS': 'Ticker',
  'CASH': 'Liquidità',
};

/// Sezione "Smart Portfolio Rebalancer" (parità `#rebalancerCard`).
///
/// Contiene il form CRUD delle allocazioni target, il campo liquidità, il
/// piano ordini generato da `POST /portfolio/rebalance/preview` e gli
/// scostamenti correnti/target per bucket.
class RebalancerSection extends ConsumerStatefulWidget {
  /// Crea la sezione Rebalancer.
  const RebalancerSection({super.key});

  @override
  ConsumerState<RebalancerSection> createState() => _RebalancerSectionState();
}

class _RebalancerSectionState extends ConsumerState<RebalancerSection> {
  final TextEditingController _cash = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _percent = TextEditingController();
  final TextEditingController _scopeValue = TextEditingController();

  String _scopeType = 'MARKET';
  bool _adding = false;

  @override
  void dispose() {
    _cash.dispose();
    _name.dispose();
    _percent.dispose();
    _scopeValue.dispose();
    super.dispose();
  }

  double? _parse(TextEditingController controller) =>
      double.tryParse(controller.text.trim().replaceAll(',', '.'));

  // --- Azioni -------------------------------------------------------------

  Future<void> _addTarget() async {
    final String name = _name.text.trim();
    final double? percent = _parse(_percent);
    final String scopeValue = _scopeValue.text.trim().toUpperCase();

    if (name.isEmpty) {
      showAppToast(
        context,
        message: 'Inserisci un nome per l\'allocazione target',
        type: AppToastType.error,
      );
      return;
    }
    if (percent == null || percent < 0 || percent > 100) {
      showAppToast(
        context,
        message: 'La percentuale target deve essere un numero tra 0 e 100',
        type: AppToastType.error,
      );
      return;
    }
    if (_scopeType != 'CASH' && scopeValue.isEmpty) {
      showAppToast(
        context,
        message: _scopeType == 'MARKET'
            ? 'Per lo scope Mercato indica il valore (IT, US, EU)'
            : 'Per lo scope Ticker indica i simboli (es. AAPL,MSFT)',
        type: AppToastType.error,
      );
      return;
    }

    setState(() => _adding = true);
    try {
      await ref
          .read(portfolioApiProvider)
          .addRebalanceTarget(
            name: name,
            targetPercent: percent,
            scopeType: _scopeType,
            scopeValue: scopeValue,
          );
      ref.invalidate(rebalanceTargetsProvider);
      if (!mounted) return;
      _name.clear();
      _percent.clear();
      _scopeValue.clear();
      showAppToast(
        context,
        message: 'Allocazione target aggiunta con successo',
        type: AppToastType.success,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      showAppToast(context, message: error.message, type: AppToastType.error);
    } catch (_) {
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Errore durante l\'aggiunta dell\'allocazione target',
        type: AppToastType.error,
      );
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _deleteTarget(RebalanceTarget target) async {
    final bool confirmed = await showAppConfirm(
      context,
      title: 'Elimina allocazione target',
      message: 'Sei sicuro di voler eliminare l\'allocazione "${target.name}"?',
      confirmLabel: 'Elimina',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    try {
      await ref.read(portfolioApiProvider).deleteRebalanceTarget(target.id);
      ref.invalidate(rebalanceTargetsProvider);
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Allocazione target rimossa',
        type: AppToastType.info,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      showAppToast(context, message: error.message, type: AppToastType.error);
    } catch (_) {
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Errore durante l\'eliminazione dell\'allocazione target',
        type: AppToastType.error,
      );
    }
  }

  Future<void> _calculate() async {
    final double parsed = _parse(_cash) ?? 0;
    final String? error = await ref
        .read(rebalancePreviewProvider.notifier)
        .calculate(parsed < 0 ? 0 : parsed);
    if (!mounted || error == null) return;
    showAppToast(context, message: error, type: AppToastType.error);
  }

  // --- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<RebalanceTarget>> targets = ref.watch(
      rebalanceTargetsProvider,
    );
    final AsyncValue<RebalancePreview?> preview = ref.watch(
      rebalancePreviewProvider,
    );
    final bool calculating = preview.isLoading;

    final Widget targetsColumn = _buildTargets(context, targets);
    final Widget planColumn = _buildPlan(context, preview);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SectionHeader(
            variant: SectionHeaderVariant.rule,
            icon: Icons.balance_outlined,
            overline: 'Strumenti',
            title: 'Ribilanciatore intelligente',
            subtitle:
                'Definisci le allocazioni target (es. 40% US Tech, 30% IT '
                'Dividend, 30% Liquidità) e ottieni gli ordini di '
                'ribilanciamento suggeriti.',
          ),
          Wrap(
            spacing: AppSpacing.s10,
            runSpacing: AppSpacing.s10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              StepperInput(
                controller: _cash,
                min: 0,
                step: 500,
                large: true,
                width: 190,
                hint: 'Liquidità (€)',
                semanticsLabel: 'Liquidità da investire (€)',
                decreaseLabel: 'Diminuisci (−500 €)',
                increaseLabel: 'Aumenta (+500 €)',
              ),
              AppButton(
                label: 'Calcola ordini',
                icon: const Icon(Icons.calculate_outlined),
                size: AppButtonSize.sm,
                loading: calculating,
                loadingLabel: 'Calcolo...',
                onPressed: calculating ? null : _calculate,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s16),
          if (context.isDrawerLayout)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                targetsColumn,
                const SizedBox(height: AppSpacing.s16),
                planColumn,
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(flex: 10, child: targetsColumn),
                const SizedBox(width: AppSpacing.s14),
                Expanded(flex: 13, child: planColumn),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildTargets(
    BuildContext context,
    AsyncValue<List<RebalanceTarget>> async,
  ) {
    final Widget content;
    if (async.isLoading && !async.hasValue) {
      content = const PortfolioTableSkeleton();
    } else if (async.hasError && !async.hasValue) {
      content = AppErrorPanel(
        message: 'Errore nel caricamento delle allocazioni target.',
        onRetry: () => ref.invalidate(rebalanceTargetsProvider),
      );
    } else {
      final List<RebalanceTarget> targets =
          async.value ?? const <RebalanceTarget>[];
      content = targets.isEmpty
          ? const EmptyState(
              icon: Icon(Icons.playlist_add),
              message: 'Nessuna allocazione target definita.',
            )
          : _targetsTable(context, targets);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const SectionHeader(
          dense: true,
          icon: Icons.track_changes,
          title: 'Allocazioni target',
          padding: EdgeInsets.only(bottom: AppSpacing.s12),
        ),
        Wrap(
          spacing: AppSpacing.s8,
          runSpacing: AppSpacing.s8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 150,
              child: TextField(
                controller: _name,
                enabled: !_adding,
                decoration: const InputDecoration(
                  hintText: 'Nome (es. US Tech)',
                ),
              ),
            ),
            StepperInput(
              controller: _percent,
              min: 0,
              max: 100,
              step: 5,
              width: 110,
              enabled: !_adding,
              hint: '%',
              semanticsLabel: 'Percentuale target',
              decreaseLabel: 'Diminuisci (−5%)',
              increaseLabel: 'Aumenta (+5%)',
            ),
            SizedBox(
              width: 130,
              child: DropdownButtonFormField<String>(
                initialValue: _scopeType,
                isExpanded: true,
                decoration: const InputDecoration(hintText: 'Scope'),
                items: <DropdownMenuItem<String>>[
                  for (final MapEntry<String, String> entry
                      in _scopeLabels.entries)
                    DropdownMenuItem<String>(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: _adding
                    ? null
                    : (String? value) =>
                          setState(() => _scopeType = value ?? 'MARKET'),
              ),
            ),
            SizedBox(
              width: 160,
              child: TextField(
                controller: _scopeValue,
                enabled: !_adding,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(hintText: 'US / AAPL,MSFT'),
              ),
            ),
            AppButton(
              label: 'Aggiungi',
              icon: const Icon(Icons.add),
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.sm,
              tooltip: 'Aggiungi allocazione target',
              loading: _adding,
              onPressed: _adding ? null : _addTarget,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s12),
        content,
      ],
    );
  }

  Widget _targetsTable(BuildContext context, List<RebalanceTarget> targets) {
    return PortfolioTable(
      minWidth: 520,
      child: Column(
        children: <Widget>[
          const PortfolioTableHeader(
            cells: <Widget>[
              Expanded(flex: 12, child: PortfolioHeaderLabel('Bucket')),
              SizedBox(
                width: 140,
                child: PortfolioHeaderLabel(
                  'Scope',
                  alignment: Alignment.center,
                ),
              ),
              SizedBox(
                width: 90,
                child: PortfolioHeaderLabel(
                  'Target %',
                  alignment: Alignment.centerRight,
                ),
              ),
              SizedBox(width: 44, child: PortfolioHeaderLabel('')),
            ],
          ),
          for (final RebalanceTarget target in targets)
            PortfolioTableRow(
              cells: <Widget>[
                Expanded(
                  flex: 12,
                  child: Text(
                    target.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.mono(
                      context,
                      size: 13,
                      weight: FontWeight.w700,
                    ),
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: PortfolioCell(
                    alignment: Alignment.center,
                    child: Wrap(
                      spacing: AppSpacing.s6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      alignment: WrapAlignment.center,
                      children: <Widget>[
                        AppBadge(
                          label:
                              _scopeLabels[target.scopeType] ?? target.scopeType,
                          tone: BadgeTone.warning,
                        ),
                        if (target.scopeValue.isNotEmpty)
                          Text(
                            target.scopeValue,
                            style: AppText.mono(
                              context,
                              size: 11.5,
                              weight: FontWeight.w500,
                              color: context.tokens.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: 90,
                  child: PortfolioCell(
                    alignment: Alignment.centerRight,
                    child: Text(
                      formatSharePercent(target.targetPercent, decimals: 1),
                      style: AppText.tableCellNum(context).copyWith(
                        color: context.tokens.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: PortfolioCell(
                    alignment: Alignment.centerRight,
                    child: PortfolioActionsReveal(
                      child: AppIconButton(
                        icon: const Icon(Icons.delete_outline),
                        size: AppSizes.iconButtonSm,
                        iconSize: AppSizes.iconSm,
                        minTargetSize: AppSizes.touchTarget,
                        tooltip: 'Elimina target',
                        semanticLabel:
                            'Elimina allocazione ${target.name}',
                        danger: true,
                        onPressed: () => unawaited(_deleteTarget(target)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildPlan(BuildContext context, AsyncValue<RebalancePreview?> async) {
    final Widget content;
    if (async.isLoading) {
      content = const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.s18),
        child: Center(child: AppSpinner()),
      );
    } else if (async.hasError) {
      final Object? error = async.error;
      content = AppErrorPanel(
        message: error is ApiException
            ? error.message
            : 'Errore durante il calcolo del piano',
        onRetry: () => unawaited(_calculate()),
      );
    } else {
      final RebalancePreview? plan = async.value;
      if (plan == null) {
        content = const EmptyState(
          icon: Icon(Icons.calculate_outlined),
          message:
              'Configura le allocazioni target e clicca "Calcola ordini" per '
              'generare il piano.',
        );
      } else if (plan.orders.isEmpty) {
        content = EmptyState(
          icon: Icon(
            plan.portfolioEmpty
                ? Icons.inventory_2_outlined
                : Icons.check_circle_outline,
          ),
          message: plan.portfolioEmpty
              ? 'Portafoglio vuoto: aggiungi delle posizioni per generare un '
                    'piano di ribilanciamento.'
              : 'Il portafoglio è già allineato alle allocazioni target: '
                    'nessun ordine necessario.',
        );
      } else {
        content = _planContent(context, plan);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const SectionHeader(
          dense: true,
          icon: Icons.format_list_numbered,
          title: 'Piano di ribilanciamento',
          padding: EdgeInsets.only(bottom: AppSpacing.s12),
        ),
        content,
      ],
    );
  }

  Widget _planContent(BuildContext context, RebalancePreview plan) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _PlanSummary(plan: plan),
        if (plan.allocations.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.s14),
          for (final RebalanceAllocation allocation in plan.allocations)
            _AllocationGauge(allocation: allocation),
        ],
        const SizedBox(height: AppSpacing.s14),
        _ordersTable(context, plan),
      ],
    );
  }

  Widget _ordersTable(BuildContext context, RebalancePreview plan) {
    final AppTokens t = context.tokens;
    return PortfolioTable(
      minWidth: 620,
      child: Column(
        children: <Widget>[
          const PortfolioTableHeader(
            cells: <Widget>[
              SizedBox(
                width: 76,
                child: PortfolioHeaderLabel(
                  'Lato',
                  alignment: Alignment.center,
                ),
              ),
              Expanded(flex: 30, child: PortfolioHeaderLabel('Titolo')),
              SizedBox(
                width: 92,
                child: PortfolioHeaderLabel(
                  'Quantità',
                  alignment: Alignment.centerRight,
                ),
              ),
              SizedBox(
                width: 118,
                child: PortfolioHeaderLabel(
                  'Prezzo stimato',
                  alignment: Alignment.centerRight,
                ),
              ),
              SizedBox(
                width: 124,
                child: PortfolioHeaderLabel(
                  'Importo',
                  alignment: Alignment.centerRight,
                ),
              ),
            ],
          ),
          for (final RebalanceOrder order in plan.orders)
            PortfolioTableRow(
              cells: <Widget>[
                SizedBox(
                  width: 76,
                  child: PortfolioCell(
                    alignment: Alignment.center,
                    child: AppBadge.trade(order.side),
                  ),
                ),
                Expanded(
                  flex: 30,
                  child: _OrderTickerCell(order: order),
                ),
                SizedBox(
                  width: 92,
                  child: PortfolioCell(
                    alignment: Alignment.centerRight,
                    child: Text(
                      formatDraftNumber(order.quantity),
                      style: AppText.tableCellNum(context),
                    ),
                  ),
                ),
                SizedBox(
                  width: 118,
                  child: PortfolioCell(
                    alignment: Alignment.centerRight,
                    child: Text(
                      formatCurrency(
                        order.estimatedPrice,
                        currency: order.currency,
                      ),
                      style: AppText.tableCellNum(context),
                    ),
                  ),
                ),
                SizedBox(
                  width: 124,
                  child: PortfolioCell(
                    alignment: Alignment.centerRight,
                    child: Text(
                      formatCurrency(
                        order.estimatedValue,
                        currency: order.currency,
                      ),
                      style: AppText.tableCellNum(context).copyWith(
                        color: order.side == 'BUY' ? t.successText : t.danger,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// --- Widget privati ---------------------------------------------------------

/// Riepilogo del piano: valore totale, acquisti e vendite.
class _PlanSummary extends StatelessWidget {
  const _PlanSummary({required this.plan});

  final RebalancePreview plan;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Wrap(
      spacing: AppSpacing.s10,
      runSpacing: AppSpacing.s10,
      children: <Widget>[
        _PlanDatum(
          label: 'Valore totale (incl. liquidità)',
          value: formatCurrency(plan.totalValue),
          color: t.primary,
        ),
        _PlanDatum(
          label: 'Acquisti (BUY)',
          value: formatCurrency(plan.totalBuyValue),
          color: t.successText,
        ),
        _PlanDatum(
          label: 'Vendite (SELL)',
          value: formatCurrency(plan.totalSellValue),
          color: t.danger,
        ),
      ],
    );
  }
}

class _PlanDatum extends StatelessWidget {
  const _PlanDatum({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s8,
      ),
      decoration: BoxDecoration(
        color: t.surfaceSunken,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label.toUpperCase(), style: AppText.statLabel(context)),
          const SizedBox(height: AppSpacing.s4),
          Text(
            value,
            style: AppText.mono(
              context,
              size: 15,
              weight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bucket del piano: quota corrente su target con segnaposto e scostamento.
class _AllocationGauge extends StatelessWidget {
  const _AllocationGauge({required this.allocation});

  final RebalanceAllocation allocation;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final double current = allocation.currentPercent;
    final double target = allocation.targetPercent;
    final double drift = allocation.driftPct;
    final bool aligned = drift.abs() < 0.5;
    final String currentLabel = formatSharePercent(current, decimals: 1);
    final String targetLabel = formatSharePercent(target, decimals: 1);

    final Widget driftBadge;
    if (aligned) {
      driftBadge = const AppBadge(
        label: 'In linea',
        tone: BadgeTone.success,
        icon: Icon(Icons.check),
      );
    } else if (drift > 0) {
      driftBadge = const AppBadge(
        label: 'Da aumentare',
        tone: BadgeTone.warning,
        icon: Icon(Icons.arrow_upward),
      );
    } else {
      driftBadge = const AppBadge(
        label: 'Da ridurre',
        tone: BadgeTone.warning,
        icon: Icon(Icons.arrow_downward),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  allocation.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.mono(
                    context,
                    size: 12.5,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s6),
              driftBadge,
              const SizedBox(width: AppSpacing.s8),
              Text(
                _signedMoney(allocation.delta),
                style: AppText.mono(
                  context,
                  size: 12,
                  weight: FontWeight.w600,
                  color: allocation.delta >= 0
                      ? t.warning
                      : t.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s6),
          AppProgressBar(
            value: (current / 100).clamp(0, 1).toDouble(),
            target: (target / 100).clamp(0, 1).toDouble(),
            height: 5,
            tone: AppProgressTone.neutral,
            semanticsLabel:
                '${allocation.name}: corrente $currentLabel, target '
                '$targetLabel',
          ),
          const SizedBox(height: AppSpacing.s4),
          Row(
            children: <Widget>[
              Text(
                'Corrente $currentLabel',
                style: AppText.caption(context),
              ),
              const Spacer(),
              Text('Target $targetLabel', style: AppText.caption(context)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Cella titolo dell'ordine: tag di mercato, ticker mono e nome/bucket.
class _OrderTickerCell extends StatelessWidget {
  const _OrderTickerCell({required this.order});

  final RebalanceOrder order;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final String detail = <String>[
      if (order.name.isNotEmpty) order.name,
      if (order.allocationName?.isNotEmpty ?? false) order.allocationName!,
    ].join(' • ');

    return Row(
      children: <Widget>[
        AppMarketTag.forTicker(order.ticker),
        const SizedBox(width: AppSpacing.s6),
        InkWell(
          onTap: () => unawaited(showStockDetail(context, order.ticker)),
          borderRadius: BorderRadius.circular(AppRadii.small),
          child: Text(
            order.ticker,
            style: AppText.mono(
              context,
              size: 13,
              weight: FontWeight.w700,
              color: t.primary,
            ),
          ),
        ),
        if (detail.isNotEmpty) ...<Widget>[
          const SizedBox(width: AppSpacing.s6),
          Expanded(
            child: Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption(context),
            ),
          ),
        ],
      ],
    );
  }
}

/// Importo firmato (`+1.234,56 €` / `−120,00 €`), mai solo colore.
String _signedMoney(num? value) {
  if (value == null || !value.isFinite) return '—';
  final String formatted = formatCurrency(value.abs());
  if (value > 0) return '+$formatted';
  if (value < 0) return '−$formatted';
  return formatted;
}
