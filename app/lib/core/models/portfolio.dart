import 'parse_utils.dart';

/// Portfolio position row from `GET /api/portfolio/`.
class Holding {
  final int id;
  final int stockId;
  final String ticker;
  final String name;
  final String market;
  final String currency;
  final double quantity;
  final double avgPurchasePrice;
  final double currentPrice;
  final double? previousClose;
  final bool priceStale;
  final double totalValue;
  final double totalInvested;
  final double totalValueEur;
  final double totalInvestedEur;
  final double fxRateToEur;
  final double pnlAbsolute;
  final double pnlPercent;
  final double? dailyPnl;
  final DateTime? purchaseDate;
  final String notes;

  const Holding({
    required this.id,
    required this.stockId,
    required this.ticker,
    required this.name,
    required this.market,
    required this.currency,
    required this.quantity,
    required this.avgPurchasePrice,
    required this.currentPrice,
    this.previousClose,
    this.priceStale = false,
    required this.totalValue,
    required this.totalInvested,
    required this.totalValueEur,
    required this.totalInvestedEur,
    this.fxRateToEur = 1,
    required this.pnlAbsolute,
    required this.pnlPercent,
    this.dailyPnl,
    this.purchaseDate,
    this.notes = '',
  });

  factory Holding.fromJson(Map<String, dynamic> json) {
    final totalValue = asDouble(json['total_value']) ?? 0;
    final totalInvested = asDouble(json['total_invested']) ?? 0;
    return Holding(
      id: asInt(json['id']) ?? 0,
      stockId: asInt(json['stock_id']) ?? 0,
      ticker: asString(json['ticker']),
      name: asString(json['name']),
      market: asString(json['market'], fallback: 'US'),
      currency: asString(json['currency'], fallback: 'EUR'),
      quantity: asDouble(json['quantity']) ?? 0,
      avgPurchasePrice: asDouble(json['avg_purchase_price']) ?? 0,
      currentPrice: asDouble(json['current_price']) ?? 0,
      previousClose: asDouble(json['previous_close']),
      priceStale: asBool(json['price_stale']),
      totalValue: totalValue,
      totalInvested: totalInvested,
      totalValueEur: asDouble(json['total_value_eur']) ?? totalValue,
      totalInvestedEur: asDouble(json['total_invested_eur']) ?? totalInvested,
      fxRateToEur: asDouble(json['fx_rate_to_eur']) ?? 1,
      pnlAbsolute: asDouble(json['pnl_absolute']) ?? 0,
      pnlPercent: asDouble(json['pnl_percent']) ?? 0,
      dailyPnl: asDouble(json['daily_pnl']),
      purchaseDate: parseServerDate(json['purchase_date']?.toString()),
      notes: asString(json['notes']),
    );
  }
}

/// Aggregated portfolio summary from `GET /api/portfolio/summary`.
class PortfolioSummary {
  final double totalValue;
  final double totalInvested;
  final double totalPnl;
  final double totalPnlPercent;
  final double dailyPnl;
  final double dailyPnlPercent;
  final int holdingsCount;
  final Holding? topGainer;
  final Holding? topLoser;
  final Map<String, double> marketAllocation;
  final double estimatedAnnualDividends;
  final double estimatedDividendYield;
  final double fxUsdEur;

  const PortfolioSummary({
    this.totalValue = 0,
    this.totalInvested = 0,
    this.totalPnl = 0,
    this.totalPnlPercent = 0,
    this.dailyPnl = 0,
    this.dailyPnlPercent = 0,
    this.holdingsCount = 0,
    this.topGainer,
    this.topLoser,
    this.marketAllocation = const {},
    this.estimatedAnnualDividends = 0,
    this.estimatedDividendYield = 0,
    this.fxUsdEur = 1,
  });

