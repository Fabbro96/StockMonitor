import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/portfolio_api.dart';
import '../../core/api/stocks_api.dart';
import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/models/portfolio.dart';
import '../../core/models/stock.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/badges.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/section_header.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/stepper_input.dart';
import '../../widgets/toast.dart';
import '../stock_detail/stock_detail_modal.dart' show showStockDetail;
import 'portfolio_edits.dart' show formatDraftNumber;
import 'portfolio_providers.dart' show realizedPnlProvider, reloadPortfolio;
import 'portfolio_tools_providers.dart';

/// Sezione "📖 Trade Ledger & Storico Transazioni" (parità `#tradeLedgerCard`).
///
/// Filtri server (`ALL`/`BUY`/`SELL`/`DIVIDEND`), tabella del registro,
/// eliminazione con conferma e modal "Registra Transazione" (con quantità
/// opzionale per i dividendi, fix bug #3, e data locale senza shift UTC).
class TransactionsSection extends ConsumerStatefulWidget {
  /// Crea la sezione Trade Ledger.
  const TransactionsSection({super.key});

  @override
  ConsumerState<TransactionsSection> createState() =>
      _TransactionsSectionState();
}

class _TransactionsSectionState extends ConsumerState<TransactionsSection> {
  static const List<({String value, String label})> _filters =
      <({String value, String label})>[
        (value: kAllTransactionsFilter, label: 'Tutte'),
        (value: 'BUY', label: '🟢 Acquisti (BUY)'),
        (value: 'SELL', label: '🔴 Vendite (SELL)'),
        (value: 'DIVIDEND', label: '💰 Dividendi'),
      ];

  String _filter = kAllTransactionsFilter;

  Future<void> _openTxDialog() async {
    final bool? created = await showDialog<bool>(
      context: context,
      barrierColor: context.tokens.scrim,
      builder: (BuildContext _) => const _TransactionDialog(),
    );
    if (created != true || !mounted) return;
    // Invalida l'intero family: con più viste filtro in cache (o ricreate)
    // anche "Tutte"/"Vendite" vedono subito la nuova transazione.
    ref.invalidate(transactionsProvider);
    ref.invalidate(realizedPnlProvider);
    ref.invalidate(dividendsProvider);
    // BUY/SELL aggiornano atomicamente le holdings lato backend.
    await reloadPortfolio(ref);
  }

