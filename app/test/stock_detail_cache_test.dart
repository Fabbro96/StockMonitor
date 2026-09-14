import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_monitor/core/api/portfolio_api.dart';
import 'package:stock_monitor/core/api/stocks_api.dart';
import 'package:stock_monitor/core/api_client.dart';
import 'package:stock_monitor/core/models/deep_dive.dart';
import 'package:stock_monitor/core/models/portfolio.dart';
import 'package:stock_monitor/core/models/stock.dart';
import 'package:stock_monitor/features/stock_detail/stock_detail_modal.dart';
import 'package:stock_monitor/widgets/skeleton.dart';

/// Fake di [StocksApi]: candele con breve ritardo per osservare lo spinner,
/// conteggio chiamate per timeframe API (`1m`, `1w`, ...).
class _FakeStocksApi extends StocksApi {
  _FakeStocksApi() : super(ApiClient());

  final Map<String, int> candleCalls = <String, int>{};

  /// Fetch completate per timeframe (il conteggio parte all'avvio).
  final Map<String, int> candleCompletions = <String, int>{};

  @override
  Future<StockDetails> details(String ticker) async => StockDetails(
    ticker: ticker,
    name: 'Apple Inc.',
    currency: 'USD',
    currentPrice: 190.0,
  );

  @override
  Future<List<Candle>> candles(String ticker, String timeframe) async {
    candleCalls[timeframe] = (candleCalls[timeframe] ?? 0) + 1;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    candleCompletions[timeframe] = (candleCompletions[timeframe] ?? 0) + 1;
    return const <Candle>[
      Candle(
        time: '2026-09-01',
        open: 188.0,
        high: 191.0,
        low: 187.0,
        close: 190.0,
        value: 190.0,
        volume: 1000,
      ),
      Candle(
        time: '2026-09-02',
        open: 190.0,
        high: 193.0,
        low: 189.0,
        close: 192.0,
        value: 192.0,
        volume: 1100,
      ),
    ];
  }
}

/// Fake di [PortfolioApi]: nessuna holding (niente linea prezzo medio).
class _FakePortfolioApi extends PortfolioApi {
  _FakePortfolioApi() : super(ApiClient());

  @override
  Future<List<Holding>> holdings() async => <Holding>[];
}

Widget _app(_FakeStocksApi stocks, _FakePortfolioApi portfolio) {
  return ProviderScope(
    overrides: [
      stocksApiProvider.overrideWithValue(stocks),
      portfolioApiProvider.overrideWithValue(portfolio),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => ElevatedButton(
            onPressed: () => showStockDetail(context, 'AAPL'),
            child: const Text('Apri'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('cache candele: revisit di un timeframe senza spinner', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final _FakeStocksApi stocks = _FakeStocksApi();
    await tester.pumpWidget(_app(stocks, _FakePortfolioApi()));
    await tester.tap(find.text('Apri'));
    await tester.pump();

    // Primo caricamento: grafico in spinner.
    expect(find.byType(AppSpinner), findsWidgets);
    await tester.pumpAndSettle();
    expect(find.byType(AppSpinner), findsNothing);
    expect(stocks.candleCalls['1m'], 1);

    // Cambio su timeframe mai visto: spinner, poi una sola fetch.
    await tester.tap(find.text('1S'));
    await tester.pump();
    expect(find.byType(AppSpinner), findsWidgets);
    await tester.pumpAndSettle();
    expect(find.byType(AppSpinner), findsNothing);
    expect(stocks.candleCalls['1w'], 1);

    // Ritorno su 1M (in cache): niente spinner, refresh silenzioso dopo.
    await tester.tap(find.text('1M'));
    await tester.pump();
    expect(find.byType(AppSpinner), findsNothing);
    expect(stocks.candleCompletions['1m'], 1);
    await tester.pumpAndSettle();
    expect(find.byType(AppSpinner), findsNothing);
    expect(stocks.candleCalls['1m'], 2);
    expect(stocks.candleCompletions['1m'], 2);

    expect(tester.takeException(), isNull);
  });
}
