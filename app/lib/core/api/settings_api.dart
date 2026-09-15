import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api_client.dart';
import '../models/parse_utils.dart';
import '../models/settings.dart';

/// Settings and alert rules endpoints.
class SettingsApi {
  const SettingsApi(this._client);

  final ApiClient _client;

  /// `GET /api/settings/`
  Future<UserSettings> getSettings() async {
    final data = await _client.get('/settings/');
    return UserSettings.fromJson(asMap(data));
  }

  /// `PUT /api/settings/`
  ///
  /// Only the provided fields are sent; the response has no `apiStatus`.
  Future<UserSettings> updateSettings({
    String? strategy,
    double? budget,
    List<String>? markets,
    int? reportFreq,
    List<String>? reportTimes,
  }) async {
    final data = await _client.put(
      '/settings/',
      body: {
        'strategy': ?strategy,
        'budget': ?budget,
        'markets': ?markets,
        'reportFreq': ?reportFreq,
        'reportTimes': ?reportTimes,
      },
    );
    return UserSettings.fromJson(asMap(data));
  }

  /// `GET /api/settings/alerts`
  Future<List<AlertRule>> getAlertRules() async {
    final data = await _client.get('/settings/alerts');
    return asMapList(data).map(AlertRule.fromJson).toList();
  }

  /// `POST /api/settings/alerts`
  ///
  /// The response omits `name` and `threshold_percent`.
  Future<AlertRule> addAlertRule({
    required String ticker,
    required double threshold,
    String direction = 'BOTH',
    bool active = true,
  }) async {
    final data = await _client.post(
      '/settings/alerts',
      body: {
        'ticker': ticker,
        'threshold': threshold,
        'direction': direction,
        'active': active,
      },
    );
    return AlertRule.fromJson(asMap(data));
  }

  /// `DELETE /api/settings/alerts/{id}`
  Future<void> deleteAlertRule(int id) async {
    await _client.delete('/settings/alerts/$id');
  }

  /// `POST /api/settings/telegram/test`
  Future<void> testTelegram() async {
    await _client.post('/settings/telegram/test');
  }

  /// `PUT /api/settings/gemini-key`
  ///
  /// Salva la chiave Gemini cifrata (mai restituita intera dal server).
  Future<Map<String, dynamic>> saveGeminiKey({required String key}) async {
    final data = await _client.put('/settings/gemini-key', body: {'key': key});
    return asMap(data);
  }

  /// `POST /api/settings/gemini/test`
  ///
  /// Sempre 200 con `{ok, reason?, model}`; mai eccezione per chiave invalida.
  Future<GeminiTestResult> testGemini() async {
    final data = await _client.post('/settings/gemini/test');
    return GeminiTestResult.fromJson(asMap(data));
  }
}

final settingsApiProvider = Provider<SettingsApi>(
  (ref) => SettingsApi(ref.watch(apiClientProvider)),
);
