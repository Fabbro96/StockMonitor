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
import '../../widgets/app_confirm_dialog.dart';
import '../../widgets/app_error_panel.dart';
import '../../widgets/app_market_tag.dart';
import '../../widgets/app_segmented.dart';
import '../../widgets/badges.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/section_header.dart';
import '../../widgets/stepper_input.dart';
import '../../widgets/toast.dart';
import '../stock_detail/stock_detail_modal.dart' show showStockDetail;
import 'portfolio_edits.dart' show formatDraftNumber;
import 'portfolio_modal.dart';
import 'portfolio_providers.dart' show realizedPnlProvider, reloadPortfolio;
import 'portfolio_table.dart';
import 'portfolio_tools_providers.dart';

/// Sezione "Trade Ledger & Storico Transazioni" (parità `#tradeLedgerCard`).
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
        (value: 'BUY', label: 'Acquisti'),
        (value: 'SELL', label: 'Vendite'),
        (value: 'DIVIDEND', label: 'Dividendi'),
      ];

  String _filter = kAllTransactionsFilter;

  Future<void> _openTxDialog() async {
    final bool? created = await showPortfolioModal<bool>(
      context,
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
    final bool confirmed = await showAppConfirm(
      context,
      title: 'Elimina transazione',
      message: 'Sei sicuro di voler eliminare la transazione #${tx.id}?',
      confirmLabel: 'Elimina',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

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
            variant: SectionHeaderVariant.rule,
            icon: Icons.receipt_long_outlined,
            overline: 'Registro',
            title: 'Transazioni',
            subtitle:
                'Traccia ogni acquisto, vendita e accredito dividendi '
                'calcolando automaticamente il P&L realizzato e le commissioni.',
            trailing: AppButton(
              label: 'Registra',
              icon: const Icon(Icons.add),
              size: AppButtonSize.sm,
              onPressed: () => unawaited(_openTxDialog()),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: AppSegmented<String>(
              selected: _filter,
              dense: true,
              expand: context.isCompact,
              semanticsLabel: 'Filtra transazioni per tipo',
              segments: <AppSegment<String>>[
                for (final ({String value, String label}) filter in _filters)
                  AppSegment<String>(
                    value: filter.value,
                    label: filter.label,
                  ),
              ],
              onSelected: (String value) => setState(() => _filter = value),
            ),
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
    if (async.isLoading && !async.hasValue) {
      return const PortfolioTableSkeleton();
    }
    if (async.hasError && !async.hasValue) {
      return AppErrorPanel(
        message: 'Errore nel caricamento del Trade Ledger',
        onRetry: () => ref.invalidate(transactionsProvider(_filter)),
      );
    }

    final List<Transaction> transactions = async.value ?? const <Transaction>[];
    if (transactions.isEmpty) {
      return EmptyState(
        icon: const Icon(Icons.receipt_long_outlined),
        message: _filter == kAllTransactionsFilter
            ? 'Nessuna transazione registrata.'
            : 'Nessuna transazione registrata con filtro $_filter.',
        actions: <Widget>[
          AppButton(
            label: 'Registra la prima esecuzione',
            icon: const Icon(Icons.add),
            size: AppButtonSize.sm,
            onPressed: () => unawaited(_openTxDialog()),
          ),
        ],
      );
    }

    return PortfolioTable(
      minWidth: 1100,
      child: Column(
        children: <Widget>[
          const PortfolioTableHeader(
            cells: <Widget>[
              SizedBox(width: 92, child: PortfolioHeaderLabel('Data')),
              SizedBox(width: 104, child: PortfolioHeaderLabel('Tipo')),
              Expanded(flex: 24, child: PortfolioHeaderLabel('Titolo')),
              SizedBox(
                width: 92,
                child: PortfolioHeaderLabel(
                  'Quantità',
                  alignment: Alignment.centerRight,
                ),
              ),
              SizedBox(
                width: 108,
                child: PortfolioHeaderLabel(
                  'Prezzo',
                  alignment: Alignment.centerRight,
                ),
              ),
              SizedBox(
                width: 92,
                child: PortfolioHeaderLabel(
                  'Commissione',
                  alignment: Alignment.centerRight,
                ),
              ),
              SizedBox(
                width: 118,
                child: PortfolioHeaderLabel(
                  'P&L realizzato',
                  alignment: Alignment.centerRight,
                ),
              ),
              Expanded(flex: 18, child: PortfolioHeaderLabel('Note')),
              SizedBox(width: 44, child: PortfolioHeaderLabel('')),
            ],
          ),
          for (final Transaction tx in transactions)
            _TransactionRow(
              transaction: tx,
              onDelete: () => unawaited(_deleteTransaction(tx)),
            ),
        ],
      ),
    );
  }
}

/// Riga del registro: 40px, tag di lato, importi mono tabulari e azione di
/// eliminazione rivelata con hover/focus.
class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.transaction, required this.onDelete});

  final Transaction transaction;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool isSell = transaction.type == 'SELL';
    final bool isDividend = transaction.type == 'DIVIDEND';
    final double? pnl = transaction.realizedPnl;
    final String notes = transaction.notes;

    final Widget pnlCell;
    if ((isSell || isDividend) && pnl != null) {
      final Color color = isSell
          ? (pnl >= 0 ? t.success : t.danger)
          : t.success;
      pnlCell = Text(
        _signedMoney(pnl, transaction.currency),
        textAlign: TextAlign.right,
        style: AppText.tableCellNum(context).copyWith(color: color),
      );
    } else {
      pnlCell = Text(
        '—',
        textAlign: TextAlign.right,
        style: AppText.tableCellNum(context).copyWith(color: t.textMuted),
      );
    }

    return PortfolioTableRow(
      cells: <Widget>[
        SizedBox(
          width: 92,
          child: Text(
            formatDate(transaction.transactionDate),
            style: AppText.mono(
              context,
              size: 11.5,
              weight: FontWeight.w500,
              color: t.textMuted,
            ),
          ),
        ),
        SizedBox(width: 104, child: _typeBadge(transaction.type)),
        Expanded(
          flex: 24,
          child: _TickerCell(transaction: transaction),
        ),
        SizedBox(
          width: 92,
          child: PortfolioCell(
            alignment: Alignment.centerRight,
            child: Text(
              isDividend ? '—' : formatDraftNumber(transaction.quantity),
              style: AppText.tableCellNum(context),
            ),
          ),
        ),
        SizedBox(
          width: 108,
          child: PortfolioCell(
            alignment: Alignment.centerRight,
            child: Text(
              formatCurrency(transaction.price, currency: transaction.currency),
              style: AppText.tableCellNum(context),
            ),
          ),
        ),
        SizedBox(
          width: 92,
          child: PortfolioCell(
            alignment: Alignment.centerRight,
            child: Text(
              transaction.fee > 0 ? formatCurrency(transaction.fee) : '—',
              style: AppText.tableCellNum(context).copyWith(
                color: t.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        SizedBox(
          width: 118,
          child: PortfolioCell(alignment: Alignment.centerRight, child: pnlCell),
        ),
        Expanded(
          flex: 18,
          child: notes.isEmpty
              ? Text(
                  '—',
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
                    _truncate(notes, 32),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption(context),
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
                tooltip: 'Elimina transazione',
                semanticLabel: 'Elimina transazione #${transaction.id}',
                danger: true,
                onPressed: onDelete,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Cella titolo: tag di mercato, ticker mono collegato alla scheda e nome.
class _TickerCell extends StatelessWidget {
  const _TickerCell({required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Row(
      children: <Widget>[
        AppMarketTag.forTicker(
          transaction.ticker,
          market: transaction.market,
        ),
        const SizedBox(width: AppSpacing.s6),
        InkWell(
          onTap: () => unawaited(showStockDetail(context, transaction.ticker)),
          borderRadius: BorderRadius.circular(AppRadii.small),
          child: Text(
            transaction.ticker,
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
            transaction.name.isEmpty ? transaction.ticker : transaction.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption(context).copyWith(color: t.textSecondary),
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
    'DIVIDEND' => const AppBadge(label: 'DIVIDENDO', tone: BadgeTone.warning),
    _ => AppBadge(label: type, tone: BadgeTone.neutral),
  };
}

/// Importo firmato (`+1.234,56 €` / `−120,00 €`), mai solo colore.
String _signedMoney(num? value, String currency) {
  if (value == null || !value.isFinite) return '—';
  final String formatted = formatCurrency(value.abs(), currency: currency);
  if (value > 0) return '+$formatted';
  if (value < 0) return '−$formatted';
  return formatted;
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
      _type == 'DIVIDEND' ? 'Quote possedute (opzionale)' : 'Quantità quote';

  String get _quantityHint =>
      _type == 'DIVIDEND' ? '0 = importo totale nel prezzo' : 'Es. 50';

  String get _priceLabel =>
      _type == 'DIVIDEND' ? 'Importo totale dividendo' : 'Prezzo unitario';

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
    return PortfolioModalShell(
      title: 'Registra transazione',
      onClose: _saving ? null : () => Navigator.of(context).pop(false),
      actions: <Widget>[
        AppButton(
          label: 'Annulla',
          variant: AppButtonVariant.ghost,
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: 'Registra transazione',
          loading: _saving,
          loadingLabel: 'Registrazione...',
          onPressed: _saving ? null : _submit,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _FieldLabel('Tipo operazione'),
          const SizedBox(height: AppSpacing.s6),
          DropdownButtonFormField<String>(
            initialValue: _type,
            isExpanded: true,
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem<String>(
                value: 'BUY',
                child: Text('Acquisto (BUY) — apre o incrementa la posizione'),
              ),
              DropdownMenuItem<String>(
                value: 'SELL',
                child: Text('Vendita (SELL) — chiude e calcola il P&L'),
              ),
              DropdownMenuItem<String>(
                value: 'DIVIDEND',
                child: Text('Dividendo (DIVIDEND) — accredito incassato'),
              ),
            ],
            onChanged: _saving
                ? null
                : (String? value) => setState(() => _type = value ?? 'BUY'),
          ),
          const SizedBox(height: AppSpacing.s14),
          const _FieldLabel('Ticker simbolo'),
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
                      decoration: const InputDecoration(hintText: 'Es. 2.95'),
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
                    const _FieldLabel('Data operazione'),
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
          const _FieldLabel('Note operazione'),
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
              child: Row(
                children: <Widget>[
                  AppMarketTag.forTicker(item.ticker),
                  const SizedBox(width: AppSpacing.s8),
                  Text(
                    item.ticker,
                    style: AppText.mono(
                      context,
                      size: 13,
                      weight: FontWeight.w700,
                      color: t.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  Expanded(
                    child: Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption(context),
                    ),
                  ),
                ],
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
