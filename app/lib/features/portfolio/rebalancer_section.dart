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
import '../../widgets/badges.dart';
import '../../widgets/section_header.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/stepper_input.dart';
import '../../widgets/toast.dart';
import '../stock_detail/stock_detail_modal.dart' show showStockDetail;
import 'portfolio_edits.dart' show formatDraftNumber;
import 'portfolio_tools_providers.dart';

/// Etichette degli scope del Rebalancer (legacy `SCOPE_LABELS`).
const Map<String, String> _scopeLabels = <String, String>{
  'MARKET': 'Mercato',
  'TICKERS': 'Ticker',
  'CASH': 'Liquidità',
};

/// Sezione "⚖️ Smart Portfolio Rebalancer" (parità `#rebalancerCard`).
///
/// Contiene il form CRUD delle allocazioni target, il campo liquidità e il
/// piano ordini generato da `POST /portfolio/rebalance/preview`.
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
    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierColor: context.tokens.scrim,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Elimina allocazione target'),
        content: Text(
          'Sei sicuro di voler eliminare l\'allocazione "${target.name}"?',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'Elimina',
              style: TextStyle(color: context.tokens.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

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
          const SectionHeader(
            title: '⚖️ Smart Portfolio Rebalancer',
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
                label: 'Calcola Ordini ➔',
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
    final AppTokens t = context.tokens;
    final Widget content;
    if (async.isLoading && !async.hasValue) {
      content = const Column(
        children: <Widget>[SkeletonRow(), SkeletonRow(), SkeletonRow()],
      );
    } else if (async.hasError && !async.hasValue) {
      content = _CenteredNote(
        text: 'Errore nel caricamento delle allocazioni target.',
        color: t.danger,
      );
    } else {
      final List<RebalanceTarget> targets =
          async.value ?? const <RebalanceTarget>[];
      content = targets.isEmpty
          ? const _CenteredNote(text: 'Nessuna allocazione target definita.')
          : _targetsTable(context, targets);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const _SubsectionTitle('🎯 Allocazioni Target'),
        const SizedBox(height: AppSpacing.s12),
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
              label: '➕',
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
    final AppTokens t = context.tokens;
    final Table table = Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: const <int, TableColumnWidth>{
        0: FlexColumnWidth(1.2),
        1: FlexColumnWidth(1.4),
        2: FixedColumnWidth(90),
        3: FixedColumnWidth(50),
      },
      border: TableBorder(
        horizontalInside: BorderSide(color: t.borderSubtle),
        bottom: BorderSide(color: t.border),
      ),
      children: <TableRow>[
        TableRow(
          children: <Widget>[
            _headerCell(context, 'Bucket'),
            _headerCell(context, 'Scope', alignment: Alignment.center),
            _headerCell(context, 'Target %', alignment: Alignment.centerRight),
            _headerCell(context, ''),
          ],
        ),
        for (final RebalanceTarget target in targets)
          TableRow(
            children: <Widget>[
              _bodyCell(
                context,
                child: Text(
                  target.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.mono(
                    context,
                    size: 13,
                    weight: FontWeight.w700,
                    color: t.primary,
                  ),
                ),
              ),
              _bodyCell(
                context,
                alignment: Alignment.center,
                child: Wrap(
                  spacing: AppSpacing.s6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.center,
                  children: <Widget>[
                    AppBadge(
                      label: _scopeLabels[target.scopeType] ?? target.scopeType,
                      tone: BadgeTone.warning,
                    ),
                    if (target.scopeValue.isNotEmpty)
                      Text(
                        target.scopeValue,
                        style: AppText.mono(
                          context,
                          size: 11.5,
                          weight: FontWeight.w500,
                          color: t.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              _bodyCell(
                context,
                alignment: Alignment.centerRight,
                child: Text(
                  '${target.targetPercent.toStringAsFixed(1)}%',
                  style: AppText.mono(
                    context,
                    size: 13,
                    weight: FontWeight.w700,
                    color: t.primary,
                  ),
                ),
              ),
              _bodyCell(
                context,
                alignment: Alignment.center,
                child: AppIconButton(
                  icon: const Text('🗑️', style: TextStyle(fontSize: 14)),
                  size: 30,
                  iconSize: 14,
                  bordered: false,
                  danger: true,
                  tooltip: 'Elimina target',
                  semanticLabel: 'Elimina allocazione ${target.name}',
                  onPressed: () => unawaited(_deleteTarget(target)),
                ),
              ),
            ],
          ),
      ],
    );

    return _scrollableTable(minWidth: 520, table: table);
  }

  Widget _buildPlan(BuildContext context, AsyncValue<RebalancePreview?> async) {
    final AppTokens t = context.tokens;
    final Widget content;
    if (async.isLoading) {
      content = const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.s18),
        child: Center(child: AppSpinner()),
      );
    } else if (async.hasError) {
      final Object? error = async.error;
      content = _CenteredNote(
        text: error is ApiException
            ? error.message
            : 'Errore durante il calcolo del piano',
        color: t.danger,
      );
    } else {
      final RebalancePreview? plan = async.value;
      if (plan == null) {
        content = const _CenteredNote(
          text:
              'Configura le allocazioni target e clicca "Calcola Ordini" per '
              'generare il piano.',
        );
      } else if (plan.orders.isEmpty) {
        content = _CenteredNote(
          text: plan.portfolioEmpty
              ? 'Portafoglio vuoto: aggiungi delle posizioni per generare un '
                    'piano di ribilanciamento.'
              : 'Il portafoglio è già allineato alle allocazioni target: '
                    'nessun ordine necessario.',
        );
      } else {
        content = _planTable(context, plan);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const _SubsectionTitle('📋 Piano di Ribilanciamento'),
        const SizedBox(height: AppSpacing.s12),
        content,
      ],
    );
  }

  Widget _planTable(BuildContext context, RebalancePreview plan) {
    final AppTokens t = context.tokens;
    final TextStyle caption = AppText.caption(context);
    final Table table = Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: const <int, TableColumnWidth>{
        0: FixedColumnWidth(80),
        1: FlexColumnWidth(1.6),
        2: FixedColumnWidth(80),
        3: FixedColumnWidth(120),
        4: FixedColumnWidth(120),
      },
      border: TableBorder(
        horizontalInside: BorderSide(color: t.borderSubtle),
        bottom: BorderSide(color: t.border),
      ),
      children: <TableRow>[
        TableRow(
          children: <Widget>[
            _headerCell(context, 'Lato', alignment: Alignment.center),
            _headerCell(context, 'Titolo'),
            _headerCell(context, 'Quantità', alignment: Alignment.centerRight),
            _headerCell(
              context,
              'Prezzo Stimato',
              alignment: Alignment.centerRight,
            ),
            _headerCell(context, 'Importo', alignment: Alignment.centerRight),
          ],
        ),
        for (final RebalanceOrder order in plan.orders)
          TableRow(
            children: <Widget>[
              _bodyCell(
                context,
                alignment: Alignment.center,
                child: AppBadge.trade(order.side),
              ),
              _bodyCell(
                context,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    InkWell(
                      onTap: () =>
                          unawaited(showStockDetail(context, order.ticker)),
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
                    if (order.name.isNotEmpty ||
                        (order.allocationName?.isNotEmpty ?? false))
                      Text(
                        <String>[
                          if (order.name.isNotEmpty) order.name,
                          if (order.allocationName?.isNotEmpty ?? false)
                            order.allocationName!,
                        ].join(' • '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: caption,
                      ),
                  ],
                ),
              ),
              _bodyCell(
                context,
                alignment: Alignment.centerRight,
                child: Text(
                  formatDraftNumber(order.quantity),
                  style: AppText.mono(context, size: 13),
                ),
              ),
              _bodyCell(
                context,
                alignment: Alignment.centerRight,
                child: Text(
                  formatCurrency(
                    order.estimatedPrice,
                    currency: order.currency,
                  ),
                  style: AppText.mono(context, size: 13),
                ),
              ),
              _bodyCell(
                context,
                alignment: Alignment.centerRight,
                child: Text(
                  formatCurrency(
                    order.estimatedValue,
                    currency: order.currency,
                  ),
                  style: AppText.mono(
                    context,
                    size: 13,
                    weight: FontWeight.w700,
                    color: order.side == 'BUY' ? t.success : t.danger,
                  ),
                ),
              ),
            ],
          ),
      ],
    );

    final TextStyle monoPrimary = AppText.mono(
      context,
      size: 13,
      weight: FontWeight.w700,
      color: t.primary,
    );
    final TextStyle monoSuccess = AppText.mono(
      context,
      size: 13,
      weight: FontWeight.w700,
      color: t.success,
    );
    final TextStyle monoDanger = AppText.mono(
      context,
      size: 13,
      weight: FontWeight.w700,
      color: t.danger,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.s10,
          runSpacing: AppSpacing.s4,
          children: <Widget>[
            Text.rich(
              TextSpan(
                text: 'Valore totale (incl. liquidità): ',
                children: <InlineSpan>[
                  TextSpan(
                    text: formatCurrency(plan.totalValue),
                    style: monoPrimary,
                  ),
                ],
              ),
              style: caption,
            ),
            Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  const TextSpan(text: 'BUY: '),
                  TextSpan(
                    text: formatCurrency(plan.totalBuyValue),
                    style: monoSuccess,
                  ),
                  const TextSpan(text: ' • '),
                  const TextSpan(text: 'SELL: '),
                  TextSpan(
                    text: formatCurrency(plan.totalSellValue),
                    style: monoDanger,
                  ),
                ],
              ),
              style: caption,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s10),
        _scrollableTable(minWidth: 640, table: table),
      ],
    );
  }
}

