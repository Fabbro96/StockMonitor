import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api_client.dart';
import '../models/deep_dive.dart';
import '../models/parse_utils.dart';
import '../models/stock.dart';

/// Stocks endpoints: search, deep dive, candles and market correction.
class StocksApi {
  const StocksApi(this._client);

  final ApiClient _client;

  /// `GET /api/stocks/search?q=`
  Future<List<StockSearchResult>> search(String q) async {
    final data = await _client.get('/stocks/search', query: {'q': q});
    return asMapList(data).map(StockSearchResult.fromJson).toList();
  }

  /// `GET /api/stocks/{ticker}/details`
  Future<StockDetails> details(String ticker) async {
    final data = await _client.get('/stocks/$ticker/details');
    return StockDetails.fromJson(asMap(data));
  }

  /// `GET /api/stocks/{ticker}/candles?timeframe=`
  ///
  /// [timeframe] must be one of `1d`, `1w`, `1m`, `6m`, `1y`, `5y`.
  Future<List<Candle>> candles(String ticker, String timeframe) async {
    final data = await _client.get(
      '/stocks/$ticker/candles',
      query: {'timeframe': timeframe},
    );
    return asMapList(data).map(Candle.fromJson).toList();
  }

  /// `PUT /api/stocks/{ticker}` with `{market}` (`IT`, `US` or `EU`).
  Future<StockRecord> updateMarket(String ticker, String market) async {
    final data = await _client.put('/stocks/$ticker', body: {'market': market});
    return StockRecord.fromJson(asMap(data));
  }
}

final stocksApiProvider = Provider<StocksApi>(
  (ref) => StocksApi(ref.watch(apiClientProvider)),
);
