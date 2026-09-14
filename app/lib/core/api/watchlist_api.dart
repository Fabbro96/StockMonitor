import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api_client.dart';
import '../models/parse_utils.dart';
import '../models/watchlist_item.dart';

/// Outcome of a watchlist mutation (`POST /api/watchlist/` and friends).
class WatchlistMutationResult {
  final String status;
  final String message;
  final int? id;

  const WatchlistMutationResult({
    required this.status,
    this.message = '',
    this.id,
  });

  factory WatchlistMutationResult.fromJson(Map<String, dynamic> json) {
    return WatchlistMutationResult(
      status: asString(json['status']),
      message: asString(json['message']),
      id: asInt(json['id']),
    );
  }
}

/// Watchlist endpoints.
class WatchlistApi {
  const WatchlistApi(this._client);

  final ApiClient _client;

  /// `GET /api/watchlist/`
  ///
  /// Guardia array (bug #7): un payload non-lista è un errore di contratto,
  /// non una watchlist vuota. Lancia [ApiException] così il provider passa in
  /// `AsyncError` (toast + empty + retry) invece di mostrare "Nessun titolo".
  Future<List<WatchlistItem>> list() async {
    final data = await _client.get('/watchlist/');
    if (data is! List) {
      throw ApiException('Risposta watchlist non valida.');
    }
    return asMapList(data).map(WatchlistItem.fromJson).toList();
  }

  /// `POST /api/watchlist/`
  ///
  /// The response can be `exists` when the ticker was already present (in that
  /// case the notes/alerts are updated server side).
  Future<WatchlistMutationResult> add({
    required String ticker,
    String? notes,
    double? alertAbove,
    double? alertBelow,
  }) async {
    final data = await _client.post(
      '/watchlist/',
      body: {
        'ticker': ticker,
        'notes': notes,
        'alert_above': alertAbove,
        'alert_below': alertBelow,
      },
    );
    return WatchlistMutationResult.fromJson(asMap(data));
  }

  /// `PUT /api/watchlist/{id}/alert`
  ///
  /// Both thresholds are always overwritten: passing `null` clears the alert.
  Future<WatchlistMutationResult> updateAlert(
    int id, {
    double? above,
    double? below,
  }) async {
    final data = await _client.put(
      '/watchlist/$id/alert',
      body: {'alert_above': above, 'alert_below': below},
    );
    return WatchlistMutationResult.fromJson(asMap(data));
  }

  /// `DELETE /api/watchlist/{id}`
  Future<WatchlistMutationResult> remove(int id) async {
    final data = await _client.delete('/watchlist/$id');
    return WatchlistMutationResult.fromJson(asMap(data));
  }

  /// `DELETE /api/watchlist/ticker/{ticker}`
  Future<WatchlistMutationResult> removeByTicker(String ticker) async {
    final data = await _client.delete('/watchlist/ticker/$ticker');
    return WatchlistMutationResult.fromJson(asMap(data));
  }
}

final watchlistApiProvider = Provider<WatchlistApi>(
  (ref) => WatchlistApi(ref.watch(apiClientProvider)),
);
