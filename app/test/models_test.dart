import 'package:flutter_test/flutter_test.dart';
import 'package:stock_monitor/core/models/advice.dart';
import 'package:stock_monitor/core/models/dashboard.dart';
import 'package:stock_monitor/core/models/deep_dive.dart';
import 'package:stock_monitor/core/models/parse_utils.dart';
import 'package:stock_monitor/core/models/portfolio.dart';
import 'package:stock_monitor/core/models/settings.dart';
import 'package:stock_monitor/core/models/stock.dart';
import 'package:stock_monitor/core/models/user.dart';
import 'package:stock_monitor/core/models/watchlist_item.dart';

void main() {
  group('parse_utils', () {
    test('asDouble tollera null, stringhe e valori non finiti', () {
      expect(asDouble(null), isNull);
      expect(asDouble('12.5'), 12.5);
      expect(asDouble(3), 3.0);
      expect(asDouble('abc'), isNull);
      expect(asDouble(double.nan), isNull);
      expect(asDouble(''), isNull);
    });

    test('asInt tollera null e stringhe numeriche', () {
      expect(asInt(null), isNull);
      expect(asInt('42'), 42);
      expect(asInt(42.9), 42);
      expect(asInt('not-a-number'), isNull);
    });

    test('asString applica il fallback', () {
      expect(asString(null), '');
      expect(asString(null, fallback: 'x'), 'x');
      expect(asString(7), '7');
    });

    test('asBool interpreta i formati accettati', () {
      expect(asBool(true), isTrue);
      expect(asBool('false'), isFalse);
      expect(asBool('1'), isTrue);
      expect(asBool('yes'), isTrue);
      expect(asBool(null, fallback: true), isTrue);
      expect(asBool('boh'), isFalse);
    });

    test('asStringList accetta lista o stringa CSV', () {
      expect(asStringList(['IT', 'US']), ['IT', 'US']);
      expect(asStringList('IT, US ,EU'), ['IT', 'US', 'EU']);
      expect(asStringList(null), isEmpty);
    });

    test('parseServerDateTime tollera spazio, T, frazioni e offset', () {
      expect(parseServerDateTime(null), isNull);
      expect(parseServerDateTime(''), isNull);
      expect(
        parseServerDateTime('2026-09-01 10:30:00'),
        DateTime(2026, 9, 1, 10, 30),
      );
      expect(
        parseServerDateTime('2026-09-01T10:30:00.123456'),
        DateTime(2026, 9, 1, 10, 30, 0, 123, 456),
      );
      expect(
        parseServerDateTime('2026-09-01 10:30:00.123456+00:00'),
        DateTime.utc(2026, 9, 1, 10, 30, 0, 123, 456),
      );
    });

    test('parseServerDate ignora la parte oraria', () {
      expect(parseServerDate('2026-09-01 10:30:00'), DateTime(2026, 9, 1));
      expect(parseServerDate('2026-09-01T23:59:59+02:00'), DateTime(2026, 9, 1));
    });
  });

  group('stock models', () {
    test('StockSearchResult e StockRecord', () {
      final search = StockSearchResult.fromJson({
        'ticker': 'AAPL',
        'name': 'Apple Inc.',
        'market': 'US',
      });
      expect(search.ticker, 'AAPL');
      expect(search.name, 'Apple Inc.');
      expect(search.market, 'US');

      final record = StockRecord.fromJson({
        'id': 3,
        'ticker': 'ENEL.MI',
        'name': 'Enel S.p.A.',
        'market': 'IT',
        'currency': 'EUR',
        'is_active': true,
      });
      expect(record.id, 3);
      expect(record.currency, 'EUR');
      expect(record.isActive, isTrue);
    });

    test('Candle con time int (intraday)', () {
      final candle = Candle.fromJson({
        'time': 1726000000,
        'open': 1.0,
        'high': 2.0,
        'low': 0.5,
        'close': 1.5,
        'value': 1.5,
        'volume': 100,
      });
      expect(candle.time, 1726000000);
      expect(candle.close, 1.5);
      expect(candle.volume, 100);
    });

    test('Candle con time stringa (giornaliero) e campi mancanti', () {
      final candle = Candle.fromJson({'time': '2026-09-12', 'close': 10.5});
      expect(candle.time, '2026-09-12');
      expect(candle.close, 10.5);
      expect(candle.open, isNull);
      expect(candle.volume, isNull);
    });
  });

  group('StockDetails', () {
    test('fallback stale senza ~20 chiavi: solo ticker obbligatorio', () {
      final fallback = StockDetails.fromJson({
        'ticker': 'AAPL',
        'name': 'Apple Inc.',
        'current_price': 190.0,
        'change_abs': 1.2,
        'change_percent': 0.64,
        'currency': 'USD',
        'stale': true,
        'technical': {
          'rsi_14': 52.0,
          'rsi_status': 'Neutro',
          'rsi_badge': 'badge-hold',
          'trend': 'Neutro',
        },
      });

      expect(fallback.ticker, 'AAPL');
      expect(fallback.stale, isTrue);
      expect(fallback.currentPrice, 190.0);
      expect(fallback.technical?.rsi14, 52.0);
      expect(fallback.technical?.sma20, isNull);
      // Campi omessi dal fallback.
      expect(fallback.previousClose, isNull);
      expect(fallback.dayHigh, isNull);
      expect(fallback.marketCap, isNull);
      expect(fallback.peRatio, isNull);
      expect(fallback.forwardPe, isNull);
      expect(fallback.eps, isNull);
      expect(fallback.beta, isNull);
      expect(fallback.dividendYield, isNull);
      expect(fallback.fiftyTwoWeekHigh, isNull);
      expect(fallback.fiftyTwoWeekLow, isNull);
      expect(fallback.sector, isNull);
      expect(fallback.industry, isNull);
      expect(fallback.summary, isNull);
    });

    test('scheda completa con technical annidato', () {
      final details = StockDetails.fromJson({
        'ticker': 'ENEL.MI',
        'stale': false,
        'name': 'Enel S.p.A.',
        'market': 'IT',
        'currency': 'EUR',
        'current_price': 7.15,
        'previous_close': 7.05,
        'change_abs': 0.1,
        'change_percent': 1.42,
        'day_high': 7.2,
        'day_low': 7.0,
        'volume': 12345678,
        'avg_volume': 20000000,
        'market_cap': 72000000000,
        'pe_ratio': 12.3,
        'forward_pe': 11.8,
        'eps': 0.58,
        'beta': 0.72,
        'dividend_yield': 6.1,
        'fifty_two_week_high': 7.9,
        'fifty_two_week_low': 5.4,
        'fifty_two_week_pct': 70.0,
        'sector': 'Utilities',
        'industry': 'Regulated Electric',
        'summary': 'Enel opera nel settore energetico.',
        'technical': {
          'rsi_14': 61.2,
          'rsi_status': 'Neutro (Neutral)',
          'rsi_badge': 'badge-hold',
          'sma_20': 7.02,
          'sma_50': 6.88,
          'trend': 'Rialzista (Bullish)',
        },
      });

      expect(details.market, 'IT');
      expect(details.dividendYield, 6.1);
      expect(details.fiftyTwoWeekPct, 70.0);
      expect(details.technical?.sma20, 7.02);
      expect(details.technical?.trend, 'Rialzista (Bullish)');
      expect(details.stale, isFalse);
    });
  });

  group('WatchlistItem', () {
    test('default backend quando il deep dive manca', () {
      final item = WatchlistItem.fromJson({
        'id': 1,
        'stock_id': 2,
        'ticker': 'X',
        'name': 'X Corp',
        'market': 'US',
        'currency': 'USD',
        'current_price': 0.0,
        'change_abs': 0.0,
        'change_percent': 0.0,
        'day_high': null,
        'day_low': null,
        'fifty_two_week_high': null,
        'fifty_two_week_low': null,
        'fifty_two_week_pct': null,
        'pe_ratio': null,
        'dividend_yield': null,
        'rsi': null,
        'rsi_status': null,
        'rsi_badge': null,
        'notes': '',
        'alert_above': null,
        'alert_below': 10.0,
        'alert_triggered': false,
        'is_in_portfolio': true,
        'added_at': '2026-09-01 08:00:00',
      });

      expect(item.currentPrice, 0);
      expect(item.fiftyTwoWeekHigh, 0);
      expect(item.fiftyTwoWeekLow, 0);
      expect(item.fiftyTwoWeekPct, 50);
      expect(item.rsi, 50);
      expect(item.rsiStatus, 'Neutro');
      expect(item.rsiBadge, 'badge-hold');
      expect(item.notes, '');
      expect(item.alertBelow, 10.0);
      expect(item.alertTriggered, isFalse);
      expect(item.isInPortfolio, isTrue);
      expect(item.addedAt, DateTime(2026, 9, 1, 8));
    });

    test('alert scattato e campi valorizzati', () {
      final item = WatchlistItem.fromJson({
        'id': 5,
        'stock_id': 7,
        'ticker': 'AAPL',
        'name': 'Apple Inc.',
        'market': 'US',
        'currency': 'USD',
        'current_price': 230.5,
        'change_percent': 1.2,
        'alert_above': 220.0,
        'alert_triggered': true,
        'notes': 'Breakout',
        'rsi': 71.5,
        'rsi_status': 'Ipercomprato (Overbought)',
        'rsi_badge': 'badge-sell',
      });
      expect(item.alertTriggered, isTrue);
      expect(item.alertAbove, 220.0);
      expect(item.rsiBadge, 'badge-sell');
      expect(item.notes, 'Breakout');
    });
  });

  group('portfolio models', () {
    test('Holding con nullable (previous_close/daily_pnl/purchase_date)', () {
      final holding = Holding.fromJson({
        'id': 1,
        'stock_id': 10,
        'ticker': 'AAPL',
        'name': 'Apple Inc.',
        'market': 'US',
        'currency': 'USD',
        'quantity': 10.0,
        'avg_purchase_price': 150.0,
        'current_price': 190.0,
        'previous_close': null,
        'price_stale': true,
        'total_value': 1900.0,
        'total_invested': 1500.0,
        'total_value_eur': 1748.0,
        'total_invested_eur': 1380.0,
        'fx_rate_to_eur': 0.92,
        'pnl_absolute': 400.0,
        'pnl_percent': 26.67,
        'daily_pnl': null,
        'purchase_date': null,
        'notes': '',
      });

      expect(holding.previousClose, isNull);
      expect(holding.dailyPnl, isNull);
      expect(holding.purchaseDate, isNull);
      expect(holding.priceStale, isTrue);
      expect(holding.totalValueEur, 1748.0);
      expect(holding.fxRateToEur, 0.92);
      expect(holding.notes, '');
    });

    test('PortfolioSummary con top gainer e market allocation', () {
      final summary = PortfolioSummary.fromJson({
        'total_value': 10000.0,
        'total_invested': 9000.0,
        'total_pnl': 1000.0,
        'total_pnl_percent': 11.11,
        'daily_pnl': 50.0,
        'daily_pnl_percent': 0.5,
        'holdings_count': 2,
        'top_gainer': {
          'id': 1,
          'stock_id': 10,
          'ticker': 'AAPL',
          'name': 'Apple Inc.',
          'market': 'US',
          'currency': 'USD',
          'quantity': 10.0,
          'avg_purchase_price': 150.0,
          'current_price': 190.0,
          'pnl_percent': 26.67,
        },
        'top_loser': null,
        'market_allocation': {'IT': 4000.0, 'US': 6000.0, 'EU': 0.0},
        'estimated_annual_dividends': 120.0,
        'estimated_dividend_yield': 1.2,
        'fx_usd_eur': 0.92,
      });

      expect(summary.holdingsCount, 2);
      expect(summary.topGainer?.ticker, 'AAPL');
      expect(summary.topLoser, isNull);
      expect(summary.marketAllocation['US'], 6000.0);
      expect(summary.estimatedAnnualDividends, 120.0);
      expect(summary.fxUsdEur, 0.92);
    });

    test('RiskMetrics con betas e serie opzionale', () {
      final metrics = RiskMetrics.fromJson({
        'days_analyzed': 120,
        'series_start': '2026-01-01',
        'series_end': null,
        'max_drawdown_pct': -8.5,
        'annualized_volatility_pct': 14.2,
        'sharpe_ratio': 0.85,
        'annualized_return_pct': 12.3,
        'weighted_beta': 1.05,
        'risk_free_rate_pct': 3.5,
        'current_value': 10000.0,
        'betas': {'AAPL': 1.2, 'ENEL.MI': 0.72},
      });

      expect(metrics.daysAnalyzed, 120);
      expect(metrics.seriesStart, DateTime(2026, 1, 1));
      expect(metrics.seriesEnd, isNull);
      expect(metrics.betas?['AAPL'], 1.2);
      expect(metrics.maxDrawdownPct, -8.5);
    });

    test('BenchmarksResult con map annidata', () {
      final result = BenchmarksResult.fromJson({
        'start_date': '2026-06-01',
        'end_date': '2026-09-01',
        'portfolio': [
          {'date': '2026-06-01', 'growth_pct': 0.0},
          {'date': '2026-09-01', 'growth_pct': 6.2},
        ],
        'benchmarks': {
          '^GSPC': {
            'name': 'S&P 500',
            'flag': '🇺🇸',
            'data': [
              {'date': '2026-06-01', 'growth_pct': 0.0},
              {'date': '2026-09-01', 'growth_pct': 4.1},
            ],
          },
          'FTSEMIB.MI': {'name': 'FTSE MIB', 'flag': '🇮🇹', 'data': []},
        },
      });

      expect(result.startDate, DateTime(2026, 6, 1));
      expect(result.portfolio.length, 2);
      expect(result.portfolio.last.growthPct, 6.2);
      expect(result.benchmarks['^GSPC']?.name, 'S&P 500');
      expect(result.benchmarks['^GSPC']?.data.first.growthPct, 0.0);
      expect(result.benchmarks['FTSEMIB.MI']?.data, isEmpty);
    });

    test('DividendsResult e DividendHolding', () {
      final result = DividendsResult.fromJson({
        'holdings': [
          {
            'ticker': 'ENEL.MI',
            'name': 'Enel S.p.A.',
            'market': 'IT',
            'currency': 'EUR',
            'quantity': 400.0,
            'current_price': 7.15,
            'avg_purchase_price': 6.2,
            'dividend_yield_pct': 6.1,
            'yield_on_cost_pct': 7.03,
            'annual_dividend_per_share': 0.44,
            'annual_income_eur': 176.0,
            'monthly_income_eur': 14.67,
          },
        ],
        'total_annual_dividend_eur': 176.0,
        'total_monthly_dividend_eur': 14.67,
        'portfolio_total_value': 2860.0,
        'portfolio_yield_on_cost': 7.03,
      });

      expect(result.holdings.single.ticker, 'ENEL.MI');
      expect(result.holdings.single.monthlyIncomeEur, 14.67);
      expect(result.totalAnnualDividendEur, 176.0);
      expect(result.portfolioYieldOnCost, 7.03);
    });

    test('Transaction con data separata da spazio e pnl nullo', () {
      final tx = Transaction.fromJson({
        'id': 4,
        'stock_id': 1,
        'ticker': 'AAPL',
        'name': 'Apple Inc.',
        'market': 'US',
        'type': 'BUY',
        'quantity': 5.0,
        'price': 150.0,
        'fee': 1.5,
        'realized_pnl': null,
        'currency': 'USD',
        'transaction_date': '2026-08-20 14:45:00.123456',
        'notes': 'Primo ingresso',
      });

      expect(tx.realizedPnl, isNull);
      expect(tx.transactionDate, DateTime(2026, 8, 20, 14, 45, 0, 123, 456));
      expect(tx.type, 'BUY');
      expect(tx.notes, 'Primo ingresso');
    });

    test('Transaction con offset timezone', () {
      final tx = Transaction.fromJson({
        'id': 5,
        'stock_id': 1,
        'ticker': 'AAPL',
        'type': 'SELL',
        'transaction_date': '2026-08-21T09:05:00+00:00',
        'realized_pnl': 12.5,
      });
      expect(tx.transactionDate, DateTime.utc(2026, 8, 21, 9, 5));
      expect(tx.realizedPnl, 12.5);
    });

    test('RealizedPnl', () {
      final pnl = RealizedPnl.fromJson({
        'total_realized_capital_gains': 250.5,
        'total_dividends_collected': 80.0,
        'total_fees_paid': 12.0,
        'net_realized_profit': 318.5,
        'trade_count': 6,
        'win_trades': 4,
        'loss_trades': 2,
        'win_rate_percent': 66.7,
        'transactions_count': 10,
      });

      expect(pnl.netRealizedProfit, 318.5);
      expect(pnl.winTrades, 4);
      expect(pnl.lossTrades, 2);
      expect(pnl.winRatePercent, 66.7);
    });

    test('RebalancePreview con allocazioni e ordini', () {
      final preview = RebalancePreview.fromJson({
        'total_value': 10000.0,
        'extra_cash': 500.0,
        'targets_sum_percent': 100.0,
        'allocations': [
          {
            'id': 1,
            'name': 'Italia',
            'scope_type': 'MARKET',
            'scope_value': 'IT',
            'target_percent': 60.0,
            'current_percent': 55.0,
            'target_value': 6000.0,
            'current_value': 5500.0,
            'delta': 500.0,
            'drift_pct': 5.0,
          },
        ],
        'orders': [
          {
            'ticker': 'ENEL.MI',
            'name': 'Enel S.p.A.',
            'allocation_name': 'Italia',
            'side': 'BUY',
            'quantity': 69.93,
            'estimated_price': 7.15,
            'estimated_value': 500.0,
            'currency': 'EUR',
          },
        ],
        'orders_count': 1,
        'total_buy_value': 500.0,
        'total_sell_value': 0.0,
        'portfolio_empty': false,
      });

      expect(preview.allocations.single.driftPct, 5.0);
      expect(preview.orders.single.side, 'BUY');
      expect(preview.orders.single.allocationName, 'Italia');
      expect(preview.ordersCount, 1);
      expect(preview.totalBuyValue, 500.0);
      expect(preview.totalSellValue, 0.0);
      expect(preview.portfolioEmpty, isFalse);
    });

    test('RebalanceTarget con scope value vuoto', () {
      final target = RebalanceTarget.fromJson({
        'id': 3,
        'name': 'Cash',
        'target_percent': 10.0,
        'scope_type': 'CASH',
        'scope_value': '',
      });
      expect(target.scopeType, 'CASH');
      expect(target.scopeValue, '');
      expect(target.targetPercent, 10.0);
    });
  });

  group('dashboard models', () {
    test('DashboardData con market status e advice recenti', () {
      final dashboard = DashboardData.fromJson({
        'portfolio_summary': {
          'total_value': 10000.0,
          'total_invested': 9000.0,
          'holdings_count': 2,
          'market_allocation': {'IT': 4000.0, 'US': 6000.0, 'EU': 0.0},
        },
        'recent_advices': [
          {
            'id': 7,
            'market': 'IT',
            'title': 'Borsa Italiana',
            'action': 'MANTENIMENTO',
            'overview': 'Consolidamento.',
            'strategy': 'Selettività.',
            'stocks_analysis': [],
            'risks': null,
            'confidence': 'MEDIUM',
            'timeframe': 'Medio Termine',
            'targetPrice': null,
            'suggestedQuantity': null,
            'followed': false,
            'timestamp': '2026-09-13 09:00:00',
            'ticker': null,
            'name': null,
          },
        ],
        'active_alerts_count': 2,
        'market_status': {
          'IT': 'OPEN',
          'US': 'CLOSED',
          'EU': 'CLOSED',
          'ANY_OPEN': 'OPEN',
          'details': {
            'IT': {
              'name': 'Borsa Italiana (Milano)',
              'flag': '🇮🇹',
              'status': 'OPEN',
              'hours': '09:00 - 17:30',
            },
            'US': {
              'name': 'Wall Street (New York)',
              'flag': '🇺🇸',
              'status': 'CLOSED',
              'hours': '15:30 - 22:00',
            },
          },
        },
      });

      expect(dashboard.portfolioSummary.totalValue, 10000.0);
      expect(dashboard.recentAdvices.length, 1);
      expect(dashboard.recentAdvices.single.title, 'Borsa Italiana');
      expect(dashboard.activeAlertsCount, 2);
      expect(dashboard.marketStatus.it, 'OPEN');
      expect(dashboard.marketStatus.us, 'CLOSED');
      expect(dashboard.marketStatus.anyOpen, isTrue);
      expect(dashboard.marketStatus.details['IT']?.flag, '🇮🇹');
      expect(dashboard.marketStatus.details['US']?.hours, '15:30 - 22:00');
      expect(dashboard.marketStatus.details.containsKey('EU'), isFalse);
    });

    test('IndexQuote, HeatmapItem e PerformanceSeries', () {
      final index = IndexQuote.fromJson({
        'ticker': '^GSPC',
        'name': 'S&P 500',
        'flag': '🇺🇸',
        'type': 'index',
        'price': 5600.25,
        'change_abs': 12.5,
        'change_percent': 0.22,
        'stale': false,
      });
      expect(index.price, 5600.25);
      expect(index.stale, isFalse);

      final heat = HeatmapItem.fromJson({
        'ticker': 'AAPL',
        'name': 'Apple Inc.',
        'market': 'US',
        'currency': 'USD',
        'current_price': 190.0,
        'change_percent': -1.2,
        'change_abs': -2.3,
        'day_high': 193.0,
        'day_low': 188.0,
        'volume': 1000000,
        'stale': true,
      });
      expect(heat.changePercent, -1.2);
      expect(heat.volume, 1000000);
      expect(heat.stale, isTrue);

      final perf = PerformanceSeries.fromJson({
        'data': [
          {'date': '2026-09-01', 'value': 9000.0},
          {'date': '2026-09-02', 'value': 9100.0},
        ],
        'source': 'real',
        'points': 2,
      });
      expect(perf.source, 'real');
      expect(perf.points, 2);
      expect(perf.data.last.value, 9100.0);
    });

    test('PerformanceSeries senza points usa la lunghezza della serie', () {
      final perf = PerformanceSeries.fromJson({
        'data': [
          {'date': '2026-09-01', 'value': 1.0},
        ],
        'source': 'fallback',
      });
      expect(perf.points, 1);
    });
  });

  group('advice models', () {
    test('Advice list con camelCase e stocks_analysis snake_case', () {
      final advice = Advice.fromJson({
        'id': 12,
        'market': 'US',
        'title': 'Borsa Americana (Wall Street)',
        'action': 'ACCUMULO',
        'overview': 'Resilienza tech.',
        'strategy': 'Accumulare sui pullback.',
        'stocks_analysis': [
          {
            'ticker': 'AAPL',
            'name': 'Apple Inc.',
            'action': 'BUY',
            'priority': 'ALTA',
            'target_price': 250.0,
            'note': 'Breakout',
          },
        ],
        'risks': 'Volatilità macro.',
        'confidence': 'HIGH',
        'timeframe': 'Medio Termine',
        'targetPrice': 240.5,
        'suggestedQuantity': 3.0,
        'followed': true,
        'timestamp': '2026-09-13T08:15:00',
        'ticker': 'AAPL',
        'name': 'Apple Inc.',
      });

      expect(advice.id, 12);
      expect(advice.targetPrice, 240.5);
      expect(advice.suggestedQuantity, 3.0);
      expect(advice.followed, isTrue);
      expect(advice.stocksAnalysis.single.ticker, 'AAPL');
      expect(advice.stocksAnalysis.single.targetPrice, 250.0);
      expect(advice.timestamp, DateTime(2026, 9, 13, 8, 15));
    });

    test('latest senza ticker/name', () {
      final advice = Advice.fromJson({
        'id': 9,
        'market': 'ALL',
        'title': 'Analisi di Mercato',
        'action': 'PRUDENZA',
        'overview': 'Attendere.',
        'strategy': 'Liquidità.',
        'stocks_analysis': [],
        'risks': null,
        'confidence': 'MEDIUM',
        'timeframe': 'Breve Termine',
        'targetPrice': null,
        'suggestedQuantity': null,
        'followed': false,
        'timestamp': '2026-09-13 07:00:00',
      });

      expect(advice.ticker, isNull);
      expect(advice.name, isNull);
      expect(advice.stocksAnalysis, isEmpty);
      expect(advice.timestamp, DateTime(2026, 9, 13, 7));
    });

    test('generate non ha id e conta gli advice', () {
      final result = GenerateAdviceResult.fromJson({
        'status': 'success',
        'generated_count': 2,
        'advices': [
          {
            'market': 'IT',
            'title': 'Borsa Italiana (Piazza Affari)',
            'action': 'MANTENIMENTO',
            'overview': 'Consolidamento.',
            'strategy': 'Selettività.',
            'stocks_analysis': [],
            'risks': null,
            'confidence': 'MEDIUM',
            'timeframe': 'Medio Termine',
            'timestamp': '2026-09-13 09:00:00',
            'user_id': 1,
          },
        ],
      });

      expect(result.status, 'success');
      expect(result.generatedCount, 2);
      expect(result.advices.single.id, isNull);
    });

    test('StockAnalysis con holding_context', () {
      final analysis = StockAnalysis.fromJson({
        'ticker': 'AAPL',
        'name': 'Apple Inc.',
        'action': 'MANTENIMENTO',
        'action_label': '🟡 Mantenimento / Hold',
        'target_price': 210.0,
        'stop_loss': 175.0,
        'upside_potential_pct': 10.5,
        'timeframe': 'Medio Termine',
        'confidence': 'MEDIA',
        'summary': 'Sintesi.',
        'bull_case': 'Servizi in crescita.',
        'bear_case': 'Valutazioni elevate.',
        'technical_verdict': 'RSI neutro.',
        'operational_strategy': 'Mantenere.',
        'holding_context': {
          'in_portfolio': true,
          'quantity': 10.0,
          'avg_purchase_price': 150.0,
          'total_invested': 1500.0,
          'current_pnl_abs': 400.0,
          'current_pnl_pct': 26.67,
        },
      });

      expect(analysis.actionLabel, '🟡 Mantenimento / Hold');
      expect(analysis.upsidePotentialPct, 10.5);
      expect(analysis.holdingContext?.inPortfolio, isTrue);
      expect(analysis.holdingContext?.currentPnlPct, 26.67);
    });

    test('StockAnalysis con holding_context null', () {
      final analysis = StockAnalysis.fromJson({
        'ticker': 'AAPL',
        'action': 'PRUDENZA',
        'holding_context': null,
      });
      expect(analysis.holdingContext, isNull);
      expect(analysis.bullCase, isNull);
    });
  });

  group('settings models', () {
    test('UserSettings GET include apiStatus', () {
      final settings = UserSettings.fromJson({
        'id': 4,
        'strategy': 'long_term',
        'markets': ['IT', 'US', 'EU'],
        'budget': 15000.0,
        'total_budget': 15000.0,
        'reportFreq': 2,
        'reportTimes': ['09:00', '18:00'],
        'apiStatus': {
          'telegram': true,
          'gemini': false,
          'gemini_model': 'gemini-3.7-flash',
          'reddit': true,
        },
      });

      expect(settings.id, 4);
      expect(settings.markets, ['IT', 'US', 'EU']);
      expect(settings.budget, 15000.0);
      expect(settings.totalBudget, 15000.0);
      expect(settings.reportTimes, ['09:00', '18:00']);
      expect(settings.apiStatus?.telegram, isTrue);
      expect(settings.apiStatus?.gemini, isFalse);
      expect(settings.apiStatus?.geminiModel, 'gemini-3.7-flash');
    });

    test('UserSettings PUT senza apiStatus', () {
      final settings = UserSettings.fromJson({
        'id': 4,
        'strategy': 'short_term',
        'markets': ['US'],
        'budget': 5000.0,
        'total_budget': 5000.0,
        'reportFreq': 1,
        'reportTimes': [],
      });

      expect(settings.apiStatus, isNull);
      expect(settings.markets, ['US']);
      expect(settings.reportTimes, isEmpty);
    });

    test('UserSettings tollera campi null legacy', () {
      final settings = UserSettings.fromJson({
        'id': null,
        'strategy': null,
        'markets': null,
        'budget': null,
        'total_budget': null,
        'reportFreq': null,
        'reportTimes': null,
      });

      expect(settings.id, isNull);
      expect(settings.strategy, 'mixed');
      expect(settings.markets, isEmpty);
      expect(settings.reportFreq, 2);
    });

    test('AlertRule da GET con name e threshold_percent', () {
      final rule = AlertRule.fromJson({
        'id': 9,
        'stock_id': 3,
        'ticker': 'AAPL',
        'name': 'Apple Inc.',
        'direction': 'BOTH',
        'threshold': 5.0,
        'threshold_percent': 5.0,
        'active': true,
      });

      expect(rule.name, 'Apple Inc.');
      expect(rule.threshold, 5.0);
      expect(rule.thresholdPercent, 5.0);
      expect(rule.active, isTrue);
    });

    test('AlertRule da POST senza name/threshold_percent', () {
      final rule = AlertRule.fromJson({
        'id': 10,
        'stock_id': 3,
        'ticker': 'AAPL',
        'direction': 'UP',
        'threshold': 3.5,
        'active': true,
      });

      expect(rule.name, isNull);
      expect(rule.thresholdPercent, isNull);
      expect(rule.threshold, 3.5);
      expect(rule.direction, 'UP');
    });
  });

  group('user models', () {
    test('AuthUser dal profilo /me', () {
      final user = AuthUser.fromJson({
        'id': 1,
        'username': 'admin',
        'is_admin': true,
        'is_active': true,
        'created_at': '2026-01-01T10:00:00',
        'last_login': '2026-09-13 09:30:00',
      });

      expect(user.id, 1);
      expect(user.username, 'admin');
      expect(user.isAdmin, isTrue);
      expect(user.createdAt, DateTime(2026, 1, 1, 10));
      expect(user.lastLogin, DateTime(2026, 9, 13, 9, 30));
    });

    test('AuthUser con campi opzionali assenti', () {
      final user = AuthUser.fromJson({'id': 2, 'username': 'mario'});
      expect(user.isAdmin, isFalse);
      expect(user.isActive, isTrue);
      expect(user.createdAt, isNull);
      expect(user.lastLogin, isNull);
    });

    test('LoginResult', () {
      final login = LoginResult.fromJson({
        'access_token': 'jwt-token',
        'token_type': 'bearer',
        'username': 'admin',
        'is_admin': true,
      });
      expect(login.accessToken, 'jwt-token');
      expect(login.username, 'admin');
      expect(login.isAdmin, isTrue);
    });
  });
}
