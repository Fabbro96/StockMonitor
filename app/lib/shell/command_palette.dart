import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api/stocks_api.dart';
import '../core/models/stock.dart';
import '../features/stock_detail/stock_detail_modal.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../theme/tokens.dart';
import '../widgets/app_market_tag.dart';
import '../widgets/badges.dart';
import '../widgets/skeleton.dart';
import 'shortcuts_help.dart';

/// Apre la Command Palette globale (ricerca titoli, indici e navigazione
/// rapida; scorciatoia `Ctrl/Cmd+K` o `/`).
///
/// Linguaggio Registro: pannello `surfaceRaised` con raggio 10, campo di
/// ricerca a 42px con anello d'accento, gruppi `NAVIGAZIONE` / `AZIONI` /
/// `TITOLI`, righe a 44px con tag di mercato e scorciatoie a destra.
///
/// Comportamento invariato rispetto alla palette storica:
/// - backdrop cliccabile e `esc` chiudono; card max 620px allineata in alto
///   (10vh, 6vh sotto 640px), corpo max 380px (60vh su mobile);
/// - input autofocus con debounce 300ms su `GET /stocks/search` e guardia
///   anti-stale; i risultati locali restano visibili se la ricerca remota
///   fallisce (fallback silenzioso, merge max 8);
/// - ↑/↓ con wrap, ↵ esegue, esc chiude, click esegue;
/// - stock → `showStockDetail`, nav → `context.go`, tema →
///   [themeControllerProvider], help → [showShortcutsHelp].
Future<void> showAppCommandPalette(BuildContext context) {
  final AppTokens t = context.tokens;
  final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: t.scrim,
    barrierLabel: 'Chiudi command palette',
    transitionDuration: reduceMotion ? Duration.zero : AppMotion.overlay,
    pageBuilder: (
      BuildContext dialogContext,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
    ) => _CommandPalette(hostContext: context),
    transitionBuilder:
        (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
          Widget child,
        ) {
          if (reduceMotion) return child;
          final Animation<double> curved = CurvedAnimation(
            parent: animation,
            curve: AppMotion.ease,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.02),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
  );
}

/// Azione associata a una voce della palette.
enum _PaletteAction { navigate, themeToggle, shortcutsHelp, stock }

/// Gruppo di appartenenza della voce (guida le intestazioni e l'ordine).
enum _PaletteGroup { navigation, action, stock }

/// Voce selezionabile della palette (navigazione, azione rapida o titolo).
class _PaletteEntry {
  const _PaletteEntry({
    required this.action,
    required this.group,
    required this.title,
    this.icon,
    this.description = '',
    this.shortcut,
    this.path,
    this.name,
    this.ticker,
    this.market,
  });

  final _PaletteAction action;
  final _PaletteGroup group;
  final IconData? icon;
  final String title;
  final String description;
  final String? shortcut;
  final String? path;
  final String? name;
  final String? ticker;
  final String? market;

  bool get isStock => action == _PaletteAction.stock;
}

/// Titolo/indice noto mostrato a query vuota (parità con `DEFAULT_POPULAR_STOCKS`).
class _PopularStock {
  const _PopularStock({
    required this.ticker,
    required this.name,
    required this.market,
  });

  final String ticker;
  final String name;
  final String market;
}

/// Destinazioni di navigazione, nello stesso ordine della sidebar.
const List<_PaletteEntry> _navigationEntries = <_PaletteEntry>[
  _PaletteEntry(
    action: _PaletteAction.navigate,
    group: _PaletteGroup.navigation,
    icon: Icons.space_dashboard_outlined,
    title: 'Dashboard',
    description: 'Panoramica patrimonio, indici globali e heatmap',
    shortcut: 'D',
    path: '/dashboard',
  ),
  _PaletteEntry(
    action: _PaletteAction.navigate,
    group: _PaletteGroup.navigation,
    icon: Icons.travel_explore,
    title: 'Mercati',
    description: 'Watchlist e radar: titoli osservati e alert prezzi',
    shortcut: 'W',
    path: '/watchlist',
  ),
  _PaletteEntry(
    action: _PaletteAction.navigate,
    group: _PaletteGroup.navigation,
    icon: Icons.account_balance_wallet_outlined,
    title: 'Portafoglio',
    description: 'Holdings, trade ledger, dividendi e ribilanciamento',
    shortcut: 'P',
    path: '/portfolio',
  ),
  _PaletteEntry(
    action: _PaletteAction.navigate,
    group: _PaletteGroup.navigation,
    icon: Icons.insights_outlined,
    title: 'Analisi',
    description: 'Consigli IA, report di intelligence e sentiment',
    shortcut: 'C',
    path: '/advice',
  ),
  _PaletteEntry(
    action: _PaletteAction.navigate,
    group: _PaletteGroup.navigation,
    icon: Icons.tune,
    title: 'Impostazioni',
    description: 'Budget, strategia, notifiche e configurazione',
    shortcut: 'S',
    path: '/settings',
  ),
];

