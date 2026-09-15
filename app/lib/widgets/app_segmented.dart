import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

/// Voce di un [AppSegmented].
class AppSegment<T> {
  /// Crea una voce.
  const AppSegment({
    required this.value,
    required this.label,
    this.icon,
    this.tooltip,
  });

  /// Valore associato alla voce.
  final T value;

  /// Etichetta mostrata.
  final String label;

  /// Icona Material opzionale.
  final IconData? icon;

  /// Tooltip opzionale.
  final String? tooltip;
}

/// Controllo segmentato a selezione singola (timeframe, viste, filtri).
///
/// Geometria Registro: contenitore incassato (`surfaceSunken`, bordo 1px,
/// raggio 4), segmento attivo su `surface` con testo d'accento. Da tastiera:
/// Tab entra nel gruppo, ←/→ spostano la selezione (l'anello di focus compare
/// solo quando si naviga da tastiera).
class AppSegmented<T> extends StatelessWidget {
  /// Crea un controllo segmentato.
  const AppSegmented({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelected,
    this.dense = false,
    this.expand = false,
    this.semanticsLabel,
  });

  /// Voci disponibili (ordine di visualizzazione).
  final List<AppSegment<T>> segments;

  /// Valore selezionato.
  final T selected;

  /// Callback di selezione.
  final ValueChanged<T> onSelected;

  /// True = altezza e padding ridotti.
  final bool dense;

  /// True = larghezza piena, voci equamente distribuite.
  final bool expand;

  /// Etichetta accessibile del gruppo.
  final String? semanticsLabel;

  void _move(int delta) {
    if (segments.isEmpty) return;
    final int current = segments.indexWhere((AppSegment<T> s) => s.value == selected);
    final int next = ((current < 0 ? 0 : current) + delta).clamp(0, segments.length - 1);
    if (next != current) onSelected(segments[next].value);
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final double height = dense ? AppSizes.controlSm : AppSizes.control;

    final Widget row = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      children: <Widget>[
        for (final AppSegment<T> segment in segments)
          if (expand)
            Expanded(
              child: _Segment<T>(
                segment: segment,
                active: segment.value == selected,
                dense: dense,
                height: height,
                onTap: () => onSelected(segment.value),
                onArrow: _move,
              ),
            )
          else
            Flexible(
              fit: FlexFit.loose,
              child: _Segment<T>(
                segment: segment,
                active: segment.value == selected,
                dense: dense,
                height: height,
                onTap: () => onSelected(segment.value),
                onArrow: _move,
              ),
            ),
      ],
    );

    final Widget control = Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: t.surfaceSunken,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: row,
    );

    return Semantics(label: semanticsLabel, container: true, child: control);
  }
}

class _Segment<T> extends StatefulWidget {
  const _Segment({
    required this.segment,
    required this.active,
    required this.dense,
    required this.height,
    required this.onTap,
    required this.onArrow,
  });

  final AppSegment<T> segment;
  final bool active;
  final bool dense;
  final double height;
  final VoidCallback onTap;
  final ValueChanged<int> onArrow;

  @override
  State<_Segment<T>> createState() => _SegmentState<T>();
}

class _SegmentState<T> extends State<_Segment<T>> {
  final FocusNode _focusNode = FocusNode();
  bool _hovered = false;
  bool _focused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      widget.onArrow(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      widget.onArrow(1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final Color foreground = widget.active
        ? t.primary
        : (_hovered || _focused ? t.textPrimary : t.textSecondary);
    // L'anello di focus compare solo con la navigazione da tastiera: il tap
    // del mouse sposta il focus (per abilitare le frecce) senza accenderlo.
    final bool keyboardFocus =
        _focused && FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

    final Widget body = AnimatedContainer(
      duration: AppMotion.effective(context, AppMotion.fast),
      curve: AppMotion.ease,
      height: widget.height - 6,
      padding: EdgeInsets.symmetric(horizontal: widget.dense ? 8 : 12),
      decoration: BoxDecoration(
        color: widget.active ? t.surface : (_hovered ? t.surfaceHover : Colors.transparent),
        border: Border.all(color: widget.active ? t.border : Colors.transparent),
        borderRadius: BorderRadius.circular(AppRadii.tag),
        boxShadow: keyboardFocus
            ? <BoxShadow>[
                BoxShadow(color: t.focusRing, blurRadius: 0, spreadRadius: 2),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (widget.segment.icon != null) ...<Widget>[
            Icon(widget.segment.icon, size: AppSizes.iconSm, color: foreground),
            const SizedBox(width: AppSpacing.s6),
          ],
          Flexible(
            child: Text(
              widget.segment.label,
              style: TextStyle(
                color: foreground,
                fontSize: widget.dense ? 12 : 12.8,
                fontWeight: widget.active ? FontWeight.w600 : FontWeight.w500,
                height: 1.25,
                fontFamilyFallback: AppTokens.fontFallback,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

    Widget content = Focus(
      canRequestFocus: false,
      onKeyEvent: _onKey,
      child: Semantics(
        button: true,
        selected: widget.active,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            focusNode: _focusNode,
            onTap: () {
              // Il focus segue il tap: così le frecce ←/→ funzionano subito.
              _focusNode.requestFocus();
              widget.onTap();
            },
            onHover: (bool value) => setState(() => _hovered = value),
            onFocusChange: (bool value) => setState(() => _focused = value),
            borderRadius: BorderRadius.circular(AppRadii.tag),
            hoverColor: Colors.transparent,
            focusColor: Colors.transparent,
            child: body,
          ),
        ),
      ),
    );

    if (widget.segment.tooltip != null) {
      content = Tooltip(message: widget.segment.tooltip!, child: content);
    }
    return content;
  }
}