  factory PortfolioSummary.fromJson(Map<String, dynamic> json) {
    return PortfolioSummary(
      totalValue: asDouble(json['total_value']) ?? 0,
      totalInvested: asDouble(json['total_invested']) ?? 0,
      totalPnl: asDouble(json['total_pnl']) ?? 0,
      totalPnlPercent: asDouble(json['total_pnl_percent']) ?? 0,
      dailyPnl: asDouble(json['daily_pnl']) ?? 0,
      dailyPnlPercent: asDouble(json['daily_pnl_percent']) ?? 0,
      holdingsCount: asInt(json['holdings_count']) ?? 0,
      topGainer: json['top_gainer'] is Map
          ? Holding.fromJson(asMap(json['top_gainer']))
          : null,
      topLoser: json['top_loser'] is Map
          ? Holding.fromJson(asMap(json['top_loser']))
          : null,
      marketAllocation: _doubleMap(json['market_allocation']),
      estimatedAnnualDividends:
          asDouble(json['estimated_annual_dividends']) ?? 0,
      estimatedDividendYield: asDouble(json['estimated_dividend_yield']) ?? 0,
      fxUsdEur: asDouble(json['fx_usd_eur']) ?? 1,
    );
  }
}

/// Risk/performance metrics from `GET /api/portfolio/risk-metrics`.
class RiskMetrics {
  final int daysAnalyzed;
  final DateTime? seriesStart;
  final DateTime? seriesEnd;
  final double maxDrawdownPct;
  final double annualizedVolatilityPct;
  final double sharpeRatio;
  final double annualizedReturnPct;
  final double weightedBeta;
  final double riskFreeRatePct;
  final double currentValue;
  final Map<String, double>? betas;

  const RiskMetrics({
    this.daysAnalyzed = 0,
    this.seriesStart,
    this.seriesEnd,
    this.maxDrawdownPct = 0,
    this.annualizedVolatilityPct = 0,
    this.sharpeRatio = 0,
    this.annualizedReturnPct = 0,
    this.weightedBeta = 0,
    this.riskFreeRatePct = 0,
    this.currentValue = 0,
    this.betas,
  });

  factory RiskMetrics.fromJson(Map<String, dynamic> json) {
    return RiskMetrics(
      daysAnalyzed: asInt(json['days_analyzed']) ?? 0,
      seriesStart: parseServerDate(json['series_start']?.toString()),
      seriesEnd: parseServerDate(json['series_end']?.toString()),
      maxDrawdownPct: asDouble(json['max_drawdown_pct']) ?? 0,
      annualizedVolatilityPct:
          asDouble(json['annualized_volatility_pct']) ?? 0,
      sharpeRatio: asDouble(json['sharpe_ratio']) ?? 0,
      annualizedReturnPct: asDouble(json['annualized_return_pct']) ?? 0,
      weightedBeta: asDouble(json['weighted_beta']) ?? 0,
      riskFreeRatePct: asDouble(json['risk_free_rate_pct']) ?? 0,
      currentValue: asDouble(json['current_value']) ?? 0,
      betas: json['betas'] == null ? null : _doubleMap(json['betas']),
    );
  }
}

/// Single point of a normalised growth series (`{date, growth_pct}`).
class GrowthPoint {
  final DateTime? date;
  final double growthPct;

  const GrowthPoint({this.date, this.growthPct = 0});

  factory GrowthPoint.fromJson(Map<String, dynamic> json) {
    return GrowthPoint(
      date: parseServerDate(json['date']?.toString()),
      growthPct: asDouble(json['growth_pct']) ?? 0,
    );
  }
}

/// One benchmark series from `GET /api/portfolio/benchmarks`.
class BenchmarkSeries {
  final String name;
  final String flag;
  final List<GrowthPoint> data;

  const BenchmarkSeries({
    this.name = '',
    this.flag = '',
    this.data = const [],
  });

  factory BenchmarkSeries.fromJson(Map<String, dynamic> json) {
    return BenchmarkSeries(
      name: asString(json['name']),
      flag: asString(json['flag']),
      data: asMapList(json['data']).map(GrowthPoint.fromJson).toList(),
    );
  }
}

