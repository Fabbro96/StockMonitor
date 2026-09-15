import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/stocks_api.dart';
import '../../core/api_client.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_market_tag.dart';
import '../../widgets/badges.dart';
import '../../widgets/toast.dart';

/// Mercati supportati dall'editor (parità con `openMarketEditor` di `app.js`).
const List<({String value, String label})> _marketOptions = [
  (value: 'IT', label: 'Borsa Italiana'),
  (value: 'US', label: 'Wall Street'),
  (value: 'EU', label: 'Europa'),
];

/// Tinta del tag di mercato coerente con [AppMarketTag.resolve].
BadgeTone _marketTone(String market) => switch (market) {
  'IT' => BadgeTone.primary,
  'EU' => BadgeTone.cyan,
  _ => BadgeTone.neutral,
};

/// Nota informativa comune al dialog (la modifica è globale per tutti gli
/// utenti).
const String _globalNote =
    'La correzione vale per tutti gli utenti: il mercato è '
    'una proprietà del titolo, non della posizione.';

/// Normalizza un mercato a `IT`/`US`/`EU`; qualsiasi altro valore → `null`.
String? _normalizeMarket(String? market) {
  final String? upper = market?.trim().toUpperCase();
  return switch (upper) {
    'IT' || 'US' || 'EU' => upper,
    _ => null,
  };
}

/// Apre l'editor del mercato di quotazione di [ticker].
///
/// Il mercato è una proprietà globale del titolo (non della posizione), quindi
/// la modifica vale per tutti gli utenti. [onSaved] riceve il mercato
/// effettivamente salvato (`IT`/`US`/`EU`).
///
/// Se [initialMarket] è `IT`/`US`/`EU` viene preselezionato senza chiamate di
/// rete. Se è assente (o non valido) il mercato corrente viene letto da
/// `GET /stocks/{ticker}/details`; finché la lettura non riesce `Salva` resta
/// disabilitato, per impedire di sovrascrivere il mercato con un default.
Future<void> showMarketEditor(
  BuildContext context,
  String ticker, {
  String? initialMarket,
  ValueChanged<String>? onSaved,
}) {
  final String normalized = ticker.trim().toUpperCase();
  if (normalized.isEmpty) return Future<void>.value();
  return showDialog<void>(
    context: context,
    barrierColor: context.tokens.scrim,
    builder: (BuildContext _) => _MarketEditorDialog(
      ticker: normalized,
      initialMarket: _normalizeMarket(initialMarket),
      onSaved: onSaved,
    ),
  );
}

class _MarketEditorDialog extends ConsumerStatefulWidget {
  const _MarketEditorDialog({
    required this.ticker,
    this.initialMarket,
    this.onSaved,
  });

  final String ticker;
  final String? initialMarket;
  final ValueChanged<String>? onSaved;

  @override
  ConsumerState<_MarketEditorDialog> createState() =>
      _MarketEditorDialogState();
}

class _MarketEditorDialogState extends ConsumerState<_MarketEditorDialog> {
  String _market = 'US';

  /// True solo quando serve leggere il mercato corrente (nessun
  /// [initialMarket] valido).
  bool _loading = false;

