import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

/// Contratto di persistenza locale dell'app (interfaccia congelata).
abstract class AppStorage {
  Future<String?> getToken();
  Future<void> setToken(String? token);

  Future<String?> getUsername();
  Future<void> setUsername(String? username);

  Future<void> clearSession();

  Future<String?> getServerBaseUrl();
  Future<void> setServerBaseUrl(String url);

  Future<String?> getThemeMode();
  Future<void> setThemeMode(String mode);

  Future<bool> getSidebarCollapsed();
  Future<void> setSidebarCollapsed(bool value);
}

/// Implementazione platform-conditional:
///
/// - token su `flutter_secure_storage` (Android/iOS), `shared_preferences`
///   altrove (web e desktop);
/// - username, server, tema e sidebar sempre su `shared_preferences`.
///
/// Ogni accesso alla piattaforma è protetto da try/catch con fallback: in
/// caso di errore il valore viene letto/scritto sul backend alternativo o
/// ignorato, senza mai propagare eccezioni all'utente.
class AppStorageImpl implements AppStorage {
  AppStorageImpl();

  static const String _tokenKey = 'auth_token';
  static const String _usernameKey = 'auth_username';
  static const String _serverKey = 'server_base_url';
  static const String _themeKey = 'theme_mode';
  static const String _sidebarKey = 'sidebar_collapsed';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  SharedPreferencesAsync? _prefs;

  bool get _useSecureStorage =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  SharedPreferencesAsync get _preferences =>
      _prefs ??= SharedPreferencesAsync();

  /// Log di debug quando il secure storage fallisce e si degrada su
  /// `shared_preferences` (nessun cambio di comportamento).
  void _debugSecureFallback(String operation, Object error) {
    if (kDebugMode) {
      debugPrint(
        'AppStorage: secure storage $operation fallito '
        '($error) — fallback su shared_preferences.',
      );
    }
  }

  @override
  Future<String?> getToken() async {
    if (_useSecureStorage) {
      try {
        return await _secureStorage.read(key: _tokenKey);
      } catch (error) {
        _debugSecureFallback('read', error);
      }
    }
    try {
      return await _preferences.getString(_tokenKey);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> setToken(String? token) async {
    if (_useSecureStorage) {
      try {
        if (token == null) {
          await _secureStorage.delete(key: _tokenKey);
        } else {
          await _secureStorage.write(key: _tokenKey, value: token);
        }
        return;
      } catch (error) {
        _debugSecureFallback(token == null ? 'delete' : 'write', error);
      }
    }
    try {
      if (token == null) {
        await _preferences.remove(_tokenKey);
      } else {
        await _preferences.setString(_tokenKey, token);
      }
    } catch (_) {
      // Storage non disponibile: nessuna persistenza.
    }
  }

  @override
  Future<String?> getUsername() async {
    try {
      return await _preferences.getString(_usernameKey);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> setUsername(String? username) async {
    try {
      if (username == null) {
        await _preferences.remove(_usernameKey);
      } else {
        await _preferences.setString(_usernameKey, username);
      }
    } catch (_) {
      // Storage non disponibile: nessuna persistenza.
    }
  }

  @override
  Future<void> clearSession() async {
    await setToken(null);
    await setUsername(null);
  }

  @override
  Future<String?> getServerBaseUrl() async {
    try {
      return await _preferences.getString(_serverKey);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> setServerBaseUrl(String url) async {
    final normalized = AppConfig.normalizeOrigin(url);
    final current = await getServerBaseUrl();
    if (current == normalized) return;

    // Cambiare server invalida sempre la sessione corrente.
    await clearSession();

    try {
      if (normalized.isEmpty) {
        await _preferences.remove(_serverKey);
      } else {
        await _preferences.setString(_serverKey, normalized);
      }
    } catch (_) {
      // Storage non disponibile: nessuna persistenza.
    }
  }

  @override
  Future<String?> getThemeMode() async {
    try {
      return await _preferences.getString(_themeKey);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> setThemeMode(String mode) async {
    try {
      await _preferences.setString(_themeKey, mode);
    } catch (_) {
      // Storage non disponibile: nessuna persistenza.
    }
  }

  @override
  Future<bool> getSidebarCollapsed() async {
    try {
      return await _preferences.getBool(_sidebarKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> setSidebarCollapsed(bool value) async {
    try {
      await _preferences.setBool(_sidebarKey, value);
    } catch (_) {
      // Storage non disponibile: nessuna persistenza.
    }
  }
}

final appStorageProvider = Provider<AppStorage>((ref) => AppStorageImpl());
