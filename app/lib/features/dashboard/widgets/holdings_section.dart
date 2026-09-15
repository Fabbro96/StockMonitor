import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/formatters.dart';
import '../../../core/models/portfolio.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_delta.dart';
import '../../../widgets/app_error_panel.dart';
import '../../../widgets/app_market_tag.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/skeleton.dart';
import 'price_flash.dart';

/// Tabella delle posizioni in portafoglio (prime 6 righe) con card-list
/// sotto i 640px.
///
/// Colonne: Titolo (tag mercato + ticker + nome) | Quantità | Prezzo |
/// Controvalore | P&L netto | Δ% | Azioni. Righe da 40px, testata su
/// `surfaceSunken`, numeri mono tabulari allineati a destra.
///
/// Stati: 3 skeleton row su primo load, pannello d'errore incassato in errore
/// senza dati, empty con `Aggiungi posizione` / `Prova demo`, footnote
/// `Mostrate 6 di N posizioni` sopra le 6 righe.
class HoldingsSection extends StatelessWidget {
  /// Crea la sezione.
  const HoldingsSection({
    super.key,
    required this.holdings,
    required this.loading,
    required this.failed,
    required this.onOpenStock,
    required this.onAddHolding,
    required this.onSeedDemo,
    this.onRetry,
  });

  /// Righe del portafoglio; `null` finché mai caricate.
  final List<Holding>? holdings;

  /// True durante il primo caricamento.
  final bool loading;

  /// True se la sezione è fallita senza dati precedenti.
  final bool failed;

  /// Apre la scheda tecnica del ticker.
  final ValueChanged<String> onOpenStock;

  /// Naviga al portafoglio per aggiungere una holding.
  final VoidCallback onAddHolding;

  /// Carica i dati demo.
  final VoidCallback onSeedDemo;

  /// Ritenta il caricamento della sezione.
  final VoidCallback? onRetry;

  /// Numero massimo di righe mostrate in dashboard.
  static const int maxRows = 6;

  @override
  Widget build(BuildContext context) {
    if (holdings == null && loading) {
      return const Column(
        children: <Widget>[
          SkeletonRow(height: AppSizes.rowCompact),
          SkeletonRow(height: AppSizes.rowCompact),
          SkeletonRow(height: AppSizes.rowCompact),
        ],
      );
    }

    if (holdings == null && failed) {
      return AppErrorPanel(
        message: 'Posizioni non disponibili.',
        onRetry: onRetry,
      );
    }

    final List<Holding> list = holdings ?? const <Holding>[];
    if (list.isEmpty) {
      return EmptyState(
        message: 'Nessun titolo nel portafoglio.',
        actions: <Widget>[
          AppButton(
            label: 'Aggiungi posizione',
            icon: const Icon(Icons.add),
            size: AppButtonSize.sm,
            onPressed: onAddHolding,
          ),
          AppButton(
            label: 'Prova demo',
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
            onPressed: onSeedDemo,
          ),
        ],
      );
    }

    final List<Holding> visible = list.take(maxRows).toList();
    final bool compact = context.isCompact;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (compact)
          for (final Holding holding in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s10),
              child: _HoldingCard(
                key: ValueKey<int>(holding.id),
                holding: holding,
                onOpenStock: onOpenStock,
              ),
            )
        else
          _HoldingsTable(holdings: visible, onOpenStock: onOpenStock),
        if (list.length > maxRows)
          TableNote(
            left: Text('Mostrate ${visible.length} di ${list.length} posizioni'),
          ),
      ],
    );
  }
}

// --- Tabella (≥640px) -------------------------------------------------------

class _HoldingsTable extends StatelessWidget {
  const _HoldingsTable({required this.holdings, required this.onOpenStock});

  final List<Holding> holdings;
  final ValueChanged<String> onOpenStock;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.control),
      child: Column(
        children: <Widget>[
          const _HoldingsHeader(),
          for (final Holding holding in holdings)
            _HoldingsRow(
              key: ValueKey<int>(holding.id),
              holding: holding,
              onOpenStock: onOpenStock,
            ),
        ],
      ),
    );
  }
}

class _HoldingsHeader extends StatelessWidget {
  const _HoldingsHeader();

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final TextStyle style = AppText.tableHeader(context);
    return Container(
      height: AppSizes.tableHeader,
      color: t.surfaceSunken,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: <Widget>[
          Expanded(flex: 30, child: Text('TITOLO', style: style)),
          Expanded(flex: 12, child: Text('QUANTITÀ', style: style, textAlign: TextAlign.right)),
          Expanded(flex: 15, child: Text('PREZZO', style: style, textAlign: TextAlign.right)),
          Expanded(flex: 16, child: Text('CONTROVALORE', style: style, textAlign: TextAlign.right)),
          Expanded(flex: 15, child: Text('P&L', style: style, textAlign: TextAlign.right)),
          Expanded(flex: 11, child: Text('Δ%', style: style, textAlign: TextAlign.right)),
          const SizedBox(width: 34),
        ],
      ),
    );
  }
}

class _HoldingsRow extends StatefulWidget {
  const _HoldingsRow({super.key, required this.holding, required this.onOpenStock});

  final Holding holding;
  final ValueChanged<String> onOpenStock;

  @override
  State<_HoldingsRow> createState() => _HoldingsRowState();
}

