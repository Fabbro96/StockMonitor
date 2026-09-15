import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_monitor/core/api/settings_api.dart';
import 'package:stock_monitor/core/api_client.dart';
import 'package:stock_monitor/core/models/settings.dart';
import 'package:stock_monitor/core/session/auth_controller.dart';
import 'package:stock_monitor/core/storage.dart';
import 'package:stock_monitor/features/settings/settings_providers.dart';

/// Fake di [SettingsApi] con risposte controllabili.
class _FakeSettingsApi extends SettingsApi {
  _FakeSettingsApi() : super(ApiClient());

  UserSettings? getResult;
  UserSettings? putResult;
  List<AlertRule> rules = <AlertRule>[];
  AlertRule? createdRule;
  final List<int> deleted = <int>[];
  final List<Map<String, Object?>> updates = <Map<String, Object?>>[];
  int getCalls = 0;

  @override
  Future<UserSettings> getSettings() async {
    getCalls++;
    return getResult ?? const UserSettings();
  }

  @override
  Future<UserSettings> updateSettings({
    String? strategy,
    double? budget,
    List<String>? markets,
    int? reportFreq,
    List<String>? reportTimes,
  }) async {
    updates.add(<String, Object?>{
      'strategy': strategy,
      'budget': budget,
      'markets': markets,
      'reportFreq': reportFreq,
      'reportTimes': reportTimes,
    });
    return putResult ?? const UserSettings();
  }

  @override
  Future<List<AlertRule>> getAlertRules() async => List<AlertRule>.of(rules);

  @override
  Future<AlertRule> addAlertRule({
    required String ticker,
    required double threshold,
    String direction = 'BOTH',
    bool active = true,
  }) async {
    return createdRule ??
        AlertRule(
          id: 0,
          ticker: ticker,
          threshold: threshold,
          direction: direction,
        );
  }

  @override
  Future<void> deleteAlertRule(int id) async {
    deleted.add(id);
    rules = <AlertRule>[
      for (final AlertRule rule in rules)
        if (rule.id != id) rule,
    ];
  }
}

/// Fake di [AppStorage] con sessione e server in memoria.
class _FakeStorage implements AppStorage {
  String? token;
  String? username;
  String? server;

  @override
  Future<void> clearSession() async {
    token = null;
    username = null;
  }

  @override
  Future<String?> getServerBaseUrl() async => server;

  @override
  Future<bool> getSidebarCollapsed() async => false;

  @override
  Future<String?> getThemeMode() async => null;

  @override
  Future<String?> getToken() async => token;

  @override
  Future<String?> getUsername() async => username;

  @override
  Future<void> setServerBaseUrl(String url) async {
    server = url.trim();
    // Stessa semantica del vero storage: cambiare server azzera la sessione.
    await clearSession();
  }

  @override
  Future<void> setSidebarCollapsed(bool value) async {}

  @override
  Future<void> setThemeMode(String mode) async {}

  @override
  Future<void> setToken(String? value) async => token = value;

  @override
  Future<void> setUsername(String? value) async => username = value;
}

