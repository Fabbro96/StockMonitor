import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Input numerico con bottoni `+`/`−` (`.modern-stepper`).
///
/// Il valore vive nel [controller] passato: i bottoni incrementano/decrementano
/// di [step] rispettando [min]/[max] e riscrivono il testo con [decimals]
/// (se `null`, i numeri interi restano interi). Il campo resta editabile a
/// mano e [onChanged] riceve il valore parsato a ogni modifica valida
/// (accetta sia `.` sia `,` come separatore decimale).
///
/// [expand] rende lo stepper a larghezza piena (`.stepper-full`), [large]
/// usa il font grande in primary del campo liquidità del Rebalancer.
class StepperInput extends StatefulWidget {
  /// Crea uno stepper numerico.
  const StepperInput({
    super.key,
    required this.controller,
    this.min,
    this.max,
    this.step = 1,
    this.decimals,
    this.hint,
    this.enabled = true,
    this.expand = false,
    this.width,
    this.large = false,
    this.semanticsLabel,
    this.decreaseLabel = 'Diminuisci',
    this.increaseLabel = 'Aumenta',
    this.onChanged,
  });

  /// Controller del testo (il chiamante lo possiede e lo dispose-a).
  final TextEditingController controller;

  /// Valore minimo consentito dai bottoni.
  final double? min;

  /// Valore massimo consentito dai bottoni.
  final double? max;

  /// Passo di incremento/decremento.
  final double step;

  /// Numero di decimali da mostrare dopo un bump; `null` = interi quando interi.
  final int? decimals;

  /// Placeholder del campo (es. `Liquidità (€)`).
  final String? hint;

  /// True = stepper attivo.
  final bool enabled;

  /// True = larghezza piena (`.stepper-full`).
  final bool expand;

  /// Larghezza massima fissa (default 170 come `.modern-stepper`).
  final double? width;

  /// True = campo grande in primary (`.input-lg`, es. liquidità Rebalancer).
  final bool large;

  /// Etichetta accessibile del gruppo.
  final String? semanticsLabel;

  /// Etichetta del bottone di decremento.
  final String decreaseLabel;

  /// Etichetta del bottone di incremento.
  final String increaseLabel;

  /// Callback con il valore parsato a ogni modifica valida.
  final ValueChanged<double>? onChanged;

  @override
  State<StepperInput> createState() => _StepperInputState();
}

