import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/models/portfolio.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_error_panel.dart';
import '../../widgets/app_market_tag.dart';
import '../../widgets/badges.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/section_header.dart';
import '../stock_detail/stock_detail_modal.dart' show showStockDetail;
import 'portfolio_edits.dart' show formatDraftNumber, formatSharePercent;
import 'portfolio_table.dart';
import 'portfolio_tools_providers.dart';

/// Sezione "Calendario Dividendi" (parità `#dividendsCard`).
///
/// Mostra i riepiloghi a timbro (reddito annuo/mensile, yield on cost) e la
/// tabella per titolo; il bottone "Aggiorna" rifà `GET /portfolio/dividends`.
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
            variant: SectionHeaderVariant.rule,
            icon: Icons.calendar_month_outlined,
            overline: 'Registro',
            title: 'Calendario dividendi',
            subtitle:
                'Stima del reddito cedolare annuo e mensile generato dalle '
                'posizioni in portafoglio.',
            trailing: AppButton(
              label: 'Aggiorna',
              icon: const Icon(Icons.refresh),
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
          _DividendsTable(async: async, onRetry: () => ref.invalidate(dividendsProvider)),
        ],
      ),
    );
  }
}

// --- Riepiloghi a timbro -----------------------------------------------------

class _CalloutGrid extends StatelessWidget {
  const _CalloutGrid({this.annual, this.monthly, this.yieldOnCost});

  final double? annual;
  final double? monthly;
  final double? yieldOnCost;

  @override
  Widget build(BuildContext context) {
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
                label: 'Reddito annuo stimato',
                icon: Icons.savings_outlined,
                value: annual == null ? null : formatCurrency(annual),
                tone: BadgeTone.success,
                stampIcon: Icons.check,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _Callout(
                label: 'Reddito mensile medio',
                icon: Icons.calendar_view_month_outlined,
                value: monthly == null ? null : formatCurrency(monthly),
                tone: BadgeTone.neutral,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _Callout(
                label: 'Yield on cost',
                icon: Icons.percent,
                value: yieldOnCost == null
                    ? null
                    : formatSharePercent(yieldOnCost!),
                tone: BadgeTone.primary,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Callout extends StatelessWidget {
  const _Callout({
    required this.label,
    required this.value,
    this.icon,
    this.tone = BadgeTone.neutral,
    this.stampIcon,
  });

  final String label;
  final String? value;
  final IconData? icon;
  final BadgeTone tone;
  final IconData? stampIcon;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return AppCard(
      subtle: true,
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: AppSizes.iconXs, color: t.textFaint),
                const SizedBox(width: AppSpacing.s6),
              ],
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.statLabel(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          if (value == null)
            Text(
              '—',
              style: AppText.mono(
                context,
                size: 20,
                weight: FontWeight.w700,
                color: t.textMuted,
              ),
            )
          else
            _Stamp(value: value!, tone: tone, icon: stampIcon),
        ],
      ),
    );
  }
}

/// Valore "a timbro": riquadro bordato con numero mono, per i dati di
/// reddito (verde quando c'è un importo, neutro quando è in attesa).
class _Stamp extends StatelessWidget {
  const _Stamp({required this.value, this.tone = BadgeTone.neutral, this.icon});

