import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Stato vuoto centrato (`.table-empty`): icona opzionale, messaggio e azioni.
///
/// Usato sotto tabelle, card e liste quando non ci sono dati o il filtro non
/// produce risultati.
class EmptyState extends StatelessWidget {
  /// Crea uno stato vuoto.
  const EmptyState({
    super.key,
    required this.message,
    this.icon,
    this.actions = const <Widget>[],
    this.padding,
  });

  /// Messaggio centrale (es. `Nessun titolo nel radar.`).
  final String message;

  /// Icona/emoji opzionale sopra il messaggio.
  final Widget? icon;

  /// Azioni sotto il messaggio (bottoni, link), centrate.
  final List<Widget> actions;

  /// Padding esterno; default 26×16 come `.table-empty`.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Padding(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            IconTheme.merge(
              data: IconThemeData(color: t.textMuted, size: 22),
              child: icon!,
            ),
            const SizedBox(height: AppSpacing.s10),
          ],
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: t.textMuted,
              fontSize: 13.6,
              fontWeight: FontWeight.w400,
              height: 1.5,
              fontFamilyFallback: AppTokens.fontFallback,
            ),
          ),
          if (actions.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.s12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: AppSpacing.s8,
              runSpacing: AppSpacing.s8,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}

/// Nota a piè di tabella (`.table-note`): testo muted a sinistra e contenuto
/// a destra, con wrap su mobile.
class TableNote extends StatelessWidget {
  /// Crea una nota di tabella.
  const TableNote({super.key, required this.left, this.right});

  /// Testo/Widget a sinistra.
  final Widget left;

  /// Contenuto a destra (es. link "Vedi tutte").
  final Widget? right;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s10),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.s10,
        runSpacing: AppSpacing.s4,
        children: <Widget>[
          DefaultTextStyle.merge(
            style: TextStyle(
              color: t.textMuted,
              fontSize: 12.5,
              fontWeight: FontWeight.w400,
              fontFamilyFallback: AppTokens.fontFallback,
            ),
            child: left,
          ),
          ?right,
        ],
      ),
    );
  }
}
