import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_monitor/core/api/advice_api.dart';
import 'package:stock_monitor/core/api/dashboard_api.dart';
import 'package:stock_monitor/core/api/portfolio_api.dart';
import 'package:stock_monitor/core/api/watchlist_api.dart';
import 'package:stock_monitor/core/api_client.dart';
import 'package:stock_monitor/core/models/advice.dart';
import 'package:stock_monitor/core/models/dashboard.dart';
import 'package:stock_monitor/core/models/parse_utils.dart';
import 'package:stock_monitor/core/models/portfolio.dart';
import 'package:stock_monitor/core/models/stock.dart';
import 'package:stock_monitor/core/models/watchlist_item.dart';
import 'package:stock_monitor/features/dashboard/dashboard_providers.dart';
import 'package:stock_monitor/features/watchlist/watchlist_providers.dart';

/// Fake di [DashboardApi]: dashboard ok, heatmap controllabile.
class _FakeDashboardApi extends DashboardApi {
  _FakeDashboardApi() : super(ApiClient());

  bool failHeatmap = false;

  @override
  Future<DashboardData> dashboard() async {
    return DashboardData(
      portfolioSummary: PortfolioSummary.fromJson(<String, dynamic>{
        'total_value': 1000.0,
        'holdings_count': 1,
      }),
    );
  }

  @override
  Future<List<HeatmapItem>> heatmap() async {
    if (failHeatmap) throw ApiException('heatmap non disponibile');
    return <HeatmapItem>[
      HeatmapItem.fromJson(<String, dynamic>{
        'ticker': 'AAPL',
        'name': 'Apple Inc.',
        'market': 'US',
        'currency': 'USD',
        'current_price': 190.0,
        'change_percent': 1.2,
      }),
    ];
  }
}

/// Fake di [PortfolioApi]: holdings controllabili (fallimento on demand).
class _FakePortfolioApi extends PortfolioApi {
  _FakePortfolioApi() : super(ApiClient());

  bool failHoldings = false;

  @override
  Future<List<Holding>> holdings() async {
    if (failHoldings) throw ApiException('portafoglio non disponibile');
    return <Holding>[
      Holding.fromJson(<String, dynamic>{
        'id': 1,
        'stock_id': 2,
        'ticker': 'AAPL',
        'name': 'Apple Inc.',
        'market': 'US',
        'currency': 'USD',
        'quantity': 3.0,
        'avg_purchase_price': 150.0,
        'current_price': 190.0,
        'pnl_absolute': 120.0,
        'pnl_percent': 26.67,
      }),
    ];
  }
}

/// Fake di [AdviceApi]: nessun consiglio recente.
class _FakeAdviceApi extends AdviceApi {
  _FakeAdviceApi() : super(ApiClient());

  @override
  Future<List<Advice>> latest() async => const <Advice>[];
}

/// Fake di [WatchlistApi] che simula la guardia array del data layer:
/// `list()` lancia [ApiException] su payload non-lista.
class _FailingWatchlistApi extends WatchlistApi {
  _FailingWatchlistApi() : super(ApiClient());

  @override
  Future<List<WatchlistItem>> list() async {
    throw ApiException(
      'Risposta non valida dal server: elenco Watchlist atteso.',
    );
  }
}

/// Fake di [WatchlistApi] con payload valido (lista anche vuota).
class _EmptyWatchlistApi extends WatchlistApi {
  _EmptyWatchlistApi() : super(ApiClient());

  @override
  Future<List<WatchlistItem>> list() async => const <WatchlistItem>[];
}

/// Predicato del toast di errore della dashboard (`dashboard_screen.dart`):
/// scatta con sezioni fallite, load NON silente e `loadCount` cambiato.
bool _dashboardToastSignal(DashboardState? previous, DashboardState next) {
  if (next.failedSections.isEmpty) return false;
  if (next.lastLoadSilent) return false;
  if (previous?.loadCount == next.loadCount) return false;
  return true;
}