/// Portfolio vs benchmarks comparison.
class BenchmarksResult {
  final DateTime? startDate;
  final DateTime? endDate;
  final List<GrowthPoint> portfolio;
  final Map<String, BenchmarkSeries> benchmarks;

  const BenchmarksResult({
    this.startDate,
    this.endDate,
    this.portfolio = const [],
    this.benchmarks = const {},
  });

  factory BenchmarksResult.fromJson(Map<String, dynamic> json) {
    return BenchmarksResult(
      startDate: parseServerDate(json['start_date']?.toString()),
      endDate: parseServerDate(json['end_date']?.toString()),
      portfolio: asMapList(json['portfolio']).map(GrowthPoint.fromJson).toList(),
      benchmarks: asMap(json['benchmarks']).map(
        (key, value) =>
            MapEntry(key, BenchmarkSeries.fromJson(asMap(value))),
      ),
    );
  }
}

/// Dividend calendar row from `GET /api/portfolio/dividends`.
class DividendHolding {
  final String ticker;
  final String name;
  final String market;
  final String currency;
  final double quantity;
  final double currentPrice;
  final double avgPurchasePrice;
  final double dividendYieldPct;
  final double yieldOnCostPct;
  final double annualDividendPerShare;
  final double annualIncomeEur;
  final double monthlyIncomeEur;

  const DividendHolding({
    required this.ticker,
    this.name = '',
    this.market = '',
    this.currency = 'EUR',
    this.quantity = 0,
    this.currentPrice = 0,
    this.avgPurchasePrice = 0,
    this.dividendYieldPct = 0,
    this.yieldOnCostPct = 0,
    this.annualDividendPerShare = 0,
    this.annualIncomeEur = 0,
    this.monthlyIncomeEur = 0,
  });

  factory DividendHolding.fromJson(Map<String, dynamic> json) {
    return DividendHolding(
      ticker: asString(json['ticker']),
      name: asString(json['name']),
      market: asString(json['market']),
      currency: asString(json['currency'], fallback: 'EUR'),
      quantity: asDouble(json['quantity']) ?? 0,
      currentPrice: asDouble(json['current_price']) ?? 0,
      avgPurchasePrice: asDouble(json['avg_purchase_price']) ?? 0,
      dividendYieldPct: asDouble(json['dividend_yield_pct']) ?? 0,
      yieldOnCostPct: asDouble(json['yield_on_cost_pct']) ?? 0,
      annualDividendPerShare: asDouble(json['annual_dividend_per_share']) ?? 0,
      annualIncomeEur: asDouble(json['annual_income_eur']) ?? 0,
      monthlyIncomeEur: asDouble(json['monthly_income_eur']) ?? 0,
    );
  }
}

/// Dividends overview from `GET /api/portfolio/dividends`.
class DividendsResult {
  final List<DividendHolding> holdings;
  final double totalAnnualDividendEur;
  final double totalMonthlyDividendEur;
  final double portfolioTotalValue;
  final double portfolioYieldOnCost;

  const DividendsResult({
    this.holdings = const [],
    this.totalAnnualDividendEur = 0,
    this.totalMonthlyDividendEur = 0,
    this.portfolioTotalValue = 0,
    this.portfolioYieldOnCost = 0,
  });

  factory DividendsResult.fromJson(Map<String, dynamic> json) {
    return DividendsResult(
      holdings:
          asMapList(json['holdings']).map(DividendHolding.fromJson).toList(),
      totalAnnualDividendEur:
          asDouble(json['total_annual_dividend_eur']) ?? 0,
      totalMonthlyDividendEur:
          asDouble(json['total_monthly_dividend_eur']) ?? 0,
      portfolioTotalValue: asDouble(json['portfolio_total_value']) ?? 0,
      portfolioYieldOnCost: asDouble(json['portfolio_yield_on_cost']) ?? 0,
    );
  }
}

