import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_monitor/core/api/auth_api.dart';
import 'package:stock_monitor/core/api_client.dart';
import 'package:stock_monitor/core/models/user.dart';
import 'package:stock_monitor/core/session/auth_controller.dart';
import 'package:stock_monitor/core/session/session_epoch.dart';
import 'package:stock_monitor/core/storage.dart';
import 'package:stock_monitor/features/login/login_screen.dart';

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

/// Fake di [AuthApi]: login/logout/me sempre riusciti.
class _FakeAuthApi extends AuthApi {
  _FakeAuthApi() : super(ApiClient());

  @override
  Future<LoginResult> login(String username, String password) async =>
      LoginResult(
        accessToken: 'token-nuovo',
        username: username.trim(),
        isAdmin: false,
      );

  @override
  Future<void> logout() async {}

  @override
  Future<AuthUser> me() async =>
      const AuthUser(id: 1, username: 'u', isAdmin: false, isActive: true);
}

/// Probe provider con stato mutabile, usato per verificare che la ricreazione
/// dello scope azzeri le cache.
class _ProbeController extends Notifier<int> {
  static int instances = 0;

  @override
  int build() {
    instances++;
    return 0;
  }

  void setValue(int value) => state = value;
}

final _probeProvider = NotifierProvider<_ProbeController, int>(
  _ProbeController.new,
);

ProviderContainer _container(_FakeStorage storage, {ApiClient? client}) {
  return ProviderContainer(
    retry: (int retryCount, Object error) => null,
    overrides: [
      appStorageProvider.overrideWithValue(storage),
      apiClientProvider.overrideWithValue(
        client ?? ApiClient(tokenProvider: storage.getToken),
      ),
      authApiProvider.overrideWithValue(_FakeAuthApi()),
    ],
  );
}

_FakeStorage _loggedInStorage() => _FakeStorage()
  ..token = 'token-vecchio'
  ..username = 'u';

