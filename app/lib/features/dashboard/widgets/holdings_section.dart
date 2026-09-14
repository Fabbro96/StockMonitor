import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/formatters.dart';
import '../../../core/models/portfolio.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/skeleton.dart';
import '../../../widgets/ticker_flag.dart';
import 'price_flash.dart';

/// Tabella delle posizioni in portafoglio (prime 6 righe) con card-list
/// sotto i 640px. Colonne come `index.html`: Ticker & Titolo | Quantità |
/// Prezzo Attuale | Controvalore | P&L Netto (€) | P&L % | Dettagli.
///
/// Stati: 3 skeleton row su primo load, `Dati non disponibili.` in errore
/// senza dati, empty con `Aggiungi Holding` / `Prova Demo`, footnote
/// `Mostrate 6 di N posizioni` + `Vedi tutte ➔` sopra le 6 righe.
class HoldingsSection extends StatelessWidget {
  /// Crea la sezione.
  const HoldingsSection({
    super.key,
    required this.holdings,
    required this.loading,
    required this.failed,
    required this.onOpenStock,
    required this.onAddHolding,
    required this.onSeeAll,
    required this.onSeedDemo,
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

  /// Naviga al portafoglio completo.
  final VoidCallback onSeeAll;

  /// Carica i dati demo.
  final VoidCallback onSeedDemo;

  /// Numero massimo di righe mostrate in dashboard.
  static const int maxRows = 6;

  @override
  Widget build(BuildContext context) {
    if (holdings == null && loading) {
      return const Column(
        children: <Widget>[SkeletonRow(), SkeletonRow(), SkeletonRow()],
      );
    }

    if (holdings == null && failed) {
      return const EmptyState(message: 'Dati non disponibili.');
    }

    final List<Holding> list = holdings ?? const <Holding>[];
    if (list.isEmpty) {
      return EmptyState(
        message: 'Nessun titolo nel portafoglio.',
        actions: <Widget>[
          AppButton(
            label: '➕ Aggiungi Holding',
            size: AppButtonSize.sm,
            onPressed: onAddHolding,
          ),
          AppButton(
            label: '🚀 Prova Demo',
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
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              // Larghezza definita (>=760) così le celle Expanded hanno un
              // vincolo finito anche dentro lo scroll orizzontale.
              final double tableWidth =
                  constraints.maxWidth < 760 ? 760 : constraints.maxWidth;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: tableWidth,
                  child: Column(
                    children: <Widget>[
                      const _HoldingsHeader(),
                      for (final Holding holding in visible)
                        _HoldingsRow(
                          key: ValueKey<int>(holding.id),
                          holding: holding,
                          onOpenStock: onOpenStock,
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        if (list.length > maxRows)
          TableNote(
            left: Text('Mostrate ${visible.length} di ${list.length} posizioni'),
            right: _SeeAllLink(onTap: onSeeAll),
          ),
      ],
    );
  }
}

class _SeeAllLink extends StatelessWidget {
  const _SeeAllLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.small),
      child: Text('Vedi tutte ➔', style: AppText.link(context)),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(flex: 30, child: Text('TICKER & TITOLO', style: style)),
          Expanded(flex: 12, child: Text('QUANTITÀ', style: style, textAlign: TextAlign.right)),
          Expanded(flex: 16, child: Text('PREZZO ATTUALE', style: style, textAlign: TextAlign.right)),
          Expanded(flex: 17, child: Text('CONTROVALORE', style: style, textAlign: TextAlign.right)),
          Expanded(flex: 14, child: Text('P&L NETTO (€)', style: style, textAlign: TextAlign.right)),
          Expanded(flex: 11, child: Text('P&L %', style: style, textAlign: TextAlign.right)),
          SizedBox(width: 80, child: Text('DETTAGLI', style: style, textAlign: TextAlign.center)),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _hovered ? t.surfaceHover : Colors.transparent,
          border: Border(bottom: BorderSide(color: t.borderSubtle)),
        ),
        child: Row(
          children: <Widget>[
            Expanded(flex: 30, child: _tickerCell(context, holding)),
            Expanded(flex: 12, child: _numericCell(context, _formatQuantity(holding.quantity))),
            Expanded(
              flex: 16,
              child: Align(
                alignment: Alignment.centerRight,
                child: PriceFlash(
                  value: holding.currentPrice,
                  rising: up,
                  child: Text(
                    formatCurrency(holding.currentPrice, currency: holding.currency),
                    style: AppText.mono(context, size: 13.1, weight: FontWeight.w600),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 17,
              child: _numericCell(
                context,
                formatCurrency(holding.totalValue, currency: holding.currency),
                color: t.primary,
              ),
            ),
            Expanded(
              flex: 14,
              child: _numericCell(
                context,
                formatCurrency(holding.pnlAbsolute, currency: holding.currency),
                color: up ? t.successText : t.danger,
              ),
            ),
            Expanded(
              flex: 11,
              child: _numericCell(
                context,
                formatPercent(holding.pnlPercent),
                color: holding.pnlPercent >= 0 ? t.successText : t.danger,
              ),
            ),
            SizedBox(
              width: 80,
              child: Center(
                child: AppIconButton(
                  icon: const Text('🔍', style: TextStyle(fontSize: 13)),
                  size: 28,
                  bordered: true,
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
        Text(
          TickerFlags.forTicker(holding.ticker, market: holding.market),
          style: const TextStyle(fontSize: 13, height: 1.2),
        ),
        const SizedBox(width: AppSpacing.s8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              InkWell(
                onTap: () => widget.onOpenStock(holding.ticker),
                borderRadius: BorderRadius.circular(AppRadii.small),
                child: Text(
                  holding.ticker,
                  style: AppText.link(context).copyWith(
                    fontFamily: AppTokens.monoFontFamily,
                    fontFamilyFallback: AppTokens.monoFontFallback,
                  ),
                ),
              ),
              Text(
                holding.name.isEmpty ? holding.ticker : holding.name,
                style: AppText.caption(context).copyWith(fontSize: 12.2, color: t.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
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
        style: AppText.mono(context, size: 13.1, weight: FontWeight.w600, color: color),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _HoldingCard extends StatelessWidget {
  const _HoldingCard({super.key, required this.holding, required this.onOpenStock});

  final Holding holding;
  final ValueChanged<String> onOpenStock;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool up = holding.pnlAbsolute >= 0;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s12),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                TickerFlags.forTicker(holding.ticker, market: holding.market),
                style: const TextStyle(fontSize: 14, height: 1.2),
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      holding.ticker,
                      style: AppText.link(context).copyWith(fontSize: 14.4),
                    ),
                    Text(
                      holding.name.isEmpty ? holding.ticker : holding.name,
                      style: AppText.caption(context).copyWith(fontSize: 12.2, color: t.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              AppIconButton(
                icon: const Text('🔍', style: TextStyle(fontSize: 13)),
                size: 28,
                tooltip: 'Apri scheda completa',
                semanticLabel: 'Apri scheda completa di ${holding.ticker}',
                onPressed: () => onOpenStock(holding.ticker),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s10),
          Row(
            children: <Widget>[
              Expanded(child: _metric(context, 'Quantità', Text(_formatQuantity(holding.quantity), style: AppText.mono(context, size: 13.1, weight: FontWeight.w600)))),
              Expanded(
                child: _metric(
                  context,
                  'Prezzo Attuale',
                  PriceFlash(
                    value: holding.currentPrice,
                    rising: up,
                    child: Text(
                      formatCurrency(holding.currentPrice, currency: holding.currency),
                      style: AppText.mono(context, size: 13.1, weight: FontWeight.w600),
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
                    style: AppText.mono(context, size: 13.1, weight: FontWeight.w600, color: t.primary),
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
                  'P&L Netto (€)',
                  Text(
                    formatCurrency(holding.pnlAbsolute, currency: holding.currency),
                    style: AppText.mono(
                      context,
                      size: 13.1,
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
                  Text(
                    formatPercent(holding.pnlPercent),
                    style: AppText.mono(
                      context,
                      size: 13.1,
                      weight: FontWeight.w600,
                      color: holding.pnlPercent >= 0 ? t.successText : t.danger,
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

  Widget _metric(BuildContext context, String label, Widget value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: AppText.caption(context).copyWith(fontSize: 11)),
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