void main() {
  group('Helper impostazioni', () {
    test('strategia: mappa i valori legacy e ricade su mixed', () {
      expect(normalizeStrategyValue('long_term'), 'long');
      expect(normalizeStrategyValue('short_term'), 'short');
      expect(normalizeStrategyValue('mixed'), 'mixed');
      expect(normalizeStrategyValue('long'), 'long');
      expect(normalizeStrategyValue(' SHORT '), 'short');
      expect(normalizeStrategyValue(''), 'mixed');
      expect(normalizeStrategyValue(null), 'mixed');
      expect(normalizeStrategyValue('sconosciuto'), 'mixed');
    });

    test('mercati: filtro e ordine canonico IT/US/EU', () {
      expect(orderedMarkets(<String>{'EU', 'IT'}), <String>['IT', 'EU']);
      expect(orderedMarkets(<String>{'US', 'IT', 'EU'}), <String>[
        'IT',
        'US',
        'EU',
      ]);
      expect(orderedMarkets(<String>{}), isEmpty);
    });

    test('orari report: default 09:00 poi 18:00 e validazione HH:MM', () {
      expect(defaultReportTimes(), <String>['09:00', '18:00']);
      expect(reportTimeAt(const <String>[], 0), '09:00');
      expect(reportTimeAt(const <String>[], 1), '18:00');
      expect(reportTimeAt(const <String>['07:30'], 0), '07:30');
      expect(reportTimeAt(const <String>['07:30'], 2), '18:00');

      expect(normalizeTimeValue('09:00'), '09:00');
      expect(normalizeTimeValue('9:5'), isNull);
      expect(normalizeTimeValue('9:05'), '09:05');
      expect(normalizeTimeValue('24:00'), isNull);
      expect(normalizeTimeValue('23:60'), isNull);
      expect(normalizeTimeValue('abc'), isNull);
      expect(normalizeTimeValue(''), isNull);
    });

    test(
      'soglia alert: preferisce threshold_percent e formatta i decimali',
      () {
        final AlertRule listed = AlertRule.fromJson(<String, dynamic>{
          'id': 1,
          'ticker': 'AAPL',
          'direction': 'BOTH',
          'threshold': 2.0,
          'threshold_percent': 2.5,
          'active': true,
        });
        expect(alertThresholdValue(listed), 2.5);
        expect(formatThresholdPercent(2.5), '2.5');
        expect(formatThresholdPercent(2.0), '2');
        expect(formatThresholdPercent(1.25), '1.25');

        final AlertRule created = AlertRule.fromJson(<String, dynamic>{
          'id': 2,
          'ticker': 'AAPL',
          'direction': 'UP',
          'threshold': 3.0,
        });
        expect(alertThresholdValue(created), 3.0);
        expect(formatThresholdPercent(alertThresholdValue(created)), '3');
      },
    );

    test('numero editabile senza separatori di migliaia', () {
      expect(formatEditableNumber(10000), '10000');
      expect(formatEditableNumber(2500.5), '2500.5');
      expect(formatEditableNumber(1234.25), '1234.25');
    });
  });

  group('SettingsController', () {
    test('save invia i cinque campi e conserva apiStatus del GET', () async {
      final _FakeSettingsApi api = _FakeSettingsApi()
        ..getResult = const UserSettings(
          strategy: 'long_term',
          markets: <String>['IT'],
          budget: 5000,
          reportFreq: 2,
          reportTimes: <String>['09:00', '18:00'],
          apiStatus: ApiStatus(
            telegram: true,
            gemini: true,
            geminiModel: 'gemini-3.8-flash',
          ),
        )
        ..putResult = const UserSettings(
          strategy: 'mixed',
          markets: <String>['US', 'EU'],
          budget: 20000,
          reportFreq: 3,
          reportTimes: <String>['08:00', '13:00', '20:00'],
        );

      final ProviderContainer container = ProviderContainer(
        retry: (int retryCount, Object error) => null,
        overrides: [settingsApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      final UserSettings initial = await container.read(
        settingsProvider.future,
      );
      expect(initial.apiStatus?.telegram, isTrue);

      await container
          .read(settingsProvider.notifier)
          .save(
            strategy: 'mixed',
            budget: 20000,
            markets: <String>['US', 'EU'],
            reportFreq: 3,
            reportTimes: <String>['08:00', '13:00', '20:00'],
          );

      expect(api.updates, hasLength(1));
      expect(api.updates.single['strategy'], 'mixed');
      expect(api.updates.single['budget'], 20000.0);
      expect(api.updates.single['markets'], <String>['US', 'EU']);
      expect(api.updates.single['reportFreq'], 3);
      expect(api.updates.single['reportTimes'], <String>[
        '08:00',
        '13:00',
        '20:00',
      ]);

      final UserSettings? saved = container.read(settingsProvider).value;
      expect(saved?.budget, 20000);
      // Il PUT non restituisce apiStatus: resta quello letto dal GET.
      expect(saved?.apiStatus?.telegram, isTrue);
      expect(saved?.apiStatus?.geminiModel, 'gemini-3.8-flash');
    });
  });

  group('AlertRulesController', () {
    test('add con id valido accoda la regola senza rifetch', () async {
      final _FakeSettingsApi api = _FakeSettingsApi()
        ..rules = <AlertRule>[
          const AlertRule(id: 1, ticker: 'AAPL', threshold: 2, direction: 'UP'),
        ]
        ..createdRule = const AlertRule(
          id: 9,
          ticker: 'ENEL.MI',
          threshold: 1.5,
          direction: 'BOTH',
        );

      final ProviderContainer container = ProviderContainer(
        retry: (int retryCount, Object error) => null,
        overrides: [settingsApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      await container.read(alertRulesProvider.future);
      final int callsAfterLoad = api.getCalls;
      await container
          .read(alertRulesProvider.notifier)
          .add(ticker: 'ENEL.MI', threshold: 1.5, direction: 'BOTH');

      final List<AlertRule> rules = container.read(alertRulesProvider).value!;
      expect(rules.map((AlertRule rule) => rule.id), <int>[1, 9]);
      expect(
        api.getCalls,
        callsAfterLoad,
        reason: 'nessun rifetch con id valido',
      );
    });

    test('add senza id ricarica dal server (niente id inventati)', () async {
      final _FakeSettingsApi api = _FakeSettingsApi()..rules = <AlertRule>[];

      final ProviderContainer container = ProviderContainer(
        retry: (int retryCount, Object error) => null,
        overrides: [settingsApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      await container.read(alertRulesProvider.future);
      // Il backend ha salvato ma la risposta POST non espone l'id: il GET
      // successivo lo include.
      api.rules = <AlertRule>[
        const AlertRule(id: 3, ticker: 'NVDA', threshold: 4, direction: 'DOWN'),
      ];
      api.createdRule = null; // AlertRule(id: 0, ...) dal fake

      await container
          .read(alertRulesProvider.notifier)
          .add(ticker: 'NVDA', threshold: 4, direction: 'DOWN');

      final List<AlertRule> rules = container.read(alertRulesProvider).value!;
      expect(rules.single.id, 3);
      expect(rules.single.ticker, 'NVDA');
    });

    test('remove filtra la regola dallo stato locale', () async {
      final _FakeSettingsApi api = _FakeSettingsApi()
        ..rules = <AlertRule>[
          const AlertRule(id: 1, ticker: 'AAPL', threshold: 2, direction: 'UP'),
          const AlertRule(
            id: 2,
            ticker: 'MSFT',
            threshold: 3,
            direction: 'DOWN',
          ),
        ];

      final ProviderContainer container = ProviderContainer(
        retry: (int retryCount, Object error) => null,
        overrides: [settingsApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      await container.read(alertRulesProvider.future);
      await container.read(alertRulesProvider.notifier).remove(1);

      expect(api.deleted, <int>[1]);
      final List<AlertRule> rules = container.read(alertRulesProvider).value!;
      expect(rules.single.id, 2);
    });
  });

  group('AuthController.changeServer', () {
    test('cambia base URL, persiste il server e sloggia senza chiamare logout', () async {
      final _FakeStorage storage = _FakeStorage()
        ..token = 'token-123'
        ..username = 'fabbro';
      final ApiClient client = ApiClient(tokenProvider: storage.getToken);

      final ProviderContainer container = ProviderContainer(
        retry: (int retryCount, Object error) => null,
        overrides: [
          appStorageProvider.overrideWithValue(storage),
          apiClientProvider.overrideWithValue(client),
        ],
      );
      addTearDown(container.dispose);

      final AuthState initial = await container.read(
        authControllerProvider.future,
      );
      // Con token salvato e `me()` non raggiungibile si resta loggati offline.
      expect(initial.isLoggedIn, isTrue);

      await container
          .read(authControllerProvider.notifier)
          .changeServer('http://192.168.1.50:8000');

      expect(storage.server, 'http://192.168.1.50:8000');
      expect(storage.token, isNull);
      expect(storage.username, isNull);
      expect(container.read(authControllerProvider).value?.isLoggedIn, isFalse);
      expect(client.isConfigured, isTrue);
    });
  });
}