/// Azioni rapide (non navigano): tema e guida scorciatoie.
const List<_PaletteEntry> _actionEntries = <_PaletteEntry>[
  _PaletteEntry(
    action: _PaletteAction.themeToggle,
    group: _PaletteGroup.action,
    icon: Icons.brightness_6_outlined,
    title: 'Alterna Tema (Chiaro/Scuro)',
    description: 'Passa al tema chiaro o scuro',
    shortcut: 'T',
  ),
  _PaletteEntry(
    action: _PaletteAction.shortcutsHelp,
    group: _PaletteGroup.action,
    icon: Icons.keyboard_outlined,
    title: 'Scorciatoie Tastiera',
    description: 'Visualizza tutte le scorciatoie disponibili',
    shortcut: '?',
  ),
];

/// Voci cercabili: navigazione prima delle azioni, come nell'ordine mostrato.
const List<_PaletteEntry> _navEntries = <_PaletteEntry>[
  ..._navigationEntries,
  ..._actionEntries,
];

const List<_PopularStock> _popularStocks = <_PopularStock>[
  _PopularStock(ticker: 'FTSEMIB.MI', name: 'FTSE MIB', market: 'IT'),
  _PopularStock(ticker: '^GSPC', name: 'S&P 500', market: 'US'),
  _PopularStock(ticker: '^IXIC', name: 'NASDAQ', market: 'US'),
  _PopularStock(ticker: 'BTC-USD', name: 'Bitcoin', market: 'CRYPTO'),
  _PopularStock(ticker: 'GC=F', name: 'Oro (Futures)', market: 'COMMODITY'),
  _PopularStock(ticker: 'RACE.MI', name: 'Ferrari N.V.', market: 'IT'),
  _PopularStock(ticker: 'ENEL.MI', name: 'Enel S.p.A.', market: 'IT'),
  _PopularStock(ticker: 'AAPL', name: 'Apple Inc.', market: 'US'),
  _PopularStock(ticker: 'NVDA', name: 'NVIDIA Corp.', market: 'US'),
];

_PaletteEntry _stockEntry({
  required String ticker,
  required String name,
  required String market,
}) => _PaletteEntry(
  action: _PaletteAction.stock,
  group: _PaletteGroup.stock,
  title: ticker,
  name: name,
  ticker: ticker,
  market: market,
);

class _CommandPalette extends ConsumerStatefulWidget {
  const _CommandPalette({required this.hostContext});

  /// Context della shell, usato per navigare/aprire la scheda titolo dopo
  /// la chiusura della palette.
  final BuildContext hostContext;

