import 'parse_utils.dart';

/// Watchlist row from `GET /api/watchlist/`.
///
/// When the backend deep dive falls back (offline), prices/changes default to
/// 0, the 52 week range to `0/0` with position `50%` and RSI to
/// `50 / Neutro / badge-hold`.
class WatchlistItem {
  final int id;
  final int stockId;
  final String ticker;
  final String? name;
  final String? market;
  final String? currency;
  final double currentPrice;
  final double changeAbs;
  final double changePercent;
  final double? dayHigh;
  final double? dayLow;
  final double? fiftyTwoWeekHigh;
  final double? fiftyTwoWeekLow;
  final double? fiftyTwoWeekPct;
  final double? peRatio;
  final double? dividendYield;
  final double rsi;
  final String rsiStatus;
  final String rsiBadge;
  final String notes;
  final double? alertAbove;
  final double? alertBelow;
  final bool alertTriggered;
  final bool isInPortfolio;
  final DateTime? addedAt;

  const WatchlistItem({
    required this.id,
    required this.stockId,
    required this.ticker,
    this.name,
    this.market,
    this.currency,
    this.currentPrice = 0,
    this.changeAbs = 0,
    this.changePercent = 0,
    this.dayHigh,
    this.dayLow,
    this.fiftyTwoWeekHigh,
    this.fiftyTwoWeekLow,
    this.fiftyTwoWeekPct,
    this.peRatio,
    this.dividendYield,
    this.rsi = 50,
    this.rsiStatus = 'Neutro',
    this.rsiBadge = 'badge-hold',
    this.notes = '',
    this.alertAbove,
    this.alertBelow,
    this.alertTriggered = false,
    this.isInPortfolio = false,
    this.addedAt,
  });

  factory WatchlistItem.fromJson(Map<String, dynamic> json) {
    return WatchlistItem(
      id: asInt(json['id']) ?? 0,
      stockId: asInt(json['stock_id']) ?? 0,
      ticker: asString(json['ticker']),
      name: json['name'] == null ? null : asString(json['name']),
      market: json['market'] == null ? null : asString(json['market']),
      currency: json['currency'] == null ? null : asString(json['currency']),
      currentPrice: asDouble(json['current_price']) ?? 0,
      changeAbs: asDouble(json['change_abs']) ?? 0,
      changePercent: asDouble(json['change_percent']) ?? 0,
      dayHigh: asDouble(json['day_high']),
      dayLow: asDouble(json['day_low']),
      fiftyTwoWeekHigh: asDouble(json['fifty_two_week_high']) ?? 0,
      fiftyTwoWeekLow: asDouble(json['fifty_two_week_low']) ?? 0,
      fiftyTwoWeekPct: asDouble(json['fifty_two_week_pct']) ?? 50,
      peRatio: asDouble(json['pe_ratio']),
      dividendYield: asDouble(json['dividend_yield']),
      rsi: asDouble(json['rsi']) ?? 50,
      rsiStatus: asString(json['rsi_status'], fallback: 'Neutro'),
      rsiBadge: asString(json['rsi_badge'], fallback: 'badge-hold'),
      notes: asString(json['notes']),
      alertAbove: asDouble(json['alert_above']),
      alertBelow: asDouble(json['alert_below']),
      alertTriggered: asBool(json['alert_triggered']),
      isInPortfolio: asBool(json['is_in_portfolio']),
      addedAt: parseServerDateTime(json['added_at']?.toString()),
    );
  }
}
