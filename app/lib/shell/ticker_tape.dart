import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/api/dashboard_api.dart';
import '../core/models/dashboard.dart';
import '../features/stock_detail/stock_detail_modal.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/app_delta.dart';
import '../widgets/app_market_tag.dart';

/// Ticker tape globale (marquee) con gli indici di mercato.
///
/// Linguaggio Registro:
/// - altezza 32px, fondo `surface`, bordo inferiore, velo sfumato sui bordi;
/// - item = tag di mercato + nome + prezzo mono + [AppDelta] firmato, divisi da
///   una riga verticale da 1px (niente emoji bandiera);
/// - scorrimento lineare continuo (translate 0 → -50%, 55s), in pausa su hover;
/// - con `prefers-reduced-motion` nessuna animazione: riga statica scorrevole
///   a mano;
/// - la seconda copia del track è solo decorativa: [ExcludeSemantics] e fuori
///   dalla navigazione da tastiera, ma ancora cliccabile col mouse.
///
/// Con risposta vuota o in errore il widget non occupa spazio (nessun tape
/// vuoto).
class TickerTape extends ConsumerStatefulWidget {
  /// Crea il ticker tape.
  const TickerTape({super.key});

  @override
  ConsumerState<TickerTape> createState() => _TickerTapeState();
}

class _TickerTapeState extends ConsumerState<TickerTape>
    with SingleTickerProviderStateMixin {
  static const Duration _scrollDuration = Duration(seconds: 55);
  static const double _height = 32;

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
        padding: const EdgeInsets.only(left: 12),
        child: Row(mainAxisSize: MainAxisSize.min, children: items),
      );
    } else {
      final Widget copy = Row(mainAxisSize: MainAxisSize.min, children: items);
      final Widget decorativeCopy = Row(
        mainAxisSize: MainAxisSize.min,
        children: decorativeItems,
      );
      content = ClipRect(
        child: AnimatedBuilder(
          animation: _controller,
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            maxWidth: double.infinity,
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
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
      );
    }

    return MouseRegion(
      onEnter: (_) => _pause(),
      onExit: (_) => _resume(),
      child: Container(
        height: _height,
        decoration: BoxDecoration(
          color: t.surface,
          border: Border(bottom: BorderSide(color: t.border)),
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: <Widget>[
            Positioned.fill(child: content),
            // Velo sfumato ai bordi: il nastro entra/esce senza tagli netti.
            _EdgeFade(alignment: Alignment.centerLeft, color: t.surface),
            _EdgeFade(alignment: Alignment.centerRight, color: t.surface),
          ],
        ),
      ),
    );
  }
}

/// Sfumatura di 26px che scioglie il nastro nel fondo del tape.
class _EdgeFade extends StatelessWidget {
  const _EdgeFade({required this.alignment, required this.color});

  final Alignment alignment;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final bool left = alignment == Alignment.centerLeft;
    return Positioned(
      top: 0,
      bottom: 0,
      left: left ? 0 : null,
      right: left ? null : 0,
      width: 26,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: left ? Alignment.centerLeft : Alignment.centerRight,
              end: left ? Alignment.centerRight : Alignment.centerLeft,
              colors: <Color>[color, color.withValues(alpha: 0)],
            ),
          ),
        ),
      ),
    );
  }
}

/// Formattazione it-IT del prezzo nel nastro (stessa lingua dei delta).
final NumberFormat _priceFormat = NumberFormat('#,##0.00', 'it_IT');

/// Singolo elemento del tape: tag di mercato, nome, prezzo e variazione.
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
    final bool highlight = _hovered || _focused;

    return Padding(
      // Margine destro nell'item (non `spacing` di Row): la larghezza di una
      // copia include il gap finale, così il loop a -50% è senza cuciture.
      padding: const EdgeInsets.only(right: AppSpacing.s12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(width: AppSizes.rule, height: 12, color: t.borderSubtle),
          const SizedBox(width: AppSpacing.s12),
          Tooltip(
            message: 'Apri scheda tecnica',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                canRequestFocus: !widget.decorative,
                onHover: (bool value) => setState(() => _hovered = value),
                onFocusChange: (bool value) => setState(() => _focused = value),
                borderRadius: BorderRadius.circular(AppRadii.tag),
                hoverColor: t.surfaceHover,
                focusColor: t.primaryGlow,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      AppMarketTag.forTicker(quote.ticker, type: quote.type),
                      const SizedBox(width: AppSpacing.s8),
                      Text(
                        quote.name.isEmpty ? quote.ticker : quote.name,
                        style: AppText.smallFor(t).copyWith(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: highlight ? t.primary : t.textPrimary,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s8),
                      Text(
                        _priceFormat.format(quote.price),
                        style: AppText.mono(
                          context,
                          size: 12.5,
                          weight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s8),
                      AppDelta(
                        value: quote.changePercent,
                        suffix: '%',
                        size: 11.5,
                        semanticsLabel: 'Variazione ${quote.name}',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
