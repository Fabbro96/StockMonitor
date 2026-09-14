import 'parse_utils.dart';

/// Result of `GET /api/stocks/search?q=`.
class StockSearchResult {
  final String ticker;
  final String name;
  final String market;

  const StockSearchResult({
    required this.ticker,
    required this.name,
    required this.market,
  });

  factory StockSearchResult.fromJson(Map<String, dynamic> json) {
    return StockSearchResult(
      ticker: asString(json['ticker']),
      name: asString(json['name']),
      market: asString(json['market']),
    );
  }
}

/// Stock registry row (`GET/POST /api/stocks/`, `PUT /api/stocks/{ticker}`).
class StockRecord {
  final int id;
  final String ticker;
  final String? name;
  final String? market;
  final String? currency;
  final bool isActive;

  const StockRecord({
    required this.id,
    required this.ticker,
    this.name,
    this.market,
    this.currency,
    this.isActive = true,
  });

  factory StockRecord.fromJson(Map<String, dynamic> json) {
    return StockRecord(
      id: asInt(json['id']) ?? 0,
      ticker: asString(json['ticker']),
      name: json['name'] == null ? null : asString(json['name']),
      market: json['market'] == null ? null : asString(json['market']),
      currency: json['currency'] == null ? null : asString(json['currency']),
      isActive: asBool(json['is_active'], fallback: true),
    );
  }
}

/// Single OHLC candle from `GET /api/stocks/{ticker}/candles`.
///
/// [time] is an epoch int for intraday timeframes (`1d`, `1w`) and a
/// `YYYY-MM-DD` string otherwise.
class Candle {
  final dynamic time;
  final double? open;
  final double? high;
  final double? low;
  final double? close;
  final double? value;
  final int? volume;

  const Candle({
    required this.time,
    this.open,
    this.high,
    this.low,
    this.close,
    this.value,
    this.volume,
  });

  factory Candle.fromJson(Map<String, dynamic> json) {
    return Candle(
      time: json['time'],
      open: asDouble(json['open']),
      high: asDouble(json['high']),
      low: asDouble(json['low']),
      close: asDouble(json['close']),
      value: asDouble(json['value']),
      volume: asInt(json['volume']),
    );
  }
}