  final String value;
  final BadgeTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final (Color background, Color border, Color foreground) = switch (tone) {
      BadgeTone.success => (t.successBg, t.successBorder, t.successText),
      BadgeTone.primary => (t.primaryGlow, t.primary, t.primary),
      _ => (t.surface, t.border, t.textPrimary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s4,
      ),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(AppRadii.tag),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: AppSizes.iconXs, color: foreground),
            const SizedBox(width: AppSpacing.s6),
          ],
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.mono(
                context,
                size: 14,
                weight: FontWeight.w700,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Tabella dividendi ------------------------------------------------------

class _DividendsTable extends StatelessWidget {
  const _DividendsTable({required this.async, required this.onRetry});

  final AsyncValue<DividendsResult> async;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    if (async.isLoading && !async.hasValue) {
      return const PortfolioTableSkeleton();
    }
    if (async.hasError && !async.hasValue) {
      return AppErrorPanel(
        message: 'Errore nel caricamento dei dividendi',
        onRetry: onRetry,
      );
    }

    final List<DividendHolding> holdings =
        async.value?.holdings ?? const <DividendHolding>[];
    if (holdings.isEmpty) {
      return const EmptyState(
        icon: Icon(Icons.savings_outlined),
        message:
            'Nessun dato sui dividendi disponibile. Aggiungi posizioni con '
            'titoli che distribuiscono dividendi oppure aggiorna i dati.',
      );
    }

    return PortfolioTable(
      minWidth: 980,
      child: Column(
        children: <Widget>[
          const PortfolioTableHeader(
            cells: <Widget>[
              Expanded(flex: 26, child: PortfolioHeaderLabel('Titolo')),
              SizedBox(
                width: 88,
                child: PortfolioHeaderLabel(
                  'Quota',
                  alignment: Alignment.centerRight,
                ),
              ),
              SizedBox(
                width: 124,
                child: PortfolioHeaderLabel(
                  'Dividendo/azione',
                  alignment: Alignment.centerRight,
                ),
              ),
              SizedBox(
                width: 84,
                child: PortfolioHeaderLabel(
                  'Yield',
                  alignment: Alignment.centerRight,
                ),
              ),
              SizedBox(
                width: 104,
                child: PortfolioHeaderLabel(
                  'Yield on cost',
                  alignment: Alignment.centerRight,
                ),
              ),
              SizedBox(
                width: 132,
                child: PortfolioHeaderLabel(
                  'Reddito/anno',
                  alignment: Alignment.centerRight,
                ),
              ),
              SizedBox(
                width: 120,
                child: PortfolioHeaderLabel(
                  'Reddito/mese',
                  alignment: Alignment.centerRight,
                ),
              ),
            ],
          ),
          for (final DividendHolding holding in holdings)
            PortfolioTableRow(
              cells: <Widget>[
                Expanded(
                  flex: 26,
                  child: _TickerCell(holding: holding),
                ),
                SizedBox(
                  width: 88,
                  child: PortfolioCell(
                    alignment: Alignment.centerRight,
                    child: Text(
                      formatDraftNumber(holding.quantity),
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
                        holding.annualDividendPerShare,
                        currency: holding.currency,
                      ),
                      style: AppText.tableCellNum(context),
                    ),
                  ),
                ),
                SizedBox(
                  width: 84,
                  child: PortfolioCell(
                    alignment: Alignment.centerRight,
                    child: Text(
                      formatSharePercent(holding.dividendYieldPct),
                      style: AppText.tableCellNum(context),
                    ),
                  ),
                ),
                SizedBox(
                  width: 104,
                  child: PortfolioCell(
                    alignment: Alignment.centerRight,
                    child: Text(
                      formatSharePercent(holding.yieldOnCostPct),
                      style: AppText.tableCellNum(context).copyWith(
                        color: t.successText,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 132,
                  child: PortfolioCell(
                    alignment: Alignment.centerRight,
                    child: _incomeStamp(context, holding.annualIncomeEur),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: PortfolioCell(
                    alignment: Alignment.centerRight,
                    child: Text(
                      formatCurrency(holding.monthlyIncomeEur),
                      style: AppText.tableCellNum(context).copyWith(
                        color: t.textSecondary,
                        fontWeight: FontWeight.w500,
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

  /// Timbro del reddito annuo: verde quando c'è un importo stimato, neutro
  /// quando la posizione è in attesa di dividendo.
  Widget _incomeStamp(BuildContext context, double income) {
    final bool pending = income <= 0;
    return Tooltip(
      message: pending
          ? 'Nessun dividendo stimato per questa posizione'
          : 'Reddito annuo stimato',
      child: _Stamp(
        value: formatCurrency(income),
        tone: pending ? BadgeTone.neutral : BadgeTone.success,
        icon: pending ? Icons.schedule : Icons.check,
      ),
    );
  }
}

/// Cella titolo: tag di mercato, ticker mono collegato alla scheda e nome.
class _TickerCell extends StatelessWidget {
  const _TickerCell({required this.holding});

  final DividendHolding holding;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Row(
      children: <Widget>[
        AppMarketTag.forTicker(holding.ticker, market: holding.market),
        const SizedBox(width: AppSpacing.s6),
        InkWell(
          onTap: () => unawaited(showStockDetail(context, holding.ticker)),
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
        const SizedBox(width: AppSpacing.s6),
        Expanded(
          child: Text(
            holding.name.isEmpty ? holding.ticker : holding.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption(context).copyWith(color: t.textSecondary),
          ),
        ),
      ],
    );
  }
}