// --- Widget privati condivisi dalla sezione --------------------------------

class _SubsectionTitle extends StatelessWidget {
  const _SubsectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: AppText.small(context)
          .copyWith(fontWeight: FontWeight.w700, color: context.tokens.primary),
    );
  }
}

class _CenteredNote extends StatelessWidget {
  const _CenteredNote({required this.text, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s18,
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppText.small(context)
            .copyWith(color: color ?? context.tokens.textMuted),
      ),
    );
  }
}

Widget _headerCell(
  BuildContext context,
  String label, {
  Alignment alignment = Alignment.centerLeft,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.s10,
      vertical: AppSpacing.s8,
    ),
    child: Text(
      label.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: _textAlignFor(alignment),
      style: AppText.tableHeader(context),
    ),
  );
}

Widget _bodyCell(
  BuildContext context, {
  required Widget child,
  Alignment alignment = Alignment.centerLeft,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.s10,
      vertical: AppSpacing.s8,
    ),
    child: Align(alignment: alignment, child: child),
  );
}

TextAlign _textAlignFor(Alignment alignment) {
  if (alignment == Alignment.centerRight) return TextAlign.right;
  if (alignment == Alignment.center) return TextAlign.center;
  return TextAlign.left;
}

Widget _scrollableTable({required double minWidth, required Table table}) {
  return LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      if (constraints.maxWidth < minWidth) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: minWidth, child: table),
        );
      }
      return table;
    },
  );
}
