import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/models/advice.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_callout.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_market_tag.dart';
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

/// Badge azione della card macro (`ACCUMULO / BUY`, `MANTENIMENTO`, ...).
({String label, BadgeTone tone, IconData icon}) macroActionBadge(String? action) {
  final String act = (action ?? '').toUpperCase();
  if (act.contains('ACCUMULO') || act.contains('BUY')) {
    return (
      label: 'ACCUMULO / BUY',
      tone: BadgeTone.success,
      icon: Icons.arrow_upward,
    );
  }
  if (act.contains('PROFITTO') ||
      act.contains('SELL') ||
      act.contains('ALLEGGERIMENTO')) {
    return (
      label: 'PRESA PROFITTO / SELL',
      tone: BadgeTone.danger,
      icon: Icons.arrow_downward,
    );
  }
  if (act.contains('PRUDENZA')) {
    return (label: 'PRUDENZA', tone: BadgeTone.warning, icon: Icons.shield_outlined);
  }
  return (label: 'MANTENIMENTO', tone: BadgeTone.warning, icon: Icons.remove);
}

/// Badge azione di una riga `stocks_analysis` (`COMPRA`/`VENDI`/`TIENI`).
({String label, BadgeTone tone, IconData icon}) stockActionBadge(String? action) {
  final String act = (action ?? 'HOLD').toUpperCase();
  if (act.contains('BUY') || act.contains('ACCUMULO')) {
    return (label: 'COMPRA', tone: BadgeTone.success, icon: Icons.arrow_upward);
  }
  if (act.contains('SELL') || act.contains('PROFITTO')) {
    return (label: 'VENDI', tone: BadgeTone.danger, icon: Icons.arrow_downward);
  }
  return (label: 'TIENI', tone: BadgeTone.warning, icon: Icons.remove);
}

/// Badge priorità (`Alta` / `Media` / `Opportunità` / `Rischio`).
({String label, BadgeTone tone, IconData icon}) priorityBadge(String? priority) {
  final String prio = (priority ?? 'MEDIA').toUpperCase();
  if (prio.contains('ALTA') || prio.contains('HIGH')) {
    return (label: 'Alta', tone: BadgeTone.danger, icon: Icons.priority_high);
  }
  if (prio.contains('OPPORTUN')) {
    return (
      label: 'Opportunità',
      tone: BadgeTone.success,
      icon: Icons.lightbulb_outline,
    );
  }
  if (prio.contains('RISCH') || prio.contains('RISK')) {
    return (label: 'Rischio', tone: BadgeTone.warning, icon: Icons.warning_amber);
  }
  return (label: 'Media', tone: BadgeTone.primary, icon: Icons.remove);
}

/// Card di un consiglio macro (`advice-card`).
///
/// Riga dell'archivio: overline con data di elaborazione, tag di mercato,
/// badge azione e priorità, follow e un dettaglio espandibile (quadro,
/// strategia, righe titolo, rischi, footer confidenza-orizzonte).
///
/// L'accent laterale distingue il mercato senza usare il verde/rosso semantico
/// (riservato a guadagno/perdita): IT = accento, altri mercati = ciano.
class AdviceCard extends StatefulWidget {
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
  State<AdviceCard> createState() => _AdviceCardState();
}

class _AdviceCardState extends State<AdviceCard> {
  /// Il dettaglio parte aperto (parità con la vista precedente) e si può
  /// comprimere per scorrere l'archivio come un ledger.
  bool _expanded = true;

  void _toggleExpanded() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final Advice advice = widget.advice;
    final bool isIt = advice.market == 'IT';
    final String title = advice.title.isNotEmpty
        ? advice.title
        : (isIt ? 'Borsa Italiana (Piazza Affari)' : 'Wall Street');
    final List<AdviceStockAnalysis> stocks = advice.stocksAnalysis;
    final ({String label, BadgeTone tone, IconData icon}) action =
        macroActionBadge(advice.action);
    final ({String label, BadgeTone tone, IconData icon})? priority =
        stocks.isEmpty ? null : priorityBadge(stocks.first.priority);