  @override
  ConsumerState<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends ConsumerState<_CommandPalette> {
  static const Duration _debounceDelay = Duration(milliseconds: 300);
  static const int _maxResults = 8;

  final TextEditingController _query = TextEditingController();
  final FocusNode _inputFocus = FocusNode(debugLabel: 'command-palette-input');
  final ScrollController _scroll = ScrollController();
  final Map<int, GlobalKey> _itemKeys = <int, GlobalKey>{};

  Timer? _debounce;
  int _searchSeq = 0;
  String _queryText = '';
  bool _searchPending = false;
  bool _inputFocused = false;
  List<_PaletteEntry> _navMatches = const <_PaletteEntry>[];
  List<_PaletteEntry> _stockMatches = const <_PaletteEntry>[];
  List<_PaletteEntry> _entries = const <_PaletteEntry>[];
  int _activeIndex = 0;

  @override
  void initState() {
    super.initState();
    _inputFocus.addListener(_onInputFocusChanged);
    _showEmptyQuery();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _inputFocus.removeListener(_onInputFocusChanged);
    _query.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onInputFocusChanged() {
    if (_inputFocus.hasFocus == _inputFocused) return;
    setState(() => _inputFocused = _inputFocus.hasFocus);
  }

  void _showEmptyQuery() {
    _queryText = '';
    _searchPending = false;
    _navMatches = _navEntries;
    _stockMatches = _popularStocks
        .map(
          (_PopularStock s) => _stockEntry(
            ticker: s.ticker,
            name: s.name,
            market: s.market,
          ),
        )
        .toList(growable: false);
    _syncEntries(resetSelection: true);
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final String query = value.trim();
    _queryText = query;

    if (query.isEmpty) {
      setState(_showEmptyQuery);
      return;
    }

    final String lower = query.toLowerCase();
    final List<_PaletteEntry> nav = _navEntries
        .where(
          (_PaletteEntry entry) =>
              entry.title.toLowerCase().contains(lower) ||
              entry.description.toLowerCase().contains(lower) ||
              entry.shortcut?.toLowerCase() == lower,
        )
        .toList(growable: false);

    if (lower.length < 2) {
      setState(() {
        _searchPending = false;
        _navMatches = nav;
        _stockMatches = const <_PaletteEntry>[];
        _syncEntries(resetSelection: true);
      });
      return;
    }

    final List<_PaletteEntry> local = _popularStocks
        .where(
          (_PopularStock s) =>
              s.ticker.toLowerCase().contains(lower) ||
              s.name.toLowerCase().contains(lower),
        )
        .map(
          (_PopularStock s) => _stockEntry(
            ticker: s.ticker,
            name: s.name,
            market: s.market,
          ),
        )
        .take(_maxResults)
        .toList(growable: false);

    setState(() {
      _searchPending = true;
      _navMatches = nav;
      _stockMatches = local;
      _syncEntries(resetSelection: true);
    });

    _debounce = Timer(_debounceDelay, () => unawaited(_searchRemote(query)));
  }

  Future<void> _searchRemote(String query) async {
    final int seq = ++_searchSeq;
    final String lower = query.toLowerCase();
    try {
      final List<StockSearchResult> results = await ref
          .read(stocksApiProvider)
          .search(query);
      if (!mounted || seq != _searchSeq || lower != _queryText.toLowerCase()) {
        return;
      }
      setState(() {
        _searchPending = false;
        final List<_PaletteEntry> merged = <_PaletteEntry>[..._stockMatches];
        for (final StockSearchResult result in results) {
          if (merged.length >= _maxResults) break;
          if (result.ticker.isEmpty) continue;
          if (merged.any(
            (_PaletteEntry entry) => entry.ticker == result.ticker,
          )) {
            continue;
          }
          merged.add(
            _stockEntry(
              ticker: result.ticker,
              name: result.name,
              market: result.market,
            ),
          );
        }
        _stockMatches = merged;
        _syncEntries();
      });
    } on Object {
      // Fallback silenzioso: restano i risultati locali già mostrati.
      if (!mounted || seq != _searchSeq || lower != _queryText.toLowerCase()) {
        return;
      }
      setState(() => _searchPending = false);
    }
  }

  /// Ricompone la lista selezionabile.
  ///
  /// [resetSelection] riporta la selezione sulla prima voce: va usato quando
  /// cambia la query (parità con `app.js:1414`), non quando arrivano i
  /// risultati remoti (l'utente può aver già navigato la lista).
  void _syncEntries({bool resetSelection = false}) {
    _entries = <_PaletteEntry>[..._navMatches, ..._stockMatches];
    if (resetSelection) _activeIndex = 0;
    if (_activeIndex >= _entries.length) _activeIndex = 0;
  }

  void _moveSelection(int delta) {
    if (_entries.isEmpty) return;
    setState(() {
      _activeIndex = (_activeIndex + delta + _entries.length) % _entries.length;
    });
    _ensureActiveVisible();
  }

  void _ensureActiveVisible() {
    final GlobalKey? key = _itemKeys[_activeIndex];
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      final BuildContext? itemContext = key?.currentContext;
      if (itemContext == null) return;
      Scrollable.ensureVisible(
        itemContext,
        alignment: 0.5,
        duration: AppMotion.effective(context, AppMotion.fast),
        curve: AppMotion.ease,
      );
    });
  }

  void _executeActive() {
    if (_entries.isEmpty) return;
    _execute(_entries[_activeIndex]);
  }

