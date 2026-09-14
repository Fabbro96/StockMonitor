import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/dashboard_api.dart';
import '../core/models/dashboard.dart';
import '../features/stock_detail/stock_detail_modal.dart';
import '../theme/tokens.dart';

/// Ticker tape globale (marquee) con gli indici di mercato.
///
/// Parità con `.ticker-tape-container` del frontend HTML:
/// - fetch una sola volta di `GET /api/dashboard/indices`; con risposta vuota
///   o in errore il widget non occupa spazio (nessun tape vuoto);
/// - altezza 36px, sfondo `surface` e bordo inferiore, primo figlio del
///   contenuto subito sotto la topbar;
/// - ogni item è un bottone `flag · nome · prezzo · variazione` (segno `+`
///   quando la variazione è ≥ 0, verde su/rosso giù), click → `showStockDetail`;
/// - scorrimento lineare continuo (translate 0 → -50%, 55s), in pausa su
///   hover;
/// - con `prefers-reduced-motion` nessuna animazione: riga statica
///   scorrevole manualmente;
/// - la seconda copia del track è solo decorativa: [ExcludeSemantics] e fuori
///   dalla navigazione da tastiera, ma ancora cliccabile col mouse.
class TickerTape extends ConsumerStatefulWidget {
  /// Crea il ticker tape.
  const TickerTape({super.key});

  @override
  ConsumerState<TickerTape> createState() => _TickerTapeState();
}

class _TickerTapeState extends ConsumerState<TickerTape>
    with SingleTickerProviderStateMixin {
  static const Duration _scrollDuration = Duration(seconds: 55);
  static const double _height = 36;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _scrollDuration,
  );

  final GlobalKey _trackKey = GlobalKey();

  List<IndexQuote>? _indices;
  double _trackWidth = 0;
  bool _reduceMotion = false;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _syncAnimation();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final List<IndexQuote> indices = await ref
          .read(dashboardApiProvider)
          .indices();
      if (!mounted) return;
      setState(() => _indices = indices);
      _syncAnimation();
      _scheduleMeasure();
    } on Object {
      // Errore silenzioso: niente tape (il contenitore non viene mostrato).
    }
  }

  void _syncAnimation() {
    final bool shouldAnimate =
        !_reduceMotion && !_paused && (_indices?.isNotEmpty ?? false);
    if (shouldAnimate) {
      if (!_controller.isAnimating) _controller.repeat();
    } else if (_controller.isAnimating) {
      _controller.stop();
    }
  }

  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted) return;
      final Size? size = _trackKey.currentContext?.size;
      if (size == null) return;
      if ((size.width - _trackWidth).abs() < 0.5) return;
      setState(() => _trackWidth = size.width);
    });
  }

  void _pause() {
    _paused = true;
    _syncAnimation();
  }

  void _resume() {
    _paused = false;
    _syncAnimation();
  }

  void _openStock(String ticker) {
    if (ticker.isEmpty) return;
    unawaited(showStockDetail(context, ticker));
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final List<IndexQuote>? indices = _indices;
    if (indices == null || indices.isEmpty) return const SizedBox.shrink();

    final List<Widget> items = <Widget>[
      for (final IndexQuote quote in indices)
        _TickerItem(quote: quote, onTap: () => _openStock(quote.ticker)),
    ];
    final List<Widget> decorativeItems = <Widget>[
      for (final IndexQuote quote in indices)
        _TickerItem(
          quote: quote,
          decorative: true,
          onTap: () => _openStock(quote.ticker),
        ),
    ];

    final Widget content;
    if (_reduceMotion) {
      // Nessuna animazione: riga statica scorrevole a mano, senza copia
      // decorativa (non serve al loop).
      content = SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(mainAxisSize: MainAxisSize.min, children: items),
      );
    } else {
      final Widget copy = Row(mainAxisSize: MainAxisSize.min, children: items);
      final Widget decorativeCopy = Row(
        mainAxisSize: MainAxisSize.min,
        children: decorativeItems,
      );
      content = ClipRect(
        child: MouseRegion(
          onEnter: (_) => _pause(),
          onExit: (_) => _resume(),
          child: AnimatedBuilder(
            animation: _controller,
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              maxWidth: double.infinity,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  key: _trackKey,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    copy,
                    ExcludeSemantics(child: decorativeCopy),
                  ],
                ),
              ),
            ),
            builder: (BuildContext context, Widget? child) {
              final double offset = _trackWidth * 0.5 * _controller.value;
              return Transform.translate(
                offset: Offset(-offset, 0),
                child: child,
              );
            },
          ),
        ),
      );
    }

    return Container(
      height: _height,
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      clipBehavior: Clip.hardEdge,
      child: content,
    );
  }
}

/// Singolo elemento del tape: pill con bandiera, nome, prezzo e variazione.
///
/// Con [decorative] l'item resta visivamente e cliccabilmente identico ma non
/// è focusabile (usato per la seconda copia del loop).
class _TickerItem extends StatefulWidget {
  const _TickerItem({
    required this.quote,
    required this.onTap,
    this.decorative = false,
  });

  final IndexQuote quote;
  final VoidCallback onTap;
  final bool decorative;

  @override
  State<_TickerItem> createState() => _TickerItemState();
}

class _TickerItemState extends State<_TickerItem> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final IndexQuote quote = widget.quote;
    final bool up = quote.changePercent >= 0;
    final String change =
        '${up ? '+' : ''}${quote.changePercent.toStringAsFixed(2)}%';
    final String flag = quote.flag.isNotEmpty ? quote.flag : '📊';
    final bool highlight = _hovered || _focused;

    return Padding(
      // Margine destro nell'item (non `spacing` di Row): la larghezza di una
      // copia include il gap finale, così il loop a -50% è senza cuciture.
      padding: const EdgeInsets.only(right: AppSpacing.s10),
      child: Tooltip(
        message: 'Apri scheda tecnica',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: t.surfaceHover,
            border: Border.all(color: highlight ? t.primary : t.borderSubtle),
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              canRequestFocus: !widget.decorative,
              onHover: (bool value) => setState(() => _hovered = value),
              onFocusChange: (bool value) => setState(() => _focused = value),
              borderRadius: BorderRadius.circular(AppRadii.pill),
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(flag, style: const TextStyle(fontSize: 12.8)),
                  const SizedBox(width: 7),
                  Text(
                    quote.name,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 12.8,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                      fontFamilyFallback: AppTokens.fontFallback,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    quote.price.toStringAsFixed(2),
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 12.8,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                      fontFamily: AppTokens.monoFontFamily,
                      fontFamilyFallback: AppTokens.monoFontFallback,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    change,
                    style: TextStyle(
                      color: up ? t.successText : t.danger,
                      fontSize: 11.8,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                      fontFamily: AppTokens.monoFontFamily,
                      fontFamilyFallback: AppTokens.monoFontFallback,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