    return AppCard(
      accent: true,
      accentColor: isIt ? t.primary : t.cyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _header(context, t, title: title, action: action, priority: priority),
          AnimatedSize(
            duration: AppMotion.effective(context, AppMotion.medium),
            curve: AppMotion.ease,
            alignment: Alignment.topCenter,
            child: _expanded
                ? _detail(context, t, advice, stocks)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  // --- Testata -------------------------------------------------------------

  Widget _header(
    BuildContext context,
    AppTokens t, {
    required String title,
    required ({String label, BadgeTone tone, IconData icon}) action,
    required ({String label, BadgeTone tone, IconData icon})? priority,
  }) {
    final Advice advice = widget.advice;
    final Widget meta = Wrap(
      spacing: AppSpacing.s8,
      runSpacing: AppSpacing.s6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        // Overline con la data di elaborazione del report.
        Text(
          'Analisi elaborata: ${formatDateTime(advice.timestamp)}',
          style: AppText.microFor(t).copyWith(color: t.textMuted),
        ),
        AppMarketTag.forTicker(advice.ticker ?? '', market: advice.market),
        AppBadge(
          label: action.label,
          tone: action.tone,
          icon: Icon(action.icon),
        ),
        if (priority != null)
          AppBadge(
            label: priority.label,
            tone: priority.tone,
            icon: Icon(priority.icon),
            tooltip: 'Priorità del titolo principale del report',
          ),
      ],
    );

    final Widget titleText = Text(
      title,
      style: AppText.cardTitleFor(t).copyWith(fontSize: 16.5, height: 1.3),
    );

    final Widget followButton = AppButton(
      label: widget.followed ? 'Segnato come letto' : 'Segna come letto',
      icon: Icon(widget.followed ? Icons.done_all : Icons.done),
      variant: widget.followed
          ? AppButtonVariant.success
          : AppButtonVariant.ghost,
      size: AppButtonSize.sm,
      loading: widget.followBusy,
      onPressed: widget.followBusy ? null : widget.onToggleFollow,
    );

    final Widget expandToggle = AppIconButton(
      icon: Icon(_expanded ? Icons.unfold_less : Icons.unfold_more),
      tooltip: _expanded ? 'Comprimi dettaglio' : 'Espandi dettaglio',
      semanticLabel: _expanded ? 'Comprimi dettaglio' : 'Espandi dettaglio',
      size: 30,
      iconSize: AppSizes.icon,
      bordered: true,
      onPressed: _toggleExpanded,
    );

    final Widget actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Flexible: a 320px il label del follow va in ellissi, mai overflow.
        Flexible(child: followButton),
        const SizedBox(width: AppSpacing.s6),
        expandToggle,
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        meta,
        const SizedBox(height: AppSpacing.s8),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            if (constraints.maxWidth < 620) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  titleText,
                  const SizedBox(height: AppSpacing.s10),
                  actions,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: titleText),
                const SizedBox(width: AppSpacing.s12),
                actions,
              ],
            );
          },
        ),
      ],
    );
  }

  // --- Dettaglio espandibile -----------------------------------------------

  Widget _detail(
    BuildContext context,
    AppTokens t,
    Advice advice,
    List<AdviceStockAnalysis> stocks,
  ) {
    final String? overview = advice.overview?.trim();
    final String? strategy = advice.strategy?.trim();
    final String? risks = advice.risks?.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: AppSpacing.s14),
        Container(height: AppSizes.rule, color: t.borderSubtle),
        if (overview != null && overview.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.s14),
          _sectionLabel(context, 'Quadro & scenario generale'),
          const SizedBox(height: AppSpacing.s6),
          Text(overview, style: AppText.body(context)),
        ],
        if (strategy != null && strategy.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.s14),
          AppCallout(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _sectionLabel(context, "Strategia operativa & piano d'azione"),
                const SizedBox(height: AppSpacing.s6),
                Text(strategy, style: AppText.body(context)),
              ],
            ),
          ),
        ],
        if (stocks.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.s14),
          _stocksSection(context, t, stocks: stocks),
        ],
        if (risks != null && risks.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.s14),
          AppCallout(
            tone: AppCalloutTone.danger,
            accent: true,
            icon: const Icon(Icons.warning_amber),
            title: 'Punti di attenzione & rischi chiave',
            body: risks,
            padding: const EdgeInsets.all(AppSpacing.s10),
          ),
        ],
        const SizedBox(height: AppSpacing.s14),
        _footer(context, t),
      ],
    );
  }

  Widget _sectionLabel(BuildContext context, String label) {
    return Text(label.toUpperCase(), style: AppText.sectionLabel(context));
  }

  Widget _stocksSection(
    BuildContext context,
    AppTokens t, {
    required List<AdviceStockAnalysis> stocks,
  }) {
    final Widget header = Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.s10,
      runSpacing: AppSpacing.s4,
      children: <Widget>[
        Text(
          'Analisi strategiche prioritizzate (${stocks.length})',
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
          decoration: BoxDecoration(color: t.surfaceSunken),
          children: <Widget>[
            _headerCell(context, 'Ticker & titolo'),
            _headerCell(context, 'Azione', align: TextAlign.center),
            _headerCell(context, 'Priorità', align: TextAlign.center),
            _headerCell(context, 'Target', align: TextAlign.right),
            _headerCell(context, 'Motivo sintetico & catalizzatore'),
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
    final ({String label, BadgeTone tone, IconData icon}) action =
        stockActionBadge(stock.action);
    final ({String label, BadgeTone tone, IconData icon}) priority =
        priorityBadge(stock.priority);

    return <Widget>[
      Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s10,
          vertical: AppSpacing.s10,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: AppSpacing.s6,
              runSpacing: AppSpacing.s4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                _TickerLink(
                  ticker: stock.ticker,
                  onTap: () => widget.onOpenStock(stock.ticker),
                ),
                AppMarketTag.forTicker(stock.ticker),
              ],
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
      _badgeCell(
        context,
        AppBadge(label: action.label, tone: action.tone, icon: Icon(action.icon)),
      ),
      _badgeCell(
        context,
        AppBadge(
          label: priority.label,
          tone: priority.tone,
          icon: Icon(priority.icon),
        ),
      ),
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
          child: AppIconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: 'Apri scheda tecnica',
            semanticLabel: 'Apri scheda tecnica di ${stock.ticker}',
            size: AppSizes.iconButtonSm,
            iconSize: AppSizes.iconSm,
            minTargetSize: AppSizes.touchTarget,
            bordered: true,
            onPressed: () => widget.onOpenStock(stock.ticker),
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
      if ((widget.advice.confidence ?? '').trim().isNotEmpty)
        Text.rich(
          TextSpan(
            style: AppText.caption(context),
            children: <InlineSpan>[
              const TextSpan(text: 'Confidenza IA: '),
              TextSpan(
                text: widget.advice.confidence!.trim(),
                style: TextStyle(color: t.primary, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      if ((widget.advice.timeframe ?? '').trim().isNotEmpty)
        Text.rich(
          TextSpan(
            style: AppText.caption(context),
            children: <InlineSpan>[
              const TextSpan(text: 'Orizzonte: '),
              TextSpan(
                text: widget.advice.timeframe!.trim(),
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
            'Archivio ultimi 7 giorni • Gemini 3.8 Flash',
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
