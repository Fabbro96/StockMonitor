import 'advice.dart';
import 'parse_utils.dart';
import 'portfolio.dart';

/// Dashboard payload from `GET /api/dashboard/`.
class DashboardData {
  final PortfolioSummary portfolioSummary;
  final List<Advice> recentAdvices;
  final int activeAlertsCount;
  final MarketStatusInfo marketStatus;

  const DashboardData({
    this.portfolioSummary = const PortfolioSummary(),
    this.recentAdvices = const [],
    this.activeAlertsCount = 0,
    this.marketStatus = const MarketStatusInfo(),
  });

  factory DashboardData.fromJson(Map<String, dynamic> json) {
    return DashboardData(
      portfolioSummary:
          PortfolioSummary.fromJson(asMap(json['portfolio_summary'])),
      recentAdvices:
          asMapList(json['recent_advices']).map(Advice.fromJson).toList(),
      activeAlertsCount: asInt(json['active_alerts_count']) ?? 0,
      marketStatus: MarketStatusInfo.fromJson(asMap(json['market_status'])),
    );
  }
}

/// Single market detail (name, flag, status, hours).
class MarketDetail {
  final String name;
  final String flag;
  final String status;
  final String hours;

  const MarketDetail({
    this.name = '',
    this.flag = '',
    this.status = 'CLOSED',
    this.hours = '',
  });

  factory MarketDetail.fromJson(Map<String, dynamic> json) {
    return MarketDetail(
      name: asString(json['name']),
      flag: asString(json['flag']),
      status: asString(json['status'], fallback: 'CLOSED'),
      hours: asString(json['hours']),
    );
  }
}

/// Structured market status from the dashboard payload.
class MarketStatusInfo {
  final String it;
  final String us;
  final String eu;
  final bool anyOpen;
  final Map<String, MarketDetail> details;

  const MarketStatusInfo({
    this.it = 'CLOSED',
    this.us = 'CLOSED',
    this.eu = 'CLOSED',
    this.anyOpen = false,
    this.details = const {},
  });

  factory MarketStatusInfo.fromJson(Map<String, dynamic> json) {
    return MarketStatusInfo(
      it: asString(json['IT'], fallback: 'CLOSED'),
      us: asString(json['US'], fallback: 'CLOSED'),
      eu: asString(json['EU'], fallback: 'CLOSED'),
      anyOpen: asString(json['ANY_OPEN']).toUpperCase() == 'OPEN',
      details: asMap(json['details']).map(
        (key, value) =>
            MapEntry(key.toUpperCase(), MarketDetail.fromJson(asMap(value))),
      ),
    );
  }
}

/// Global index/commodity quote from `GET /api/dashboard/indices`.
class IndexQuote {
  final String ticker;
  final String name;
  final String flag;
  final String type;
  final double price;
  final double changeAbs;
  final double changePercent;
  final bool stale;

  const IndexQuote({
    required this.ticker,
    this.name = '',
    this.flag = '',
    this.type = '',
    this.price = 0,
    this.changeAbs = 0,
    this.changePercent = 0,
    this.stale = false,
  });

  factory IndexQuote.fromJson(Map<String, dynamic> json) {
    return IndexQuote(
      ticker: asString(json['ticker']),
      name: asString(json['name']),
      flag: asString(json['flag']),
      type: asString(json['type']),
      price: asDouble(json['price']) ?? 0,
      changeAbs: asDouble(json['change_abs']) ?? 0,
      changePercent: asDouble(json['change_percent']) ?? 0,
      stale: asBool(json['stale']),
    );
  }
}

/// Heatmap row from `GET /api/dashboard/heatmap`.
class HeatmapItem {
  final String ticker;
  final String name;
  final String market;
  final String currency;
  final double currentPrice;
  final double changePercent;
  final double? changeAbs;
  final double? dayHigh;
  final double? dayLow;
  final int? volume;
  final bool stale;

  const HeatmapItem({
    required this.ticker,
    this.name = '',
    this.market = '',
    this.currency = 'EUR',
    this.currentPrice = 0,
    this.changePercent = 0,
    this.changeAbs,
    this.dayHigh,
    this.dayLow,
    this.volume,
    this.stale = false,
  });

  factory HeatmapItem.fromJson(Map<String, dynamic> json) {
    return HeatmapItem(
      ticker: asString(json['ticker']),
      name: asString(json['name']),
      market: asString(json['market']),
      currency: asString(json['currency'], fallback: 'EUR'),
      currentPrice: asDouble(json['current_price']) ?? 0,
      changePercent: asDouble(json['change_percent']) ?? 0,
      changeAbs: asDouble(json['change_abs']),
      dayHigh: asDouble(json['day_high']),
      dayLow: asDouble(json['day_low']),
      volume: asInt(json['volume']),
      stale: asBool(json['stale']),
    );
  }
}

/// Single point of the portfolio performance series.
class PricePoint {
  final DateTime? date;
  final double value;
  final int? volume;

  const PricePoint({this.date, this.value = 0, this.volume});

  factory PricePoint.fromJson(Map<String, dynamic> json) {
    return PricePoint(
      date: parseServerDate(json['date']?.toString()),
      value: asDouble(json['value']) ?? 0,
      volume: asInt(json['volume']),
    );
  }
}

/// Performance series from `GET /api/dashboard/performance`.
class PerformanceSeries {
  final List<PricePoint> data;
  final String source;
  final int points;

  const PerformanceSeries({
    this.data = const [],
    this.source = '',
    this.points = 0,
  });

  factory PerformanceSeries.fromJson(Map<String, dynamic> json) {
    final data = asMapList(json['data']).map(PricePoint.fromJson).toList();
    return PerformanceSeries(
      data: data,
      source: asString(json['source']),
      points: asInt(json['points']) ?? data.length,
    );
  }
}
