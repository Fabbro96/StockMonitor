import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/portfolio_api.dart';
import '../../../core/api_client.dart';
import '../../../core/formatters.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/toast.dart';
import '../portfolio_tools_providers.dart';

/// Esporta il portafoglio in CSV (`GET /portfolio/export`).
///
/// Su web il file viene scaricato dal browser; su Android/desktop viene
/// salvato su disco e il toast mostra il percorso (come da spec migrazione).
/// Il nome file è `portafoglio_YYYY-MM-DD.csv` (data locale).
Future<void> exportPortfolioCsv(BuildContext context) async {
  try {
    final PortfolioApi api = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(portfolioApiProvider);
    final Uint8List bytes = await api.exportCsv();
    final String filename = 'portafoglio_${dateToApi(DateTime.now())}';
    final String path = await FileSaver.instance.saveFile(
      name: filename,
      bytes: bytes,
      fileExtension: 'csv',
      mimeType: MimeType.csv,
    );
    if (!context.mounted) return;
    showAppToast(
      context,
      message: kIsWeb ? 'Portafoglio esportato in CSV!' : 'File salvato: $path',
      type: AppToastType.success,
    );
  } on ApiException catch (error) {
    if (!context.mounted) return;
    showAppToast(context, message: error.message, type: AppToastType.error);
  } catch (_) {
    if (!context.mounted) return;
    showAppToast(
      context,
      message: kIsWeb
          ? 'Errore durante l\'esportazione CSV'
          : 'Esportazione non riuscita: il salvataggio CSV è supportato su Android 10+. Riprova o usa la versione web.',
      type: AppToastType.error,
    );
  }
}

/// Apre il modal "📤 Importa Portafoglio da CSV" (parità `#importModal`).
///
/// La selezione file usa `file_picker`; l'upload va a `POST /portfolio/import`.
Future<void> showImportPortfolioDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: context.tokens.scrim,
    builder: (BuildContext _) => const _ImportPortfolioDialog(),
  );
}

class _ImportPortfolioDialog extends ConsumerStatefulWidget {
  const _ImportPortfolioDialog();

  @override
  ConsumerState<_ImportPortfolioDialog> createState() =>
      _ImportPortfolioDialogState();
}

class _ImportPortfolioDialogState
    extends ConsumerState<_ImportPortfolioDialog> {
  PlatformFile? _file;
  bool _importing = false;
  String? _error;

  Future<void> _pickFile() async {
    try {
      final PlatformFile? picked = await FilePicker.pickFile(
        dialogTitle: 'Seleziona un file CSV da caricare',
        type: FileType.custom,
        allowedExtensions: <String>['csv'],
      );
      if (!mounted) return;
      if (picked == null) {
        showAppToast(
          context,
          message: 'Seleziona un file CSV da caricare',
          type: AppToastType.error,
        );
        return;
      }
      setState(() {
        _file = picked;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Errore durante la selezione del file',
        type: AppToastType.error,
      );
    }
  }

  Future<void> _submit() async {
    final PlatformFile? file = _file;
    if (file == null) {
      showAppToast(
        context,
        message: 'Seleziona un file CSV da caricare',
        type: AppToastType.error,
      );
      return;
    }

    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final Uint8List bytes = await file.readAsBytes();
      final Map<String, dynamic> result = await ref
          .read(portfolioApiProvider)
          .importCsv(bytes: bytes, filename: file.name);
      final List<Object?> errors = result['errors'] is List
          ? (result['errors'] as List<dynamic>).cast<Object?>()
          : const <Object?>[];
      final int imported = (result['imported'] as num?)?.toInt() ?? 0;
      final int updated = (result['updated'] as num?)?.toInt() ?? 0;
      if (!mounted) return;
      ref.invalidate(dividendsProvider);
      if (errors.isNotEmpty) {
        final String first = _truncate(errors.first.toString(), 160);
        showAppToast(
          context,
          message: 'Importazione con errori (${errors.length}): $first',
          type: AppToastType.error,
        );
      } else {
        showAppToast(
          context,
          message: 'Importate: $imported nuove, Aggiornate: $updated',
          type: AppToastType.success,
        );
      }
      Navigator.of(context).pop();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _importing = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _importing = false;
        _error = 'Errore durante l\'importazione del file CSV';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final TextStyle mono = AppText.mono(context, size: 12.5);

    return AlertDialog(
      title: const Text('📤 Importa Portafoglio da CSV'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text.rich(
              TextSpan(
                text:
                    'Carica un file CSV con le tue azioni. Colonne '
                    'riconosciute automaticamente: ',
                children: <InlineSpan>[
                  TextSpan(text: 'ticker', style: mono),
                  const TextSpan(text: ', '),
                  TextSpan(text: 'quantity', style: mono),
                  const TextSpan(text: ', '),
                  TextSpan(text: 'avg_purchase_price', style: mono),
                  const TextSpan(text: ', '),
                  TextSpan(text: 'notes', style: mono),
                  const TextSpan(text: '.'),
                ],
              ),
              style: AppText.small(context).copyWith(color: t.textSecondary),
            ),
            const SizedBox(height: AppSpacing.s14),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s12,
                vertical: AppSpacing.s10,
              ),
              decoration: BoxDecoration(
                color: t.surfaceHover,
                border: Border.all(color: t.border),
                borderRadius: BorderRadius.circular(AppRadii.input),
              ),
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final Widget fileName = Row(
                    children: <Widget>[
                      const Text('📄', style: TextStyle(fontSize: 14)),
                      const SizedBox(width: AppSpacing.s8),
                      Expanded(
                        child: Text(
                          _file?.name ?? 'Nessun file selezionato',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _file == null
                              ? AppText.caption(context)
                              : mono.copyWith(color: t.textPrimary),
                        ),
                      ),
                    ],
                  );
                  final Widget pick = AppButton(
                    label: '📂 Seleziona file CSV',
                    variant: AppButtonVariant.ghost,
                    size: AppButtonSize.xs,
                    onPressed: _importing ? null : () => unawaited(_pickFile()),
                  );
                  // Sotto ~330px il bottone va a capo: nel Row resta
                  // non-flex e con label lunghe overflowa la cella.
                  if (constraints.maxWidth < 330) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        fileName,
                        const SizedBox(height: AppSpacing.s8),
                        Align(alignment: Alignment.centerLeft, child: pick),
                      ],
                    );
                  }
                  return Row(
                    children: <Widget>[
                      Expanded(child: fileName),
                      const SizedBox(width: AppSpacing.s8),
                      pick,
                    ],
                  );
                },
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
      actions: <Widget>[
        AppButton(
          label: 'Annulla',
          variant: AppButtonVariant.ghost,
          onPressed: _importing ? null : () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: 'Carica e Importa',
          loading: _importing,
          loadingLabel: 'Importazione in corso...',
          onPressed: _importing ? null : _submit,
        ),
      ],
    );
  }
}

String _truncate(String value, int max) =>
    value.length <= max ? value : value.substring(0, max);
