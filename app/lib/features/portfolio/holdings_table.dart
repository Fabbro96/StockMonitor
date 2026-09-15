import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/models/portfolio.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_delta.dart';
import '../../widgets/app_key_value.dart';
import '../../widgets/app_market_tag.dart';
import '../../widgets/stepper_input.dart';
import 'portfolio_edits.dart';
import 'portfolio_table.dart';

/// Callback di modifica inline: quantità e/o prezzo in bozza.
typedef HoldingEditCallback = void Function(
  Holding holding, {
  double? quantity,
  double? avgPrice,
});

/// Larghezza minima della tabella: sotto questa soglia scroll orizzontale
/// (e sotto 900px si passa alle card, pattern della Watchlist).
const double _tableMinWidth = 1060;

/// Tabella holdings con inline edit (≥900px) e card list (<900px).
class HoldingsTable extends StatelessWidget {
  /// Crea la tabella holdings.
  const HoldingsTable({
    super.key,
    required this.holdings,
    required this.edits,
    required this.epoch,
    required this.onEdit,
    required this.onDelete,
    required this.onOpenTicker,
    required this.onEditMarket,
  });

  /// Holdings server.
  final List<Holding> holdings;

  /// Modifiche inline pendenti.
  final Map<int, HoldingEdit> edits;

  /// Contatore che invalida i controller delle celle dopo annulla/salva.
  final int epoch;

  /// Notifica una modifica di quantità/prezzo.
  final HoldingEditCallback onEdit;

  /// Elimina la posizione (con undo a carico della pagina).
  final ValueChanged<Holding> onDelete;

  /// Apre la scheda titolo.
  final ValueChanged<Holding> onOpenTicker;

  /// Apre l'editor del mercato.
  final ValueChanged<Holding> onEditMarket;

  @override
  Widget build(BuildContext context) {
    if (context.isDrawerLayout) {
      return Column(
        children: <Widget>[
          for (final Holding holding in holdings)
            _HoldingCard(
              holding: holding,
              edit: holdingEditOf(holding, edits),
              epoch: epoch,
              onEdit: onEdit,
              onDelete: onDelete,
              onOpenTicker: onOpenTicker,
              onEditMarket: onEditMarket,
            ),
        ],
      );
    }
    return _buildTable(context);
  }

  Widget _buildTable(BuildContext context) {
    return PortfolioTable(
      minWidth: _tableMinWidth,
      child: Column(
        children: <Widget>[
          const PortfolioTableHeader(
            cells: <Widget>[
              Expanded(flex: 26, child: PortfolioHeaderLabel('Titolo')),
              SizedBox(
                width: 140,
                child: PortfolioHeaderLabel(
                  'Quantità',
                  alignment: Alignment.centerRight,
                ),
              ),
              SizedBox(
                width: 150,
                child: PortfolioHeaderLabel(
                  'Prezzo carico',
                  alignment: Alignment.centerRight,
                ),
              ),
              Expanded(
                flex: 10,
                child: PortfolioHeaderLabel(
                  'Prezzo live',
                  alignment: Alignment.centerRight,
                ),
              ),
              Expanded(
                flex: 11,
                child: PortfolioHeaderLabel(
                  'Controvalore',
                  alignment: Alignment.centerRight,
                ),
              ),
              Expanded(
                flex: 11,
                child: PortfolioHeaderLabel(
                  'P&L netto',
                  alignment: Alignment.centerRight,
                ),
              ),
              Expanded(
                flex: 8,
                child: PortfolioHeaderLabel(
                  'P&L %',
                  alignment: Alignment.centerRight,
                ),
              ),
              SizedBox(width: 76, child: PortfolioHeaderLabel('')),
            ],
          ),
          for (final Holding holding in holdings)
            _HoldingRow(
              holding: holding,
              edit: holdingEditOf(holding, edits),
              epoch: epoch,
              onEdit: onEdit,
              onDelete: onDelete,
              onOpenTicker: onOpenTicker,
              onEditMarket: onEditMarket,
            ),
        ],
      ),
    );
  }
}

/// Riga della tabella desktop: 40px, numeri mono tabulari allineati a destra,
/// azioni rivelate con hover/focus.
class _HoldingRow extends StatelessWidget {
  const _HoldingRow({
    required this.holding,
    required this.edit,
    required this.epoch,
    required this.onEdit,
    required this.onDelete,
    required this.onOpenTicker,
    required this.onEditMarket,
  });

  final Holding holding;
  final HoldingEdit edit;
  final int epoch;
  final HoldingEditCallback onEdit;
  final ValueChanged<Holding> onDelete;
  final ValueChanged<Holding> onOpenTicker;
  final ValueChanged<Holding> onEditMarket;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final Color pnlColor = edit.pnlAbsolute >= 0 ? t.success : t.danger;

