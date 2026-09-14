import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api_client.dart';
import '../models/dashboard.dart';
import '../models/parse_utils.dart';

/// Dashboard endpoints.
class DashboardApi {
  const DashboardApi(this._client);

  final ApiClient _client;

  /// `GET /api/dashboard/`
  Future<DashboardData> dashboard() async {
    final data = await _client.get('/dashboard/');
    return DashboardData.fromJson(asMap(data));
  }

  /// `GET /api/dashboard/indices`
  Future<List<IndexQuote>> indices() async {
    final data = await _client.get('/dashboard/indices');
    return asMapList(data).map(IndexQuote.fromJson).toList();
  }

  /// `GET /api/dashboard/heatmap`
  Future<List<HeatmapItem>> heatmap() async {
    final data = await _client.get('/dashboard/heatmap');
    return asMapList(data).map(HeatmapItem.fromJson).toList();
  }

  /// `GET /api/dashboard/performance?days=`
  Future<PerformanceSeries> performance(int days) async {
    final data = await _client.get(
      '/dashboard/performance',
      query: {'days': days},
    );
    return PerformanceSeries.fromJson(asMap(data));
  }
}

final dashboardApiProvider = Provider<DashboardApi>(
  (ref) => DashboardApi(ref.watch(apiClientProvider)),
);
