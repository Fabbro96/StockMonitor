import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_monitor/core/api/advice_api.dart';
import 'package:stock_monitor/core/api/stocks_api.dart';
import 'package:stock_monitor/core/api_client.dart';
import 'package:stock_monitor/core/formatters.dart';
import 'package:stock_monitor/core/models/advice.dart';
import 'package:stock_monitor/core/models/deep_dive.dart';
import 'package:stock_monitor/features/advice/advice_providers.dart';

Advice _advice(int id, {String market = 'IT'}) => Advice(
  id: id,
  market: market,
  title: 'Report $id',
  action: 'ACCUMULO',
  overview: 'Quadro $id',
  strategy: 'Strategia $id',
  confidence: 'Media',
  timeframe: 'Breve',
  followed: false,
  timestamp: DateTime(2026, 9, 10),
);

/// Fake di [AdviceApi] con pagine controllabili.
///
/// - con `market == 'IT'` la prima pagina è corta (3), altrimenti 10;
/// - `delayNextPage` blocca la pagina di `loadMore` su un [Completer] per
///   simulare una risposta lenta (test F3);
/// - registra `skips`/`markets` per verificare i parametri server.
class _FakeAdviceApi extends AdviceApi {
  _FakeAdviceApi() : super(ApiClient());

  int listCalls = 0;
  final List<int?> skips = <int?>[];
  final List<String?> markets = <String?>[];
  bool delayNextPage = false;
  Completer<List<Advice>>? pendingPage;

  @override
  Future<List<Advice>> list({
    int? skip,
    int limit = 10,
    int? days,
    String? market,
    String? action,
    String? date,
  }) {
    listCalls++;
    skips.add(skip);
    markets.add(market);
    if (skip == null) {
      final int count = market == 'IT' ? 3 : 10;
      return Future<List<Advice>>.value(<Advice>[
        for (int i = 0; i < count; i++) _advice(i, market: market ?? 'IT'),
      ]);
    }
    if (delayNextPage) {
      pendingPage = Completer<List<Advice>>();
      return pendingPage!.future;
    }
    return Future<List<Advice>>.value(<Advice>[_advice(10), _advice(11)]);
  }
}

/// Fake di [StocksApi] per la valuta dei details.
class _FakeStocksApi extends StocksApi {
  _FakeStocksApi({this.currency, this.fails = false}) : super(ApiClient());

  final String? currency;
  final bool fails;

  @override
  Future<StockDetails> details(String ticker) async {
    if (fails) throw ApiException('details non disponibili');
    return StockDetails(ticker: ticker, currency: currency);
  }
}

