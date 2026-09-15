import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_monitor/core/api/watchlist_api.dart';
import 'package:stock_monitor/core/api_client.dart';
import 'package:stock_monitor/core/models/portfolio.dart';
import 'package:stock_monitor/core/models/watchlist_item.dart';
import 'package:stock_monitor/features/portfolio/holdings_table.dart';
import 'package:stock_monitor/features/portfolio/portfolio_edits.dart';
import 'package:stock_monitor/features/portfolio/portfolio_table.dart';
import 'package:stock_monitor/features/watchlist/watchlist_screen.dart';
import 'package:stock_monitor/theme/app_theme.dart';

/// Regressione a11y: le azioni rivelate nelle righe di tabella devono avere
/// un'area interattiva ≥32px senza cambiare l'altezza delle righe (40px) né
/// causare overflow ai breakpoint 640/900/1024/1440.
class _FakeWatchlistApi extends WatchlistApi {
  _FakeWatchlistApi() : super(ApiClient());

  @override
  Future<List<WatchlistItem>> list() async => const <WatchlistItem>[
    WatchlistItem(
      id: 1,
      stockId: 1,
      ticker: 'AAPL',
      name: 'Apple Inc.',
      market: 'US',
      currency: 'USD',
      currentPrice: 190,
      changePercent: 1.2,
      rsi: 55,
    ),
  ];
}

Holding _holding() => Holding.fromJson(<String, dynamic>{
  'id': 1,
  'stock_id': 1,
  'ticker': 'AAPL',
  'name': 'Apple Inc.',
  'market': 'US',
  'currency': 'USD',
  'quantity': 10.0,
  'avg_purchase_price': 100.0,
  'current_price': 120.0,
});

Widget _holdings() => MaterialApp(
  theme: lightTheme,
  home: Scaffold(
    body: HoldingsTable(
      holdings: <Holding>[_holding()],
      edits: const <int, HoldingEdit>{},
      epoch: 0,
      onEdit: (Holding holding, {double? quantity, double? avgPrice}) {},
      onDelete: (_) {},
      onOpenTicker: (_) {},
      onEditMarket: (_) {},
    ),
  ),
);

Widget _watchlist() => ProviderScope(
  overrides: [
    watchlistApiProvider.overrideWithValue(_FakeWatchlistApi()),
  ],
  child: MaterialApp(
    theme: lightTheme,
    home: const Scaffold(body: WatchlistScreen()),
  ),
);

Future<void> _pumpAt(WidgetTester tester, Widget widget, double width) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(widget);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 60));
}

void _expectTarget(WidgetTester tester, String tooltip) {
  final Size size = tester.getSize(find.byTooltip(tooltip));
  expect(size.width, greaterThanOrEqualTo(32), reason: tooltip);
  expect(size.height, greaterThanOrEqualTo(32), reason: tooltip);
}

void main() {
  for (final double width in <double>[640, 900, 1024, 1440]) {
    testWidgets('holdings ${width.toInt()}: senza overflow, target ≥32', (
      WidgetTester tester,
    ) async {
      await _pumpAt(tester, _holdings(), width);

      expect(tester.takeException(), isNull);
      // Sotto 900px si usa la card list: le azioni di riga compaiono da 900
      // in su (tabella con scroll orizzontale sotto la larghezza minima).
      if (width >= 900) {
        _expectTarget(tester, 'Apri scheda completa');
        _expectTarget(tester, 'Elimina');
        // L'altezza della riga resta quella compatta del linguaggio Registro.
        expect(tester.getSize(find.byType(PortfolioTableRow)).height, 40);
      }
    });
  }

  for (final double width in <double>[640, 900, 1024, 1440]) {
    testWidgets('watchlist ${width.toInt()}: riga senza overflow, target ≥32', (
      WidgetTester tester,
    ) async {
      await _pumpAt(tester, _watchlist(), width);

      expect(tester.takeException(), isNull);
      // Le quattro azioni rivelate compaiono sopra 900px; il menu di overflow
      // sotto. In entrambi i casi la riga resta da 40px.
      if (width >= 900) {
        _expectTarget(tester, 'Apri scheda completa');
        _expectTarget(tester, 'Imposta alert di prezzo');
        _expectTarget(tester, 'Aggiungi alle holding');
        _expectTarget(tester, 'Rimuovi dal radar');
      }
    });
  }
}