class _StepperInputState extends State<StepperInput> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onFocusChanged() => setState(() {});

  void _onTextChanged() {
    // Ridisegna solo per abilitare/disabilitare i bottoni (min/max).
    if (mounted) setState(() {});
  }

  double? _parse(String raw) => double.tryParse(raw.trim().replaceAll(',', '.'));

  String _format(double value) {
    if (widget.decimals != null) return value.toStringAsFixed(widget.decimals!);
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value
        .toStringAsFixed(4)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  void _bump(int direction) {
    final double current = _parse(widget.controller.text) ?? widget.min ?? 0;
    double next = current + widget.step * direction;
    if (widget.min != null && next < widget.min!) next = widget.min!;
    if (widget.max != null && next > widget.max!) next = widget.max!;
    widget.controller.text = _format(next);
    widget.controller.selection = TextSelection.collapsed(offset: widget.controller.text.length);
    widget.onChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool compact = context.isCompact;
    final double buttonSize = compact ? 26 : 22;
    final Duration duration = AppMotion.effective(context, AppMotion.fast);
    final TextStyle inputStyle = widget.large
        ? AppText.mono(context, size: 16, weight: FontWeight.w700, color: t.primary)
        : AppText.mono(context, size: 13.5, weight: FontWeight.w600);

    final Widget minus = _StepperButton(
      icon: Icons.remove,
      size: buttonSize,
      enabled: widget.enabled && _canDecrease(),
      label: widget.decreaseLabel,
      onPressed: () => _bump(-1),
    );
    final Widget plus = _StepperButton(
      icon: Icons.add,
      size: buttonSize,
      enabled: widget.enabled && _canIncrease(),
      label: widget.increaseLabel,
      onPressed: () => _bump(1),
    );

    final Widget field = TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      enabled: widget.enabled,
      textAlign: TextAlign.center,
      style: inputStyle,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ],
      onChanged: (String raw) {
        final double? value = _parse(raw);
        if (value != null) widget.onChanged?.call(value);
      },
      decoration: InputDecoration(
        filled: false,
        isDense: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        hintText: widget.hint,
        hintStyle: AppText.mono(
          context,
          size: 12.5,
          weight: FontWeight.w500,
          color: t.textMuted,
        ),
      ),
    );

    Widget stepper = AnimatedContainer(
      duration: duration,
      curve: AppMotion.ease,
      width: widget.expand ? double.infinity : null,
      constraints: widget.expand
          ? null
          : BoxConstraints(minWidth: 104, maxWidth: widget.width ?? 170),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: t.surfaceSunken,
        border: Border.all(color: _focusNode.hasFocus ? t.primary : t.border),
        borderRadius: BorderRadius.circular(AppRadii.input),
        boxShadow: _focusNode.hasFocus
            ? <BoxShadow>[
                BoxShadow(color: t.focusRing, blurRadius: 0, spreadRadius: 2),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
        children: <Widget>[
          minus,
          widget.expand
              ? Expanded(child: field)
              : Flexible(fit: FlexFit.loose, child: field),
          plus,
        ],
      ),
    );

    if (widget.semanticsLabel != null) {
      stepper = Semantics(label: widget.semanticsLabel, child: stepper);
    }
    return stepper;
  }

  bool _canDecrease() {
    if (widget.min == null) return true;
    final double? current = _parse(widget.controller.text);
    return current == null || current > widget.min!;
  }

  bool _canIncrease() {
    if (widget.max == null) return true;
    final double? current = _parse(widget.controller.text);
    return current == null || current < widget.max!;
  }
}

/// Bottone `+`/`−` dello stepper (`.stepper-btn`): 24/28px, bordo, hover pieno
/// primary, scala 0.94 alla pressione.
class _StepperButton extends StatefulWidget {
  const _StepperButton({
    required this.icon,
    required this.size,
    required this.enabled,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final double size;
  final bool enabled;
  final String label;
  final VoidCallback onPressed;

  @override
  State<_StepperButton> createState() => _StepperButtonState();
}

class _StepperButtonState extends State<_StepperButton> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool enabled = widget.enabled;
    final Color background = !enabled
        ? t.surfaceActive
        : (_hovered ? t.primarySolid : t.surface);
    final Color foreground = !enabled
        ? t.textFaint
        : (_hovered ? t.onPrimarySolid : t.textPrimary);
    final Color border = !enabled
        ? t.borderSubtle
        : (_hovered ? t.primarySolid : (_focused ? t.primary : t.border));

    Widget button = AnimatedScale(
      scale: _pressed && enabled ? 0.94 : 1,
      duration: AppMotion.effective(context, AppMotion.fast),
      curve: AppMotion.ease,
      child: AnimatedContainer(
        duration: AppMotion.effective(context, AppMotion.fast),
        curve: AppMotion.ease,
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(AppRadii.tag),
          boxShadow: _focused && enabled
              ? <BoxShadow>[
                  BoxShadow(color: t.focusRing, blurRadius: 0, spreadRadius: 2),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? widget.onPressed : null,
            canRequestFocus: enabled,
            onHover: (bool value) => setState(() => _hovered = value),
            onHighlightChanged: (bool value) => setState(() => _pressed = value),
            onFocusChange: (bool value) => setState(() => _focused = value),
            borderRadius: BorderRadius.circular(AppRadii.tag),
            hoverColor: Colors.transparent,
            focusColor: Colors.transparent,
            child: Icon(widget.icon, size: widget.size * 0.6, color: foreground),
          ),
        ),
      ),
    );

    button = Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: Tooltip(message: widget.label, child: button),
    );
    return button;
  }
}
