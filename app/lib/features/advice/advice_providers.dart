import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/advice_api.dart';
import '../../core/api/dashboard_api.dart';
import '../../core/api/stocks_api.dart';
import '../../core/api_client.dart';
import '../../core/models/advice.dart';
import '../../core/models/dashboard.dart';
import '../../core/models/deep_dive.dart';

/// Filtri della pagina Consigli.
///
/// [query] è solo client-side (il backend `GET /advice` non supporta `q`):
/// filtra l'accumulato senza rifare richieste. [date]/[market]/[action] sono
/// invece parametri server.
@immutable
class AdviceFilters {
  /// Crea i filtri.
  const AdviceFilters({
    this.date = '',
    this.market = '',
    this.action = '',
    this.query = '',
  });

  /// Data `YYYY-MM-DD` (`''` = tutta la settimana).
  final String date;

  /// Mercato `IT`/`US` (`''` = tutti).
  final String market;

  /// Azione `ACCUMULO`/`MANTENIMENTO`/`PRESA_PROFITTO` (`''` = tutte).
  final String action;

  /// Ricerca client-side su titolo/testi/ticker (`''` = nessuna).
  final String query;

  /// True se almeno un filtro server è attivo.
  bool get hasServerFilters =>
      date.isNotEmpty || market.isNotEmpty || action.isNotEmpty;

  /// Copia con i campi indicati sostituiti.
  AdviceFilters copyWith({
    String? date,
    String? market,
    String? action,
    String? query,
  }) {
    return AdviceFilters(
      date: date ?? this.date,
      market: market ?? this.market,
      action: action ?? this.action,
      query: query ?? this.query,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AdviceFilters &&
        other.date == date &&
        other.market == market &&
        other.action == action &&
        other.query == query;
  }

  @override
  int get hashCode => Object.hash(date, market, action, query);
}

/// Controller dei filtri (stato in memoria, non persistito come il legacy).
class AdviceFiltersController extends Notifier<AdviceFilters> {
  @override
  AdviceFilters build() => const AdviceFilters();

  /// Imposta il filtro data (`YYYY-MM-DD` o `''`).
  void setDate(String value) => state = state.copyWith(date: value);

  /// Imposta il filtro mercato (`IT`/`US` o `''`).
  void setMarket(String value) => state = state.copyWith(market: value);

  /// Imposta il filtro azione (`ACCUMULO`/`MANTENIMENTO`/`PRESA_PROFITTO` o `''`).
  void setAction(String value) => state = state.copyWith(action: value);

  /// Imposta la ricerca client-side.
  void setQuery(String value) => state = state.copyWith(query: value);

  /// Azzera tutti i filtri (`↺ Mostra Tutta la Settimana`).
  void reset() => state = const AdviceFilters();
}

/// Filtri correnti della pagina Consigli.
final adviceFiltersProvider =
    NotifierProvider<AdviceFiltersController, AdviceFilters>(
      AdviceFiltersController.new,
    );

/// Stato della lista consigli paginata.
@immutable
class AdviceListState {
  /// Crea lo stato della lista.
  const AdviceListState({
    this.items = const <Advice>[],
    this.hasMore = false,
    this.loadingMore = false,
    this.followedOverrides = const <int, bool>{},
  });

  /// Consigli accumulati (pagine caricate).
  final List<Advice> items;

  /// True se l'ultima pagina ha restituito esattamente [AdviceListController.pageSize]
  /// elementi (fix bug #8: nessuna euristica sulla pagina grezza).
  final bool hasMore;

  /// True durante il caricamento di una pagina successiva.
  final bool loadingMore;

  /// Stati `followed` aggiornati localmente dopo il toggle, per id.
  final Map<int, bool> followedOverrides;

  /// Stato `followed` effettivo per [advice] (override locale > payload).
  bool isFollowed(Advice advice) {
    final int? id = advice.id;
    if (id == null) return advice.followed;
    return followedOverrides[id] ?? advice.followed;
  }

  /// Copia con i campi indicati sostituiti.
  AdviceListState copyWith({
    List<Advice>? items,
    bool? hasMore,
    bool? loadingMore,
    Map<int, bool>? followedOverrides,
  }) {
    return AdviceListState(
      items: items ?? this.items,
      hasMore: hasMore ?? this.hasMore,
      loadingMore: loadingMore ?? this.loadingMore,
      followedOverrides: followedOverrides ?? this.followedOverrides,
    );
  }
}

/// Carica e pagina i consigli macro (`GET /api/advice/`).
///
/// I filtri server sono osservati con `select`: cambiare la ricerca client-side
/// non rifà la richiesta. [loadMore] accoda la pagina successiva e ripropaga
/// l'eventuale errore al chiamante (toast a carico della schermata).
class AdviceListController extends AsyncNotifier<AdviceListState> {
  /// Dimensione pagina (legacy: 10).
  static const int pageSize = 10;

  /// Finestra archivio richiesta al backend (legacy: 7 giorni).
  static const int archiveDays = 7;

  /// Generation dei filtri: incrementata a ogni `build`.
  ///
  /// [loadMore] la cattura all'inizio e scarta il risultato dopo l'await se
  /// nel frattempo i filtri sono cambiati (stesso pattern delle candele in
  /// stock detail): senza guardia la pagina del filtro vecchio verrebbe
  /// accodata alla lista nuova.
  int _generation = 0;

