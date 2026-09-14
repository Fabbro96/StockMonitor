import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:stock_monitor/core/api/portfolio_api.dart';
import 'package:stock_monitor/core/api/settings_api.dart';
import 'package:stock_monitor/core/api/stocks_api.dart';
import 'package:stock_monitor/core/api_client.dart';
import 'package:stock_monitor/core/models/portfolio.dart';
import 'package:stock_monitor/core/models/settings.dart';
import 'package:stock_monitor/core/models/stock.dart';
import 'package:stock_monitor/features/portfolio/portfolio_providers.dart';
import 'package:stock_monitor/features/portfolio/portfolio_screen.dart';
import 'package:stock_monitor/features/settings/settings_providers.dart';

// ---------------------------------------------------------------------------
// Fake API (nessuna rete)
// ---------------------------------------------------------------------------

class _FakePortfolioApi extends PortfolioApi {
  _FakePortfolioApi({List<Holding>? holdings})
    : _holdings = holdings ?? const <Holding>[],
      super(ApiClient());

  List<Holding> _holdings;

  /// Numero di fetch del calendario dividendi (per la regressione F5).
  int dividendsCalls = 0;

  @override
  Future<List<Holding>> holdings() async => _holdings;

  @override
  Future<PortfolioSummary> summary() async => const PortfolioSummary(
    totalValue: 1200,
    totalInvested: 1000,
    totalPnl: 200,
    totalPnlPercent: 20,
    holdingsCount: 1,
  );

  @override
  Future<RealizedPnl> realizedPnl() async => const RealizedPnl();

  @override
  Future<DividendsResult> dividends() async {
    dividendsCalls++;
    return const DividendsResult();
  }

  @override
  Future<List<RebalanceTarget>> rebalanceTargets() async =>
      const <RebalanceTarget>[];

  @override
  Future<List<Transaction>> transactions({String? type}) async =>
      const <Transaction>[];

  @override
  Future<void> deleteHolding(int id) async {
    _holdings = <Holding>[
      for (final Holding holding in _holdings)
        if (holding.id != id) holding,
    ];
  }
}

class _FakeSettingsApi extends SettingsApi {
  _FakeSettingsApi([
    this.settings = const UserSettings(budget: 10000, totalBudget: 10000),
  ]) : super(ApiClient());

  UserSettings settings;

  @override
  Future<UserSettings> getSettings() async => settings;

  @override
  Future<UserSettings> updateSettings({
    String? strategy,
    double? budget,
    List<String>? markets,
    int? reportFreq,
    List<String>? reportTimes,
  }) async {
    settings = UserSettings(
      id: settings.id,
      strategy: strategy ?? settings.strategy,
      markets: markets ?? settings.markets,
      budget: budget ?? settings.budget,
      totalBudget: budget ?? settings.totalBudget,
      reportFreq: reportFreq ?? settings.reportFreq,
      reportTimes: reportTimes ?? settings.reportTimes,
      apiStatus: settings.apiStatus,
    );
    return settings;
  }
}

class _FakeStocksApi extends StocksApi {
  _FakeStocksApi() : super(ApiClient());

