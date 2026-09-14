import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api_client.dart';
import '../formatters.dart';
import '../models/parse_utils.dart';
import '../models/portfolio.dart';

/// Portfolio, trade ledger, dividends and smart rebalancer endpoints.
class PortfolioApi {
  const PortfolioApi(this._client);

  final ApiClient _client;

  // --- Holdings & summary -------------------------------------------------

  /// `GET /api/portfolio/`
  ///
  /// Guardia array: un payload non-lista è un errore di contratto, non un
  /// portafoglio vuoto. Lancia [ApiException] così la UI mostra l'errore
  /// pulito invece di un falso "Nessun titolo nel portafoglio".
  Future<List<Holding>> holdings() async {
    final data = await _client.get('/portfolio/');
    if (data is! List) {
      throw ApiException('Risposta holdings non valida.');
    }
    return asMapList(data).map(Holding.fromJson).toList();
  }

  /// `GET /api/portfolio/summary`
  Future<PortfolioSummary> summary() async {
    final data = await _client.get('/portfolio/summary');
    return PortfolioSummary.fromJson(asMap(data));
  }

  /// `GET /api/portfolio/risk-metrics?days=`
  Future<RiskMetrics> riskMetrics(int days) async {
    final data = await _client.get(
      '/portfolio/risk-metrics',
      query: {'days': days},
    );
    return RiskMetrics.fromJson(asMap(data));
  }

  /// `GET /api/portfolio/benchmarks?days=&tickers=`
  ///
  /// [tickers] is the optional comma separated benchmark list.
  Future<BenchmarksResult> benchmarks(int days, {List<String>? tickers}) async {
    final data = await _client.get(
      '/portfolio/benchmarks',
      query: {
        'days': days,
        if (tickers != null && tickers.isNotEmpty) 'tickers': tickers.join(','),
      },
    );
    return BenchmarksResult.fromJson(asMap(data));
  }

  /// `POST /api/portfolio/seed-demo`
  Future<Map<String, dynamic>> seedDemo() async {
    final data = await _client.post('/portfolio/seed-demo');
    return asMap(data);
  }

  /// `POST /api/portfolio/holdings`
  ///
  /// Specify either [ticker] or [stockId]; an existing position is merged.
  Future<Holding> addHolding({
    String? ticker,
    int? stockId,
    required double quantity,
    required double avgPurchasePrice,
    DateTime? purchaseDate,
    String? notes,
  }) async {
    final data = await _client.post(
      '/portfolio/holdings',
      body: {
        'ticker': ticker,
        'stock_id': stockId,
        'quantity': quantity,
        'avg_purchase_price': avgPurchasePrice,
        'purchase_date': purchaseDate == null ? null : dateToApi(purchaseDate),
        'notes': notes,
      },
    );
    return Holding.fromJson(asMap(data));
  }

  /// `DELETE /api/portfolio/holdings/{id}`
  Future<void> deleteHolding(int id) async {
    await _client.delete('/portfolio/holdings/$id');
  }

  /// `PUT /api/portfolio/batch`
  Future<Map<String, dynamic>> batchUpdateHoldings(
    List<({int id, double quantity, double avgPurchasePrice, String? notes})>
    holdings,
  ) async {
    final data = await _client.put(
      '/portfolio/batch',
      body: {
        'holdings': [
          for (final item in holdings)
            {
              'id': item.id,
              'quantity': item.quantity,
              'avg_purchase_price': item.avgPurchasePrice,
              'notes': item.notes,
            },
        ],
      },
    );
    return asMap(data);
  }

  // --- Transactions & realised P&L ----------------------------------------

  /// `GET /api/portfolio/transactions?type=`
  ///
  /// Guardia array: payload non-lista → [ApiException] (niente ledger vuoto
  /// silenzioso).
  Future<List<Transaction>> transactions({String? type}) async {
    final data = await _client.get(
      '/portfolio/transactions',
      query: type == null ? null : {'type': type},
    );
    if (data is! List) {
      throw ApiException('Risposta transazioni non valida.');
    }
    return asMapList(data).map(Transaction.fromJson).toList();
  }