ProviderContainer _container({AdviceApi? adviceApi, StocksApi? stocksApi}) {
  final ProviderContainer container = ProviderContainer(
    retry: (int retryCount, Object error) => null,
    overrides: [
      if (adviceApi != null) adviceApiProvider.overrideWithValue(adviceApi),
      if (stocksApi != null) stocksApiProvider.overrideWithValue(stocksApi),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('hasMore è true solo se la pagina è piena (limit elementi)', () async {
    final fake = _FakeAdviceApi();
    final container = _container(adviceApi: fake);

    final AdviceListState first = await container.read(
      adviceListProvider.future,
    );
    expect(first.items, hasLength(10));
    expect(first.hasMore, isTrue);

    await container.read(adviceListProvider.notifier).loadMore();
    final AdviceListState afterLoad = container
        .read(adviceListProvider)
        .requireValue;
    expect(afterLoad.items, hasLength(12));
    expect(afterLoad.hasMore, isFalse);

    // Filtro server con pagina corta: niente "Carica Altri".
    container.read(adviceFiltersProvider.notifier).setMarket('IT');
    final AdviceListState filtered = await container.read(
      adviceListProvider.future,
    );
    expect(filtered.items, hasLength(3));
    expect(filtered.hasMore, isFalse);
  });

  test('loadMore accoda la pagina con skip = items.length', () async {
    final fake = _FakeAdviceApi();
    final container = _container(adviceApi: fake);
    await container.read(adviceListProvider.future);

    await container.read(adviceListProvider.notifier).loadMore();

    expect(fake.skips, <int?>[null, 10]);
    final AdviceListState state = container
        .read(adviceListProvider)
        .requireValue;
    expect(state.items.map((Advice a) => a.id), <int>[
      ...List<int>.generate(10, (int i) => i),
      10,
      11,
    ]);
  });

  test('follow override locale senza toccare il payload', () async {
    final fake = _FakeAdviceApi();
    final container = _container(adviceApi: fake);
    await container.read(adviceListProvider.future);

    container.read(adviceListProvider.notifier).setFollowed(3, true);

    final AdviceListState state = container
        .read(adviceListProvider)
        .requireValue;
    final Advice item = state.items.firstWhere((Advice a) => a.id == 3);
    expect(state.isFollowed(item), isTrue);
    expect(item.followed, isFalse);
  });

  test('F3: loadMore scarta la pagina se i filtri cambiano', () async {
    final fake = _FakeAdviceApi();
    final container = _container(adviceApi: fake);
    await container.read(adviceListProvider.future);

    fake.delayNextPage = true;
    final Future<void> stale = container
        .read(adviceListProvider.notifier)
        .loadMore();
    expect(fake.pendingPage, isNotNull, reason: 'pagina in volo');

    // Cambio filtro mentre la pagina è in volo: `build` riparte.
    container.read(adviceFiltersProvider.notifier).setMarket('IT');
    final AdviceListState filtered = await container.read(
      adviceListProvider.future,
    );
    expect(filtered.items, hasLength(3));

    // La pagina del filtro vecchio arriva ora: non deve essere accodata.
    fake.pendingPage!.complete(<Advice>[
      for (int i = 100; i < 110; i++) _advice(i),
    ]);
    await stale;

    final AdviceListState finalState = container
        .read(adviceListProvider)
        .requireValue;
    expect(finalState.items, hasLength(3), reason: 'pagina stale scartata');
    expect(
      finalState.items.map((Advice a) => a.id),
      everyElement(lessThan(100)),
    );
  });

  test(
    'ricerca client-side: la query non rifà la GET, il mercato sì',
    () async {
      final fake = _FakeAdviceApi();
      final container = _container(adviceApi: fake);
      await container.read(adviceListProvider.future);
      final int callsAfterBuild = fake.listCalls;

      container.read(adviceFiltersProvider.notifier).setQuery('nvda');
      await Future<void>.delayed(Duration.zero);
      expect(fake.listCalls, callsAfterBuild, reason: 'query solo client-side');

      container.read(adviceFiltersProvider.notifier).setMarket('US');
      await container.read(adviceListProvider.future);
      expect(fake.listCalls, callsAfterBuild + 1);
      expect(fake.markets.last, 'US');
    },
  );

  test('F7: valuta single-stock dai details con fallback EUR', () async {
    final usd = _container(stocksApi: _FakeStocksApi(currency: 'USD'));
    expect(await usd.read(adviceCurrencyProvider('AAPL').future), 'USD');

    final failing = _container(stocksApi: _FakeStocksApi(fails: true));
    expect(await failing.read(adviceCurrencyProvider('AAPL').future), 'EUR');

    final unsupported = _container(stocksApi: _FakeStocksApi(currency: 'CHF'));
    expect(
      await unsupported.read(adviceCurrencyProvider('AAPL').future),
      'EUR',
    );
  });

  test('F7: formato USD con simbolo e locale it-IT', () async {
    final container = _container(stocksApi: _FakeStocksApi(currency: 'USD'));
    final String currency = await container.read(
      adviceCurrencyProvider('AAPL').future,
    );

    final String formatted = formatCurrency(240, currency: currency);
    expect(formatted, contains(r'$'));
    expect(formatted, isNot(contains('€')));
  });
}
