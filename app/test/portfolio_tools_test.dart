import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_monitor/core/api/portfolio_api.dart';
import 'package:stock_monitor/core/api_client.dart';
import 'package:stock_monitor/core/models/portfolio.dart';
import 'package:stock_monitor/features/portfolio/portfolio_tools_providers.dart';
import 'package:stock_monitor/features/portfolio/rebalancer_section.dart';

/// Fake di [PortfolioApi] con registro transazioni in memoria e preview del
/// Rebalancer controllabile: nessuna rete nei test dei tool del Portafoglio.
class _FakePortfolioApi extends PortfolioApi {
  _FakePortfolioApi() : super(ApiClient());

  /// Registro transazioni simulato.
  final List<Transaction> ledger = <Transaction>[];

  /// Numero di fetch per chiave filtro (`ALL`, `BUY`, ...).
  final Map<String, int> fetchCounts = <String, int>{};

  /// Preview restituita da [rebalancePreview].
  RebalancePreview preview = const RebalancePreview();

  /// True = [rebalancePreview] lancia [ApiException].
  bool failPreview = false;

  int _nextId = 1;

  @override
  Future<List<Transaction>> transactions({String? type}) async {
    final String key = type ?? kAllTransactionsFilter;
    fetchCounts[key] = (fetchCounts[key] ?? 0) + 1;
    return <Transaction>[
      for (final Transaction tx in ledger)
        if (type == null || tx.type == type) tx,
    ];
  }

  @override
  Future<Transaction> createTransaction({
    required String ticker,
    required String type,
    double quantity = 0,
    double price = 0,
    double fee = 0,
    DateTime? transactionDate,
    String? notes,
  }) async {
    final Transaction tx = Transaction(
      id: _nextId++,
      stockId: 1,
      ticker: ticker,
      name: ticker,
      type: type,
      quantity: quantity,
      price: price,
      fee: fee,
      transactionDate: transactionDate,
      notes: notes ?? '',
    );
    ledger.add(tx);
    return tx;
  }

  @override
  Future<List<RebalanceTarget>> rebalanceTargets() async =>
      const <RebalanceTarget>[];

  @override
  Future<RebalancePreview> rebalancePreview(double extraCash) async {
    if (failPreview) throw ApiException('preview non disponibile');
    return preview;
  }
}

ProviderContainer _container(_FakePortfolioApi api) {
  return ProviderContainer(
    // Niente retry automatico: stati deterministici nei test.
    retry: (int retryCount, Object error) => null,
    overrides: [portfolioApiProvider.overrideWithValue(api)],
  );
}

