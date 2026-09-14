import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_monitor/core/api/dashboard_api.dart';
import 'package:stock_monitor/core/api_client.dart';
import 'package:stock_monitor/core/models/dashboard.dart';
import 'package:stock_monitor/features/advice/advice_providers.dart';

/// Doppio di [ApiClient] per `GET /dashboard/market-status`.
class _FakeApiClient extends ApiClient {
  _FakeApiClient({this.getResponse});

  Object? getResponse;
  int getCalls = 0;
  String? lastGetPath;

  @override
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    Duration? receiveTimeout,
  }) async {
    getCalls++;
    lastGetPath = path;
    return getResponse;
  }
}

Map<String, dynamic> _statusBlock() => <String, dynamic>{
  'IT': 'OPEN',
  'US': 'CLOSED',
  'EU': 'CLOSED',
  'ANY_OPEN': 'OPEN',
  'details': <String, dynamic>{
    'IT': <String, dynamic>{
      'name': 'Borsa Italiana (Milano)',
      'flag': '🇮🇹',
      'status': 'OPEN',
      'hours': '09:00 - 17:30',
    },
  },
};

/// Doppio di [DashboardApi]: conta `marketStatus()` vs `dashboard()`.
class _FakeDashboardApi extends DashboardApi {
  _FakeDashboardApi() : super(ApiClient());

  int marketStatusCalls = 0;
  bool dashboardCalled = false;
  bool fail = false;

  @override
  Future<MarketStatusInfo> marketStatus() async {
    marketStatusCalls++;
    if (fail) throw ApiException('rete assente');
    return MarketStatusInfo.fromJson(_statusBlock());
  }

  @override
  Future<DashboardData> dashboard() async {
    dashboardCalled = true;
    throw StateError('dashboard() non deve essere chiamato');
  }
}

void main() {
  group('DashboardApi.marketStatus', () {
    test('chiama /dashboard/market-status e parsifica il blocco', () async {
      final _FakeApiClient client = _FakeApiClient(
        getResponse: _statusBlock(),
      );
      final MarketStatusInfo status = await DashboardApi(
        client,
      ).marketStatus();
      expect(client.lastGetPath, '/dashboard/market-status');
      expect(status.it, 'OPEN');
      expect(status.us, 'CLOSED');
      expect(status.anyOpen, isTrue);
      expect(status.details['IT']?.hours, '09:00 - 17:30');
    });
  });

  group('adviceMarketStatusProvider', () {
    test('usa marketStatus() e non dashboard()', () async {
      final _FakeDashboardApi api = _FakeDashboardApi();
      final ProviderContainer container = ProviderContainer(
        overrides: [dashboardApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      final MarketStatusInfo? status = await container.read(
        adviceMarketStatusProvider.future,
      );
      expect(status?.it, 'OPEN');
      expect(status?.anyOpen, isTrue);
      expect(api.marketStatusCalls, 1);
      expect(api.dashboardCalled, isFalse);
    });

    test('in errore restituisce null (fallback orologio)', () async {
      final _FakeDashboardApi api = _FakeDashboardApi()..fail = true;
      final ProviderContainer container = ProviderContainer(
        overrides: [dashboardApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      expect(
        await container.read(adviceMarketStatusProvider.future),
        isNull,
      );
      expect(api.marketStatusCalls, 1);
    });
  });
}
