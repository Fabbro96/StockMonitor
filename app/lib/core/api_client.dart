import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config.dart';
import 'storage.dart';

/// Messaggio mostrato quando la sessione non è più valida (401).
const String kSessionExpiredMessage =
    'Sessione non valida o scaduta. Effettua il login.';

/// Eccezione applicativa uniforme per tutte le chiamate API.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.detail});

  /// Codice HTTP della risposta; `null` per errori di rete/parsing.
  final int? statusCode;

  /// Messaggio leggibile, pronto per essere mostrato all'utente.
  final String message;

  /// Payload originale (`detail` del backend) per usi diagnostici.
  final Object? detail;

  @override
  String toString() => message;
}

/// Callback invocato quando una richiesta autenticata riceve 401.
typedef UnauthorizedCallback = void Function();

/// Client HTTP unico dell'app (Dio).
///
/// - Web: base URL = stessa origine del backend (`Uri.base.resolve('/api')`).
/// - Android/desktop: origin salvato in [AppStorage] + `/api`; la variabile di
///   build `API_BASE_URL` fa da fallback. Non configurato finché assente.
class ApiClient {
  ApiClient({this.tokenProvider, this.onUnauthorized, Dio? dio})
    : _dio = dio ?? Dio() {
    _dio.options
      ..connectTimeout = const Duration(seconds: 10)
      ..receiveTimeout = const Duration(seconds: 20)
      ..sendTimeout = const Duration(seconds: 10)
      ..headers['Accept'] = 'application/json';
    _dio.interceptors.add(
      InterceptorsWrapper(onRequest: _onRequest, onError: _onError),
    );
  }

  final Dio _dio;
  AppStorage? _storage;
  String? _origin;

  /// Provider del Bearer token (fornito in costruzione o riassegnato dopo
  /// `init`); se null/assente nessun header Authorization viene inviato.
  Future<String?> Function()? tokenProvider;

  /// Callback invocato quando una richiesta autenticata riceve 401.
  UnauthorizedCallback? onUnauthorized;

  /// True quando la base URL è disponibile e il client può fare richieste.
  bool get isConfigured => _dio.options.baseUrl.isNotEmpty;

  /// Carica la configurazione persistita e applica la base URL corrente.
  Future<void> init(AppStorage storage) async {
    _storage = storage;
    _origin = await storage.getServerBaseUrl();
    _applyBaseUrl();
  }

  /// Imposta (o azzera) l'origin del server. Su web è sempre la stessa origine.
  ///
  /// Persiste il valore tramite [AppStorage]: un cambio di origin azzera la
  /// sessione salvata (vedi `AppStorage.setServerBaseUrl`).
  void setBaseUrl(String? url) {
    final normalized = (url == null || url.trim().isEmpty)
        ? null
        : AppConfig.normalizeOrigin(url);
    _origin = normalized;
    _applyBaseUrl();
    final storage = _storage;
    if (storage != null && normalized != null) {
      unawaited(storage.setServerBaseUrl(normalized).catchError((Object _) {}));
    }
  }

