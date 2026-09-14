import 'parse_utils.dart';

/// One stock suggestion inside a macro advice (`stocks_analysis`).
class AdviceStockAnalysis {
  final String ticker;
  final String name;
  final String action;
  final String priority;
  final double? targetPrice;
  final String? note;

  const AdviceStockAnalysis({
    required this.ticker,
    this.name = '',
    this.action = '',
    this.priority = '',
    this.targetPrice,
    this.note,
  });

  factory AdviceStockAnalysis.fromJson(Map<String, dynamic> json) {
    return AdviceStockAnalysis(
      ticker: asString(json['ticker']),
      name: asString(json['name']),
      action: asString(json['action']),
      priority: asString(json['priority']),
      targetPrice: asDouble(json['target_price'] ?? json['targetPrice']),
      note: json['note'] == null ? null : asString(json['note']),
    );
  }
}

/// Macro advice row from `GET /api/advice/` (and the other advice endpoints).
///
/// `latest` omits `ticker`/`name`; `generate` omits `id`.
class Advice {
  final int? id;
  final String? market;
  final String title;
  final String? action;
  final String? overview;
  final String? strategy;
  final List<AdviceStockAnalysis> stocksAnalysis;
  final String? risks;
  final String? confidence;
  final String? timeframe;
  final double? targetPrice;
  final double? suggestedQuantity;
  final bool followed;
  final DateTime? timestamp;
  final String? ticker;
  final String? name;

  const Advice({
    this.id,
    this.market,
    this.title = '',
    this.action,
    this.overview,
    this.strategy,
    this.stocksAnalysis = const [],
    this.risks,
    this.confidence,
    this.timeframe,
    this.targetPrice,
    this.suggestedQuantity,
    this.followed = false,
    this.timestamp,
    this.ticker,
    this.name,
  });

  factory Advice.fromJson(Map<String, dynamic> json) {
    return Advice(
      id: asInt(json['id']),
      market: json['market'] == null ? null : asString(json['market']),
      title: asString(json['title']),
      action: json['action'] == null ? null : asString(json['action']),
      overview: json['overview'] == null ? null : asString(json['overview']),
      strategy: json['strategy'] == null ? null : asString(json['strategy']),
      stocksAnalysis: asMapList(json['stocks_analysis'])
          .map(AdviceStockAnalysis.fromJson)
          .toList(),
      risks: json['risks'] == null ? null : asString(json['risks']),
      confidence:
          json['confidence'] == null ? null : asString(json['confidence']),
      timeframe:
          json['timeframe'] == null ? null : asString(json['timeframe']),
      targetPrice: asDouble(json['targetPrice']),
      suggestedQuantity: asDouble(json['suggestedQuantity']),
      followed: asBool(json['followed']),
      timestamp: parseServerDateTime(json['timestamp']?.toString()),
      ticker: json['ticker'] == null ? null : asString(json['ticker']),
      name: json['name'] == null ? null : asString(json['name']),
    );
  }
}

/// User position context attached to an on-demand stock analysis.
class HoldingContext {
  final bool inPortfolio;
  final double quantity;
  final double avgPurchasePrice;
  final double totalInvested;
  final double currentPnlAbs;
  final double currentPnlPct;

  const HoldingContext({
    this.inPortfolio = false,
    this.quantity = 0,
    this.avgPurchasePrice = 0,
    this.totalInvested = 0,
    this.currentPnlAbs = 0,
    this.currentPnlPct = 0,
  });

  factory HoldingContext.fromJson(Map<String, dynamic> json) {
    return HoldingContext(
      inPortfolio: asBool(json['in_portfolio']),
      quantity: asDouble(json['quantity']) ?? 0,
      avgPurchasePrice: asDouble(json['avg_purchase_price']) ?? 0,
      totalInvested: asDouble(json['total_invested']) ?? 0,
      currentPnlAbs: asDouble(json['current_pnl_abs']) ?? 0,
      currentPnlPct: asDouble(json['current_pnl_pct']) ?? 0,
    );
  }
}

/// On-demand single stock analysis (`POST /api/advice/stock/{ticker}`).
class StockAnalysis {
  final String ticker;
  final String name;
  final String action;
  final String? actionLabel;
  final double? targetPrice;
  final double? stopLoss;
  final double? upsidePotentialPct;
  final String? timeframe;
  final String? confidence;
  final String? summary;
  final String? bullCase;
  final String? bearCase;
  final String? technicalVerdict;
  final String? operationalStrategy;
  final HoldingContext? holdingContext;

  const StockAnalysis({
    required this.ticker,
    this.name = '',
    this.action = '',
    this.actionLabel,
    this.targetPrice,
    this.stopLoss,
    this.upsidePotentialPct,
    this.timeframe,
    this.confidence,
    this.summary,
    this.bullCase,
    this.bearCase,
    this.technicalVerdict,
    this.operationalStrategy,
    this.holdingContext,
  });

  factory StockAnalysis.fromJson(Map<String, dynamic> json) {
    final holding = json['holding_context'];
    return StockAnalysis(
      ticker: asString(json['ticker']),
      name: asString(json['name']),
      action: asString(json['action']),
      actionLabel:
          json['action_label'] == null ? null : asString(json['action_label']),
      targetPrice: asDouble(json['target_price']),
      stopLoss: asDouble(json['stop_loss']),
      upsidePotentialPct: asDouble(json['upside_potential_pct']),
      timeframe:
          json['timeframe'] == null ? null : asString(json['timeframe']),
      confidence:
          json['confidence'] == null ? null : asString(json['confidence']),
      summary: json['summary'] == null ? null : asString(json['summary']),
      bullCase: json['bull_case'] == null ? null : asString(json['bull_case']),
      bearCase: json['bear_case'] == null ? null : asString(json['bear_case']),
      technicalVerdict: json['technical_verdict'] == null
          ? null
          : asString(json['technical_verdict']),
      operationalStrategy: json['operational_strategy'] == null
          ? null
          : asString(json['operational_strategy']),
      holdingContext: holding is Map
          ? HoldingContext.fromJson(asMap(holding))
          : null,
    );
  }
}

/// Result of `POST /api/advice/generate`.
class GenerateAdviceResult {
  final String status;
  final int generatedCount;
  final List<Advice> advices;

  const GenerateAdviceResult({
    this.status = '',
    this.generatedCount = 0,
    this.advices = const [],
  });

  factory GenerateAdviceResult.fromJson(Map<String, dynamic> json) {
    final advices =
        asMapList(json['advices']).map(Advice.fromJson).toList();
    return GenerateAdviceResult(
      status: asString(json['status']),
      generatedCount: asInt(json['generated_count']) ?? advices.length,
      advices: advices,
    );
  }
}