void main() {
  setUp(() {
    sessionEpoch.value = 0;
    sessionExpiredFlag.value = false;
    sessionNotice.value = null;
  });
  tearDown(() {
    sessionEpoch.value = 0;
    sessionExpiredFlag.value = false;
    sessionNotice.value = null;
  });

  group('sessionEpoch (unit, AuthController)', () {
    test('build non incrementa l\'epoch', () async {
      final ProviderContainer container = _container(_loggedInStorage());
      addTearDown(container.dispose);

      await container.read(authControllerProvider.future);

      expect(sessionEpoch.value, 0);
    });

    test('build consuma sessionExpiredFlag e lo resetta', () async {
      sessionExpiredFlag.value = true;
      final ProviderContainer container = _container(_FakeStorage());
      addTearDown(container.dispose);

      final AuthState state = await container.read(
        authControllerProvider.future,
      );

      expect(state.sessionExpired, isTrue);
      expect(state.isLoggedIn, isFalse);
      expect(sessionExpiredFlag.value, isFalse);
    });

    test(
      'login incrementa l\'epoch, pulisce i segnali e pubblica lo stato',
      () async {
        final _FakeStorage storage = _loggedInStorage();
        final ProviderContainer container = _container(storage);
        addTearDown(container.dispose);

        await container.read(authControllerProvider.future);
        // Segnali pendenti dalla sessione precedente.
        sessionExpiredFlag.value = true;
        sessionNotice.value = 'notice vecchia';

        await container
            .read(authControllerProvider.notifier)
            .login('utente', 'password');

        expect(sessionEpoch.value, 1);
        expect(sessionExpiredFlag.value, isFalse);
        expect(sessionNotice.value, isNull);
        expect(
          container.read(authControllerProvider).value?.isLoggedIn,
          isTrue,
        );
      },
    );

    test('logout incrementa l\'epoch e azzera lo stato', () async {
      final _FakeStorage storage = _loggedInStorage();
      final ProviderContainer container = _container(storage);
      addTearDown(container.dispose);

      await container.read(authControllerProvider.future);
      await container.read(authControllerProvider.notifier).logout();

      expect(sessionEpoch.value, 1);
      expect(container.read(authControllerProvider).value?.isLoggedIn, isFalse);
    });

    test(
      'changeServer incrementa l\'epoch, setta la notice e sloggia',
      () async {
        final _FakeStorage storage = _loggedInStorage();
        final ProviderContainer container = _container(storage);
        addTearDown(container.dispose);

        await container.read(authControllerProvider.future);
        sessionNotice.value = 'notice vecchia';
        await container
            .read(authControllerProvider.notifier)
            .changeServer('http://192.168.1.50:8000');

        expect(sessionEpoch.value, 1);
        expect(sessionNotice.value, kServerChangedNotice);
        expect(storage.server, 'http://192.168.1.50:8000');
        expect(
          container.read(authControllerProvider).value?.isLoggedIn,
          isFalse,
        );
      },
    );

    test(
      'markSessionExpired è idempotente: due chiamate, un solo bump',
      () async {
        final ProviderContainer container = _container(_loggedInStorage());
        addTearDown(container.dispose);

        await container.read(authControllerProvider.future);
        final AuthController controller = container.read(
          authControllerProvider.notifier,
        );
        controller.markSessionExpired();
        controller.markSessionExpired();

        expect(sessionEpoch.value, 1);
        expect(sessionExpiredFlag.value, isTrue);
        final AuthState? state = container.read(authControllerProvider).value;
        expect(state?.isLoggedIn, isFalse);
        expect(state?.sessionExpired, isTrue);
      },
    );

    test(
      'un 401 tardivo dopo la dispose non tocca la sessione né l\'epoch',
      () async {
        final _FakeStorage storage = _loggedInStorage();
        final ApiClient client = ApiClient(tokenProvider: storage.getToken);
        final ProviderContainer container = _container(storage, client: client);

        await container.read(authControllerProvider.future);
        final void Function()? staleUnauthorized = client.onUnauthorized;
        expect(staleUnauthorized, isNotNull);

        container.dispose();

        // La dispose rilascia il callback verso il vecchio controller.
        expect(client.onUnauthorized, isNull);

        // Anche invocando il callback catturato prima della dispose, il guard
        // `_disposed` impedisce pulizia sessione e bump.
        staleUnauthorized!.call();

        expect(storage.token, 'token-vecchio');
        expect(storage.username, 'u');
        expect(sessionEpoch.value, 0);
        expect(sessionExpiredFlag.value, isFalse);
      },
    );
  });

  group('sessionEpoch (widget)', () {
    testWidgets('il bump azzera lo stato dei provider (nuovo scope)', (
      WidgetTester tester,
    ) async {
      _ProbeController.instances = 0;

      // Harness minimale: stesso pattern di `main.dart` (ListenableBuilder +
      // ProviderScope con chiave legata all'epoch).
      Widget harness() => ListenableBuilder(
        listenable: sessionEpoch,
        builder: (BuildContext context, Widget? child) => ProviderScope(
          key: ValueKey<String>('session-${sessionEpoch.value}'),
          child: MaterialApp(
            home: Consumer(
              builder: (BuildContext context, WidgetRef ref, Widget? _) {
                final int value = ref.watch(_probeProvider);
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text('value: $value'),
                    TextButton(
                      onPressed: () =>
                          ref.read(_probeProvider.notifier).setValue(42),
                      child: const Text('set'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpWidget(harness());
      expect(find.text('value: 0'), findsOneWidget);
      expect(_ProbeController.instances, 1);

      await tester.tap(find.text('set'));
      await tester.pump();
      expect(find.text('value: 42'), findsOneWidget);

      bumpSessionEpoch();
      await tester.pumpAndSettle();

      // Nuovo scope: cache azzerata e notifier ricreato.
      expect(find.text('value: 0'), findsOneWidget);
      expect(find.text('value: 42'), findsNothing);
      expect(_ProbeController.instances, 2);
    });

    testWidgets('LoginScreen mostra l\'alert expired consumando il segnale', (
      WidgetTester tester,
    ) async {
      sessionExpiredFlag.value = true;
      final ProviderContainer container = _container(_FakeStorage());
      addTearDown(container.dispose);
      final AuthState state = await container.read(
        authControllerProvider.future,
      );
      expect(state.sessionExpired, isTrue);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LoginScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Sessione non valida o scaduta. Effettua il login.'),
        findsOneWidget,
      );
      expect(sessionExpiredFlag.value, isFalse);
    });

    testWidgets('LoginScreen mostra e consuma la notice di cambio server', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = _container(_FakeStorage());
      addTearDown(container.dispose);
      await container.read(authControllerProvider.future);

      sessionNotice.value = kServerChangedNotice;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LoginScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(kServerChangedNotice), findsOneWidget);
      expect(sessionNotice.value, isNull);
    });
  });
}
