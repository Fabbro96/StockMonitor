import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/models/advice.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/badges.dart';

/// Tinta del badge azione (macro e per-titolo), tollerante alle varianti
/// (`includes`) come `getActionBadgeClass` del legacy.
BadgeTone actionToneFor(String? action) {
  final String act = (action ?? '').toUpperCase();
  if (act.contains('ACCUMULO') || act.contains('BUY')) return BadgeTone.success;
  if (act.contains('PROFITTO') ||
      act.contains('SELL') ||
      act.contains('ALLEGGERIMENTO')) {
    return BadgeTone.danger;
  }
  return BadgeTone.warning;
}

/// Badge azione della card macro (`🟢 ACCUMULO / BUY`, `🟡 MANTENIMENTO`, ...).
({String label, BadgeTone tone}) macroActionBadge(String? action) {
  final String act = (action ?? '').toUpperCase();
  if (act.contains('ACCUMULO') || act.contains('BUY')) {
    return (label: '🟢 ACCUMULO / BUY', tone: BadgeTone.success);
  }
  if (act.contains('PROFITTO') ||
      act.contains('SELL') ||
      act.contains('ALLEGGERIMENTO')) {
    return (label: '🔴 PRESA PROFITTO / SELL', tone: BadgeTone.danger);
  }
  if (act.contains('PRUDENZA')) {
    return (label: '🛡️ PRUDENZA', tone: BadgeTone.warning);
  }
  return (label: '🟡 MANTENIMENTO', tone: BadgeTone.warning);
}

/// Badge azione di una riga `stocks_analysis` (`COMPRA`/`VENDI`/`TIENI`).
({String label, BadgeTone tone}) stockActionBadge(String? action) {
  final String act = (action ?? 'HOLD').toUpperCase();
  if (act.contains('BUY') || act.contains('ACCUMULO')) {
    return (label: '🟢 COMPRA', tone: BadgeTone.success);
  }
  if (act.contains('SELL') || act.contains('PROFITTO')) {
    return (label: '🔴 VENDI', tone: BadgeTone.danger);
  }
  return (label: '🟡 TIENI', tone: BadgeTone.warning);
}

/// Badge priorità (`🚨 Alta` / `⚡ Media` / `💡 Opportunità` / `🛡️ Rischio`).
({String label, BadgeTone tone}) priorityBadge(String? priority) {
  final String prio = (priority ?? 'MEDIA').toUpperCase();
  if (prio.contains('ALTA') || prio.contains('HIGH')) {
    return (label: '🚨 Alta', tone: BadgeTone.danger);
  }
  if (prio.contains('OPPORTUN')) {
    return (label: '💡 Opportunità', tone: BadgeTone.success);
  }
  if (prio.contains('RISCH') || prio.contains('RISK')) {
    return (label: '🛡️ Rischio', tone: BadgeTone.warning);
  }
  return (label: '⚡ Media', tone: BadgeTone.primary);
}

/// Box con bordo/raggio del DS e barra accent opzionale a sinistra
/// (`.callout`, `.callout-accent`, `.callout-success`, `.callout-danger`).
///
/// La barra è disegnata con uno `Stack` clippato: un `Border` Flutter non può
/// mescolare colori non uniformi con il border-radius.
class AdviceCallout extends StatelessWidget {
  /// Crea un callout.
  const AdviceCallout({
    super.key,
    required this.child,
    this.background,
    this.borderColor,
    this.accent,
    this.accentWidth = 2,
    this.padding = const EdgeInsets.all(AppSpacing.s12),
  });

  /// Contenuto.
  final Widget child;

  /// Sfondo; default `surfaceHover`.
  final Color? background;

  /// Colore del bordo; default `border`.
  final Color? borderColor;

  /// Colore della barra sinistra (null = nessuna).
  final Color? accent;

  /// Spessore della barra accent.
  final double accentWidth;

  /// Padding interno (la barra accent non riduce il contenuto).
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: background ?? t.surfaceHover,
        border: Border.all(color: borderColor ?? t.border),
        borderRadius: BorderRadius.circular(AppRadii.input),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: <Widget>[
          Padding(
            padding: EdgeInsets.only(
              left: padding.left + (accent == null ? 0 : accentWidth),
              top: padding.top,
              right: padding.right,
              bottom: padding.bottom,
            ),
            child: child,
          ),
          if (accent != null)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: accentWidth,
              child: ColoredBox(color: accent!),
            ),
        ],
      ),
    );
  }
}

/// Card di un consiglio macro (`advice-card`).
///
/// Accent laterale verde per il mercato IT, blu (primary) per US/altro; header
/// con flag, titolo, badge azione e data, sezioni quadro/strategia/consigli
/// prioritizzati/rischi e footer confidenza-orizzonte.
class AdviceCard extends StatelessWidget {
  /// Crea la card.
  const AdviceCard({
    super.key,
    required this.advice,
    required this.followed,
    required this.followBusy,
    required this.onToggleFollow,
    required this.onOpenStock,
  });