  Future<void> _deleteTransaction(Transaction tx) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierColor: context.tokens.scrim,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Elimina transazione'),
        content: Text(
          'Sei sicuro di voler eliminare la transazione #${tx.id}?',
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
      await ref.read(portfolioApiProvider).deleteTransaction(tx.id);
      // Come dopo la registrazione: invalida tutto il family dei filtri.
      ref.invalidate(transactionsProvider);
      ref.invalidate(realizedPnlProvider);
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Transazione rimossa dal registro',
        type: AppToastType.info,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      showAppToast(context, message: error.message, type: AppToastType.error);
    } catch (_) {
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Errore durante la cancellazione',
        type: AppToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Transaction>> async = ref.watch(
      transactionsProvider(_filter),
    );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SectionHeader(
            title: '📖 Trade Ledger & Storico Transazioni',
            subtitle:
                'Traccia ogni acquisto, vendita e accredito dividendi '
                'calcolando automaticamente il P&L Realizzato e le commissioni.',
            trailing: AppButton(
              label: '➕ Registra Transazione',
              size: AppButtonSize.sm,
              onPressed: () => unawaited(_openTxDialog()),
            ),
          ),
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text('Filtra per:', style: AppText.caption(context)),
              for (final ({String value, String label}) filter in _filters)
                AppPill(
                  label: filter.label,
                  selected: _filter == filter.value,
                  onPressed: () => setState(() => _filter = filter.value),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          _buildTable(context, async),
        ],
      ),
    );
  }

  Widget _buildTable(
    BuildContext context,
    AsyncValue<List<Transaction>> async,
  ) {
    final AppTokens t = context.tokens;
    if (async.isLoading && !async.hasValue) {
      return const Column(
        children: <Widget>[SkeletonRow(), SkeletonRow(), SkeletonRow()],
      );
    }
    if (async.hasError && !async.hasValue) {
      return const EmptyState(
        icon: Icon(Icons.error_outline),
        message: 'Errore nel caricamento del Trade Ledger',
      );
    }

    final List<Transaction> transactions = async.value ?? const <Transaction>[];
    if (transactions.isEmpty) {
      return EmptyState(
        message: _filter == kAllTransactionsFilter
            ? 'Nessuna transazione registrata.'
            : 'Nessuna transazione registrata con filtro $_filter.',
        actions: <Widget>[
          AppButton(
            label: '➕ Registra la prima esecuzione',
            size: AppButtonSize.sm,
            onPressed: () => unawaited(_openTxDialog()),
          ),
        ],
      );
    }

    final Table table = Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: const <int, TableColumnWidth>{
        0: FixedColumnWidth(90),
        1: FixedColumnWidth(110),
        2: FlexColumnWidth(0.9),
        3: FlexColumnWidth(1.2),
        4: FixedColumnWidth(80),
        5: FixedColumnWidth(110),
        6: FixedColumnWidth(90),
        7: FixedColumnWidth(120),
        8: FlexColumnWidth(1.2),
        9: FixedColumnWidth(50),
      },
      border: TableBorder(
        horizontalInside: BorderSide(color: t.borderSubtle),
        bottom: BorderSide(color: t.border),
      ),
      children: <TableRow>[
        TableRow(
          children: <Widget>[
            _headerCell(context, 'Data'),
            _headerCell(context, 'Tipo'),
            _headerCell(context, 'Ticker'),
            _headerCell(context, 'Nome Titolo'),
            _headerCell(context, 'Quantità', alignment: Alignment.centerRight),
            _headerCell(
              context,
              'Prezzo Eseguito',
              alignment: Alignment.centerRight,
            ),
            _headerCell(
              context,
              'Commissione',
              alignment: Alignment.centerRight,
            ),
            _headerCell(
              context,
              'P&L Realizzato',
              alignment: Alignment.centerRight,
            ),
            _headerCell(context, 'Note'),
            _headerCell(context, ''),
          ],
        ),
        for (final Transaction tx in transactions) _row(context, tx),
      ],
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < 1120) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: 1120, child: table),
          );
        }
        return table;
      },
    );
  }

  TableRow _row(BuildContext context, Transaction tx) {
    final AppTokens t = context.tokens;
    final bool isSell = tx.type == 'SELL';
    final bool isDividend = tx.type == 'DIVIDEND';
    final double? pnl = tx.realizedPnl;
    final String notes = tx.notes;

    final Widget pnlCell;
    if (isSell && pnl != null) {
      pnlCell = Text(
        '${pnl >= 0 ? '+' : ''}'
        '${formatCurrency(pnl, currency: tx.currency)}',
        style: AppText.mono(
          context,
          size: 13,
          weight: FontWeight.w700,
          color: pnl >= 0 ? t.success : t.danger,
        ),
      );
    } else if (isDividend && pnl != null) {
      pnlCell = Text(
        '+${formatCurrency(pnl, currency: tx.currency)}',
        style: AppText.mono(
          context,
          size: 13,
          weight: FontWeight.w700,
          color: t.success,
        ),
      );
    } else {
      pnlCell = Text(
        '--',
        style: AppText.mono(
          context,
          size: 13,
          weight: FontWeight.w500,
          color: t.textMuted,
        ),
      );
    }

    return TableRow(
      children: <Widget>[
        _bodyCell(
          context,
          child: Text(
            formatDate(tx.transactionDate),
            style: AppText.mono(
              context,
              size: 11.5,
              weight: FontWeight.w500,
              color: t.textMuted,
            ),
          ),
        ),
        _bodyCell(context, child: _typeBadge(tx.type)),
        _bodyCell(
          context,
          child: InkWell(
            onTap: () => unawaited(showStockDetail(context, tx.ticker)),
            borderRadius: BorderRadius.circular(AppRadii.small),
            child: Text(
              tx.ticker,
              style: AppText.mono(
                context,
                size: 13,
                weight: FontWeight.w700,
                color: t.primary,
              ),
            ),
          ),
        ),
        _bodyCell(
          context,
          child: Text(
            tx.name.isEmpty ? tx.ticker : tx.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.small(context).copyWith(color: t.textSecondary),
          ),
        ),
        _bodyCell(
          context,
          alignment: Alignment.centerRight,
          child: Text(
            isDividend ? '--' : formatDraftNumber(tx.quantity),
            style: AppText.mono(context, size: 13),
          ),
        ),
        _bodyCell(
          context,
          alignment: Alignment.centerRight,
          child: Text(
            formatCurrency(tx.price, currency: tx.currency),
            style: AppText.mono(context, size: 13),
          ),
        ),
        _bodyCell(
          context,
          alignment: Alignment.centerRight,
          child: Text(
            tx.fee > 0 ? formatCurrency(tx.fee) : '0 €',
            style: AppText.mono(
              context,
              size: 11.5,
              weight: FontWeight.w500,
              color: t.textMuted,
            ),
          ),
        ),
        _bodyCell(context, alignment: Alignment.centerRight, child: pnlCell),
        _bodyCell(
          context,
          child: notes.isEmpty
              ? Text(
                  '--',
                  style: AppText.mono(
                    context,
                    size: 11.5,
                    weight: FontWeight.w500,
                    color: t.textMuted,
                  ),
                )
              : Tooltip(
                  message: notes,
                  child: Text(
                    _truncate(notes, 25),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.small(context).copyWith(color: t.textMuted),
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
            tooltip: 'Elimina transazione',
            semanticLabel: 'Elimina transazione #${tx.id}',
            onPressed: () => unawaited(_deleteTransaction(tx)),
          ),
        ),
      ],
    );
  }
}