  void _close() {
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _execute(_PaletteEntry entry) {
    final BuildContext host = widget.hostContext;
    Navigator.of(context).pop();
    switch (entry.action) {
      case _PaletteAction.themeToggle:
        unawaited(ref.read(themeControllerProvider.notifier).toggle());
      case _PaletteAction.shortcutsHelp:
        unawaited(showShortcutsHelp(host));
      case _PaletteAction.navigate:
        final String? path = entry.path;
        if (path != null) host.go(path);
      case _PaletteAction.stock:
        final String? ticker = entry.ticker;
        if (ticker != null && ticker.isNotEmpty) {
          unawaited(showStockDetail(host, ticker));
        }
    }
  }

  void _trapFocus() {
    _inputFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool compact = context.isCompact;
    final Size screen = MediaQuery.sizeOf(context);
    final double topInset = screen.height * (compact ? 0.06 : 0.10);
    final double bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Semantics(
      namesRoute: true,
      label: 'Command Palette',
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.only(
            top: topInset,
            left: 16,
            right: 16,
            bottom: 16 + bottomInset,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 620,
              maxHeight: screen.height * 0.8,
            ),
            child: CallbackShortcuts(
              bindings: <ShortcutActivator, VoidCallback>{
                const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                    _moveSelection(1),
                const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                    _moveSelection(-1),
                const SingleActivator(LogicalKeyboardKey.escape): _close,
                const SingleActivator(LogicalKeyboardKey.tab): _trapFocus,
                const SingleActivator(LogicalKeyboardKey.tab, shift: true):
                    _trapFocus,
              },
              child: Container(
                decoration: BoxDecoration(
                  color: t.surfaceRaised,
                  border: Border.all(color: t.border),
                  borderRadius: BorderRadius.circular(AppRadii.sheet),
                  boxShadow: t.shadowLg,
                ),
                clipBehavior: Clip.antiAlias,
                child: Material(
                  color: Colors.transparent,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _header(t),
                      Flexible(child: _body(t, compact)),
                      _footer(t),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(AppTokens t) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: AnimatedContainer(
              duration: AppMotion.effective(context, AppMotion.fast),
              curve: AppMotion.ease,
              height: AppSizes.controlLg,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: t.surface,
                border: Border.all(
                  color: _inputFocused ? t.primary : t.border,
                ),
                borderRadius: BorderRadius.circular(AppRadii.control),
                boxShadow: _inputFocused
                    ? <BoxShadow>[
                        BoxShadow(
                          color: t.focusRing,
                          blurRadius: 0,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.search,
                    size: AppSizes.icon,
                    color: _inputFocused ? t.primary : t.textMuted,
                  ),
                  const SizedBox(width: AppSpacing.s10),
                  Expanded(
                    child: TextField(
                      controller: _query,
                      focusNode: _inputFocus,
                      autofocus: true,
                      onChanged: _onQueryChanged,
                      onSubmitted: (_) => _executeActive(),
                      textInputAction: TextInputAction.done,
                      style: AppText.bodyFor(t).copyWith(fontSize: 15),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        hintText:
                            'Cerca titolo, ticker o naviga (es. AAPL, RACE, Portafoglio)...',
                        hintStyle: AppText.bodyFor(t)
                            .copyWith(fontSize: 15, color: t.textMuted),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s10),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(onTap: _close, child: const AppKbd('esc')),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(AppTokens t, bool compact) {
    final double maxHeight = compact
        ? MediaQuery.sizeOf(context).height * 0.6
        : 380;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: _entries.isNotEmpty
            ? _results(t)
            : (_searchPending ? _pending() : _emptyResult(t)),
      ),
    );
  }

  Widget _pending() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 22),
      child: Center(child: AppSpinner(size: 22)),
    );
  }

  Widget _emptyResult(AppTokens t) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 32),
      child: Center(
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 5,
          children: <Widget>[
            Text(
              'Nessun risultato trovato per "$_queryText". Premi',
              style: AppText.caption(context),
            ),
            const AppKbd('esc'),
            Text('per chiudere.', style: AppText.caption(context)),
          ],
        ),
      ),
    );
  }

