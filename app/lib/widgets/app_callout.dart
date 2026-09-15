import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Tinte di [AppCallout]: semantica del messaggio, mai del dato di mercato
/// (verde/rosso "guadagno/perdita" restano riservati a `AppDelta`).
enum AppCalloutTone {
  /// Neutro: blocco incassato per contenuti di servizio (strategia, metriche).
  neutral,

  /// Informativo: alone d'accento (`primaryGlow` + `primary`).
  info,

  /// Esito positivo.
  success,

  /// Attenzione.
  warning,

  /// Errore o azione distruttiva.
  danger,
}

/// Callout inline del design system: pannello tonale con bordo 1px, raggio 4 e
/// striscia d'accento opzionale a sinistra.
///
/// Due modi d'uso, stessa pelle:
/// - **messaggio** ([icon]/[title]/[body]): alert o nota con icona Material.
///   Con [title] nullo il corpo prende il colore della tinta (alert); con il
///   titolo, il corpo resta `textSecondary` (blocco informativo con etichetta);
/// - **contenuto** ([child]): composizione libera (righe P&L, badge, tabelle)
///   quando il contenuto ha una struttura propria.
///
/// La striscia accent è disegnata con uno [Stack] clippato: un [Border] non può
/// mescolare colori diversi con il border-radius. Con [liveRegion] il contenuto
/// viene annunciato dagli screen reader quando compare.
class AppCallout extends StatelessWidget {
  /// Crea un callout.
  const AppCallout({
    super.key,
    this.tone = AppCalloutTone.neutral,
    this.icon,
    this.title,
    this.body,
    this.actions = const <Widget>[],
    this.child,
    this.accent = false,
    this.accentColor,
    this.accentWidth = AppSizes.accentStrip,
    this.padding,
    this.liveRegion = false,
  })  : assert(
          child == null || (icon == null && title == null && body == null),
          'AppCallout: usa child oppure icon/title/body, non entrambi.',
        ),
        assert(
          child != null || body != null || title != null,
          'AppCallout: serve un child o almeno un titolo/corpo.',
        ),
        assert(accentWidth >= 0, 'AppCallout: accentWidth non può essere negativo.');

  /// Tinta del callout.
  final AppCalloutTone tone;

  /// Icona Material a sinistra del messaggio (sostituisce le emoji).
  final Widget? icon;

  /// Titolo breve del messaggio (opzionale).
  final String? title;

  /// Corpo del messaggio (opzionale se c'è [title]).
  final String? body;

  /// Azioni sotto il messaggio (bottoni, link), allineate a sinistra.
  final List<Widget> actions;

  /// Contenuto libero al posto del messaggio standard.
  final Widget? child;

  /// True = striscia d'accento a sinistra.
  final bool accent;

  /// Colore della striscia; default il colore della tinta.
  final Color? accentColor;

  /// Spessore della striscia d'accento.
  final double accentWidth;

  /// Padding interno; default 12 su tutti i lati.
  final EdgeInsetsGeometry? padding;

  /// True = annuncio live region quando il callout compare.
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final (Color background, Color border, Color toneColor, Color foreground) =
        switch (tone) {
      AppCalloutTone.neutral => (
          t.surfaceSunken,
          t.border,
          t.textSecondary,
          t.textSecondary,
        ),
      AppCalloutTone.info => (t.primaryGlow, t.primary, t.primary, t.primary),
      AppCalloutTone.success => (
          t.successBg,
          t.successBorder,
          t.success,
          t.successText,
        ),
      AppCalloutTone.warning => (
          t.warningBg,
          t.warningBorder,
          t.warning,
          t.warning,
        ),
      AppCalloutTone.danger => (t.dangerBg, t.dangerBorder, t.danger, t.danger),
    };
    final Color stripColor = accentColor ?? toneColor;
    final EdgeInsetsGeometry innerPadding =
        padding ?? const EdgeInsets.all(AppSpacing.s12);

    Widget content = child ?? _message(t, foreground);
    if (accent) {
      // La striscia non copre il contenuto: il padding cresce di accentWidth.
      content = Padding(
        padding: EdgeInsets.only(left: accentWidth),
        child: content,
      );
    }

    final Widget panel = Container(
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(AppRadii.input),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: <Widget>[
          Padding(padding: innerPadding, child: content),
          if (accent)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: accentWidth,
              child: ColoredBox(color: stripColor),
            ),
        ],
      ),
    );

    if (!liveRegion) return panel;

    return Semantics(
      container: true,
      liveRegion: true,
      child: panel,
    );
  }

  /// Messaggio standard: icona + titolo/corpo.
  Widget _message(AppTokens t, Color foreground) {
    final Widget? leading = icon == null
        ? null
        : IconTheme.merge(
            data: IconThemeData(color: foreground, size: AppSizes.iconSm),
            child: icon!,
          );

    final Widget message;
    if (title == null) {
      message = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (leading != null) ...<Widget>[
            leading,
            const SizedBox(width: AppSpacing.s8),
          ],
          Expanded(
            child: Text(
              body ?? '',
              style: AppText.smallFor(t)
                  .copyWith(color: foreground, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      );
    } else {
      message = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (leading != null) ...<Widget>[
                leading,
                const SizedBox(width: AppSpacing.s6),
              ],
              Expanded(
                child: Text(
                  title!,
                  style: AppText.smallFor(t)
                      .copyWith(color: foreground, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (body != null) ...<Widget>[
            const SizedBox(height: AppSpacing.s4),
            Text(
              body!,
              style: AppText.captionFor(t).copyWith(color: t.textSecondary),
            ),
          ],
        ],
      );
    }

    if (actions.isEmpty) return message;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        message,
        const SizedBox(height: AppSpacing.s8),
        Wrap(
          spacing: AppSpacing.s8,
          runSpacing: AppSpacing.s8,
          children: actions,
        ),
      ],
    );
  }
}