  /// Consiglio da renderizzare.
  final Advice advice;

  /// Stato `followed` effettivo (override locale incluso).
  final bool followed;

  /// True mentre il toggle follow è in corso.
  final bool followBusy;

  /// Callback del bottone follow.
  final VoidCallback onToggleFollow;

  /// Apre la scheda titolo per un ticker.
  final ValueChanged<String> onOpenStock;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool isIt = advice.market == 'IT';
    final String flag = isIt ? '🇮🇹' : '🇺🇸';
    final String title = advice.title.isNotEmpty
        ? advice.title
        : (isIt ? 'Borsa Italiana (Piazza Affari)' : 'Wall Street');
    final ({String label, BadgeTone tone}) action = macroActionBadge(
      advice.action,
    );
    final List<AdviceStockAnalysis> stocks = advice.stocksAnalysis;

    return AppCard(
      accent: true,
      accentColor: isIt ? t.success : t.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _header(context, t, flag: flag, title: title, action: action),
          if ((advice.overview ?? '').trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.s14),
            _sectionLabel(context, '🌐 Quadro & Scenario Generale'),
            const SizedBox(height: AppSpacing.s4),
            Text(
              advice.overview!.trim(),
              style: AppText.body(context).copyWith(color: t.textPrimary),
            ),
          ],
          if ((advice.strategy ?? '').trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.s14),
            AdviceCallout(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _sectionLabel(
                    context,
                    "🎯 Strategia Operativa & Piano d'Azione",
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  Text(advice.strategy!.trim(), style: AppText.body(context)),
                ],
              ),
            ),
          ],
          if (stocks.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.s14),
            _stocksSection(context, t, flag: flag, stocks: stocks),
          ],
          if ((advice.risks ?? '').trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.s14),
            AdviceCallout(
              background: t.dangerBg,
              borderColor: t.dangerBorder,
              accent: t.danger,
              padding: const EdgeInsets.all(AppSpacing.s10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '⚠️ Punti di Attenzione & Rischi Chiave',
                    style: AppText.small(context)
                        .copyWith(color: t.danger, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    advice.risks!.trim(),
                    style: AppText.captionFor(t)
                        .copyWith(color: t.textSecondary),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.s14),
          _footer(context, t),
        ],
      ),
    );
  }

  Widget _header(
    BuildContext context,
    AppTokens t, {
    required String flag,
    required String title,
    required ({String label, BadgeTone tone}) action,
  }) {
    final Widget titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(flag, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: AppSpacing.s10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                  letterSpacing: -0.2,
                  fontFamilyFallback: AppTokens.fontFallback,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            Flexible(child: AppBadge(label: action.label, tone: action.tone)),
          ],
        ),
        const SizedBox(height: AppSpacing.s4),
        Text.rich(
          TextSpan(
            style: AppText.caption(context),
            children: <InlineSpan>[
              const TextSpan(text: 'Analisi elaborata: '),
              TextSpan(
                text: formatDateTime(advice.timestamp),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ],
    );

    final Widget followButton = AppButton(
      label: followed
          ? '✅ Letto (Segna come Non Letto)'
          : '👁️ Segna come Letto',
      variant: followed ? AppButtonVariant.success : AppButtonVariant.ghost,
      size: AppButtonSize.sm,
      loading: followBusy,
      onPressed: followBusy ? null : onToggleFollow,
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              titleBlock,
              const SizedBox(height: AppSpacing.s10),
              followButton,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: titleBlock),
            const SizedBox(width: AppSpacing.s12),
            followButton,
          ],
        );
      },
    );
  }

  Widget _sectionLabel(BuildContext context, String label) {
    return Text(label.toUpperCase(), style: AppText.sectionLabel(context));
  }

  Widget _stocksSection(
    BuildContext context,
    AppTokens t, {
    required String flag,
    required List<AdviceStockAnalysis> stocks,
  }) {
    final Widget header = Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.s10,
      runSpacing: AppSpacing.s4,
      children: <Widget>[
        Text(
          '📋 Consigli Strategici Prioritizzati (${stocks.length}) $flag',
          style: AppText.small(context)
              .copyWith(color: t.primary, fontWeight: FontWeight.w700),
        ),
        Text(
          'Ordinati per rilevanza & priorità operativa',
          style: AppText.caption(context),
        ),
      ],
    );

    final Table table = Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: const <int, TableColumnWidth>{
        0: FlexColumnWidth(2.1),
        1: FixedColumnWidth(110),
        2: FixedColumnWidth(130),
        3: FixedColumnWidth(110),
        4: FlexColumnWidth(3),
        5: FixedColumnWidth(80),
      },
      border: TableBorder(
        horizontalInside: BorderSide(color: t.borderSubtle),
        top: BorderSide(color: t.border),
        bottom: BorderSide(color: t.border),
      ),
      children: <TableRow>[
        TableRow(
          children: <Widget>[
            _headerCell(context, 'Ticker & Titolo'),
            _headerCell(context, 'Azione', align: TextAlign.center),
            _headerCell(context, 'Priorità', align: TextAlign.center),
            _headerCell(context, 'Target', align: TextAlign.right),
            _headerCell(context, 'Motivo Sintetico & Catalizzatore'),
            _headerCell(context, 'Dettagli', align: TextAlign.center),
          ],
        ),
        for (final AdviceStockAnalysis stock in stocks)
          TableRow(children: _stockCells(context, t, stock)),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        header,
        const SizedBox(height: AppSpacing.s10),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            const double minWidth = 860;
            if (constraints.maxWidth < minWidth) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(width: minWidth, child: table),
              );
            }
            return table;
          },
        ),
      ],
    );
  }

  List<Widget> _stockCells(
    BuildContext context,
    AppTokens t,
    AdviceStockAnalysis stock,
  ) {
    final ({String label, BadgeTone tone}) action = stockActionBadge(
      stock.action,
    );
    final ({String label, BadgeTone tone}) priority = priorityBadge(
      stock.priority,
    );

    return <Widget>[
      Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s10,
          vertical: AppSpacing.s10,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _TickerLink(
              ticker: stock.ticker,
              onTap: () => onOpenStock(stock.ticker),
            ),
            if (stock.name.isNotEmpty)
              Text(
                stock.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption(context),
              ),
          ],
        ),
      ),
      _badgeCell(context, AppBadge(label: action.label, tone: action.tone)),
      _badgeCell(context, AppBadge(label: priority.label, tone: priority.tone)),
      Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s10,
          vertical: AppSpacing.s8,
        ),
        child: Text(
          stock.targetPrice == null ? '--' : formatCurrency(stock.targetPrice),
          textAlign: TextAlign.right,
          style: AppText.mono(
            context,
            size: 13.1,
            weight: FontWeight.w700,
            color: t.primary,
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s10,
          vertical: AppSpacing.s8,
        ),
        child: Text(
          (stock.note ?? '').trim().isEmpty ? '--' : stock.note!.trim(),
          style: AppText.small(context)
              .copyWith(color: t.textSecondary, fontSize: 12.5),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
        child: Center(
          child: AppButton(
            label: '🔍',
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.xs,
            tooltip: 'Apri Scheda Tecnica',
            semanticLabel: 'Apri scheda tecnica di ${stock.ticker}',
            onPressed: () => onOpenStock(stock.ticker),
          ),
        ),
      ),
    ];
  }

  Widget _headerCell(
    BuildContext context,
    String label, {
    TextAlign align = TextAlign.left,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s10,
        vertical: AppSpacing.s8,
      ),
      child: Text(
        label.toUpperCase(),
        textAlign: align,
        style: AppText.tableHeader(context),
      ),
    );
  }

  Widget _badgeCell(BuildContext context, Widget badge) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s6,
        vertical: AppSpacing.s8,
      ),
      child: Center(
        child: FittedBox(fit: BoxFit.scaleDown, child: badge),
      ),
    );
  }

  Widget _footer(BuildContext context, AppTokens t) {
    final List<Widget> meta = <Widget>[
      if ((advice.confidence ?? '').trim().isNotEmpty)
        Text.rich(
          TextSpan(
            style: AppText.caption(context),
            children: <InlineSpan>[
              const TextSpan(text: 'Confidenza IA: '),
              TextSpan(
                text: advice.confidence!.trim(),
                style: TextStyle(color: t.primary, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      if ((advice.timeframe ?? '').trim().isNotEmpty)
        Text.rich(
          TextSpan(
            style: AppText.caption(context),
            children: <InlineSpan>[
              const TextSpan(text: 'Orizzonte: '),
              TextSpan(
                text: advice.timeframe!.trim(),
                style: TextStyle(color: t.primary, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
    ];

    return Container(
      padding: const EdgeInsets.only(top: AppSpacing.s12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.s16,
        runSpacing: AppSpacing.s6,
        children: <Widget>[
          Wrap(
            spacing: AppSpacing.s16,
            runSpacing: AppSpacing.s4,
            children: meta,
          ),
          Text(
            'Archivio Ultimi 7 Giorni • Gemini 3.7 Flash',
            style: AppText.caption(context),
          ),
        ],
      ),
    );
  }
}

/// Link ticker cliccabile (`.stock-ticker-link`).
class _TickerLink extends StatefulWidget {
  const _TickerLink({required this.ticker, required this.onTap});

  final String ticker;
  final VoidCallback onTap;

  @override
  State<_TickerLink> createState() => _TickerLinkState();
}

class _TickerLinkState extends State<_TickerLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(AppRadii.small),
      onHover: (bool value) => setState(() => _hovered = value),
      hoverColor: Colors.transparent,
      focusColor: t.primaryGlow,
      child: Semantics(
        button: true,
        label: 'Apri scheda tecnica di ${widget.ticker}',
        child: Text(
          widget.ticker,
          style: AppText.mono(
            context,
            size: 13.1,
            weight: FontWeight.w700,
            color: _hovered ? t.primarySolidHover : t.primary,
          ),
        ),
      ),
    );
  }
}
