import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/watchlist_api.dart';
import '../../core/models/watchlist_item.dart';

/// Statistiche client-side della Watchlist (parità con `updateStats` legacy).
class WatchlistStats {
  /// Crea le statistiche.
  const WatchlistStats({
    this.count = 0,
    this.gainers = 0,
    this.losers = 0,
    this.activeAlerts = 0,
  });

  /// Numero di titoli nel radar.
  final int count;

  /// Titoli con variazione odierna positiva.
  final int gainers;

  /// Titoli con variazione odierna negativa.
  final int losers;

  /// Titoli con almeno un alert (soglia presente o scattato).
  final int activeAlerts;
}

/// Calcola le 4 stat card della pagina dai titoli caricati.
WatchlistStats computeWatchlistStats(List<WatchlistItem> items) {
  var gainers = 0;
  var losers = 0;
  var activeAlerts = 0;
  for (final WatchlistItem item in items) {
    if (item.changePercent > 0) gainers++;
    if (item.changePercent < 0) losers++;
    if (item.alertAbove != null ||
        item.alertBelow != null ||
        item.alertTriggered) {
      activeAlerts++;
    }
  }
  return WatchlistStats(
    count: items.length,
    gainers: gainers,
    losers: losers,
    activeAlerts: activeAlerts,
  );
}

/// Filtro client-side per ticker o nome, case-insensitive (parità legacy).
///
/// Con [market] valorizzato (`IT`/`US`/`EU`) restringe anche al mercato del
/// titolo, risolto con [watchlistMarketOf] quando il backend non lo espone:
/// gli strumenti non azionari (nessun mercato) restano fuori da ogni bucket e
/// si vedono solo senza filtro.
List<WatchlistItem> filterWatchlistItems(
  List<WatchlistItem> items,
  String query, {
  String? market,
}) {
  final String needle = query.trim().toUpperCase();
  final String? wanted = market?.toUpperCase();
  return <WatchlistItem>[
    for (final WatchlistItem item in items)
      if ((wanted == null || watchlistMarketOf(item) == wanted) &&
          (needle.isEmpty ||
              item.ticker.toUpperCase().contains(needle) ||
              (item.name ?? '').toUpperCase().contains(needle)))
        item,
  ];
}

/// Mercato normalizzato di un titolo (`IT`/`US`/`EU`); `null` per gli
/// strumenti non azionari, che non appartengono a un listino.
///
/// Usa `market` quando presente e riconosciuto, altrimenti ricade sul suffisso
/// del ticker (`.MI` → IT, `.DE`/`.PA`/`.AS` → EU) e infine su `US`, come la
/// risoluzione dei tag di mercato.
String? watchlistMarketOf(WatchlistItem item) {
  final String? explicit = item.market?.toUpperCase();
  if (explicit == 'IT' || explicit == 'US' || explicit == 'EU') return explicit!;
  final String ticker = item.ticker.toUpperCase();
  if (ticker.endsWith('.MI')) return 'IT';
  if (ticker.endsWith('.DE') || ticker.endsWith('.PA') || ticker.endsWith('.AS')) {
    return 'EU';
  }
  if (_isNonEquity(ticker)) return null;
  return 'US';
}

/// True per le forme non azionarie riconosciute dai tag di mercato: coppie
/// crypto (`BTC-USD`), valute (`EURUSD=X`), indici (`^GSPC`) e future (`GC=F`).
bool _isNonEquity(String ticker) {
  return ticker.startsWith('^') ||
      ticker.endsWith('-USD') ||
      ticker.endsWith('-EUR') ||
      ticker.endsWith('=X') ||
      ticker.endsWith('=F');
}

/// Stato della Watchlist con operazioni di mutazione.
///
/// La guardia array (fix bug #7) vive nel data layer: `WatchlistApi.list()`
/// lancia `ApiException` su un payload non-lista, quindi lo stato diventa
/// `AsyncError` (toast + empty + retry) invece di una lista vuota silenziosa.
class WatchlistController extends AsyncNotifier<List<WatchlistItem>> {
  @override
  Future<List<WatchlistItem>> build() => _fetch();