    return PortfolioTableRow(
      highlighted: edit.changed,
      cells: <Widget>[
        Expanded(
          flex: 26,
          child: _TickerCell(
            holding: holding,
            onOpenTicker: onOpenTicker,
            onEditMarket: onEditMarket,
          ),
        ),
        SizedBox(
          width: 140,
          child: PortfolioCell(
            alignment: Alignment.centerRight,
            child: _QtyCell(
              key: ValueKey<String>('qty-${holding.id}-$epoch'),
              edit: edit,
              onChanged: (double value) => onEdit(holding, quantity: value),
            ),
          ),
        ),
        SizedBox(
          width: 150,
          child: PortfolioCell(
            alignment: Alignment.centerRight,
            child: _PriceCell(
              key: ValueKey<String>('price-${holding.id}-$epoch'),
              edit: edit,
              onChanged: (double value) => onEdit(holding, avgPrice: value),
            ),
          ),
        ),
        Expanded(
          flex: 10,
          child: PortfolioCell(
            alignment: Alignment.centerRight,
            child: _money(context, edit.currentPrice, currency: holding.currency),
          ),
        ),
        Expanded(
          flex: 11,
          child: PortfolioCell(
            alignment: Alignment.centerRight,
            child: _money(
              context,
              edit.totalValue,
              currency: holding.currency,
              color: t.primary,
            ),
          ),
        ),
        Expanded(
          flex: 11,
          child: PortfolioCell(
            alignment: Alignment.centerRight,
            child: Text(
              _signedMoney(edit.pnlAbsolute, holding.currency),
              textAlign: TextAlign.right,
              style: AppText.tableCellNum(context).copyWith(color: pnlColor),
            ),
          ),
        ),
        Expanded(
          flex: 8,
          child: PortfolioCell(
            alignment: Alignment.centerRight,
            child: AppDelta(
              value: edit.pnlPercent,
              suffix: '%',
              size: 12.5,
              colorOverride: pnlColor,
            ),
          ),
        ),
        SizedBox(
          width: 76,
          child: PortfolioCell(
            alignment: Alignment.centerRight,
            child: PortfolioActionsReveal(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  AppIconButton(
                    icon: const Icon(Icons.arrow_outward),
                    size: AppSizes.iconButtonSm,
                    iconSize: AppSizes.iconSm,
                    minTargetSize: AppSizes.touchTarget,
                    tooltip: 'Apri scheda completa',
                    semanticLabel:
                        'Apri la scheda completa di ${holding.ticker}',
                    onPressed: () => onOpenTicker(holding),
                  ),
                  AppIconButton(
                    icon: const Icon(Icons.delete_outline),
                    size: AppSizes.iconButtonSm,
                    iconSize: AppSizes.iconSm,
                    minTargetSize: AppSizes.touchTarget,
                    tooltip: 'Elimina',
                    semanticLabel: 'Elimina posizione ${holding.ticker}',
                    danger: true,
                    onPressed: () => onDelete(holding),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Cella titolo: tag di mercato (editor mercato), ticker mono e nome.
class _TickerCell extends StatelessWidget {
  const _TickerCell({
    required this.holding,
    required this.onOpenTicker,
    required this.onEditMarket,
  });

  final Holding holding;
  final ValueChanged<Holding> onOpenTicker;
  final ValueChanged<Holding> onEditMarket;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final String name = holding.name.isEmpty ? holding.ticker : holding.name;
    final String notes = holding.notes;
    return Row(
      children: <Widget>[
        Tooltip(
          message: 'Modifica mercato',
          child: Semantics(
            button: true,
            label: 'Modifica mercato di ${holding.ticker}',
            child: InkWell(
              onTap: () => onEditMarket(holding),
              borderRadius: BorderRadius.circular(AppRadii.tag),
              child: AppMarketTag.forTicker(
                holding.ticker,
                market: holding.market,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.s6),
        InkWell(
          onTap: () => onOpenTicker(holding),
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
          child: Tooltip(
            message: notes.isEmpty ? name : '$name\n$notes',
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption(context).copyWith(color: t.textSecondary),
            ),
          ),
        ),
        if (notes.isNotEmpty) ...<Widget>[
          const SizedBox(width: AppSpacing.s4),
          Tooltip(
            message: notes,
            child: Icon(
              Icons.sticky_note_2_outlined,
              size: AppSizes.iconXs,
              color: t.textFaint,
            ),
          ),
        ],
      ],
    );
  }
}

/// Card holdings per viewport strette (<900px).
class _HoldingCard extends StatelessWidget {
  const _HoldingCard({
    required this.holding,
    required this.edit,
    required this.epoch,
    required this.onEdit,
    required this.onDelete,
    required this.onOpenTicker,
    required this.onEditMarket,
  });

  final Holding holding;
  final HoldingEdit edit;
  final int epoch;
  final HoldingEditCallback onEdit;
  final ValueChanged<Holding> onDelete;
  final ValueChanged<Holding> onOpenTicker;
  final ValueChanged<Holding> onEditMarket;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final Color pnlColor = edit.pnlAbsolute >= 0 ? t.success : t.danger;

    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.s10),
      accent: edit.changed,
      accentColor: t.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _TickerCell(
                  holding: holding,
                  onOpenTicker: onOpenTicker,
                  onEditMarket: onEditMarket,
                ),
              ),
              AppIconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Elimina',
                semanticLabel: 'Elimina posizione ${holding.ticker}',
                danger: true,
                onPressed: () => onDelete(holding),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text('Quantità', style: AppText.statLabel(context)),
                    const SizedBox(height: AppSpacing.s4),
                    _QtyCell(
                      key: ValueKey<String>('qty-${holding.id}-$epoch'),
                      edit: edit,
                      expand: true,
                      onChanged: (double value) =>
                          onEdit(holding, quantity: value),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text('Prezzo carico', style: AppText.statLabel(context)),
                    const SizedBox(height: AppSpacing.s4),
                    _PriceCell(
                      key: ValueKey<String>('price-${holding.id}-$epoch'),
                      edit: edit,
                      expand: true,
                      onChanged: (double value) =>
                          onEdit(holding, avgPrice: value),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          AppKeyValue(
            label: 'Prezzo live',
            value: formatCurrency(
              edit.currentPrice,
              currency: holding.currency,
            ),
          ),
          AppKeyValue(
            label: 'Controvalore',
            value: formatCurrency(edit.totalValue, currency: holding.currency),
            valueColor: t.primary,
          ),
          AppKeyValue(
            label: 'P&L netto',
            value: _signedMoney(edit.pnlAbsolute, holding.currency),
            valueColor: pnlColor,
          ),
          AppKeyValue(
            label: 'P&L %',
            valueWidget: AppDelta(
              value: edit.pnlPercent,
              suffix: '%',
              size: 12.5,
              colorOverride: pnlColor,
            ),
            divider: false,
          ),
        ],
      ),
    );
  }
}

/// Importo in mono tabulare allineato a destra.
Widget _money(
  BuildContext context,
  num? value, {
  required String currency,
  Color? color,
}) {
  return Text(
    formatCurrency(value, currency: currency),
    textAlign: TextAlign.right,
    style: AppText.tableCellNum(context).copyWith(color: color),
  );
}

/// Importo firmato (`+1.234,56 €` / `−120,00 €`), mai solo colore.
String _signedMoney(num? value, String currency) {
  if (value == null || !value.isFinite) return '—';
  final String formatted = formatCurrency(value.abs(), currency: currency);
  if (value > 0) return '+$formatted';
  if (value < 0) return '−$formatted';
  return formatted;
}

class _QtyCell extends StatefulWidget {
  const _QtyCell({
    super.key,
    required this.edit,
    required this.onChanged,
    this.expand = false,
  });

  final HoldingEdit edit;
  final ValueChanged<double> onChanged;
  final bool expand;

  @override
  State<_QtyCell> createState() => _QtyCellState();
}

class _QtyCellState extends State<_QtyCell> {
  late final TextEditingController _controller = TextEditingController(
    text: formatDraftNumber(widget.edit.quantity),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StepperInput(
      controller: _controller,
      min: 0,
      step: 1,
      expand: widget.expand,
      width: widget.expand ? null : 132,
      semanticsLabel: 'Quantità per ${widget.edit.holding.ticker}',
      increaseLabel: 'Aumenta quantità per ${widget.edit.holding.ticker}',
      decreaseLabel: 'Diminuisci quantità per ${widget.edit.holding.ticker}',
      onChanged: widget.onChanged,
    );
  }
}

class _PriceCell extends StatefulWidget {
  const _PriceCell({
    super.key,
    required this.edit,
    required this.onChanged,
    this.expand = false,
  });

  final HoldingEdit edit;
  final ValueChanged<double> onChanged;
  final bool expand;

  @override
  State<_PriceCell> createState() => _PriceCellState();
}

class _PriceCellState extends State<_PriceCell> {
  late final TextEditingController _controller = TextEditingController(
    text: formatDraftNumber(widget.edit.avgPrice, decimals: 2),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StepperInput(
      controller: _controller,
      min: 0,
      step: 0.5,
      expand: widget.expand,
      width: widget.expand ? null : 142,
      semanticsLabel: 'Prezzo medio carico per ${widget.edit.holding.ticker}',
      increaseLabel:
          'Aumenta prezzo di carico per ${widget.edit.holding.ticker}',
      decreaseLabel:
          'Diminuisci prezzo di carico per ${widget.edit.holding.ticker}',
      onChanged: widget.onChanged,
    );
  }
}
