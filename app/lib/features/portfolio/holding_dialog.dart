import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/stocks_api.dart';
import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/models/stock.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_market_tag.dart';
import '../../widgets/stepper_input.dart';
import '../../widgets/toast.dart';
import 'portfolio_modal.dart';
import 'portfolio_providers.dart';

/// Apre il modal "Aggiungi Titolo al Portafoglio" (parità `#holdingModal`).
///
/// [initialTicker] precompila il ticker (usato dal deep-link `?add=TICKER`).
/// Ritorna `true` se la posizione è stata salvata: la pagina invalida poi
/// riepilogo/P&L realizzato (le holdings sono già ricaricate dal controller).
Future<bool> showAddHoldingDialog(
  BuildContext context, {
  String initialTicker = '',
}) async {
  final bool? saved = await showPortfolioModal<bool>(
    context,
    builder: (BuildContext _) => _AddHoldingDialog(initialTicker: initialTicker),
  );
  return saved ?? false;
}

class _AddHoldingDialog extends ConsumerStatefulWidget {
  const _AddHoldingDialog({this.initialTicker = ''});

  final String initialTicker;

  @override
  ConsumerState<_AddHoldingDialog> createState() => _AddHoldingDialogState();
}

class _AddHoldingDialogState extends ConsumerState<_AddHoldingDialog> {
  late final TextEditingController _ticker = TextEditingController(
    text: widget.initialTicker.toUpperCase(),
  );
  final TextEditingController _quantity = TextEditingController();
  final TextEditingController _price = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  final TextEditingController _date = TextEditingController();

  Timer? _debounce;
  int _searchSeq = 0;
  List<StockSearchResult> _suggestions = const <StockSearchResult>[];

  DateTime? _purchaseDate;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _ticker.dispose();
    _quantity.dispose();
    _price.dispose();
    _notes.dispose();
    _date.dispose();
    super.dispose();
  }

  double? _parse(String raw) =>
      double.tryParse(raw.trim().replaceAll(',', '.'));

  /// Autocomplete con debounce 250ms e stale guard (come `setupAutocomplete`).
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
      initialDate: _purchaseDate ?? now,
      firstDate: DateTime(1970),
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _purchaseDate = picked;
      _date.text = formatDate(picked);
    });
  }

  void _clearDate() {
    setState(() {
      _purchaseDate = null;
      _date.clear();
    });
  }

  Future<void> _submit() async {
    final String ticker = _ticker.text.trim().toUpperCase();
    final double? quantity = _parse(_quantity.text);
    final double? price = _parse(_price.text);

    if (ticker.isEmpty) {
      setState(() => _error = 'Inserisci un ticker.');
      return;
    }
    if (quantity == null || quantity <= 0) {
      setState(() => _error = 'La quantità deve essere maggiore di 0.');
      return;
    }
    if (price == null || price <= 0) {
      setState(
        () => _error = 'Il prezzo di acquisto deve essere maggiore di 0.',
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(portfolioProvider.notifier)
          .add(
            ticker: ticker,
            quantity: quantity,
            avgPurchasePrice: price,
            purchaseDate: _purchaseDate,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          );
      if (!mounted) return;
      showAppToast(
        context,
        message: '$ticker salvata nel portafoglio!',
        type: AppToastType.success,
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppToast(context, message: error.message, type: AppToastType.error);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppToast(
        context,
        message: 'Errore durante il salvataggio',
        type: AppToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return PortfolioModalShell(
      title: 'Aggiungi Titolo al Portafoglio',
      onClose: _saving ? null : () => Navigator.of(context).pop(false),
      actions: <Widget>[
        AppButton(
          label: 'Annulla',
          variant: AppButtonVariant.ghost,
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: 'Salva nel Portafoglio',
          variant: AppButtonVariant.primary,
          loading: _saving,
          loadingLabel: 'Salvataggio...',
          onPressed: _saving ? null : _submit,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _FieldLabel('Ticker o simbolo azione'),
          const SizedBox(height: AppSpacing.s6),
          TextField(
            controller: _ticker,
            enabled: !_saving,
            textCapitalization: TextCapitalization.characters,
            onChanged: _onTickerChanged,
            decoration: const InputDecoration(
              hintText: 'Es. G.MI, LDO.MI, ISP.MI, AAPL, NVDA...',
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
          const _FieldLabel('Quantità di azioni'),
          const SizedBox(height: AppSpacing.s6),
          StepperInput(
            controller: _quantity,
            enabled: !_saving,
            min: 0,
            step: 1,
            expand: true,
            hint: 'Es. 100',
            semanticsLabel: 'Quantità di azioni',
            increaseLabel: 'Aumenta quantità',
            decreaseLabel: 'Diminuisci quantità',
          ),
          const SizedBox(height: AppSpacing.s14),
          const _FieldLabel('Prezzo acquisto unitario (€ o \$)'),
          const SizedBox(height: AppSpacing.s6),
          StepperInput(
            controller: _price,
            enabled: !_saving,
            min: 0,
            step: 0.5,
            expand: true,
            hint: 'Es. 24.50',
            semanticsLabel: 'Prezzo di acquisto',
            increaseLabel: 'Aumenta prezzo di acquisto',
            decreaseLabel: 'Diminuisci prezzo di acquisto',
          ),
          const SizedBox(height: AppSpacing.s14),
          const _FieldLabel('Data di acquisto'),
          const SizedBox(height: AppSpacing.s6),
          TextField(
            controller: _date,
            readOnly: true,
            enabled: !_saving,
            onTap: _pickDate,
            decoration: InputDecoration(
              hintText: 'gg/mm/aaaa',
              suffixIcon: _purchaseDate == null
                  ? const Icon(Icons.calendar_today, size: 16)
                  : IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      tooltip: 'Rimuovi data',
                      onPressed: _saving ? null : _clearDate,
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.s14),
          const _FieldLabel('Note operative (opzionale)'),
          const SizedBox(height: AppSpacing.s6),
          TextField(
            controller: _notes,
            enabled: !_saving,
            decoration: const InputDecoration(
              hintText: 'Es. Primo ingresso, dividendo reinvestito...',
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
