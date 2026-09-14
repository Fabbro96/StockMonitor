import 'package:flutter_test/flutter_test.dart';
import 'package:stock_monitor/core/api/portfolio_api.dart';
import 'package:stock_monitor/core/api_client.dart';
import 'package:stock_monitor/core/models/portfolio.dart';

/// Doppio di [ApiClient]: risposte GET preimpostate per path, senza rete.
class _FakeApiClient extends ApiClient {
  _FakeApiClient({this.getResponses = const <String, Object?>{}});

  /// Payload per path (un path assente restituisce `null`).
  final Map<String, Object?> getResponses;

  /// Path GET ricevuti, in ordine.
  final List<String> getPaths = <String>[];

  @override
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    Duration? receiveTimeout,
  }) async {
    getPaths.add(path);
    return getResponses[path];
  }
}

const String _holdingsPath = '/portfolio/';
const String _transactionsPath = '/portfolio/transactions';
const String _targetsPath = '/portfolio/rebalance/targets';
const String _dividendsPath = '/portfolio/dividends';

void main() {
  group('PortfolioApi guardia array (payload non-lista)', () {
    test('holdings: mappa -> ApiException', () async {
      final _FakeApiClient client = _FakeApiClient(
        getResponses: <String, Object?>{
          _holdingsPath: <String, dynamic>{'detail': 'errore inatteso'},
        },
      );

      await expectLater(
        PortfolioApi(client).holdings(),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.message,
            'message',
            'Risposta holdings non valida.',
          ),
        ),
      );
    });

    test('holdings: null -> ApiException', () async {
      final _FakeApiClient client = _FakeApiClient();

      await expectLater(
        PortfolioApi(client).holdings(),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.message,
            'message',
            'Risposta holdings non valida.',
          ),
        ),
      );
    });

    test('transactions: mappa -> ApiException', () async {
      final _FakeApiClient client = _FakeApiClient(
        getResponses: <String, Object?>{
          _transactionsPath: <String, dynamic>{'transactions': <dynamic>[]},
        },
      );

      await expectLater(
        PortfolioApi(client).transactions(),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.message,
            'message',
            'Risposta transazioni non valida.',
          ),
        ),
      );
    });

    test('rebalanceTargets: mappa -> ApiException', () async {
      final _FakeApiClient client = _FakeApiClient(
        getResponses: <String, Object?>{
          _targetsPath: <String, dynamic>{'targets': <dynamic>[]},
        },
      );

      await expectLater(
        PortfolioApi(client).rebalanceTargets(),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.message,
            'message',
            'Risposta allocazioni target non valida.',
          ),
        ),
      );
    });

    test('dividends: holdings non-lista -> ApiException', () async {
      final _FakeApiClient client = _FakeApiClient(
        getResponses: <String, Object?>{
          _dividendsPath: <String, dynamic>{
            'holdings': <String, dynamic>{'ticker': 'AAPL'},
            'total_annual_dividend_eur': 0.0,
          },
        },
      );

      await expectLater(
        PortfolioApi(client).dividends(),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.message,
            'message',
            'Risposta dividendi non valida.',
          ),
        ),
      );
    });

    test('dividends: holdings assente (payload null) -> ApiException', () async {
      final _FakeApiClient client = _FakeApiClient();

      await expectLater(
        PortfolioApi(client).dividends(),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.message,
            'message',
            'Risposta dividendi non valida.',
          ),
        ),
      );
    });
  });

  group('PortfolioApi parse payload validi', () {
    test('holdings: lista -> righe parseggiate', () async {
      final _FakeApiClient client = _FakeApiClient(
        getResponses: <String, Object?>{
          _holdingsPath: <dynamic>[
            <String, dynamic>{
              'id': 1,
              'stock_id': 2,
              'ticker': 'AAPL',
              'name': 'Apple Inc.',
              'market': 'US',
              'currency': 'USD',
              'quantity': 10.0,
              'avg_purchase_price': 150.0,
              'current_price': 190.0,
              'total_value': 1900.0,
              'total_invested': 1500.0,
              'total_value_eur': 1748.0,
              'total_invested_eur': 1380.0,
              'pnl_absolute': 400.0,
              'pnl_percent': 26.67,
            },
          ],
        },
      );

      final List<Holding> holdings = await PortfolioApi(client).holdings();

      expect(client.getPaths, <String>[_holdingsPath]);
      expect(holdings, hasLength(1));
      expect(holdings.single.ticker, 'AAPL');
      expect(holdings.single.quantity, 10.0);
      expect(holdings.single.totalValueEur, 1748.0);
      expect(holdings.single.purchaseDate, isNull);
    });

    test('transactions: lista -> righe parseggiate', () async {
      final _FakeApiClient client = _FakeApiClient(
        getResponses: <String, Object?>{
          _transactionsPath: <dynamic>[
            <String, dynamic>{
              'id': 4,
              'stock_id': 1,
              'ticker': 'AAPL',
              'name': 'Apple Inc.',
              'type': 'BUY',
              'quantity': 5.0,
              'price': 150.0,
              'fee': 1.5,
              'realized_pnl': null,
              'currency': 'USD',
              'transaction_date': '2026-08-20 14:45:00',
            },
          ],
        },
      );

      final List<Transaction> transactions = await PortfolioApi(
        client,
      ).transactions(type: 'BUY');

      expect(transactions, hasLength(1));
      expect(transactions.single.type, 'BUY');
      expect(transactions.single.realizedPnl, isNull);
      expect(
        transactions.single.transactionDate,
        DateTime(2026, 8, 20, 14, 45),
      );
    });

    test('rebalanceTargets: lista -> target parseggiati', () async {
      final _FakeApiClient client = _FakeApiClient(
        getResponses: <String, Object?>{
          _targetsPath: <dynamic>[
            <String, dynamic>{
              'id': 3,
              'name': 'Italia',
              'target_percent': 60.0,
              'scope_type': 'MARKET',
              'scope_value': 'IT',
            },
          ],
        },
      );

      final List<RebalanceTarget> targets = await PortfolioApi(
        client,
      ).rebalanceTargets();

      expect(targets, hasLength(1));
      expect(targets.single.name, 'Italia');
      expect(targets.single.targetPercent, 60.0);
      expect(targets.single.scopeType, 'MARKET');
      expect(targets.single.scopeValue, 'IT');
    });

    test('dividends: holdings lista -> risultato parseggiato', () async {
      final _FakeApiClient client = _FakeApiClient(
        getResponses: <String, Object?>{
          _dividendsPath: <String, dynamic>{
            'holdings': <dynamic>[
              <String, dynamic>{
                'ticker': 'ENEL.MI',
                'name': 'Enel S.p.A.',
                'market': 'IT',
                'currency': 'EUR',
                'quantity': 400.0,
                'current_price': 7.15,
                'avg_purchase_price': 6.2,
                'dividend_yield_pct': 6.1,
                'yield_on_cost_pct': 7.03,
                'annual_dividend_per_share': 0.44,
                'annual_income_eur': 176.0,
                'monthly_income_eur': 14.67,
              },
            ],
            'total_annual_dividend_eur': 176.0,
            'total_monthly_dividend_eur': 14.67,
            'portfolio_total_value': 2860.0,
            'portfolio_yield_on_cost': 7.03,
          },
        },
      );

      final DividendsResult result = await PortfolioApi(client).dividends();

      expect(result.holdings, hasLength(1));
      expect(result.holdings.single.ticker, 'ENEL.MI');
      expect(result.holdings.single.monthlyIncomeEur, 14.67);
      expect(result.totalAnnualDividendEur, 176.0);
      expect(result.totalMonthlyDividendEur, 14.67);
      expect(result.portfolioYieldOnCost, 7.03);
    });
  });
}
