import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_monitor/core/api/settings_api.dart';
import 'package:stock_monitor/core/api_client.dart';
import 'package:stock_monitor/core/models/settings.dart';
import 'package:stock_monitor/core/models/user.dart';
import 'package:stock_monitor/core/session/auth_controller.dart';
import 'package:stock_monitor/features/settings/settings_providers.dart';
import 'package:stock_monitor/features/settings/settings_screen.dart';

/// Fake di [SettingsApi]: impostazioni con vocabolario legacy (`long_term`) e
/// una regola alert BOTH già configurata.
class _FakeSettingsApi extends SettingsApi {
  _FakeSettingsApi() : super(ApiClient());

  final List<Map<String, Object?>> updates = <Map<String, Object?>>[];

  @override
  Future<UserSettings> getSettings() async => const UserSettings(
    strategy: 'long_term',
    markets: <String>['IT', 'US', 'EU'],
    budget: 10000,
    reportFreq: 2,
    reportTimes: <String>['09:00', '18:00'],
    apiStatus: ApiStatus(
      telegram: true,
      gemini: true,
      geminiModel: 'gemini-3.7-flash',
    ),
  );

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
    return UserSettings(
      strategy: strategy ?? 'mixed',
      budget: budget ?? 0,
      markets: markets ?? const <String>[],
      reportFreq: reportFreq ?? 2,
      reportTimes: reportTimes ?? const <String>[],
    );
  }

  @override
  Future<List<AlertRule>> getAlertRules() async => <AlertRule>[
    const AlertRule(
      id: 1,
      ticker: 'AAPL',
      direction: 'BOTH',
      threshold: 2.5,
      thresholdPercent: 2.5,
      active: true,
    ),
  ];
}

/// Fake di [AuthController] con utente già loggato.
class _FakeAuthController extends AuthController {
  _FakeAuthController(this.user);

  final AuthUser user;

  @override
  Future<AuthState> build() async => AuthState(user: user, initialized: true);
}

/// Fake di [UsersController] per la sezione admin.
class _FakeUsersController extends UsersController {
  @override
  Future<List<AuthUser>> build() async => <AuthUser>[
    AuthUser(
      id: 1,
      username: 'fabbro',
      isAdmin: true,
      isActive: true,
      createdAt: DateTime(2025, 1, 2),
    ),
    AuthUser(
      id: 2,
      username: 'mario',
      isAdmin: false,
      isActive: true,
      createdAt: DateTime(2025, 3, 4),
      lastLogin: DateTime(2026, 9, 1, 10, 30),
    ),
  ];
}

AuthUser _admin() =>
    AuthUser(id: 1, username: 'fabbro', isAdmin: true, isActive: true);

AuthUser _plainUser() =>
    AuthUser(id: 2, username: 'mario', isAdmin: false, isActive: true);

Widget _app({
  required _FakeSettingsApi settingsApi,
  required AuthUser user,
  bool withUsers = false,
}) {
  return ProviderScope(
    overrides: [
      settingsApiProvider.overrideWithValue(settingsApi),
      authControllerProvider.overrideWith(() => _FakeAuthController(user)),
      if (withUsers) usersProvider.overrideWith(() => _FakeUsersController()),
    ],
    child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
  );
}

void main() {
  testWidgets('sezioni principali con copy di parità', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final _FakeSettingsApi api = _FakeSettingsApi();
    await tester.pumpWidget(_app(settingsApi: api, user: _plainUser()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(
      find.text('💶 Quanti soldi vuoi investire? (Capitale / Budget Totale)'),
      findsOneWidget,
    );
    expect(find.text('Capitale da Investire (€)'), findsOneWidget);
    expect(find.text('2.500 €'), findsOneWidget);
    expect(find.text('50.000 €'), findsOneWidget);
    expect(find.text('🎯 Strategia di Investimento & Rischio'), findsOneWidget);
    expect(find.text('Long Term (Cassettista / Valore)'), findsOneWidget);
    expect(find.text('Italia (MIB)'), findsOneWidget);
    expect(find.text('USA (S&P500/Nasdaq)'), findsOneWidget);
    expect(find.text('🔔 Notifiche & Invio Report'), findsOneWidget);
    expect(find.text('Orario di invio report (primo invio)'), findsOneWidget);
    expect(find.text('Orario di invio report 2'), findsOneWidget);
    expect(find.text('Invia Messaggio Test Telegram'), findsOneWidget);
    expect(
      find.text('⚡ Regole Alert Istantanee (Take Profit / Stop Loss)'),
      findsOneWidget,
    );
    expect(find.text('BOTH'), findsWidgets);
    expect(find.text('Attivo'), findsOneWidget);
    expect(find.text('🔒 Sicurezza & Password'), findsOneWidget);
    expect(find.text('Aggiorna'), findsOneWidget);
    // Non admin: la sezione utenti non compare.
    expect(find.text('👥 Gestione Utenti (Solo Amministratore)'), findsNothing);
    expect(find.text('📡 Stato Integrazioni & Motore AI'), findsOneWidget);
    expect(find.text('gemini-3.7-flash'), findsOneWidget);
    expect(find.text('✅ Attivo'), findsWidgets);
    expect(find.text('🖥️ Server'), findsOneWidget);
    expect(find.text('Salva Impostazioni'), findsOneWidget);
  });

  testWidgets('Salva Impostazioni invia strategia normalizzata e orari', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final _FakeSettingsApi api = _FakeSettingsApi();
    await tester.pumpWidget(_app(settingsApi: api, user: _plainUser()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Salva Impostazioni'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(api.updates, hasLength(1));
    // `long_term` (legacy) → `long` (valore UI) sul PUT.
    expect(api.updates.single['strategy'], 'long');
    expect(api.updates.single['budget'], 10000.0);
    expect(api.updates.single['markets'], <String>['IT', 'US', 'EU']);
    expect(api.updates.single['reportFreq'], 2);
    expect(api.updates.single['reportTimes'], <String>['09:00', '18:00']);
    expect(find.text('Impostazioni salvate con successo!'), findsOneWidget);
  });

  testWidgets('sezione admin: utenti, (Tu), reset password e delete nascosto', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final _FakeSettingsApi api = _FakeSettingsApi();
    await tester.pumpWidget(
      _app(settingsApi: api, user: _admin(), withUsers: true),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(
      find.text('👥 Gestione Utenti (Solo Amministratore)'),
      findsOneWidget,
    );
    expect(find.text('➕ Crea Nuovo Utente'), findsOneWidget);
    expect(find.text('Crea Utente'), findsOneWidget);
    expect(find.text('fabbro'), findsOneWidget);
    expect(find.text(' (Tu)'), findsOneWidget);
    expect(find.text('👑 Amministratore'), findsWidgets);
    expect(find.text('👤 Utente'), findsOneWidget);
    expect(find.text('Mai'), findsOneWidget);
    // Reset password su ogni utente; delete solo sull'utente non-self.
    expect(find.byTooltip('🔑 Reimposta password'), findsNWidgets(2));
    expect(find.byTooltip('Elimina utente'), findsOneWidget);
  });

  testWidgets('layout compatto: la tabella alert diventa card senza overflow', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final _FakeSettingsApi api = _FakeSettingsApi();
    await tester.pumpWidget(_app(settingsApi: api, user: _plainUser()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(find.text('Soglia: 2.5% • Attivo'), findsOneWidget);
    expect(find.text('Salva Impostazioni'), findsOneWidget);
  });
}
