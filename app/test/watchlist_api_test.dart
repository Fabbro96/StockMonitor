import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_monitor/core/api/watchlist_api.dart';
import 'package:stock_monitor/core/api_client.dart';
import 'package:stock_monitor/core/models/watchlist_item.dart';
import 'package:stock_monitor/features/watchlist/watchlist_providers.dart';

/// Doppio di [ApiClient]: restituisce risposte preimpostate senza rete e
/// registra path/body delle chiamate effettuate.
class _FakeApiClient extends ApiClient {
  _FakeApiClient({this.getResponse, this.postResponse});

  /// Payload restituito da [get] (lista, mappa o null).
  Object? getResponse;

  /// Payload restituito da [post].
  Object? postResponse;

  /// Numero di chiamate [get] ricevute.
  int getCalls = 0;

  /// Numero di chiamate [post] ricevute.
  int postCalls = 0;

  /// Ultimo path passato a [get].
  String? lastGetPath;

  /// Ultimo path passato a [post].
  String? lastPostPath;

  /// Ultimo body passato a [post].
  Object? lastPostBody;

  @override
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    Duration? receiveTimeout,
  }) async {
    getCalls++;
    lastGetPath = path;
    return getResponse;
  }

  @override
  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    Duration? receiveTimeout,
  }) async {
    postCalls++;
    lastPostPath = path;
    lastPostBody = body;
    return postResponse;
  }
}

void main() {
  group('WatchlistApi.list', () {
    test('payload lista: parse degli item e path corretto', () async {
      final _FakeApiClient client = _FakeApiClient(
        getResponse: <dynamic>[
          <String, dynamic>{
            'id': 1,
            'stock_id': 2,
            'ticker': 'AAPL',
            'name': 'Apple Inc.',
            'market': 'US',
            'currency': 'USD',
            'current_price': 190.0,
            'change_percent': 1.2,
            'notes': '',
            'is_in_portfolio': true,
          },
          <String, dynamic>{'id': 3, 'stock_id': 4, 'ticker': 'ENEL.MI'},
        ],
      );

      final List<WatchlistItem> items = await WatchlistApi(client).list();

      expect(client.getCalls, 1);
      expect(client.lastGetPath, '/watchlist/');
      expect(items, hasLength(2));
      expect(items.first.ticker, 'AAPL');
      expect(items.first.currentPrice, 190.0);
      expect(items.first.isInPortfolio, isTrue);
      expect(items.last.ticker, 'ENEL.MI');
    });

    test('payload mappa: ApiException con messaggio chiaro', () async {
      final _FakeApiClient client = _FakeApiClient(
        getResponse: <String, dynamic>{'detail': 'errore inatteso'},
      );

      await expectLater(
        WatchlistApi(client).list(),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.message,
            'message',
            'Risposta watchlist non valida.',
          ),
        ),
      );
    });

    test('payload null: ApiException', () async {
      final _FakeApiClient client = _FakeApiClient();

      await expectLater(
        WatchlistApi(client).list(),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('WatchlistApi.add', () {
    test('status exists: risultato corretto e body inviato', () async {
      final _FakeApiClient client = _FakeApiClient(
        postResponse: <String, dynamic>{
          'status': 'exists',
          'message': 'AAPL è già nella Watchlist (aggiornato)',
          'id': 7,
        },
      );

      final WatchlistMutationResult result = await WatchlistApi(client).add(
        ticker: 'AAPL',
        notes: 'nota',
        alertAbove: 200.0,
        alertBelow: 120.0,
      );

      expect(result.status, 'exists');
      expect(result.message, 'AAPL è già nella Watchlist (aggiornato)');
      expect(result.id, 7);
      expect(client.postCalls, 1);
      expect(client.lastPostPath, '/watchlist/');
      expect(client.lastPostBody, <String, dynamic>{
        'ticker': 'AAPL',
        'notes': 'nota',
        'alert_above': 200.0,
        'alert_below': 120.0,
      });
    });
  });

  group('Watchlist provider (end-to-end con API reale)', () {
    test('payload non-lista: AsyncError, non lista vuota silenziosa', () async {
      final _FakeApiClient client = _FakeApiClient(
        getResponse: <String, dynamic>{'not': 'a list'},
      );
      final ProviderContainer container = ProviderContainer(
        // Niente retry automatico: risposta deterministica in AsyncError.
        retry: (int retryCount, Object error) => null,
        overrides: [apiClientProvider.overrideWithValue(client)],
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
        'Risposta watchlist non valida.',
      );

      final AsyncValue<List<WatchlistItem>> state = container.read(
        watchlistProvider,
      );
      expect(state.hasError, isTrue);
      expect(state.error, isA<ApiException>());
      expect(state.value, isNull);
    });
  });
}
