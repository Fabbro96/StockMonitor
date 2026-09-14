import 'package:flutter/foundation.dart';

/// Configurazione globale dell'app (build-time e piattaforma).
class AppConfig {
  AppConfig._();

  /// Base URL opzionale fornita in build con `--dart-define=API_BASE_URL=...`.
  static const String apiBaseUrlFromEnv = String.fromEnvironment(
    'API_BASE_URL',
  );

  /// True quando l'app gira come build web (stessa origine del backend).
  static bool get isWeb => kIsWeb;

  /// Normalizza un origin inserito dall'utente.
  ///
  /// - aggiunge `http://` quando manca lo schema;
  /// - rimuove gli slash finali;
  /// - rimuove il path `/api` se è stato incollato l'URL completo.
  ///
  /// Restituisce stringa vuota se [input] è vuoto.
  static String normalizeOrigin(String input) {
    var value = input.trim();
    if (value.isEmpty) return '';
    if (!value.contains('://')) {
      value = 'http://$value';
    }
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) {
      return _stripTrailingSlashes(value);
    }
    var path = uri.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    final lowerPath = path.toLowerCase();
    if (lowerPath == '/api') {
      path = '';
    } else if (lowerPath.endsWith('/api')) {
      path = path.substring(0, path.length - '/api'.length);
    }
    return '${uri.scheme}://${uri.authority}$path';
  }

  /// True se [input] è un origin http/https valido (dopo normalizzazione).
  static bool isValidOrigin(String input) {
    final normalized = normalizeOrigin(input);
    if (normalized.isEmpty) return false;
    final uri = Uri.tryParse(normalized);
    if (uri == null || uri.host.isEmpty) return false;
    return uri.scheme == 'http' || uri.scheme == 'https';
  }

  static String _stripTrailingSlashes(String value) {
    var result = value;
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}
