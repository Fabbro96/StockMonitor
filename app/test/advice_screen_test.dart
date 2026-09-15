import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_monitor/core/api/advice_api.dart';
import 'package:stock_monitor/core/api/stocks_api.dart';
import 'package:stock_monitor/core/api_client.dart';
import 'package:stock_monitor/core/models/advice.dart';
import 'package:stock_monitor/core/models/deep_dive.dart';
import 'package:stock_monitor/features/advice/advice_screen.dart';

Advice _advice(int id) => Advice(
  id: id,
  market: id.isEven ? 'IT' : 'US',
  title: 'Report $id',
  action: 'ACCUMULO',
  overview: 'Quadro $id',
  strategy: 'Strategia $id',
  stocksAnalysis: const <AdviceStockAnalysis>[
    AdviceStockAnalysis(
      ticker: 'ENEL.MI',
      name: 'Enel S.p.A.',
      action: 'BUY',
      priority: 'ALTA',
      targetPrice: 7.5,
      note: 'Nota operativa.',
    ),
  ],
  confidence: 'Media',
  timeframe: 'Breve',
  followed: false,
  timestamp: DateTime(2026, 9, 10),
);

/// Fake della lista/pagina (nessuna richiesta di rete).
class _FakeAdviceApi extends AdviceApi {
  _FakeAdviceApi() : super(ApiClient());

  /// Elementi della prima pagina (piena, così "Carica Altri" è visibile).
  static const int pageSize = 10;

  /// Elementi della seconda pagina (corta: il bottone sparisce).
  static const int nextPageSize = 2;

  final List<int?> skips = <int?>[];

  @override
  Future<List<Advice>> list({
    int? skip,
    int limit = 10,
    int? days,
    String? market,
    String? action,
    String? date,
  }) async {
    skips.add(skip);
    final int base = skip ?? 0;
    final int count = skip == null ? pageSize : nextPageSize;
    return <Advice>[for (int i = 0; i < count; i++) _advice(base + i)];
  }

  @override
  Future<List<Advice>> latest() async => <Advice>[_advice(0)];

  @override
  Future<StockAnalysis> analyzeStock(String ticker) async => StockAnalysis(
    ticker: ticker,
    name: 'Apple Inc.',
    action: 'BUY',
    actionLabel: 'ACCUMULO',
    targetPrice: 240,
    stopLoss: 190,
    upsidePotentialPct: -5.5,
    timeframe: 'Breve',
    confidence: 'Media',
    summary: 'Sintesi dell\'analisi.',
    bullCase: 'Catalizzatori positivi.',
    bearCase: 'Rischi di mercato.',
    operationalStrategy: 'Entrare a step.',
  );
}

/// Fake dei details: valuta USD (per il wiring F7).
class _FakeStocksApi extends StocksApi {
  _FakeStocksApi() : super(ApiClient());

  @override
  Future<StockDetails> details(String ticker) async =>
      StockDetails(ticker: ticker, currency: 'USD');
}

Future<void> _pump(WidgetTester tester, {AdviceApi? adviceApi}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        adviceApiProvider.overrideWithValue(adviceApi ?? _FakeAdviceApi()),
        stocksApiProvider.overrideWithValue(_FakeStocksApi()),
      ],
      child: const MaterialApp(home: Scaffold(body: AdviceScreen())),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('rendering, analisi single-stock in USD e ricerca client-side', (
    tester,
  ) async {
    await _pump(tester);

    expect(
      find.textContaining('Analisi istantanea su singolo titolo'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Analisi strategiche prioritizzate'),
      findsWidgets,
    );
    expect(find.textContaining('ENEL.MI'), findsWidgets);

    // Analisi: Target/Stop nella valuta dei details (USD → `$`) e upside
    // negativo col segno corretto.
    await tester.enterText(find.byType(TextField).first, 'aapl');
    await tester.tap(find.text('Analizza titolo con IA'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining(r'$'), findsWidgets);
    expect(find.textContaining('(-5,50%)'), findsOneWidget);

    // Ricerca client-side senza match → empty state (nessuna GET extra).
    await tester.ensureVisible(find.byType(TextField).last);
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, 'zzzz');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(
      find.textContaining('Nessuna analisi strategica trovata'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Carica Altri visibile con pagina piena, nascosto dopo', (
    tester,
  ) async {
    final fake = _FakeAdviceApi();
    await _pump(tester, adviceApi: fake);
    expect(find.text('Carica Altri'), findsOneWidget);

    await tester.ensureVisible(find.text('Carica Altri'));
    await tester.pump();
    await tester.tap(find.text('Carica Altri'));
    await tester.pump();
    await tester.pump();

    expect(fake.skips, contains(10));
    expect(find.text('Carica Altri'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