  Future<List<WatchlistItem>> _fetch() =>
      ref.read(watchlistApiProvider).list();

  /// Ricarica la lista mantenendo i dati correnti durante il refresh.
  Future<void> reload() async {
    if (state.value == null) {
      state = const AsyncLoading<List<WatchlistItem>>();
    }
    state = await AsyncValue.guard<List<WatchlistItem>>(_fetch);
  }

  /// Aggiunge un titolo (o aggiorna note/alert se già presente).
  Future<WatchlistMutationResult> add({
    required String ticker,
    String? notes,
    double? alertAbove,
    double? alertBelow,
  }) async {
    final WatchlistMutationResult result = await ref
        .read(watchlistApiProvider)
        .add(
          ticker: ticker,
          notes: notes,
          alertAbove: alertAbove,
          alertBelow: alertBelow,
        );
    await reload();
    return result;
  }

  /// Aggiorna le soglie alert: entrambe le chiavi vengono inviate,
  /// `null` pulisce la soglia (semantica backend).
  Future<void> updateAlert(int id, {double? above, double? below}) async {
    await ref
        .read(watchlistApiProvider)
        .updateAlert(id, above: above, below: below);
    await reload();
  }

  /// Rimuove l'elemento ottimisticamente dallo stato locale dopo la conferma
  /// del server (l'eventuale undo ri-aggiunge e ricarica).
  Future<void> removeItem(int id) async {
    await ref.read(watchlistApiProvider).remove(id);
    final List<WatchlistItem>? current = state.value;
    if (current == null || !ref.mounted) return;
    state = AsyncData<List<WatchlistItem>>(
      <WatchlistItem>[
        for (final WatchlistItem item in current)
          if (item.id != id) item,
      ],
    );
  }

  /// Undo della rimozione: ri-aggiunge ticker/note/alert originali.
  Future<void> restore(WatchlistItem item) async {
    await ref.read(watchlistApiProvider).add(
      ticker: item.ticker,
      notes: item.notes.isEmpty ? null : item.notes,
      alertAbove: item.alertAbove,
      alertBelow: item.alertBelow,
    );
    await reload();
  }
}

/// Lista Watchlist (caricamento + mutazioni).
final AsyncNotifierProvider<WatchlistController, List<WatchlistItem>>
    watchlistProvider =
    AsyncNotifierProvider<WatchlistController, List<WatchlistItem>>(
      WatchlistController.new,
    );

/// Query del filtro `Filtra ticker...` (il debounce di 250ms è nella UI).
class WatchlistFilterController extends Notifier<String> {
  @override
  String build() => '';

  /// Aggiorna la query di filtro.
  void setQuery(String value) {
    if (value == state) return;
    state = value;
  }
}

/// Query corrente del filtro Watchlist.
final NotifierProvider<WatchlistFilterController, String> watchlistFilterProvider =
    NotifierProvider<WatchlistFilterController, String>(
      WatchlistFilterController.new,
    );

/// Mercato selezionato nella toolbar (`null` = tutti i mercati).
class WatchlistMarketFilterController extends Notifier<String?> {
  @override
  String? build() => null;

  /// Aggiorna il filtro di mercato (`IT`/`US`/`EU`, `null` = tutti).
  void select(String? market) {
    if (state == market) return;
    state = market;
  }
}

/// Mercato corrente del filtro Watchlist.
final NotifierProvider<WatchlistMarketFilterController, String?>
    watchlistMarketFilterProvider =
    NotifierProvider<WatchlistMarketFilterController, String?>(
      WatchlistMarketFilterController.new,
    );

/// Lista filtrata (query su ticker/nome + filtro di mercato).
final Provider<List<WatchlistItem>> filteredWatchlistProvider =
    Provider<List<WatchlistItem>>((Ref ref) {
      final List<WatchlistItem> items =
          ref.watch(watchlistProvider).value ?? const <WatchlistItem>[];
      return filterWatchlistItems(
        items,
        ref.watch(watchlistFilterProvider),
        market: ref.watch(watchlistMarketFilterProvider),
      );
    });
