import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/stocks_api.dart';
import '../../core/api/watchlist_api.dart';
import '../../core/api_client.dart';
import '../../core/models/stock.dart';
import '../../core/models/watchlist_item.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_button.dart';
import '../../widgets/badges.dart';
import '../../widgets/stepper_input.dart';
import '../../widgets/toast.dart';
import 'watchlist_providers.dart';

/// Modal "Aggiungi Titolo al Radar" (parità con `#addWatchlistModal`).
Future<void> showWatchlistAddDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) => const WatchlistAddDialog(),
  );
}

/// Modal "Imposta Alert di Prezzo" (parità con `#editAlertModal`).
Future<void> showWatchlistAlertDialog(
  BuildContext context,
  WatchlistItem item,
) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) => WatchlistAlertDialog(item: item),
  );
}

/// Dialog di aggiunta con autocomplete ticker (debounce 250ms + guardia stale).
class WatchlistAddDialog extends ConsumerStatefulWidget {
  /// Crea il dialog di aggiunta.
  const WatchlistAddDialog({super.key});

  @override
  ConsumerState<WatchlistAddDialog> createState() => _WatchlistAddDialogState();
}

class _WatchlistAddDialogState extends ConsumerState<WatchlistAddDialog> {
  final TextEditingController _tickerController = TextEditingController();
  final TextEditingController _alertAboveController = TextEditingController();
  final TextEditingController _alertBelowController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  Timer? _searchDebounce;
  int _searchSeq = 0;
  List<StockSearchResult> _suggestions = const <StockSearchResult>[];
  String? _tickerError;
  bool _submitting = false;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _tickerController.dispose();
    _alertAboveController.dispose();
    _alertBelowController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _onTickerChanged(String value) {
    _searchDebounce?.cancel();
    final int seq = ++_searchSeq;
    final String query = value.trim();
    if (query.length < 2) {
      setState(() => _suggestions = const <StockSearchResult>[]);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final List<StockSearchResult> results =
            await ref.read(stocksApiProvider).search(query);
        if (!mounted || seq != _searchSeq) return; // risposta obsoleta
        setState(() => _suggestions = results);
      } catch (_) {
        if (!mounted || seq != _searchSeq) return;
        setState(() => _suggestions = const <StockSearchResult>[]);
      }
    });
  }

  void _selectSuggestion(StockSearchResult suggestion) {
    // F4: invalida la query pendente (timer + sequenza) prima di svuotare i
    // suggerimenti, così il debounce precedente non riapre il dropdown sopra
    // il ticker appena scelto e le risposte in volo diventano stale.
    _searchDebounce?.cancel();
    _searchSeq++;
    _tickerController.text = suggestion.ticker;
    _tickerController.selection = TextSelection.collapsed(
      offset: suggestion.ticker.length,
    );
    setState(() {
      _suggestions = const <StockSearchResult>[];
      _tickerError = null;
    });
  }

  Future<void> _submit() async {
    final String ticker = _tickerController.text.trim().toUpperCase();
    if (ticker.isEmpty) {
      setState(() => _tickerError = 'Inserisci un ticker.');
      return;
    }
    setState(() {
      _submitting = true;
      _tickerError = null;
    });
    try {
      final WatchlistMutationResult result = await ref
          .read(watchlistProvider.notifier)
          .add(
            ticker: ticker,
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
            alertAbove: _parseNumber(_alertAboveController.text),
            alertBelow: _parseNumber(_alertBelowController.text),
          );
      if (!mounted) return;
      final bool exists = result.status == 'exists';
      showAppToast(
        context,
        message: result.message.isNotEmpty
            ? result.message
            : '$ticker aggiunto al Radar!',
        type: exists ? AppToastType.info : AppToastType.success,
      );
      Navigator.of(context).pop();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showAppToast(context, message: error.message, type: AppToastType.error);
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showAppToast(
        context,
        message: 'Errore durante l\'aggiunta',
        type: AppToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return AlertDialog(
      title: const Text('⭐ Aggiungi Titolo al Radar'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const _FieldLabel('Ticker o Simbolo Titolo'),
              const SizedBox(height: AppSpacing.s6),
              TextField(
                controller: _tickerController,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                onChanged: _onTickerChanged,
                decoration: InputDecoration(
                  hintText: 'Es. NVDA, TSLA, RACE.MI, ENEL.MI, AAPL...',
                  errorText: _tickerError,
                ),
              ),
              if (_suggestions.isNotEmpty) _suggestionsPanel(t),
              const SizedBox(height: AppSpacing.s14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: _AlertStepper(
                      label: '🔔 Alert Se Sale Sopra (€/\$)',
                      controller: _alertAboveController,
                      hint: 'Es. 150.00',
                      semanticsLabel: 'Alert se sale sopra (€/\$)',
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: _AlertStepper(
                      label: '🔔 Alert Se Scende Sotto (€/\$)',
                      controller: _alertBelowController,
                      hint: 'Es. 120.00',
                      semanticsLabel: 'Alert se scende sotto (€/\$)',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s14),
              const _FieldLabel('Note Operative / Strategia (Opzionale)'),
              const SizedBox(height: AppSpacing.s6),
              TextField(
                controller: _notesController,
                decoration: const InputDecoration(
                  hintText: 'Es. Attendere rottura resistenza a 20€...',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        AppButton(
          label: 'Annulla',
          variant: AppButtonVariant.ghost,
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: 'Aggiungi a Watchlist',
          loading: _submitting,
          onPressed: _submit,
        ),
      ],
    );
  }

  Widget _suggestionsPanel(AppTokens t) {
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.s6),
      constraints: const BoxConstraints(maxHeight: 172),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(AppRadii.input),
        boxShadow: t.shadowMd,
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: _suggestions.length,
        itemBuilder: (BuildContext context, int index) {
          final StockSearchResult suggestion = _suggestions[index];
          return InkWell(
            onTap: () => _selectSuggestion(suggestion),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s10,
                vertical: AppSpacing.s8,
              ),
              child: Row(
                children: <Widget>[
                  Text(
                    suggestion.ticker,
                    style: AppText.mono(
                      context,
                      size: 12.8,
                      weight: FontWeight.w700,
                      color: t.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  Expanded(
                    child: Text(
                      suggestion.name,
                      style: AppText.small(context),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (suggestion.market.isNotEmpty) ...<Widget>[
                    const SizedBox(width: AppSpacing.s6),
                    AppBadge(label: suggestion.market, tone: BadgeTone.neutral),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Dialog di modifica soglie alert (prefillate dai valori correnti).
class WatchlistAlertDialog extends ConsumerStatefulWidget {
  /// Crea il dialog alert per [item].
  const WatchlistAlertDialog({super.key, required this.item});

  /// Elemento Watchlist da modificare.
  final WatchlistItem item;

  @override
  ConsumerState<WatchlistAlertDialog> createState() =>
      _WatchlistAlertDialogState();
}

class _WatchlistAlertDialogState extends ConsumerState<WatchlistAlertDialog> {
  late final TextEditingController _aboveController = TextEditingController(
    text: _formatPrefill(widget.item.alertAbove),
  );
  late final TextEditingController _belowController = TextEditingController(
    text: _formatPrefill(widget.item.alertBelow),
  );
  bool _saving = false;

  @override
  void dispose() {
    _aboveController.dispose();
    _belowController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(watchlistProvider.notifier)
          .updateAlert(
            widget.item.id,
            above: _parseNumber(_aboveController.text),
            below: _parseNumber(_belowController.text),
          );
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Alert aggiornato con successo!',
        type: AppToastType.success,
      );
      Navigator.of(context).pop();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppToast(context, message: error.message, type: AppToastType.error);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppToast(
        context,
        message: 'Errore durante il salvataggio dell\'alert',
        type: AppToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return AlertDialog(
      title: const Text('🔔 Imposta Alert di Prezzo'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Imposta soglie per ${widget.item.ticker}',
              style: AppText.small(context).copyWith(
                color: t.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.s14),
            _AlertStepper(
              label: 'Avvisami se il prezzo sale sopra (€/\$):',
              controller: _aboveController,
              hint: 'Nessun limite superiore',
              semanticsLabel: 'Avvisa se il prezzo sale sopra (€/\$)',
            ),
            const SizedBox(height: AppSpacing.s14),
            _AlertStepper(
              label: 'Avvisami se il prezzo scende sotto (€/\$):',
              controller: _belowController,
              hint: 'Nessun limite inferiore',
              semanticsLabel: 'Avvisa se il prezzo scende sotto (€/\$)',
            ),
          ],
        ),
      ),
      actions: <Widget>[
        AppButton(
          label: 'Annulla',
          variant: AppButtonVariant.ghost,
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: 'Salva Alert',
          loading: _saving,
          onPressed: _save,
        ),
      ],
    );
  }
}

/// Etichetta di campo dei dialog.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(label, style: AppText.formLabel(context));
  }
}

/// Stepper numerico con label di campo.
class _AlertStepper extends StatelessWidget {
  const _AlertStepper({
    required this.label,
    required this.controller,
    required this.hint,
    required this.semanticsLabel,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _FieldLabel(label),
        const SizedBox(height: AppSpacing.s6),
        StepperInput(
          controller: controller,
          min: 0,
          step: 1,
          decimals: 2,
          expand: true,
          hint: hint,
          semanticsLabel: semanticsLabel,
        ),
      ],
    );
  }
}

double? _parseNumber(String raw) {
  final String value = raw.trim().replaceAll(',', '.');
  if (value.isEmpty) return null;
  return double.tryParse(value);
}

String _formatPrefill(double? value) {
  if (value == null) return '';
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(2);
}
