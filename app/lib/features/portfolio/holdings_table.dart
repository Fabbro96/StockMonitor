import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/models/portfolio.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/stepper_input.dart';
import '../../widgets/ticker_flag.dart';
import 'portfolio_edits.dart';

/// Callback di modifica inline: quantità e/o prezzo in bozza.
typedef HoldingEditCallback = void Function(
  Holding holding, {
  double? quantity,
  double? avgPrice,
});

/// Larghezza minima della tabella: sotto questa soglia scroll orizzontale
/// (e sotto 900px si passa alle card, pattern della Watchlist).
const double _tableMinWidth = 1120;

const List<({String label, double? flex, double? width})> _columns = [
  (label: 'Ticker', flex: 1.1, width: null),
  (label: 'Nome Titolo', flex: 1.2, width: null),
  (label: 'Quantità', flex: null, width: 150),
  (label: 'Prezzo Carico', flex: null, width: 160),
  (label: 'Prezzo Live', flex: 0.9, width: null),
  (label: 'Controvalore', flex: 1.0, width: null),
  (label: 'P&L Netto (€)', flex: 0.9, width: null),
  (label: 'P&L %', flex: 0.7, width: null),
  (label: 'Azioni', flex: null, width: 70),
];

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
    final AppTokens t = context.tokens;
    final Table table = Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: <int, TableColumnWidth>{
        for (int i = 0; i < _columns.length; i++)
          i: _columns[i].width != null
              ? FixedColumnWidth(_columns[i].width!)
              : FlexColumnWidth(_columns[i].flex ?? 1),
      },
      border: TableBorder(
        horizontalInside: BorderSide(color: t.borderSubtle),
        bottom: BorderSide(color: t.border),
      ),
      children: <TableRow>[
        TableRow(
          children: <Widget>[
            for (final ({String label, double? flex, double? width}) column
                in _columns)
              _headerCell(context, column.label),
          ],
        ),
        for (final Holding holding in holdings) _buildRow(context, holding),
      ],
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < _tableMinWidth) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: _tableMinWidth, child: table),
          );
        }
        return table;
      },
    );
  }

  TableRow _buildRow(BuildContext context, Holding holding) {
    final AppTokens t = context.tokens;
    final HoldingEdit edit = holdingEditOf(holding, edits);
    final bool modified = edit.changed;
    final Color pnlColor = edit.pnlAbsolute >= 0 ? t.success : t.danger;

    return TableRow(
      children: <Widget>[
        _cell(
          context,
          modified: modified,
          first: true,
          child: _TickerCell(
            holding: holding,
            onOpenTicker: onOpenTicker,
            onEditMarket: onEditMarket,
          ),
        ),
        _cell(
          context,
          modified: modified,
          child: Text(
            holding.name.isEmpty ? holding.ticker : holding.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.tableCell(context).copyWith(color: t.textSecondary),
          ),
        ),
        _cell(
          context,
          modified: modified,
          alignment: Alignment.centerRight,
          child: _QtyCell(
            key: ValueKey<String>('qty-${holding.id}-$epoch'),
            edit: edit,
            onChanged: (double value) => onEdit(holding, quantity: value),
          ),
        ),
        _cell(
          context,
          modified: modified,
          alignment: Alignment.centerRight,
          child: _PriceCell(
            key: ValueKey<String>('price-${holding.id}-$epoch'),
            edit: edit,
            onChanged: (double value) => onEdit(holding, avgPrice: value),
          ),
        ),
        _cell(
          context,
          modified: modified,
          alignment: Alignment.centerRight,
          child: _money(context, edit.currentPrice, currency: holding.currency),
        ),
        _cell(
          context,
          modified: modified,
          alignment: Alignment.centerRight,
          child: _money(
            context,
            edit.totalValue,
            currency: holding.currency,
            color: t.primary,
          ),
        ),
        _cell(
          context,
          modified: modified,
          alignment: Alignment.centerRight,
          child: _money(
            context,
            edit.pnlAbsolute,
            currency: holding.currency,
            color: pnlColor,
          ),
        ),
        _cell(
          context,
          modified: modified,
          alignment: Alignment.centerRight,
          child: Text(
            formatPercent(edit.pnlPercent),
            style: AppText.mono(
              context,
              size: 13,
              weight: FontWeight.w700,
              color: pnlColor,
            ),
          ),
        ),
        _cell(
          context,
          modified: modified,
          alignment: Alignment.center,
          child: _DeleteButton(holding: holding, onDelete: onDelete),
        ),
      ],
    );
  }

  Widget _headerCell(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s10,
        vertical: AppSpacing.s8,
      ),
      child: Text(label.toUpperCase(), style: AppText.tableHeader(context)),
    );
  }

  Widget _cell(
    BuildContext context, {
    required Widget child,
    required bool modified,
    bool first = false,
    Alignment alignment = Alignment.centerLeft,
  }) {
    final AppTokens t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s10,
        vertical: AppSpacing.s8,
      ),
      decoration: BoxDecoration(
        color: modified ? t.warningBg : null,
        border: first
            ? Border(
                left: BorderSide(
                  color: modified ? t.warning : Colors.transparent,
                  width: 3,
                ),
              )
            : null,
      ),
      alignment: alignment,
      child: child,
    );
  }

  Widget _money(
    BuildContext context,
    num? value, {
    required String currency,
    Color? color,
  }) {
    return Text(
      formatCurrency(value, currency: currency),
      textAlign: TextAlign.right,
      style: AppText.mono(
        context,
        size: 13,
        weight: FontWeight.w700,
        color: color,
      ),
    );
  }
}