  /// True quando la lettura del mercato corrente è fallita o il backend non lo
  /// espone: `Salva` resta disabilitato finché non si riprova con successo.
  bool _loadFailed = false;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final String? initial = widget.initialMarket;
    if (initial != null) {
      _market = initial;
    } else {
      _loading = true;
      _loadCurrentMarket();
    }
  }

  /// Legge il mercato attuale dal deep dive del titolo.
  ///
  /// Senza `initialMarket` il select non deve restare su `US`: un salvataggio
  /// distratto convertirebbe silenziosamente un titolo IT/EU (la modifica è
  /// globale per tutti gli utenti).
  Future<void> _loadCurrentMarket() async {
    try {
      final details = await ref.read(stocksApiProvider).details(widget.ticker);
      final String? fetched = _normalizeMarket(details.market);
      if (!mounted) return;
      if (fetched == null) {
        setState(() {
          _loading = false;
          _loadFailed = true;
        });
        return;
      }
      setState(() {
        _market = fetched;
        _loading = false;
        _loadFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  void _retryLoad() {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    _loadCurrentMarket();
  }

  Future<void> _save() async {
    if (_saving || _loading || _loadFailed) return;
    setState(() => _saving = true);
    try {
      final updated = await ref
          .read(stocksApiProvider)
          .updateMarket(widget.ticker, _market);
      if (!mounted) return;
      final String applied = (updated.market?.isNotEmpty ?? false)
          ? updated.market!
          : _market;
      showAppToast(
        context,
        message: 'Mercato di ${widget.ticker} impostato a $applied',
        type: AppToastType.success,
      );
      widget.onSaved?.call(applied);
      Navigator.of(context).pop();
    } on ApiException catch (error) {
      if (!mounted) return;
      showAppToast(context, message: error.message, type: AppToastType.error);
      setState(() => _saving = false);
    } catch (_) {
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Errore durante il salvataggio del mercato.',
        type: AppToastType.error,
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool selectEnabled = !_loading && !_loadFailed && !_saving;
    return Dialog(
      // Superficie dipinta dal DecoratedBox: fondo, bordo 1px e ombra ampia
      // dello stesso dialogo della scheda titolo.
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.sheet),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(AppRadii.sheet),
          border: Border.all(color: t.border),
          boxShadow: t.shadowLg,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.sheet),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Mercato di ${widget.ticker}',
                          style: AppText.modalTitle(context),
                        ),
                      ),
                      AppIconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Chiudi finestra',
                        semanticLabel: 'Chiudi finestra',
                        bordered: false,
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s16),
                  Text('Borsa di quotazione', style: AppText.formLabel(context)),
                  const SizedBox(height: AppSpacing.s6),
                  DropdownButtonFormField<String>(
                    initialValue: _market,
                    isExpanded: true,
                    items: <DropdownMenuItem<String>>[
                      for (final option in _marketOptions)
                        DropdownMenuItem<String>(
                          value: option.value,
                          child: Row(
                            children: <Widget>[
                              AppMarketTag(
                                code: option.value,
                                tone: _marketTone(option.value),
                              ),
                              const SizedBox(width: AppSpacing.s8),
                              Flexible(
                                child: Text(
                                  option.label,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    onChanged: selectEnabled
                        ? (String? value) {
                            if (value != null) setState(() => _market = value);
                          }
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  if (_loadFailed) ...<Widget>[
                    _LoadFailedNote(
                      ticker: widget.ticker,
                      onRetry: _saving ? null : _retryLoad,
                    ),
                    const SizedBox(height: AppSpacing.s6),
                    Text(_globalNote, style: AppText.caption(context)),
                  ] else
                    Text(
                      _loading ? 'Caricamento mercato attuale…' : _globalNote,
                      style: AppText.caption(context),
                    ),
                  const SizedBox(height: AppSpacing.s20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      AppButton(
                        label: 'Annulla',
                        variant: AppButtonVariant.ghost,
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: AppSpacing.s8),
                      AppButton(
                        label: 'Salva',
                        icon: const Icon(Icons.check),
                        variant: AppButtonVariant.primary,
                        loading: _saving,
                        loadingLabel: 'Salvataggio…',
                        onPressed: selectEnabled ? _save : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Errore di lettura del mercato corrente con azione di riprova.
class _LoadFailedNote extends StatelessWidget {
  const _LoadFailedNote({required this.ticker, this.onRetry});

  final String ticker;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'Impossibile determinare il mercato attuale di $ticker. '
          'Salvataggio disabilitato per non sovrascriverlo con un valore '
          'errato.',
          style: AppText.caption(context).copyWith(color: t.danger),
        ),
        const SizedBox(height: AppSpacing.s6),
        AppButton(
          label: 'Riprova',
          icon: const Icon(Icons.refresh),
          variant: AppButtonVariant.ghost,
          size: AppButtonSize.sm,
          onPressed: onRetry,
        ),
      ],
    );
  }
}
