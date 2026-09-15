import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Tono di [AppProgressBar].
enum AppProgressTone {
  /// Accento (default): avanzamento neutro.
  accent,

  /// Verde: obiettivo raggiunto o saldo positivo.
  success,

  /// Ambra: attenzione.
  warning,

  /// Rosso: sforamento o perdita.
  danger,

  /// Neutro: dato senza giudizio.
  neutral,
}

/// Barra di avanzamento sottile (4px, raggio 2) su track `track`.
///
/// Con [value] = null disegna una barra indeterminata; con [target] mostra un
/// segnaposto verticale (es. peso obiettivo nel rebalancer).
class AppProgressBar extends StatelessWidget {
  /// Crea una barra di avanzamento.
  const AppProgressBar({
    super.key,
    required this.value,
    this.tone = AppProgressTone.accent,
    this.height = 5,
    this.target,
    this.semanticsLabel,
  });

  /// Avanzamento tra 0 e 1; `null` = indeterminata.
  final double? value;

  /// Tono semantico.
  final AppProgressTone tone;

  /// Spessore della barra.
  final double height;

  /// Segnaposto verticale tra 0 e 1 (opzionale).
  final double? target;

  /// Etichetta accessibile.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final Color color = switch (tone) {
      AppProgressTone.accent => t.primary,
      AppProgressTone.success => t.success,
      AppProgressTone.warning => t.warning,
      AppProgressTone.danger => t.danger,
      AppProgressTone.neutral => t.textMuted,
    };
    final double? v = value?.clamp(0, 1).toDouble();

    Widget bar = ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: v == null
            ? LinearProgressIndicator(
                minHeight: height,
                color: color,
                backgroundColor: t.track,
              )
            : Stack(
                children: <Widget>[
                  Positioned.fill(child: ColoredBox(color: t.track)),
                  FractionallySizedBox(
                    widthFactor: v,
                    heightFactor: 1,
                    alignment: Alignment.centerLeft,
                    child: ColoredBox(color: color, child: const SizedBox.expand()),
                  ),
                  if (target != null)
                    Positioned.fill(
                      child: Align(
                        alignment: Alignment(target!.clamp(0, 1).toDouble() * 2 - 1, 0),
                        child: Container(width: 1.5, color: t.textPrimary.withValues(alpha: 0.55)),
                      ),
                    ),
                ],
              ),
      ),
    );

    bar = Semantics(
      label: semanticsLabel,
      value: v == null ? null : '${(v * 100).round()}%',
      child: bar,
    );
    return bar;
  }
}