/// Cella ticker: flag (market editor), link alla scheda e note.
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
    return Row(
      children: <Widget>[
        AppIconButton(
          icon: Text(
            TickerFlags.forTicker(holding.ticker, market: holding.market),
            style: const TextStyle(fontSize: 14),
          ),
          size: 28,
          iconSize: 14,
          tooltip: 'Modifica mercato',
          semanticLabel: 'Modifica mercato di ${holding.ticker}',
          onPressed: () => onEditMarket(holding),
        ),
        const SizedBox(width: AppSpacing.s6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
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
              if (holding.notes.isNotEmpty)
                Tooltip(
                  message: holding.notes,
                  child: Text(
                    '📝 ${_truncate(holding.notes, 20)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption(context),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DeleteButton extends StatelessWidget {
  const _DeleteButton({required this.holding, required this.onDelete});

  final Holding holding;
  final ValueChanged<Holding> onDelete;

  @override
  Widget build(BuildContext context) {
    return AppIconButton(
      icon: const Text('🗑️', style: TextStyle(fontSize: 14)),
      size: 30,
      iconSize: 14,
      bordered: false,
      danger: true,
      tooltip: 'Elimina',
      semanticLabel: 'Elimina posizione ${holding.ticker}',
      onPressed: () => onDelete(holding),
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
    final bool modified = edit.changed;
    final Color pnlColor = edit.pnlAbsolute >= 0 ? t.success : t.danger;
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.s10),
      child: Container(
        decoration: modified
            ? BoxDecoration(
                border: Border(left: BorderSide(color: t.warning, width: 3)),
              )
            : null,
        padding: modified ? const EdgeInsets.only(left: AppSpacing.s8) : null,
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
                _DeleteButton(holding: holding, onDelete: onDelete),
              ],
            ),
            const SizedBox(height: AppSpacing.s10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text('QUANTITÀ', style: AppText.sectionLabel(context)),
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
                      Text(
                        'PREZZO CARICO',
                        style: AppText.sectionLabel(context),
                      ),
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
            _MetricRow(
              label: 'Prezzo Live',
              value: formatCurrency(
                edit.currentPrice,
                currency: holding.currency,
              ),
            ),
            _MetricRow(
              label: 'Controvalore',
              value: formatCurrency(
                edit.totalValue,
                currency: holding.currency,
              ),
              valueColor: t.primary,
            ),
            _MetricRow(
              label: 'P&L Netto',
              value: formatCurrency(
                edit.pnlAbsolute,
                currency: holding.currency,
              ),
              valueColor: pnlColor,
            ),
            _MetricRow(
              label: 'P&L %',
              value: formatPercent(edit.pnlPercent),
              valueColor: pnlColor,
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s4),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: AppText.caption(context))),
          Text(
            value,
            style: AppText.mono(
              context,
              size: 13,
              weight: FontWeight.w700,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
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
      width: widget.expand ? null : 140,
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
      width: widget.expand ? null : 150,
      semanticsLabel: 'Prezzo medio carico per ${widget.edit.holding.ticker}',
      increaseLabel:
          'Aumenta prezzo di carico per ${widget.edit.holding.ticker}',
      decreaseLabel:
          'Diminuisci prezzo di carico per ${widget.edit.holding.ticker}',
      onChanged: widget.onChanged,
    );
  }
}

String _truncate(String value, int max) =>
    value.length <= max ? value : '${value.substring(0, max)}...';
