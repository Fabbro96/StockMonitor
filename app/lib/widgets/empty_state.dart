import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Stato vuoto centrato: icona in un riquadro squadrato, titolo opzionale,
/// messaggio e azioni.
///
/// Usato sotto tabelle, card e liste quando non ci sono dati o il filtro non
/// produce risultati.
class EmptyState extends StatelessWidget {
  /// Crea uno stato vuoto.
  const EmptyState({
    super.key,
    required this.message,
    this.title,
    this.icon,
    this.actions = const <Widget>[],
    this.padding,
  });

  /// Messaggio centrale (es. `Nessun titolo nel radar.`).
  final String message;

  /// Titolo opzionale sopra il messaggio.
  final String? title;

  /// Icona Material opzionale sopra il messaggio.
  final Widget? icon;

  /// Azioni sotto il messaggio (bottoni, link), centrate.
  final List<Widget> actions;

  /// Padding esterno; default 28×20.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Padding(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: t.surfaceSunken,
                border: Border.all(color: t.border),
                borderRadius: BorderRadius.circular(AppRadii.control),
              ),
              child: IconTheme.merge(
                data: IconThemeData(color: t.textMuted, size: AppSizes.iconLg),
                child: Center(child: icon!),
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
          ],
          if (title != null) ...<Widget>[
            Text(
              title!,
              textAlign: TextAlign.center,
              style: AppText.cardTitle(context),
            ),
            const SizedBox(height: AppSpacing.s4),
          ],
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppText.captionFor(t).copyWith(fontSize: 13),
          ),
          if (actions.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.s14),
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

/// Nota a piè di tabella: testo muted a sinistra e contenuto a destra, con
/// wrap su mobile.
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
              fontSize: 12,
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
