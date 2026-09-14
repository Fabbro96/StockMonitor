import 'parse_utils.dart';

/// Technical indicators nested in a stock deep dive.
class TechnicalIndicators {
  final double? rsi14;
  final String? rsiStatus;
  final String? rsiBadge;
  final double? sma20;
  final double? sma50;
  final String? trend;

  const TechnicalIndicators({
    this.rsi14,
    this.rsiStatus,
    this.rsiBadge,
    this.sma20,
    this.sma50,
    this.trend,
  });

  factory TechnicalIndicators.fromJson(Map<String, dynamic> json) {
    return TechnicalIndicators(
      rsi14: asDouble(json['rsi_14']),
      rsiStatus: json['rsi_status'] == null ? null : asString(json['rsi_status']),
      rsiBadge: json['rsi_badge'] == null ? null : asString(json['rsi_badge']),
      sma20: asDouble(json['sma_20']),
      sma50: asDouble(json['sma_50']),
      trend: json['trend'] == null ? null : asString(json['trend']),
    );
  }
}

/// Full stock card from `GET /api/stocks/{ticker}/details`.
///
/// The offline fallback omits ~20 keys, so every field except [ticker] is
/// optional.
class StockDetails {
  final String ticker;
  final bool stale;
  final String? name;
  final String? market;
  final String? currency;
  final double? currentPrice;
  final double? previousClose;
  final double? changeAbs;
  final double? changePercent;
  final double? dayHigh;
  final double? dayLow;
  final int? volume;
  final int? avgVolume;
  final double? marketCap;
  final double? peRatio;
  final double? forwardPe;
  final double? eps;
  final double? beta;
  final double? dividendYield;
  final double? fiftyTwoWeekHigh;
  final double? fiftyTwoWeekLow;
  final double? fiftyTwoWeekPct;
  final String? sector;
  final String? industry;
  final String? summary;
  final TechnicalIndicators? technical;

  const StockDetails({
    required this.ticker,
    this.stale = false,
    this.name,
    this.market,
    this.currency,
    this.currentPrice,
    this.previousClose,
    this.changeAbs,
    this.changePercent,
    this.dayHigh,
    this.dayLow,
    this.volume,
    this.avgVolume,
    this.marketCap,
    this.peRatio,
    this.forwardPe,
    this.eps,
    this.beta,
    this.dividendYield,
    this.fiftyTwoWeekHigh,
    this.fiftyTwoWeekLow,
    this.fiftyTwoWeekPct,
    this.sector,
    this.industry,
    this.summary,
    this.technical,
  });

  factory StockDetails.fromJson(Map<String, dynamic> json) {
    final technicalJson = json['technical'];
    return StockDetails(
      ticker: asString(json['ticker']),
      stale: asBool(json['stale']),
      name: json['name'] == null ? null : asString(json['name']),
      market: json['market'] == null ? null : asString(json['market']),
      currency: json['currency'] == null ? null : asString(json['currency']),
      currentPrice: asDouble(json['current_price']),
      previousClose: asDouble(json['previous_close']),
      changeAbs: asDouble(json['change_abs']),
      changePercent: asDouble(json['change_percent']),
      dayHigh: asDouble(json['day_high']),
      dayLow: asDouble(json['day_low']),
      volume: asInt(json['volume']),
      avgVolume: asInt(json['avg_volume']),
      marketCap: asDouble(json['market_cap']),
      peRatio: asDouble(json['pe_ratio']),
      forwardPe: asDouble(json['forward_pe']),
      eps: asDouble(json['eps']),
      beta: asDouble(json['beta']),
      dividendYield: asDouble(json['dividend_yield']),
      fiftyTwoWeekHigh: asDouble(json['fifty_two_week_high']),
      fiftyTwoWeekLow: asDouble(json['fifty_two_week_low']),
      fiftyTwoWeekPct: asDouble(json['fifty_two_week_pct']),
      sector: json['sector'] == null ? null : asString(json['sector']),
      industry: json['industry'] == null ? null : asString(json['industry']),
      summary: json['summary'] == null ? null : asString(json['summary']),
      technical: technicalJson is Map
          ? TechnicalIndicators.fromJson(asMap(technicalJson))
          : null,
    );
  }
}