  @override
  Future<AdviceListState> build() async {
    _generation++;
    final ({String date, String market, String action}) filters = ref.watch(
      adviceFiltersProvider.select(
        (AdviceFilters f) => (date: f.date, market: f.market, action: f.action),
      ),
    );
    final List<Advice> items = await _fetch(skip: null, filters: filters);
    return AdviceListState(items: items, hasMore: items.length == pageSize);
  }

  Future<List<Advice>> _fetch({
    required int? skip,
    required ({String date, String market, String action}) filters,
  }) {
    return ref
        .read(adviceApiProvider)
        .list(
          skip: skip,
          limit: pageSize,
          days: archiveDays,
          date: filters.date.isEmpty ? null : filters.date,
          market: filters.market.isEmpty ? null : filters.market,
          action: filters.action.isEmpty ? null : filters.action,
        );
  }

  /// Carica la pagina successiva accodandola all'accumulato.
  Future<void> loadMore() async {
    final AdviceListState? current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;

    final int generation = _generation;
    state = AsyncData<AdviceListState>(current.copyWith(loadingMore: true));
    try {
      final ({String date, String market, String action}) filters = ref.read(
        adviceFiltersProvider.select(
          (AdviceFilters f) =>
              (date: f.date, market: f.market, action: f.action),
        ),
      );
      final List<Advice> page = await _fetch(
        skip: current.items.length,
        filters: filters,
      );
      // F3: filtri cambiati durante l'await → `build` è ripartita e questa
      // pagina appartiene al filtro vecchio: scartala senza accodarla.
      if (!ref.mounted || generation != _generation) return;
      final AdviceListState latest = state.value ?? current;
      state = AsyncData<AdviceListState>(
        latest.copyWith(
          items: <Advice>[...latest.items, ...page],
          hasMore: page.length == pageSize,
          loadingMore: false,
        ),
      );
    } catch (_) {
      if (ref.mounted && generation == _generation) {
        state = AsyncData<AdviceListState>(
          current.copyWith(loadingMore: false),
        );
      }
      rethrow;
    }
  }

  /// Registra localmente il nuovo stato `followed` dopo il toggle.
  void setFollowed(int id, bool followed) {
    final AdviceListState? current = state.value;
    if (current == null) return;
    state = AsyncData<AdviceListState>(
      current.copyWith(
        followedOverrides: <int, bool>{
          ...current.followedOverrides,
          id: followed,
        },
      ),
    );
  }
}

/// Lista consigli paginata.
final adviceListProvider =
    AsyncNotifierProvider<AdviceListController, AdviceListState>(
      AdviceListController.new,
    );

/// Ultime analisi macro (`GET /api/advice/latest`, ultimi 7 giorni).
///
/// Usate per il testo del "Riassunto Globale del Mercato"; in errore la card
/// mostra il fallback descrittivo, senza toast.
final adviceLatestProvider = FutureProvider<List<Advice>>(
  (Ref ref) => ref.watch(adviceApiProvider).latest(),
);

/// Stato dei mercati per i pallini in topbar.
///
/// Usa l'endpoint leggero `GET /api/dashboard/market-status` invece della
/// dashboard completa. In errore restituisce `null`: [MarketStatusView] ricade
/// sull'orologio locale, come il `checkMarketStatus` legacy che falliva
/// silenziosamente.
final adviceMarketStatusProvider = FutureProvider<MarketStatusInfo?>((
  Ref ref,
) async {
  try {
    return await ref.watch(dashboardApiProvider).marketStatus();
  } catch (_) {
    return null;
  }
});

/// Valuta di Target Price / Stop Loss dell'analisi single-stock (F7).
///
/// Risolta da `GET /stocks/{ticker}/details` in parallelo all'analisi AI:
/// il render parte subito con EUR e si aggiorna quando i details arrivano.
/// Solo EUR/USD sono formattabili da [formatCurrency]: per le altre valute
/// (o se lo stock non è disponibile) si ricade su EUR, come il default legacy.
final adviceCurrencyProvider = FutureProvider.family<String, String>((
  Ref ref,
  String ticker,
) async {
  try {
    final StockDetails details = await ref
        .watch(stocksApiProvider)
        .details(ticker);
    final String currency = details.currency?.trim().toUpperCase() ?? '';
    return (currency == 'EUR' || currency == 'USD') ? currency : 'EUR';
  } catch (_) {
    return 'EUR';
  }
});

/// Generazione macro `POST /advice/generate?force=true` con stato di loading.
class AdviceGenerationController extends Notifier<bool> {
  @override
  bool build() => false;

  /// Genera i report e ricarica lista + riassunto.
  ///
  /// Ritorna il messaggio d'errore (`detail` del backend, es. mercati chiusi)
  /// oppure `null` in caso di successo: il toast è a carico della topbar.
  Future<String?> generate() async {
    if (state) return null;
    state = true;
    try {
      await ref.read(adviceApiProvider).generate(force: true);
      ref.invalidate(adviceListProvider);
      ref.invalidate(adviceLatestProvider);
      return null;
    } on ApiException catch (error) {
      return error.message;
    } catch (_) {
      return 'Errore durante la generazione dell\'analisi';
    } finally {
      if (ref.mounted) state = false;
    }
  }
}

/// True mentre la generazione macro è in corso.
final adviceGenerationProvider =
    NotifierProvider<AdviceGenerationController, bool>(
      AdviceGenerationController.new,
    );
