import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_button.dart';
import '../../widgets/toast.dart';

/// Mostra il modal `Scegli giorno` e ritorna la data scelta come
/// `YYYY-MM-DD`, oppure `null` se annullato/backdrop/esc.
///
/// [initialDate] è il valore corrente del filtro (`YYYY-MM-DD`): il calendario
/// si apre su quel mese, ma la data resta "non selezionata" finché l'utente
/// non tocca un giorno (validazione `Seleziona una data valida`).
Future<String?> showAdviceDatePicker(
  BuildContext context, {
  String? initialDate,
}) {
  return showDialog<String>(
    context: context,
    barrierColor: context.tokens.scrim,
    builder: (BuildContext dialogContext) =>
        _AdviceDatePickerDialog(initialDate: initialDate),
  );
}

class _AdviceDatePickerDialog extends StatefulWidget {
  const _AdviceDatePickerDialog({this.initialDate});

  final String? initialDate;

  @override
  State<_AdviceDatePickerDialog> createState() =>
      _AdviceDatePickerDialogState();
}

class _AdviceDatePickerDialogState extends State<_AdviceDatePickerDialog> {
  DateTime? _selected;
  late DateTime _visibleMonth;

  @override
  void initState() {
    super.initState();
    final DateTime parsed =
        parseServerDate(widget.initialDate) ?? DateTime.now();
    _visibleMonth = parsed;
    // La data corrente del filtro è una selezione valida, come il
    // `<input type="date">` prefillato del legacy.
    _selected = parseServerDate(widget.initialDate);
  }

  void _apply() {
    final DateTime? selected = _selected;
    if (selected == null) {
      showAppToast(
        context,
        message: 'Seleziona una data valida',
        type: AppToastType.error,
      );
      return;
    }
    Navigator.of(context).pop(dateToApi(selected));
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Dialog(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.sheet),
        side: BorderSide(color: t.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Scegli giorno',
                      style: AppText.modalTitle(context),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  AppIconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Chiudi finestra',
                    semanticLabel: 'Chiudi finestra',
                    size: 30,
                    iconSize: 17,
                    bordered: false,
                    danger: true,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s16),
              Text(
                'Seleziona la data da consultare:',
                style: AppText.formLabel(context),
              ),
              const SizedBox(height: AppSpacing.s10),
              SizedBox(
                height: 300,
                child: CalendarDatePicker(
                  initialDate: _visibleMonth,
                  firstDate: DateTime(2015),
                  lastDate: DateTime.now(),
                  onDateChanged: (DateTime date) {
                    setState(() {
                      _selected = date;
                      _visibleMonth = date;
                    });
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.s16),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.s8,
                runSpacing: AppSpacing.s8,
                children: <Widget>[
                  AppButton(
                    label: 'Annulla',
                    variant: AppButtonVariant.ghost,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  AppButton(label: 'Applica Filtro Data', onPressed: _apply),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