  /// Richiesta GET.
  ///
  /// [receiveTimeout] opzionale sovrascrive il timeout di ricezione globale
  /// (20s): usarlo per le chiamate lente (es. generazione AI).
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    Duration? receiveTimeout,
  }) => _send('GET', path, query: query, receiveTimeout: receiveTimeout);

  /// Richiesta POST. Vedi [get] per [receiveTimeout].
  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    Duration? receiveTimeout,
  }) => _send(
    'POST',
    path,
    query: query,
    body: body,
    receiveTimeout: receiveTimeout,
  );

  /// Richiesta PUT. Vedi [get] per [receiveTimeout].
  Future<dynamic> put(
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    Duration? receiveTimeout,
  }) => _send(
    'PUT',
    path,
    query: query,
    body: body,
    receiveTimeout: receiveTimeout,
  );

  /// Richiesta DELETE. Vedi [get] per [receiveTimeout].
  Future<dynamic> delete(
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    Duration? receiveTimeout,
  }) => _send(
    'DELETE',
    path,
    query: query,
    body: body,
    receiveTimeout: receiveTimeout,
  );

  /// Upload multipart di un singolo file (campo [field]).
  ///
  /// [receiveTimeout] opzionale sovrascrive il timeout globale di ricezione.
  Future<dynamic> uploadMultipart(
    String path, {
    required String field,
    required List<int> bytes,
    required String filename,
    Duration? receiveTimeout,
  }) async {
    _ensureConfigured();
    try {
      final formData = FormData.fromMap({
        field: MultipartFile.fromBytes(bytes, filename: filename),
      });
      final response = await _dio.post<dynamic>(
        _resolvePath(path),
        data: formData,
        options: Options(receiveTimeout: receiveTimeout),
      );
      return _normalize(response.data);
    } on DioException catch (error) {
      throw _toApiException(error);
    }
  }

  /// Scarica il body binario di [path] (export CSV, allegati, ...).
  ///
  /// [receiveTimeout] opzionale sovrascrive il timeout globale di ricezione.
  Future<Uint8List> downloadBytes(
    String path, {
    Map<String, dynamic>? query,
    Duration? receiveTimeout,
  }) async {
    _ensureConfigured();
    try {
      final response = await _dio.get<List<int>>(
        _resolvePath(path),
        queryParameters: query,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: receiveTimeout,
        ),
      );
      final data = response.data;
      return data == null ? Uint8List(0) : Uint8List.fromList(data);
    } on DioException catch (error) {
      throw _toApiException(error);
    }
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    Duration? receiveTimeout,
  }) async {
    _ensureConfigured();
    try {
      final response = await _dio.request<dynamic>(
        _resolvePath(path),
        data: body,
        queryParameters: query,
        options: Options(method: method, receiveTimeout: receiveTimeout),
      );
      return _normalize(response.data);
    } on DioException catch (error) {
      throw _toApiException(error);
    }
  }

  void _ensureConfigured() {
    if (!isConfigured) {
      throw ApiException(
        'Server non configurato. Specifica l\'indirizzo del server.',
      );
    }
  }

  /// Convenzione ufficiale: i moduli `core/api/*` passano path **relativi
  /// alla root API** (`/auth/login`, `/portfolio/`), perché la base URL
  /// include già il prefisso `/api`.
  ///
  /// Il client tollera anche il prefisso `/api` (`/api/auth/login`) rimuovendolo
  /// solo quando la base URL lo contiene già, evitando il doppio `/api/api`.
  String _resolvePath(String path) {
    var normalized = path.trim();
    if (normalized.isEmpty) return '/';
    if (!normalized.startsWith('/')) {
      normalized = '/$normalized';
    }
    if (_dio.options.baseUrl.endsWith('/api')) {
      if (normalized == '/api') {
        return '/';
      }
      if (normalized.startsWith('/api/')) {
        normalized = normalized.substring('/api'.length);
      }
    }
    return normalized;
  }

  void _applyBaseUrl() {
    if (kIsWeb) {
      // Stessa origine del backend che serve la build web.
      _dio.options.baseUrl = Uri.base.resolve('/api').toString();
      return;
    }
    final env = AppConfig.apiBaseUrlFromEnv.trim();
    final saved = _origin;
    final origin = (saved != null && saved.isNotEmpty)
        ? saved
        : (env.isEmpty ? null : AppConfig.normalizeOrigin(env));
    _dio.options.baseUrl = origin == null ? '' : '$origin/api';
  }

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await tokenProvider?.call();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  void _onError(DioException error, ErrorInterceptorHandler handler) {
    if (error.response?.statusCode == 401 &&
        !_isLoginRequest(error.requestOptions)) {
      onUnauthorized?.call();
    }
    handler.next(error);
  }

  /// Le risposte non JSON (o vuote, es. 204) valgono `null`.
  dynamic _normalize(dynamic data) {
    if (data == null) return null;
    if (data is Map || data is List || data is num || data is bool) {
      return data;
    }
    return null;
  }

  ApiException _toApiException(DioException error) {
    final response = error.response;
    final status = response?.statusCode;
    final data = response?.data;

    if (status == 401 && !_isLoginRequest(error.requestOptions)) {
      return ApiException(
        kSessionExpiredMessage,
        statusCode: status,
        detail: data,
      );
    }
    // Errore di rete puro (timeout, DNS, ...): si preferisce il messaggio Dio.
    if (status == null) {
      return ApiException(error.message ?? 'Errore di rete.', detail: data);
    }
    return ApiException(
      apiErrorMessageFor(status, data),
      statusCode: status,
      detail: data,
    );
  }

  /// Mappa `(status, body)` nel messaggio utente standard.
  ///
  /// Regole (congelate):
  /// - `detail` stringa → così com'è;
  /// - `detail` lista (422) → `msg` di ogni elemento uniti con `'; '`;
  /// - `detail` oggetto → [jsonEncode];
  /// - altrimenti `message`;
  /// - altrimenti `API Error: {status}`.
  @visibleForTesting
  static String apiErrorMessageFor(int? status, Object? body) {
    final extracted = _extractMessage(body);
    if (extracted != null && extracted.isNotEmpty) return extracted;
    if (status != null) return 'API Error: $status';
    return 'Errore di rete.';
  }

  static String? _extractMessage(dynamic data) {
    if (data is Map) {
      final detail = data['detail'];
      if (detail is String && detail.isNotEmpty) return detail;
      if (detail is List && detail.isNotEmpty) {
        final parts = <String>[
          for (final item in detail)
            if (item is Map && item['msg'] != null)
              item['msg'].toString()
            else if (item != null)
              item.toString(),
        ];
        if (parts.isNotEmpty) return parts.join('; ');
      } else if (detail != null && detail is! String) {
        return jsonEncode(detail);
      }
      final message = data['message'];
      if (message is String && message.isNotEmpty) return message;
      if (message != null) return message.toString();
      return null;
    }
    if (data is String && data.isNotEmpty) return data;
    return null;
  }

  bool _isLoginRequest(RequestOptions options) =>
      options.uri.path.endsWith('/auth/login');
}

final apiClientProvider = Provider<ApiClient>((ref) {
  final storage = ref.watch(appStorageProvider);
  return ApiClient(tokenProvider: storage.getToken);
});