  /// `POST /api/portfolio/transactions`
  ///
  /// [transactionDate] is serialised as a local `yyyy-MM-dd` (no UTC shift).
  Future<Transaction> createTransaction({
    required String ticker,
    required String type,
    double quantity = 0,
    double price = 0,
    double fee = 0,
    DateTime? transactionDate,
    String? notes,
  }) async {
    final data = await _client.post(
      '/portfolio/transactions',
      body: {
        'ticker': ticker,
        'type': type,
        'quantity': quantity,
        'price': price,
        'fee': fee,
        'transaction_date': transactionDate == null
            ? null
            : dateToApi(transactionDate),
        'notes': notes ?? '',
      },
    );
    return Transaction.fromJson(asMap(asMap(data)['transaction']));
  }

  /// `DELETE /api/portfolio/transactions/{id}`
  Future<void> deleteTransaction(int id) async {
    await _client.delete('/portfolio/transactions/$id');
  }

  /// `GET /api/portfolio/realized-pnl`
  Future<RealizedPnl> realizedPnl() async {
    final data = await _client.get('/portfolio/realized-pnl');
    return RealizedPnl.fromJson(asMap(data));
  }

  // --- Dividends ----------------------------------------------------------

  /// `GET /api/portfolio/dividends`
  ///
  /// Guardia array sulla lista annidata `holdings`: un payload senza lista
  /// valida è un errore di contratto, non un calendario dividendi vuoto.
  Future<DividendsResult> dividends() async {
    final data = await _client.get('/portfolio/dividends');
    final Map<String, dynamic> payload = asMap(data);
    if (payload['holdings'] is! List) {
      throw ApiException('Risposta dividendi non valida.');
    }
    return DividendsResult.fromJson(payload);
  }

  // --- Smart rebalancer ---------------------------------------------------

  /// `GET /api/portfolio/rebalance/targets`
  ///
  /// Guardia array: payload non-lista → [ApiException] (niente tabella target
  /// vuota con "Nessuna allocazione target definita" fuorviante).
  Future<List<RebalanceTarget>> rebalanceTargets() async {
    final data = await _client.get('/portfolio/rebalance/targets');
    if (data is! List) {
      throw ApiException('Risposta allocazioni target non valida.');
    }
    return asMapList(data).map(RebalanceTarget.fromJson).toList();
  }

  /// `POST /api/portfolio/rebalance/targets`
  Future<RebalanceTarget> addRebalanceTarget({
    required String name,
    required double targetPercent,
    String scopeType = 'MARKET',
    String scopeValue = '',
  }) async {
    final data = await _client.post(
      '/portfolio/rebalance/targets',
      body: {
        'name': name,
        'target_percent': targetPercent,
        'scope_type': scopeType,
        'scope_value': scopeValue,
      },
    );
    return RebalanceTarget.fromJson(asMap(data));
  }

  /// `DELETE /api/portfolio/rebalance/targets/{id}`
  Future<void> deleteRebalanceTarget(int id) async {
    await _client.delete('/portfolio/rebalance/targets/$id');
  }

  /// `POST /api/portfolio/rebalance/preview`
  Future<RebalancePreview> rebalancePreview(double extraCash) async {
    final data = await _client.post(
      '/portfolio/rebalance/preview',
      body: {'extra_cash': extraCash},
    );
    return RebalancePreview.fromJson(asMap(data));
  }

  // --- Import / export ----------------------------------------------------

  /// `POST /api/portfolio/import` (multipart, field `file`).
  Future<Map<String, dynamic>> importCsv({
    required List<int> bytes,
    required String filename,
  }) async {
    final data = await _client.uploadMultipart(
      '/portfolio/import',
      field: 'file',
      bytes: bytes,
      filename: filename,
    );
    return asMap(data);
  }

  /// `GET /api/portfolio/export?format=csv`
  Future<Uint8List> exportCsv() {
    return _client.downloadBytes('/portfolio/export', query: {'format': 'csv'});
  }
}

final portfolioApiProvider = Provider<PortfolioApi>(
  (ref) => PortfolioApi(ref.watch(apiClientProvider)),
);
