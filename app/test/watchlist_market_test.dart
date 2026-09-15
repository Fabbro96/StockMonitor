import 'package:flutter_test/flutter_test.dart';
import 'package:stock_monitor/core/models/watchlist_item.dart';
import 'package:stock_monitor/features/watchlist/watchlist_providers.dart';

WatchlistItem _item(String ticker, {String? market}) => WatchlistItem(
  id: ticker.hashCode,
  stockId: 1,
  ticker: ticker,
  market: market,
);

List<String> _tickers(List<WatchlistItem> items) =>
    items.map((WatchlistItem item) => item.ticker).toList();

void main() {
  group('watchlistMarketOf', () {
    test('mercato esplicito IT/US/EU vince sul suffisso', () {
      expect(watchlistMarketOf(_item('XYZ', market: 'IT')), 'IT');
      expect(watchlistMarketOf(_item('ENI.MI', market: 'US')), 'US');
      expect(watchlistMarketOf(_item('AAPL', market: 'EU')), 'EU');
    });

    test('suffissi: .MI → IT, .DE/.PA/.AS → EU, altrimenti US', () {
      expect(watchlistMarketOf(_item('ENI.MI')), 'IT');
      expect(watchlistMarketOf(_item('SAP.DE')), 'EU');
      expect(watchlistMarketOf(_item('AIR.PA')), 'EU');
      expect(watchlistMarketOf(_item('ASML.AS')), 'EU');
      expect(watchlistMarketOf(_item('AAPL')), 'US');
    });

    test('non-equity (crypto/FX/indici/commodity) senza bucket di mercato', () {
      // `AppMarketTag.resolve` classifica queste forme come CRYPTO/FX/IDX/
      // CMDTY: non appartengono a un listino, quindi il filtro IT/US/EU non
      // deve attribuirle a `US` per esclusione.
      expect(watchlistMarketOf(_item('BTC-USD')), isNull);
      expect(watchlistMarketOf(_item('ETH-EUR')), isNull);
      expect(watchlistMarketOf(_item('EURUSD=X')), isNull);
      expect(watchlistMarketOf(_item('^GSPC')), isNull);
      expect(watchlistMarketOf(_item('GC=F')), isNull);
    });

    test('il mercato esplicito resta prioritario anche sui non-equity', () {
      expect(watchlistMarketOf(_item('BTC-USD', market: 'US')), 'US');
    });
  });

  group('filterWatchlistItems', () {
    final List<WatchlistItem> items = <WatchlistItem>[
      _item('ENI.MI'),
      _item('AAPL'),
      _item('SAP.DE'),
      _item('BTC-USD'),
      _item('SPY', market: 'US'),
    ];

    test('filtra per mercato risolto, escludendo i non-equity', () {
      expect(_tickers(filterWatchlistItems(items, '', market: 'IT')), <String>[
        'ENI.MI',
      ]);
      expect(_tickers(filterWatchlistItems(items, '', market: 'US')), <String>[
        'AAPL',
        'SPY',
      ]);
      expect(_tickers(filterWatchlistItems(items, '', market: 'EU')), <String>[
        'SAP.DE',
      ]);
    });

    test('query case-insensitive su ticker e nome', () {
      expect(_tickers(filterWatchlistItems(items, 'btc')), <String>['BTC-USD']);
      expect(_tickers(filterWatchlistItems(items, 'sap')), <String>['SAP.DE']);
      expect(filterWatchlistItems(items, 'zzz'), isEmpty);
    });

    test('senza filtro mercato restituisce tutti i titoli', () {
      expect(filterWatchlistItems(items, ''), hasLength(items.length));
    });
  });
}