AppBadge _typeBadge(String type) {
  return switch (type) {
    'BUY' => const AppBadge.buy(),
    'SELL' => const AppBadge.sell(),
    'DIVIDEND' => const AppBadge(
      label: '💰 DIVIDENDO',
      tone: BadgeTone.warning,
    ),
    _ => AppBadge(label: type, tone: BadgeTone.neutral),
  };
}

// --- Modal Registra Transazione ---------------------------------------------

class _TransactionDialog extends ConsumerStatefulWidget {
  const _TransactionDialog();

  @override
  ConsumerState<_TransactionDialog> createState() => _TransactionDialogState();
}

class _TransactionDialogState extends ConsumerState<_TransactionDialog> {
  final TextEditingController _ticker = TextEditingController();
  final TextEditingController _quantity = TextEditingController();
  final TextEditingController _price = TextEditingController();
  final TextEditingController _fee = TextEditingController(text: '0.00');
  final TextEditingController _notes = TextEditingController();
  late final TextEditingController _date = TextEditingController(
    text: formatDate(DateTime.now()),
  );

  Timer? _debounce;
  int _searchSeq = 0;
  List<StockSearchResult> _suggestions = const <StockSearchResult>[];

  String _type = 'BUY';
  DateTime _transactionDate = DateTime.now();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _ticker.dispose();
    _quantity.dispose();
    _price.dispose();
    _fee.dispose();
    _notes.dispose();
    _date.dispose();
    super.dispose();
  }

  double? _parse(TextEditingController controller) =>
      double.tryParse(controller.text.trim().replaceAll(',', '.'));

  String get _quantityLabel =>
      _type == 'DIVIDEND' ? 'Quote Possedute (opzionale)' : 'Quantità Quote';

  String get _quantityHint =>
      _type == 'DIVIDEND' ? '0 = importo totale nel prezzo' : 'Es. 50';

  String get _priceLabel =>
      _type == 'DIVIDEND' ? 'Importo Totale Dividendo' : 'Prezzo Unitario';

  String get _priceHint => _type == 'DIVIDEND' ? 'Es. 120.00' : 'Es. 18.50';

  /// Autocomplete ticker con debounce 250ms e stale guard (come il legacy).
  void _onTickerChanged(String value) {
    _debounce?.cancel();
    final String query = value.trim();
    if (query.length < 2) {
      if (_suggestions.isNotEmpty) {
        setState(() => _suggestions = const <StockSearchResult>[]);
      }
      return;
    }
    final int seq = ++_searchSeq;
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final List<StockSearchResult> results = await ref
            .read(stocksApiProvider)
            .search(query);
        if (!mounted || seq != _searchSeq) return;
        setState(() => _suggestions = results);
      } catch (_) {
        if (!mounted || seq != _searchSeq) return;
        setState(() => _suggestions = const <StockSearchResult>[]);
      }
    });
  }

  void _selectTicker(String ticker) {
    _debounce?.cancel();
    _searchSeq++;
    _ticker.text = ticker;
    _ticker.selection = TextSelection.collapsed(offset: ticker.length);
    setState(() => _suggestions = const <StockSearchResult>[]);
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _transactionDate,
      firstDate: DateTime(1970),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _transactionDate = picked;
      _date.text = formatDate(picked);
    });
  }

  Future<void> _submit() async {
    final String ticker = _ticker.text.trim().toUpperCase();
    final double quantity = _parse(_quantity) ?? 0;
    final double? price = _parse(_price);
    final double fee = _parse(_fee) ?? 0;
    final String notes = _notes.text.trim();

    if (ticker.isEmpty) {
      setState(() => _error = 'Inserisci un ticker valido.');
      return;
    }
    if (_type == 'DIVIDEND') {
      if (price == null || price <= 0) {
        setState(() => _error = 'Inserisci l\'importo del dividendo.');
        return;
      }
    } else {
      if (quantity <= 0) {
        setState(() => _error = 'La quantità deve essere maggiore di 0.');
        return;
      }
      if (price == null || price <= 0) {
        setState(() => _error = 'Il prezzo deve essere maggiore di 0.');
        return;
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(portfolioApiProvider)
          .createTransaction(
            ticker: ticker,
            type: _type,
            quantity: quantity,
            price: price,
            fee: fee,
            // Data locale `yyyy-MM-dd`, niente conversione UTC (fix bug #1).
            transactionDate: _transactionDate,
            notes: notes.isEmpty ? null : notes,
          );
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Transazione $_type per $ticker registrata con successo!',
        type: AppToastType.success,
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Errore durante la registrazione della transazione';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return AlertDialog(
      title: const Text('Registra Transazione (Trade Ledger)'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const _FieldLabel('Tipo Operazione'),
              const SizedBox(height: AppSpacing.s6),
              DropdownButtonFormField<String>(
                initialValue: _type,
                isExpanded: true,
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem<String>(
                    value: 'BUY',
                    child: Text(
                      '🟢 Acquisto (BUY) - Incrementa o apre posizione',
                    ),
                  ),
                  DropdownMenuItem<String>(
                    value: 'SELL',
                    child: Text(
                      '🔴 Vendita (SELL) - Decrementa e calcola P&L realizzato',
                    ),
                  ),
                  DropdownMenuItem<String>(
                    value: 'DIVIDEND',
                    child: Text('💰 Accredito Dividendo (DIVIDEND)'),
                  ),
                ],
                onChanged: _saving
                    ? null
                    : (String? value) => setState(() => _type = value ?? 'BUY'),
              ),
              const SizedBox(height: AppSpacing.s14),
              const _FieldLabel('Ticker Simbolo'),
              const SizedBox(height: AppSpacing.s6),
              TextField(
                controller: _ticker,
                enabled: !_saving,
                textCapitalization: TextCapitalization.characters,
                onChanged: _onTickerChanged,
                decoration: const InputDecoration(
                  hintText: 'Es. ENEL.MI, AAPL, MSFT...',
                ),
              ),
              if (_suggestions.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.s4),
                _AutocompleteDropdown(
                  suggestions: _suggestions,
                  onSelected: _selectTicker,
                ),
              ],
              const SizedBox(height: AppSpacing.s14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        _FieldLabel(_quantityLabel),
                        const SizedBox(height: AppSpacing.s6),
                        StepperInput(
                          controller: _quantity,
                          enabled: !_saving,
                          min: 0,
                          step: 1,
                          expand: true,
                          hint: _quantityHint,
                          semanticsLabel: 'Quantità',
                          increaseLabel: 'Aumenta quantità',
                          decreaseLabel: 'Diminuisci quantità',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        _FieldLabel(_priceLabel),
                        const SizedBox(height: AppSpacing.s6),
                        StepperInput(
                          controller: _price,
                          enabled: !_saving,
                          min: 0,
                          step: 0.5,
                          expand: true,
                          hint: _priceHint,
                          semanticsLabel: 'Prezzo',
                          increaseLabel: 'Aumenta prezzo',
                          decreaseLabel: 'Diminuisci prezzo',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const _FieldLabel('Commissione (€)'),
                        const SizedBox(height: AppSpacing.s6),
                        TextField(
                          controller: _fee,
                          enabled: !_saving,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Es. 2.95',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const _FieldLabel('Data Operazione'),
                        const SizedBox(height: AppSpacing.s6),
                        TextField(
                          controller: _date,
                          readOnly: true,
                          enabled: !_saving,
                          onTap: _pickDate,
                          decoration: const InputDecoration(
                            hintText: 'gg/mm/aaaa',
                            suffixIcon: Icon(Icons.calendar_today, size: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s14),
              const _FieldLabel('Note Operazione'),
              const SizedBox(height: AppSpacing.s6),
              TextField(
                controller: _notes,
                enabled: !_saving,
                decoration: const InputDecoration(
                  hintText: 'Es. Primo ingresso, target raggiunto...',
                ),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: AppSpacing.s12),
                Text(
                  _error!,
                  style: AppText.caption(context).copyWith(color: t.danger),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        AppButton(
          label: 'Annulla',
          variant: AppButtonVariant.ghost,
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: 'Registra Transazione',
          loading: _saving,
          loadingLabel: 'Registrazione...',
          onPressed: _saving ? null : _submit,
        ),
      ],
    );
  }
}

// --- Widget condivisi --------------------------------------------------------

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(label, style: AppText.formLabel(context));
  }
}

/// Dropdown dei suggerimenti ticker (`.autocomplete-dropdown`).
class _AutocompleteDropdown extends StatelessWidget {
  const _AutocompleteDropdown({
    required this.suggestions,
    required this.onSelected,
  });

  final List<StockSearchResult> suggestions;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(AppRadii.input),
        boxShadow: t.shadowMd,
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: suggestions.length,
        separatorBuilder: (BuildContext _, int _) =>
            Divider(height: 1, color: t.borderSubtle),
        itemBuilder: (BuildContext context, int index) {
          final StockSearchResult item = suggestions[index];
          return InkWell(
            onTap: () => onSelected(item.ticker),
            hoverColor: t.surfaceHover,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s12,
                vertical: AppSpacing.s10,
              ),
              child: Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(
                      text: item.ticker,
                      style: AppText.mono(
                        context,
                        size: 13,
                        weight: FontWeight.w700,
                        color: t.primary,
                      ),
                    ),
                    TextSpan(
                      text: ' — ${item.name}',
                      style: AppText.caption(context),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          );
        },
      ),
    );
  }
}

String _truncate(String value, int max) =>
    value.length <= max ? value : '${value.substring(0, max)}...';

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