  Widget _results(AppTokens t) {
    final List<_PaletteEntry> navigation = _navMatches
        .where((_PaletteEntry e) => e.group == _PaletteGroup.navigation)
        .toList(growable: false);
    final List<_PaletteEntry> actions = _navMatches
        .where((_PaletteEntry e) => e.group == _PaletteGroup.action)
        .toList(growable: false);

    final List<Widget> children = <Widget>[];
    int index = 0;
    void addCategory(String label, List<_PaletteEntry> entries) {
      if (entries.isEmpty) return;
      if (children.isNotEmpty) children.add(const SizedBox(height: AppSpacing.s6));
      children.add(_category(t, label));
      for (final _PaletteEntry entry in entries) {
        children.add(_item(entry, index++));
      }
    }

    addCategory('NAVIGAZIONE', navigation);
    addCategory('AZIONI', actions);
    addCategory(
      _queryText.isEmpty ? 'TITOLI' : 'TITOLI CORRISPONDENTI',
      _stockMatches,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _category(AppTokens t, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Text(label, style: AppText.microFor(t).copyWith(color: t.textFaint)),
    );
  }

  Widget _item(_PaletteEntry entry, int index) {
    final GlobalKey key = _itemKeys.putIfAbsent(index, () => GlobalKey());
    return _PaletteItemTile(
      key: key,
      entry: entry,
      active: index == _activeIndex,
      onTap: () => _execute(entry),
    );
  }

  Widget _footer(AppTokens t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: t.surfaceSunken,
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                _hint(t, '↑↓', 'Naviga'),
                _hint(t, '↵', 'Seleziona'),
                _hint(t, 'esc', 'Chiudi'),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s10),
          Text(
            'Stock Monitor Spotlight',
            style: AppText.mono(context, size: 11.5, weight: FontWeight.w400, color: t.textFaint),
          ),
        ],
      ),
    );
  }

  Widget _hint(AppTokens t, String kbd, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AppKbd(kbd),
        const SizedBox(width: 5),
        Text(
          label,
          style: AppText.captionFor(t).copyWith(fontSize: 11.8),
        ),
      ],
    );
  }
}

/// Riga della palette: fondo `surfaceHover` su hover o selezione, barra
/// d'accento da 2px clippata a sinistra quando è la voce attiva.
class _PaletteItemTile extends StatefulWidget {
  const _PaletteItemTile({
    super.key,
    required this.entry,
    required this.active,
    required this.onTap,
  });

  final _PaletteEntry entry;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_PaletteItemTile> createState() => _PaletteItemTileState();
}

class _PaletteItemTileState extends State<_PaletteItemTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool highlighted = widget.active || _hovered;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Container(
        decoration: BoxDecoration(
          color: highlighted ? t.surfaceHover : Colors.transparent,
          border: Border.all(
            color: highlighted ? t.border : Colors.transparent,
          ),
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: <Widget>[
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                // La selezione nella palette è gestita da input + frecce:
                // niente focus traversal invisibile sugli item.
                canRequestFocus: false,
                onHover: (bool value) => setState(() => _hovered = value),
                borderRadius: BorderRadius.circular(AppRadii.control),
                hoverColor: Colors.transparent,
                focusColor: Colors.transparent,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: widget.entry.isStock ? _stockRow(t) : _navRow(t),
                  ),
                ),
              ),
            ),
            if (widget.active)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: AppSizes.accentStrip,
                child: ColoredBox(color: t.primary),
              ),
          ],
        ),
      ),
    );
  }

  Widget _navRow(AppTokens t) {
    final _PaletteEntry entry = widget.entry;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        SizedBox(
          width: 22,
          child: Icon(
            entry.icon ?? Icons.chevron_right,
            size: AppSizes.icon,
            color: t.textSecondary,
          ),
        ),
        const SizedBox(width: AppSpacing.s10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                entry.title,
                style: AppText.bodyFor(t).copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                entry.description,
                style: AppText.caption(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (entry.shortcut != null) ...<Widget>[
          const SizedBox(width: AppSpacing.s10),
          AppKbd(entry.shortcut!),
        ],
      ],
    );
  }

  Widget _stockRow(AppTokens t) {
    final _PaletteEntry entry = widget.entry;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        SizedBox(
          width: 58,
          child: Align(
            alignment: Alignment.centerLeft,
            child: AppMarketTag.forTicker(
              entry.ticker ?? entry.title,
              market: entry.market,
              tooltip: entry.market,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.s10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(
                      text: entry.title,
                      style: AppText.mono(context, size: 14, weight: FontWeight.w600),
                    ),
                    TextSpan(
                      text: entry.name == null ? '' : '  —  ${entry.name}',
                      style: AppText.caption(context),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'Apri analisi fondamentale, RSI, grafici e scheda titolo',
                style: AppText.caption(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.s10),
        const AppKbd('↵'),
      ],
    );
  }
}
