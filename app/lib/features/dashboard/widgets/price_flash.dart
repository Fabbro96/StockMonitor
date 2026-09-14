import 'package:flutter/material.dart';

import '../../../theme/tokens.dart';

/// Flash di sfondo verde/rosso quando [value] cambia (`.flash-up`/`.flash-down`
/// del CSS: 0.8s in dissolvenza). Usato su prezzi e variazioni durante il
/// refresh silente per rendere visibile il movimento senza animazioni invadenti.
///
/// Il primo build non fa lampeggiare nulla; se il valore non cambia non
/// succede niente; con `prefers-reduced-motion` l'effetto è disattivato.
class PriceFlash extends StatefulWidget {
  /// Avvolge [child] con il flash.
  const PriceFlash({
    super.key,
    required this.value,
    required this.rising,
    required this.child,
  });

  /// Valore osservato: un cambiamento fa partire il flash.
  final double value;

  /// True = movimento al rialzo (verde), false = ribasso (rosso).
  final bool rising;

  /// Contenuto (di norma un testo di prezzo).
  final Widget child;

  @override
  State<PriceFlash> createState() => _PriceFlashState();
}

class _PriceFlashState extends State<PriceFlash> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  late final Animation<double> _fade = Tween<double>(begin: 1, end: 0).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeOut),
  );

  @override
  void didUpdateWidget(PriceFlash oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value == widget.value || oldWidget.value == 0) return;
    if (MediaQuery.disableAnimationsOf(context)) return;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final Color base = widget.rising ? t.successBg : t.dangerBg;

    return AnimatedBuilder(
      animation: _fade,
      builder: (BuildContext context, Widget? child) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: base.withValues(alpha: base.a * _fade.value),
            borderRadius: BorderRadius.circular(AppRadii.small),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
