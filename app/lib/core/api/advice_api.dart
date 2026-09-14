import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api_client.dart';
import '../models/advice.dart';
import '../models/parse_utils.dart';

/// Advice endpoints: history (with `skip`/`limit`), latest, follow toggle,
/// generation and on-demand single stock analysis.
class AdviceApi {
  const AdviceApi(this._client);

  final ApiClient _client;

  /// `GET /api/advice/`
  ///
  /// Uses `skip`/`limit` (the backend has no `page`/`q` parameters).
  Future<List<Advice>> list({
    int? skip,
    int limit = 10,
    int? days,
    String? market,
    String? action,
    String? date,
  }) async {
    final data = await _client.get(
      '/advice/',
      query: {
        'skip': ?skip,
        'limit': limit,
        'days': ?days,
        'market': ?market,
        'action': ?action,
        'date': ?date,
      },
    );
    return asMapList(data).map(Advice.fromJson).toList();
  }

  /// `GET /api/advice/latest` (items have no `ticker`/`name`).
  Future<List<Advice>> latest() async {
    final data = await _client.get('/advice/latest');
    return asMapList(data).map(Advice.fromJson).toList();
  }

  /// `POST /api/advice/{id}/follow` — returns the new follow state.
  Future<bool> toggleFollow(int id) async {
    final data = await _client.post('/advice/$id/follow');
    return asBool(asMap(data)['followed']);
  }

  /// `POST /api/advice/generate?force=`
  ///
  /// Chiamata Gemini: può richiedere fino a ~2 minuti, quindi sovrascrive il
  /// timeout di ricezione globale (20s) con 120s.
  Future<GenerateAdviceResult> generate({bool force = false}) async {
    final data = await _client.post(
      '/advice/generate',
      query: {'force': force},
      receiveTimeout: _aiReceiveTimeout,
    );
    return GenerateAdviceResult.fromJson(asMap(data));
  }

  /// `POST /api/advice/stock/{ticker}`
  ///
  /// Chiamata Gemini on-demand: sovrascrive il timeout di ricezione con 120s.
  Future<StockAnalysis> analyzeStock(String ticker) async {
    final data = await _client.post(
      '/advice/stock/$ticker',
      receiveTimeout: _aiReceiveTimeout,
    );
    return StockAnalysis.fromJson(asMap(data));
  }

  /// Timeout di ricezione per le chiamate AI (Gemini, 60-120s).
  static const Duration _aiReceiveTimeout = Duration(seconds: 120);
}

final adviceApiProvider = Provider<AdviceApi>(
  (ref) => AdviceApi(ref.watch(apiClientProvider)),
);