class _HoldingsRowState extends State<_HoldingsRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final Holding holding = widget.holding;
    final bool up = holding.pnlAbsolute >= 0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: AppMotion.effective(context, AppMotion.fast),
        curve: AppMotion.ease,
        height: AppSizes.rowCompact,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: _hovered ? t.surfaceHover : Colors.transparent,
          border: Border(bottom: BorderSide(color: t.borderSubtle)),
        ),
        child: Row(
          children: <Widget>[
            Expanded(flex: 30, child: _tickerCell(context, holding)),
            Expanded(flex: 12, child: _numericCell(context, _formatQuantity(holding.quantity))),
            Expanded(
              flex: 15,
              child: Align(
                alignment: Alignment.centerRight,
                child: PriceFlash(
                  value: holding.currentPrice,
                  rising: up,
                  child: Text(
                    formatCurrency(holding.currentPrice, currency: holding.currency),
                    style: AppText.tableCellNum(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 16,
              child: _numericCell(
                context,
                formatCurrency(holding.totalValue, currency: holding.currency),
                color: t.primary,
              ),
            ),
            Expanded(
              flex: 15,
              child: _numericCell(
                context,
                formatCurrency(holding.pnlAbsolute, currency: holding.currency),
                color: up ? t.successText : t.danger,
              ),
            ),
            Expanded(
              flex: 11,
              child: Align(
                alignment: Alignment.centerRight,
                child: AppDelta(value: holding.pnlPercent, suffix: '%', size: 12.5),
              ),
            ),
            SizedBox(
              width: 34,
              child: Center(
                child: AppIconButton(
                  icon: const Icon(Icons.arrow_outward),
                  size: AppSizes.iconButtonSm,
                  iconSize: AppSizes.iconSm,
                  minTargetSize: AppSizes.touchTarget,
                  tooltip: 'Apri scheda completa',
                  semanticLabel: 'Apri scheda completa di ${holding.ticker}',
                  onPressed: () => widget.onOpenStock(holding.ticker),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tickerCell(BuildContext context, Holding holding) {
    final AppTokens t = context.tokens;
    return Row(
      children: <Widget>[
        AppMarketTag.forTicker(holding.ticker, market: holding.market),
        const SizedBox(width: AppSpacing.s6),
        InkWell(
          onTap: () => widget.onOpenStock(holding.ticker),
          borderRadius: BorderRadius.circular(AppRadii.small),
          child: Text(
            holding.ticker,
            style: AppText.mono(context, size: 12.5, weight: FontWeight.w700, color: t.primary),
          ),
        ),
        const SizedBox(width: AppSpacing.s6),
        Expanded(
          child: Text(
            holding.name.isEmpty ? holding.ticker : holding.name,
            style: AppText.caption(context).copyWith(color: t.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _numericCell(BuildContext context, String text, {Color? color}) {
    return Align(
      alignment: Alignment.centerRight,
      child: Text(
        text,
        style: AppText.tableCellNum(context).copyWith(color: color),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// --- Card (sotto 640px) -----------------------------------------------------

class _HoldingCard extends StatelessWidget {
  const _HoldingCard({super.key, required this.holding, required this.onOpenStock});

  final Holding holding;
  final ValueChanged<String> onOpenStock;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool up = holding.pnlAbsolute >= 0;

    return AppCard(
      subtle: true,
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppMarketTag.forTicker(holding.ticker, market: holding.market),
              const SizedBox(width: AppSpacing.s6),
              Expanded(
                child: InkWell(
                  onTap: () => onOpenStock(holding.ticker),
                  borderRadius: BorderRadius.circular(AppRadii.small),
                  child: Text(
                    holding.ticker,
                    style: AppText.mono(context, size: 13.5, weight: FontWeight.w700, color: t.primary),
                  ),
                ),
              ),
              AppDelta(value: holding.pnlPercent, suffix: '%', size: 12.5),
              const SizedBox(width: AppSpacing.s4),
              AppIconButton(
                icon: const Icon(Icons.arrow_outward),
                size: AppSizes.iconButtonSm,
                iconSize: AppSizes.iconSm,
                minTargetSize: AppSizes.touchTarget,
                tooltip: 'Apri scheda completa',
                semanticLabel: 'Apri scheda completa di ${holding.ticker}',
                onPressed: () => onOpenStock(holding.ticker),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(
            holding.name.isEmpty ? holding.ticker : holding.name,
            style: AppText.caption(context).copyWith(color: t.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.s10),
          Row(
            children: <Widget>[
              Expanded(child: _metric(context, 'Quantità', Text(_formatQuantity(holding.quantity), style: AppText.mono(context, size: 13, weight: FontWeight.w600)))),
              Expanded(
                child: _metric(
                  context,
                  'Prezzo',
                  PriceFlash(
                    value: holding.currentPrice,
                    rising: up,
                    child: Text(
                      formatCurrency(holding.currentPrice, currency: holding.currency),
                      style: AppText.mono(context, size: 13, weight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _metric(
                  context,
                  'Controvalore',
                  Text(
                    formatCurrency(holding.totalValue, currency: holding.currency),
                    style: AppText.mono(context, size: 13, weight: FontWeight.w600, color: t.primary),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          Row(
            children: <Widget>[
              Expanded(
                child: _metric(
                  context,
                  'P&L netto',
                  Text(
                    formatCurrency(holding.pnlAbsolute, currency: holding.currency),
                    style: AppText.mono(
                      context,
                      size: 13,
                      weight: FontWeight.w600,
                      color: up ? t.successText : t.danger,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _metric(
                  context,
                  'P&L %',
                  AppDelta(value: holding.pnlPercent, suffix: '%', size: 13),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric(BuildContext context, String label, Widget value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: AppText.micro(context).copyWith(fontSize: 10.5, color: context.tokens.textMuted)),
        const SizedBox(height: AppSpacing.s2),
        value,
      ],
    );
  }
}

String _formatQuantity(double value) {
  final NumberFormat format = value == value.roundToDouble()
      ? NumberFormat('#,##0', 'it_IT')
      : NumberFormat('#,##0.####', 'it_IT');
  return format.format(value);
}