void main() {
  group('transactionsProvider (F4: family auto-dispose)', () {
    test('il family è auto-dispose', () {
      expect(
        transactionsProvider(kAllTransactionsFilter).isAutoDispose,
        isTrue,
      );
      expect(transactionsProvider('BUY').isAutoDispose, isTrue);
    });

    test(
      'filtro rivisto dopo mutazione: ricreato, refetch e dati aggiornati',
      () async {
        final _FakePortfolioApi api = _FakePortfolioApi();
        final ProviderContainer container = _container(api);
        addTearDown(container.dispose);

        // La sezione osserva "Tutte" (primo fetch).
        final subscription = container.listen(
          transactionsProvider(kAllTransactionsFilter),
          (
            AsyncValue<List<Transaction>>? previous,
            AsyncValue<List<Transaction>> next,
          ) {},
        );
        expect(
          await container.read(
            transactionsProvider(kAllTransactionsFilter).future,
          ),
          isEmpty,
        );
        expect(api.fetchCounts[kAllTransactionsFilter], 1);

        // Cambio filtro: "Tutte" perde l'ultimo listener e viene rilasciato.
        subscription.close();
        await container.pump();

        // Nel frattempo arriva una mutazione (es. BUY registrato su un'altra
        // vista filtro).
        await api.createTransaction(
          ticker: 'AAPL',
          type: 'BUY',
          quantity: 1,
          price: 10,
        );

        // Tornando su "Tutte" il provider è stato ricreato: refetch e dato
        // aggiornato (senza il fix resterebbe la lista vuota in cache).
        final subscription2 = container.listen(
          transactionsProvider(kAllTransactionsFilter),
          (
            AsyncValue<List<Transaction>>? previous,
            AsyncValue<List<Transaction>> next,
          ) {},
        );
        final List<Transaction> refreshed = await container.read(
          transactionsProvider(kAllTransactionsFilter).future,
        );
        expect(api.fetchCounts[kAllTransactionsFilter], 2);
        expect(refreshed.map((Transaction tx) => tx.ticker), <String>['AAPL']);
        subscription2.close();
      },
    );

    test(
      'invalidate del family aggiorna anche le altre viste filtro',
      () async {
        final _FakePortfolioApi api = _FakePortfolioApi();
        final ProviderContainer container = _container(api);
        addTearDown(container.dispose);

        final allSubscription = container.listen(
          transactionsProvider(kAllTransactionsFilter),
          (
            AsyncValue<List<Transaction>>? previous,
            AsyncValue<List<Transaction>> next,
          ) {},
        );
        final buySubscription = container.listen(
          transactionsProvider('BUY'),
          (
            AsyncValue<List<Transaction>>? previous,
            AsyncValue<List<Transaction>> next,
          ) {},
        );
        expect(
          await container.read(
            transactionsProvider(kAllTransactionsFilter).future,
          ),
          isEmpty,
        );
        expect(
          await container.read(transactionsProvider('BUY').future),
          isEmpty,
        );

        await api.createTransaction(
          ticker: 'MSFT',
          type: 'BUY',
          quantity: 2,
          price: 100,
        );

        // Stessa chiamata della sezione dopo create/delete.
        container.invalidate(transactionsProvider);

        final List<Transaction> all = await container.read(
          transactionsProvider(kAllTransactionsFilter).future,
        );
        final List<Transaction> buys = await container.read(
          transactionsProvider('BUY').future,
        );
        expect(all.map((Transaction tx) => tx.ticker), <String>['MSFT']);
        expect(buys.map((Transaction tx) => tx.ticker), <String>['MSFT']);
        expect(api.fetchCounts[kAllTransactionsFilter], 2);
        expect(api.fetchCounts['BUY'], 2);

        allSubscription.close();
        buySubscription.close();
      },
    );
  });

  group('Rebalancer preview', () {
    test('calculate: piano vuoto con portfolio_empty', () async {
      final _FakePortfolioApi api = _FakePortfolioApi()
        ..preview = const RebalancePreview(portfolioEmpty: true);
      final ProviderContainer container = _container(api);
      addTearDown(container.dispose);

      final String? error = await container
          .read(rebalancePreviewProvider.notifier)
          .calculate(0);

      expect(error, isNull);
      final RebalancePreview? plan = container
          .read(rebalancePreviewProvider)
          .value;
      expect(plan, isNotNull);
      expect(plan!.portfolioEmpty, isTrue);
      expect(plan.orders, isEmpty);
      expect(container.read(rebalancePreviewProvider).hasError, isFalse);
    });

    test(
      'calculate: errore API → messaggio restituito e stato in errore',
      () async {
        final _FakePortfolioApi api = _FakePortfolioApi()..failPreview = true;
        final ProviderContainer container = _container(api);
        addTearDown(container.dispose);

        final String? error = await container
            .read(rebalancePreviewProvider.notifier)
            .calculate(500);

        expect(error, 'preview non disponibile');
        final AsyncValue<RebalancePreview?> state = container.read(
          rebalancePreviewProvider,
        );
        expect(state.hasError, isTrue);
        expect(state.value, isNull);
      },
    );

    testWidgets('messaggi del piano: portafoglio vuoto e già allineato', (
      WidgetTester tester,
    ) async {
      final _FakePortfolioApi api = _FakePortfolioApi()
        ..preview = const RebalancePreview(portfolioEmpty: true);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [portfolioApiProvider.overrideWithValue(api)],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: RebalancerSection()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Calcola Ordini ➔'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Portafoglio vuoto'), findsOneWidget);

      api.preview = const RebalancePreview();
      await tester.tap(find.text('Calcola Ordini ➔'));
      await tester.pumpAndSettle();
      expect(find.textContaining('già allineato'), findsOneWidget);
    });
  });
}