/// Trade ledger row from `GET /api/portfolio/transactions`.
class Transaction {
  final int id;
  final int stockId;
  final String ticker;
  final String name;
  final String market;
  final String type;
  final double quantity;
  final double price;
  final double fee;
  final double? realizedPnl;
  final String currency;
  final DateTime? transactionDate;
  final String notes;

  const Transaction({
    required this.id,
    required this.stockId,
    this.ticker = '',
    this.name = '',
    this.market = '',
    this.type = '',
    this.quantity = 0,
    this.price = 0,
    this.fee = 0,
    this.realizedPnl,
    this.currency = 'EUR',
    this.transactionDate,
    this.notes = '',
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: asInt(json['id']) ?? 0,
      stockId: asInt(json['stock_id']) ?? 0,
      ticker: asString(json['ticker'], fallback: '?'),
      name: asString(json['name']),
      market: asString(json['market'], fallback: 'US'),
      type: asString(json['type']),
      quantity: asDouble(json['quantity']) ?? 0,
      price: asDouble(json['price']) ?? 0,
      fee: asDouble(json['fee']) ?? 0,
      realizedPnl: asDouble(json['realized_pnl']),
      currency: asString(json['currency'], fallback: 'EUR'),
      transactionDate:
          parseServerDateTime(json['transaction_date']?.toString()),
      notes: asString(json['notes']),
    );
  }
}

/// Realised P&L summary from `GET /api/portfolio/realized-pnl`.
class RealizedPnl {
  final double totalRealizedCapitalGains;
  final double totalDividendsCollected;
  final double totalFeesPaid;
  final double netRealizedProfit;
  final int tradeCount;
  final int winTrades;
  final int lossTrades;
  final double winRatePercent;
  final int transactionsCount;

  const RealizedPnl({
    this.totalRealizedCapitalGains = 0,
    this.totalDividendsCollected = 0,
    this.totalFeesPaid = 0,
    this.netRealizedProfit = 0,
    this.tradeCount = 0,
    this.winTrades = 0,
    this.lossTrades = 0,
    this.winRatePercent = 0,
    this.transactionsCount = 0,
  });

  factory RealizedPnl.fromJson(Map<String, dynamic> json) {
    return RealizedPnl(
      totalRealizedCapitalGains:
          asDouble(json['total_realized_capital_gains']) ?? 0,
      totalDividendsCollected:
          asDouble(json['total_dividends_collected']) ?? 0,
      totalFeesPaid: asDouble(json['total_fees_paid']) ?? 0,
      netRealizedProfit: asDouble(json['net_realized_profit']) ?? 0,
      tradeCount: asInt(json['trade_count']) ?? 0,
      winTrades: asInt(json['win_trades']) ?? 0,
      lossTrades: asInt(json['loss_trades']) ?? 0,
      winRatePercent: asDouble(json['win_rate_percent']) ?? 0,
      transactionsCount: asInt(json['transactions_count']) ?? 0,
    );
  }
}

/// Smart rebalancer target allocation (`/api/portfolio/rebalance/targets`).
class RebalanceTarget {
  final int id;
  final String name;
  final double targetPercent;
  final String scopeType;
  final String scopeValue;

  const RebalanceTarget({
    required this.id,
    this.name = '',
    this.targetPercent = 0,
    this.scopeType = 'MARKET',
    this.scopeValue = '',
  });

  factory RebalanceTarget.fromJson(Map<String, dynamic> json) {
    return RebalanceTarget(
      id: asInt(json['id']) ?? 0,
      name: asString(json['name']),
      targetPercent: asDouble(json['target_percent']) ?? 0,
      scopeType: asString(json['scope_type'], fallback: 'MARKET'),
      scopeValue: asString(json['scope_value']),
    );
  }
}

/// Per-bucket allocation computed by the rebalance preview.
class RebalanceAllocation {
  final int? id;
  final String name;
  final String scopeType;
  final String scopeValue;
  final double targetPercent;
  final double currentPercent;
  final double targetValue;
  final double currentValue;
  final double delta;
  final double driftPct;

