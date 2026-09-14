import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/auth_api.dart';
import '../api_client.dart';
import '../models/user.dart';
import '../storage.dart';
import 'session_epoch.dart';

/// Stato di autenticazione globale (interfaccia congelata).
class AuthState {
  const AuthState({
    this.user,
    this.initialized = false,
    this.sessionExpired = false,
  });

  final AuthUser? user;
  final bool initialized;
  final bool sessionExpired;

  bool get isLoggedIn => user != null;
}

/// Bootstrap della sessione + operazioni di login/logout.
///
/// Flusso di [build]:
/// 1. inizializza [ApiClient] con lo storage (base URL);
/// 2. carica token + username salvati;
/// 3. se entrambi presenti valida la sessione con `GET /auth/me`:
///    - 401 → pulisce lo storage e resta sloggato;
///    - errore di rete/parsing → considera loggato l'utente salvato;
/// 4. collega `onUnauthorized` del client a [markSessionExpired] solo al
///    termine del bootstrap (evita di scrivere stato durante `build`).
class AuthController extends AsyncNotifier<AuthState> {
  AppStorage? _storage;
  bool _disposed = false;

  @override
  Future<AuthState> build() async {
    _disposed = false;
    final api = ref.read(apiClientProvider);
    ref.onDispose(() {
      _disposed = true;
      // Rilascia il riferimento al vecchio controller: dopo la ricreazione
      // dello scope un 401 in volo del vecchio ApiClient non deve più
      // azzerare la sessione (eventualmente nuova).
      api.onUnauthorized = null;
    });

    final authApi = ref.read(authApiProvider);
    final storage = ref.read(appStorageProvider);
    _storage = storage;

    // Segnale fuori scope (sopravvive alla ricreazione del ProviderScope dopo
    // un 401): consumato una sola volta per inizializzare lo stato, così
    // l'alert "Sessione non valida o scaduta" non va perso.
    final bool wasSessionExpired = sessionExpiredFlag.value;
    sessionExpiredFlag.value = false;

    // Nessun callback attivo durante il bootstrap: eventuali 401 di `me()`
    // vengono gestiti esplicitamente qui sotto.
    api.onUnauthorized = null;
    await api.init(storage);

    final token = await storage.getToken();
    final savedUsername = await storage.getUsername();
    if (token == null ||
        token.isEmpty ||
        savedUsername == null ||
        savedUsername.isEmpty) {
      _wireUnauthorized(api);
      return AuthState(initialized: true, sessionExpired: wasSessionExpired);
    }

    try {
      final user = await authApi.me();
      _wireUnauthorized(api);
      return AuthState(user: user, initialized: true);
    } on ApiException catch (error) {
      _wireUnauthorized(api);
      if (error.statusCode == 401) {
        await storage.clearSession();
        return AuthState(initialized: true, sessionExpired: wasSessionExpired);
      }
      return _offlineState(savedUsername);
    } catch (_) {
      // Risposta malformata o errore di rete: si prosegue con i dati salvati.
      _wireUnauthorized(api);
      return _offlineState(savedUsername);
    }
  }

  /// Login: salva la sessione e carica il profilo completo dell'utente.
  Future<void> login(String username, String password) async {
    final authApi = ref.read(authApiProvider);
    final storage = ref.read(appStorageProvider);

    final result = await authApi.login(username.trim(), password);
    await storage.setToken(result.accessToken);
    await storage.setUsername(result.username);

    AuthUser user;
    try {
      user = await authApi.me();
    } catch (_) {
      // Il login è andato a buon fine: si procede con i dati del token.
      user = AuthUser(
        id: 0,
        username: result.username,
        isAdmin: result.isAdmin,
        isActive: true,
      );
    }
    // Transizione di sessione: invalida le cache dei provider del server /
    // utente precedente e cancella gli avvisi pendenti della vecchia sessione.
    clearSessionSignals();
    bumpSessionEpoch();
    _setState(AuthState(user: user, initialized: true));
  }

  /// Cambia l'origin del server a runtime (sezione Server delle Impostazioni).
  ///
  /// Aggiorna subito la base URL di [ApiClient], la persiste in [AppStorage] e
  /// riporta la sessione allo stato non loggato. **Non** invia
  /// `POST /auth/logout` al server precedente: il caso tipico è proprio un
  /// indirizzo errato o irraggiungibile, dove la chiamata fallirebbe (o
  /// colpirebbe un host sbagliato). La pulizia locale è garantita da
  /// [AppStorage.setServerBaseUrl], che azzera sempre la sessione quando
  /// l'origin cambia.
  Future<void> changeServer(String url) async {
    final api = ref.read(apiClientProvider);
    final storage = ref.read(appStorageProvider);
    api.setBaseUrl(url);
    await storage.setServerBaseUrl(url);
    // Backend diverso: le cache dei provider non valgono più. La notice viene
    // letta dalla LoginScreen del nuovo scope (il toast sul vecchio scope
    // verrebbe smontato insieme a esso).
    sessionNotice.value = kServerChangedNotice;
    bumpSessionEpoch();
    _setState(const AuthState(initialized: true));
  }

  /// Logout best-effort lato server, poi pulizia locale e stato sloggato.
  Future<void> logout() async {
    try {
      await ref.read(authApiProvider).logout();
    } catch (_) {
      // Endpoint non raggiungibile: la sessione locale va pulita comunque.
    }
    await ref.read(appStorageProvider).clearSession();
    // Utente uscito: i dati in cache non devono sopravvivere al logout.
    bumpSessionEpoch();
    _setState(const AuthState(initialized: true));
  }

  /// Invalida la sessione locale (401 su una richiesta autenticata).
  ///
  /// Idempotente: con più 401 concorrenti il flag fuori scope viene marcato e
  /// lo scope ricreato **una sola volta** (i successivi early-return evitano
  /// ricreazioni ridondanti). Un 401 tardivo del vecchio `ApiClient` dopo la
  /// dispose del controller è un no-op: non pulisce la sessione nuova.
  void markSessionExpired() {
    if (_disposed) return;
    if (sessionExpiredFlag.value) return;

    sessionExpiredFlag.value = true;
    final storage = _storage;
    if (storage != null) {
      unawaited(storage.clearSession());
    }
    // Sessione non più valida: azzera le cache del vecchio utente/sessione.
    bumpSessionEpoch();
    _setState(const AuthState(initialized: true, sessionExpired: true));
  }

  void _wireUnauthorized(ApiClient api) {
    api.onUnauthorized = markSessionExpired;
  }

  AuthState _offlineState(String savedUsername) {
    return AuthState(
      user: AuthUser(
        id: 0,
        username: savedUsername,
        isAdmin: false,
        isActive: true,
      ),
      initialized: true,
    );
  }

  void _setState(AuthState newState) {
    if (_disposed) return;
    state = AsyncData(newState);
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
