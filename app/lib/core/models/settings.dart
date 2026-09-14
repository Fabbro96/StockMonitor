import 'parse_utils.dart';

/// API credentials status nested in `GET /api/settings/`.
class ApiStatus {
  final bool telegram;
  final bool gemini;
  final String geminiModel;
  final bool reddit;

  const ApiStatus({
    this.telegram = false,
    this.gemini = false,
    this.geminiModel = '',
    this.reddit = false,
  });

  factory ApiStatus.fromJson(Map<String, dynamic> json) {
    return ApiStatus(
      telegram: asBool(json['telegram']),
      gemini: asBool(json['gemini']),
      geminiModel: asString(json['gemini_model']),
      reddit: asBool(json['reddit']),
    );
  }
}

/// User settings from `GET/PUT /api/settings/`.
///
/// The PUT response omits `apiStatus` (only GET exposes it).
class UserSettings {
  final int? id;
  final String strategy;
  final List<String> markets;
  final double budget;
  final double totalBudget;
  final int reportFreq;
  final List<String> reportTimes;
  final ApiStatus? apiStatus;

  const UserSettings({
    this.id,
    this.strategy = 'mixed',
    this.markets = const [],
    this.budget = 0,
    this.totalBudget = 0,
    this.reportFreq = 2,
    this.reportTimes = const [],
    this.apiStatus,
  });

  factory UserSettings.fromJson(Map<String, dynamic> json) {
    final budget = asDouble(json['budget']) ?? asDouble(json['total_budget']) ?? 0;
    final apiStatus = json['apiStatus'];
    return UserSettings(
      id: asInt(json['id']),
      strategy: asString(json['strategy'], fallback: 'mixed'),
      markets: asStringList(json['markets']),
      budget: budget,
      totalBudget: asDouble(json['total_budget']) ?? budget,
      reportFreq: asInt(json['reportFreq']) ?? 2,
      reportTimes: asStringList(json['reportTimes'] ?? json['advice_times']),
      apiStatus:
          apiStatus is Map ? ApiStatus.fromJson(asMap(apiStatus)) : null,
    );
  }
}

/// Price alert rule from `/api/settings/alerts`.
///
/// The create response omits `name` and `threshold_percent` (it only carries
/// `threshold`); the list endpoint includes both threshold fields.
class AlertRule {
  final int id;
  final int? stockId;
  final String ticker;
  final String? name;
  final String direction;
  final double threshold;
  final double? thresholdPercent;
  final bool active;

  const AlertRule({
    required this.id,
    this.stockId,
    this.ticker = '',
    this.name,
    this.direction = 'BOTH',
    this.threshold = 0,
    this.thresholdPercent,
    this.active = true,
  });

  factory AlertRule.fromJson(Map<String, dynamic> json) {
    return AlertRule(
      id: asInt(json['id']) ?? 0,
      stockId: asInt(json['stock_id']),
      ticker: asString(json['ticker'], fallback: '?'),
      name: json['name'] == null ? null : asString(json['name']),
      direction: asString(json['direction'], fallback: 'BOTH'),
      threshold: asDouble(json['threshold'] ?? json['threshold_percent']) ?? 0,
      thresholdPercent: asDouble(json['threshold_percent']),
      active: asBool(json['active'], fallback: true),
    );
  }
}
