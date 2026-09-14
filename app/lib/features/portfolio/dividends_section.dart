import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/models/portfolio.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/section_header.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/ticker_flag.dart';
import '../stock_detail/stock_detail_modal.dart' show showStockDetail;
import 'portfolio_edits.dart' show formatDraftNumber;
import 'portfolio_tools_providers.dart';

/// Sezione "💶 Calendario Dividendi" (parità `#dividendsCard`).
///
/// Mostra i callout di riepilogo (reddito annuo/mensile, yield on cost) e la
/// tabella per titolo; il bottone "↻ Aggiorna" rifà `GET /portfolio/dividends`.
class DividendsSection extends ConsumerWidget {
  /// Crea la sezione Dividendi.
  const DividendsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<DividendsResult> async = ref.watch(dividendsProvider);
    final DividendsResult? data = async.value;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SectionHeader(
            title: '💶 Calendario Dividendi',
            subtitle:
                'Stima del reddito cedolare annuo e mensile generato dalle '
                'posizioni in portafoglio.',
            trailing: AppButton(
              label: '↻ Aggiorna',
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.sm,
              loading: async.isRefreshing,
              onPressed: () => ref.invalidate(dividendsProvider),
            ),
          ),
          _CalloutGrid(
            annual: data?.totalAnnualDividendEur,
            monthly: data?.totalMonthlyDividendEur,
            yieldOnCost: data?.portfolioYieldOnCost,
          ),
          const SizedBox(height: AppSpacing.s16),
          _DividendsTable(async: async),
        ],
      ),
    );
  }
}

// --- Callout di riepilogo ---------------------------------------------------

class _CalloutGrid extends StatelessWidget {
  const _CalloutGrid({this.annual, this.monthly, this.yieldOnCost});

  final double? annual;
  final double? monthly;
  final double? yieldOnCost;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double gap = AppSpacing.s12;
        final int columns = constraints.maxWidth >= 560
            ? 3
            : (constraints.maxWidth >= 372 ? 2 : 1);
        final double itemWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            SizedBox(
              width: itemWidth,
              child: _Callout(
                label: 'Reddito Annuo Stimato',
                value: annual == null ? '-- €' : formatCurrency(annual),
                valueColor: t.success,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _Callout(
                label: 'Reddito Mensile Medio',
                value: monthly == null ? '-- €' : formatCurrency(monthly),
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _Callout(
                label: 'Yield on Cost',
                value: yieldOnCost == null
                    ? '--%'
                    : '${yieldOnCost!.toStringAsFixed(2)}%',
                valueColor: t.primary,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Callout extends StatelessWidget {
  const _Callout({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      subtle: true,
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label.toUpperCase(), style: AppText.sectionLabel(context)),
          const SizedBox(height: AppSpacing.s4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.mono(
              context,
              size: 20,
              weight: FontWeight.w700,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

// --- Tabella dividendi ------------------------------------------------------

class _DividendsTable extends StatelessWidget {
  const _DividendsTable({required this.async});

  final AsyncValue<DividendsResult> async;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    if (async.isLoading && !async.hasValue) {
      return const Column(
        children: <Widget>[SkeletonRow(), SkeletonRow(), SkeletonRow()],
      );
    }
    if (async.hasError && !async.hasValue) {
      return const EmptyState(
        icon: Icon(Icons.error_outline),
        message: 'Errore nel caricamento dei dividendi',
      );
    }

    final List<DividendHolding> holdings =
        async.value?.holdings ?? const <DividendHolding>[];
    if (holdings.isEmpty) {
      return const EmptyState(
        icon: Text('💶', style: TextStyle(fontSize: 22)),
        message:
            'Nessun dato sui dividendi disponibile. Aggiungi posizioni con '
            'titoli che distribuiscono dividendi oppure aggiorna i dati.',
      );
    }

    final Table table = Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: const <int, TableColumnWidth>{
        0: FlexColumnWidth(1.2),
        1: FlexColumnWidth(1.2),
        2: FixedColumnWidth(80),
        3: FixedColumnWidth(120),
        4: FixedColumnWidth(90),
        5: FixedColumnWidth(110),
        6: FixedColumnWidth(120),
        7: FixedColumnWidth(120),
      },
      border: TableBorder(
        horizontalInside: BorderSide(color: t.borderSubtle),
        bottom: BorderSide(color: t.border),
      ),
      children: <TableRow>[
        TableRow(
          children: <Widget>[
            _headerCell(context, 'Ticker'),
            _headerCell(context, 'Nome'),
            _headerCell(context, 'Quota', alignment: Alignment.centerRight),
            _headerCell(
              context,
              'Dividendo/azione',
              alignment: Alignment.centerRight,
            ),
            _headerCell(context, 'Yield', alignment: Alignment.centerRight),
            _headerCell(
              context,
              'Yield on Cost',
              alignment: Alignment.centerRight,
            ),
            _headerCell(
              context,
              'Reddito/anno (€)',
              alignment: Alignment.centerRight,
            ),
            _headerCell(
              context,
              'Reddito/mese (€)',
              alignment: Alignment.centerRight,
            ),
          ],
        ),
        for (final DividendHolding holding in holdings)
          TableRow(
            children: <Widget>[
              _bodyCell(
                context,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      TickerFlags.forTicker(
                        holding.ticker,
                        market: holding.market,
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(width: AppSpacing.s6),
                    InkWell(
                      onTap: () =>
                          unawaited(showStockDetail(context, holding.ticker)),
                      borderRadius: BorderRadius.circular(AppRadii.small),
                      child: Text(
                        holding.ticker,
                        style: AppText.mono(
                          context,
                          size: 13,
                          weight: FontWeight.w700,
                          color: t.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _bodyCell(
                context,
                child: Text(
                  holding.name.isEmpty ? holding.ticker : holding.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.tableCell(context)
                      .copyWith(color: t.textSecondary),
                ),
              ),
              _bodyCell(
                context,
                alignment: Alignment.centerRight,
                child: Text(
                  formatDraftNumber(holding.quantity),
                  style: AppText.mono(context, size: 13),
                ),
              ),
              _bodyCell(
                context,
                alignment: Alignment.centerRight,
                child: Text(
                  formatCurrency(
                    holding.annualDividendPerShare,
                    currency: holding.currency,
                  ),
                  style: AppText.mono(context, size: 13),
                ),
              ),
              _bodyCell(
                context,
                alignment: Alignment.centerRight,
                child: Text(
                  '${holding.dividendYieldPct.toStringAsFixed(2)}%',
                  style: AppText.mono(context, size: 13),
                ),
              ),
              _bodyCell(
                context,
                alignment: Alignment.centerRight,
                child: Text(
                  '${holding.yieldOnCostPct.toStringAsFixed(2)}%',
                  style: AppText.mono(
                    context,
                    size: 13,
                    weight: FontWeight.w700,
                    color: t.success,
                  ),
                ),
              ),
              _bodyCell(
                context,
                alignment: Alignment.centerRight,
                child: Text(
                  formatCurrency(holding.annualIncomeEur),
                  style: AppText.mono(
                    context,
                    size: 13,
                    weight: FontWeight.w700,
                    color: t.success,
                  ),
                ),
              ),
              _bodyCell(
                context,
                alignment: Alignment.centerRight,
                child: Text(
                  formatCurrency(holding.monthlyIncomeEur),
                  style: AppText.mono(
                    context,
                    size: 13,
                    weight: FontWeight.w500,
                    color: t.textSecondary,
                  ),
                ),
              ),
            ],
          ),
      ],
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < 980) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: 980, child: table),
          );
        }
        return table;
      },
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