  @override
  Future<List<StockSearchResult>> search(String q) async =>
      const <StockSearchResult>[];
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Holding _holding({int id = 1, String ticker = 'AAPL'}) {
  return Holding.fromJson(<String, dynamic>{
    'id': id,
    'stock_id': id,
    'ticker': ticker,
    'name': 'Apple Inc.',
    'market': 'US',
    'currency': 'USD',
    'quantity': 10.0,
    'avg_purchase_price': 100.0,
    'current_price': 120.0,
  });
}

GoRouter _router() => GoRouter(
  initialLocation: '/portfolio',
  routes: <RouteBase>[
    GoRoute(
      path: '/portfolio',
      builder: (BuildContext context, GoRouterState state) =>
          const Scaffold(body: PortfolioScreen()),
    ),
  ],
);

Widget _buildApp({
  required GoRouter router,
  required _FakePortfolioApi portfolioApi,
  required _FakeSettingsApi settingsApi,
}) {
  return ProviderScope(
    overrides: [
      portfolioApiProvider.overrideWithValue(portfolioApi),
      settingsApiProvider.overrideWithValue(settingsApi),
      stocksApiProvider.overrideWithValue(_FakeStocksApi()),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required GoRouter router,
  required _FakePortfolioApi portfolioApi,
  required _FakeSettingsApi settingsApi,
}) async {
  await tester.pumpWidget(
    _buildApp(
      router: router,
      portfolioApi: portfolioApi,
      settingsApi: settingsApi,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('F1 — deep-link ?add su /portfolio', () {
    testWidgets('navigare a /portfolio?add=AAPL (stessa rotta) apre il modal', (
      WidgetTester tester,
    ) async {
      final GoRouter router = _router();
      await _pumpScreen(
        tester,
        router: router,
        portfolioApi: _FakePortfolioApi(),
        settingsApi: _FakeSettingsApi(),
      );
      expect(find.text('Aggiungi Titolo al Portafoglio'), findsNothing);

      router.go('/portfolio?add=AAPL');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Aggiungi Titolo al Portafoglio'), findsOneWidget);
      expect(find.text('AAPL'), findsOneWidget);
      // Param consumato all'apertura: niente riaperture ai rebuild.
      expect(router.state.uri.queryParameters['add'], isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('?add= vuoto apre il modal senza prefill', (
      WidgetTester tester,
    ) async {
      final GoRouter router = _router();
      await _pumpScreen(
        tester,
        router: router,
        portfolioApi: _FakePortfolioApi(),
        settingsApi: _FakeSettingsApi(),
      );

      router.go('/portfolio?add=');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Aggiungi Titolo al Portafoglio'), findsOneWidget);
      final TextField ticker = tester.widget<TextField>(
        find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(TextField),
            )
            .first,
      );
      expect(ticker.controller?.text, '');

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });

  group('F5 — dividendi invalidati dalle mutazioni holdings', () {
    testWidgets('eliminare una holding ricarica il calendario dividendi', (
      WidgetTester tester,
    ) async {
      final _FakePortfolioApi portfolioApi = _FakePortfolioApi(
        holdings: <Holding>[_holding(id: 7)],
      );
      await _pumpScreen(
        tester,
        router: _router(),
        portfolioApi: portfolioApi,
        settingsApi: _FakeSettingsApi(),
      );
      expect(portfolioApi.dividendsCalls, 1);

      await tester.tap(find.text('🗑️'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // L'invalidazione di dividendsProvider rifetcha il calendario.
      expect(portfolioApi.dividendsCalls, 2);

      // Smonta l'albero per cancellare i timer del toast (undo).
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });

  group('F6 — budget derivato dalle impostazioni', () {
    test('budgetFromSettings preferisce total_budget e usa il default', () {
      expect(
        budgetFromSettings(const UserSettings(totalBudget: 7000, budget: 3000)),
        7000,
      );
      expect(budgetFromSettings(const UserSettings(budget: 3000)), 3000);
      expect(budgetFromSettings(const UserSettings()), kDefaultPortfolioBudget);
    });

    test(
      'portfolioBudgetProvider si aggiorna dopo il salvataggio settings',
      () async {
        final _FakeSettingsApi settingsApi = _FakeSettingsApi(
          const UserSettings(budget: 5000, totalBudget: 5000),
        );
        final ProviderContainer container = ProviderContainer(
          overrides: [settingsApiProvider.overrideWithValue(settingsApi)],
        );
        addTearDown(container.dispose);

        expect(await container.read(portfolioBudgetProvider.future), 5000);

        await container
            .read(settingsProvider.notifier)
            .save(
              strategy: 'mixed',
              budget: 8000,
              markets: const <String>[],
              reportFreq: 2,
              reportTimes: const <String>[],
            );

        // Nessun reload manuale: il provider derivato segue settingsProvider.
        expect(await container.read(portfolioBudgetProvider.future), 8000);
      },
    );
  });
}