  const RebalanceAllocation({
    this.id,
    this.name = '',
    this.scopeType = 'MARKET',
    this.scopeValue = '',
    this.targetPercent = 0,
    this.currentPercent = 0,
    this.targetValue = 0,
    this.currentValue = 0,
    this.delta = 0,
    this.driftPct = 0,
  });

  factory RebalanceAllocation.fromJson(Map<String, dynamic> json) {
    return RebalanceAllocation(
      id: asInt(json['id']),
      name: asString(json['name']),
      scopeType: asString(json['scope_type'], fallback: 'MARKET'),
      scopeValue: asString(json['scope_value']),
      targetPercent: asDouble(json['target_percent']) ?? 0,
      currentPercent: asDouble(json['current_percent']) ?? 0,
      targetValue: asDouble(json['target_value']) ?? 0,
      currentValue: asDouble(json['current_value']) ?? 0,
      delta: asDouble(json['delta']) ?? 0,
      driftPct: asDouble(json['drift_pct']) ?? 0,
    );
  }
}

/// Suggested order from the rebalance preview.
class RebalanceOrder {
  final String ticker;
  final String name;
  final String? allocationName;
  final String side;
  final double quantity;
  final double estimatedPrice;
  final double estimatedValue;
  final String currency;

  const RebalanceOrder({
    required this.ticker,
    this.name = '',
    this.allocationName,
    this.side = 'BUY',
    this.quantity = 0,
    this.estimatedPrice = 0,
    this.estimatedValue = 0,
    this.currency = 'EUR',
  });

  factory RebalanceOrder.fromJson(Map<String, dynamic> json) {
    return RebalanceOrder(
      ticker: asString(json['ticker']),
      name: asString(json['name']),
      allocationName: json['allocation_name'] == null
          ? null
          : asString(json['allocation_name']),
      side: asString(json['side'], fallback: 'BUY'),
      quantity: asDouble(json['quantity']) ?? 0,
      estimatedPrice: asDouble(json['estimated_price']) ?? 0,
      estimatedValue: asDouble(json['estimated_value']) ?? 0,
      currency: asString(json['currency'], fallback: 'EUR'),
    );
  }
}

/// Rebalance plan from `POST /api/portfolio/rebalance/preview`.
class RebalancePreview {
  final double totalValue;
  final double extraCash;
  final double targetsSumPercent;
  final List<RebalanceAllocation> allocations;
  final List<RebalanceOrder> orders;
  final int ordersCount;
  final double totalBuyValue;
  final double totalSellValue;
  final bool portfolioEmpty;

  const RebalancePreview({
    this.totalValue = 0,
    this.extraCash = 0,
    this.targetsSumPercent = 0,
    this.allocations = const [],
    this.orders = const [],
    this.ordersCount = 0,
    this.totalBuyValue = 0,
    this.totalSellValue = 0,
    this.portfolioEmpty = false,
  });

  factory RebalancePreview.fromJson(Map<String, dynamic> json) {
    final allocations = asMapList(json['allocations'])
        .map(RebalanceAllocation.fromJson)
        .toList();
    final orders =
        asMapList(json['orders']).map(RebalanceOrder.fromJson).toList();
    return RebalancePreview(
      totalValue: asDouble(json['total_value']) ?? 0,
      extraCash: asDouble(json['extra_cash']) ?? 0,
      targetsSumPercent: asDouble(json['targets_sum_percent']) ?? 0,
      allocations: allocations,
      orders: orders,
      ordersCount: asInt(json['orders_count']) ?? orders.length,
      totalBuyValue: asDouble(json['total_buy_value']) ?? 0,
      totalSellValue: asDouble(json['total_sell_value']) ?? 0,
      portfolioEmpty: asBool(json['portfolio_empty']),
    );
  }
}

Map<String, double> _doubleMap(dynamic value) {
  return asMap(value).map(
    (key, item) => MapEntry(key, asDouble(item) ?? 0),
  );
}