void main() {
  group('DashboardController (errori per-sezione)', () {
    test('sezione fallita: render precedente mantenuto e failedSections', () async {
      final _FakeDashboardApi dashboardApi = _FakeDashboardApi();
      final _FakePortfolioApi portfolioApi = _FakePortfolioApi();
      final _FakeAdviceApi adviceApi = _FakeAdviceApi();

      final ProviderContainer container = ProviderContainer(
        retry: (int retryCount, Object error) => null,
        overrides: [
          dashboardApiProvider.overrideWithValue(dashboardApi),
          portfolioApiProvider.overrideWithValue(portfolioApi),
          adviceApiProvider.overrideWithValue(adviceApi),
        ],
      );
      addTearDown(container.dispose);

      // Primo load: tutte le sezioni rispondono.
      final DashboardState first = await container.read(
        dashboardProvider.future,
      );
      expect(first.failedSections, isEmpty);
      expect(first.holdings, isNotNull);
      expect(first.heatmap, isNotNull);
      expect(first.loadCount, 1);

      // Il portafoglio inizia a fallire durante il refresh silente.
      portfolioApi.failHoldings = true;
      await container.read(dashboardProvider.notifier).silentRefresh();

      final DashboardState afterSilent = container
          .read(dashboardProvider)
          .value!;
      // La sezione fallita mantiene esattamente il valore precedente; le
      // sezioni riuscite si aggiornano con i nuovi dati.
      expect(afterSilent.holdings, same(first.holdings));
      expect(afterSilent.heatmap, isNotNull);
      expect(afterSilent.failedSections, <String>['portafoglio']);
      expect(afterSilent.loadCount, 2);
      expect(afterSilent.lastLoadSilent, isTrue);
      // Refresh silente: il segnale di toast della pagina è spento.
      expect(_dashboardToastSignal(first, afterSilent), isFalse);

      // Reload esplicito: il segnale di toast torna attivo.
      await container.read(dashboardProvider.notifier).reload();

      final DashboardState afterReload = container
          .read(dashboardProvider)
          .value!;
      expect(afterReload.failedSections, contains('portafoglio'));
      expect(afterReload.lastLoadSilent, isFalse);
      expect(afterReload.loadCount, 3);
      expect(_dashboardToastSignal(afterSilent, afterReload), isTrue);
      // Anche dopo il reload fallito il render precedente resta.
      expect(afterReload.holdings, isNotNull);
    });

    test('sezione heatmap fallita non tocca le altre sezioni', () async {
      final _FakeDashboardApi dashboardApi = _FakeDashboardApi();
      final _FakePortfolioApi portfolioApi = _FakePortfolioApi();
      final _FakeAdviceApi adviceApi = _FakeAdviceApi();

      final ProviderContainer container = ProviderContainer(
        retry: (int retryCount, Object error) => null,
        overrides: [
          dashboardApiProvider.overrideWithValue(dashboardApi),
          portfolioApiProvider.overrideWithValue(portfolioApi),
          adviceApiProvider.overrideWithValue(adviceApi),
        ],
      );
      addTearDown(container.dispose);

      await container.read(dashboardProvider.future);
      dashboardApi.failHeatmap = true;
      await container.read(dashboardProvider.notifier).silentRefresh();

      final DashboardState state = container.read(dashboardProvider).value!;
      expect(state.failedSections, <String>['heatmap']);
      expect(state.holdings, isNotNull);
      expect(state.advices, isNotNull);
    });
  });

  group('Candle.time (parsing tollerante)', () {
    test('epoch secondi, epoch millisecondi, data ISO e stringa numerica', () {
      final Candle seconds = Candle.fromJson(<String, dynamic>{
        'time': 1726000000,
        'close': 1.5,
      });
      expect(seconds.time, isA<int>());
      expect(seconds.time, 1726000000);
      expect(asInt(seconds.time), 1726000000);

      final Candle milliseconds = Candle.fromJson(<String, dynamic>{
        'time': 1726000000123,
        'close': 1.5,
      });
      expect(milliseconds.time, isA<int>());
      expect(milliseconds.time, 1726000000123);
      expect(asInt(milliseconds.time), 1726000000123);

      final Candle daily = Candle.fromJson(<String, dynamic>{
        'time': '2026-09-12',
        'close': 1.5,
      });
      expect(daily.time, '2026-09-12');
      expect(parseServerDate(daily.time as String), DateTime(2026, 9, 12));

      final Candle numericString = Candle.fromJson(<String, dynamic>{
        'time': '1726000000',
        'close': 1.5,
      });
      expect(numericString.time, '1726000000');
      expect(asInt(numericString.time), 1726000000);
      // Campi numerici mancanti: nessun crash, valori null.
      expect(numericString.open, isNull);
      expect(numericString.volume, isNull);
    });
  });

  group('Watchlist provider (guardia array)', () {
    test('list() che lancia ApiException produce AsyncError, non lista vuota', () async {
      final ProviderContainer container = ProviderContainer(
        retry: (int retryCount, Object error) => null,
        overrides: [
          watchlistApiProvider.overrideWithValue(_FailingWatchlistApi()),
        ],
      );
      addTearDown(container.dispose);

      Object? caught;
      try {
        await container.read(watchlistProvider.future);
      } catch (error) {
        caught = error;
      }

      expect(caught, isA<ApiException>());
      expect(
        (caught! as ApiException).message,
        'Risposta non valida dal server: elenco Watchlist atteso.',
      );

      final AsyncValue<List<WatchlistItem>> state = container.read(
        watchlistProvider,
      );
      expect(state.hasError, isTrue);
      expect(state.error, isA<ApiException>());
      expect(state.value, isNull);
    });

    test('list() valida popola AsyncData (anche con lista vuota)', () async {
      final ProviderContainer container = ProviderContainer(
        retry: (int retryCount, Object error) => null,
        overrides: [
          watchlistApiProvider.overrideWithValue(_EmptyWatchlistApi()),
        ],
      );
      addTearDown(container.dispose);

      final List<WatchlistItem> items = await container.read(
        watchlistProvider.future,
      );
      expect(items, isEmpty);
      expect(container.read(watchlistProvider).hasError, isFalse);
    });
  });
}
