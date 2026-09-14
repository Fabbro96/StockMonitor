import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

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
/// Backoff di default tra i tentativi GET (400ms → 1200ms) + jitter.
const List<Duration> _defaultRetryDelays = <Duration>[
  Duration(milliseconds: 400),
  Duration(milliseconds: 1200),
];

class ApiClient {
  ApiClient({this.tokenProvider, this.onUnauthorized, Dio? dio, List<Duration>? retryDelays})
    : _dio = dio ?? Dio(),
      _retryDelays = retryDelays ?? _defaultRetryDelays {
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

  /// Numero massimo di tentativi totali per le GET ritentabili.
  static const int maxGetAttempts = 2;

  /// Backoff tra i tentativi (indice = numero del retry, clampato).
  final List<Duration> _retryDelays;

  /// Jitter aggiunto a ogni attesa (0–99ms).
  final math.Random _jitter = math.Random();

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
  ///
  /// Le GET sono ritentate una volta ([maxGetAttempts] tentativi totali,
  /// backoff 400ms→1200ms + jitter) solo su timeout, errori di connessione e
  /// 5xx; mai su 401/404/422/429. POST/PUT/DELETE/upload/download non sono
  /// mai ritentati (rischio doppia transazione).
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    Duration? receiveTimeout,
  }) => _send(
    'GET',
    path,
    query: query,
    receiveTimeout: receiveTimeout,
    retry: true,
  );

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
    bool retry = false,
  }) async {
    _ensureConfigured();
    final int attempts = retry ? maxGetAttempts : 1;
    DioException? lastError;
    for (int attempt = 0; attempt < attempts; attempt++) {
      try {
        final response = await _dio.request<dynamic>(
          _resolvePath(path),
          data: body,
          queryParameters: query,
          options: Options(method: method, receiveTimeout: receiveTimeout),
        );
        return _normalize(response.data);
      } on DioException catch (error) {
        lastError = error;
        final bool hasMore = attempt + 1 < attempts;
        if (!retry || !hasMore || !_isGetRetryable(error)) {
          throw _toApiException(error);
        }
        await Future<void>.delayed(_retryDelay(attempt));
      }
    }
    throw _toApiException(lastError!);
  }

  /// True se l'errore merita un retry della GET: timeout, errore di
  /// connessione o 5xx. Mai 4xx (401/404/422/429 inclusi) e mai cancellazioni.
  bool _isGetRetryable(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.badResponse:
        final int? status = error.response?.statusCode;
        return status != null && status >= 500;
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.unknown:
        return false;
    }
  }

  /// Attesa prima del retry numero [retryIndex] (backoff + jitter).
  Duration _retryDelay(int retryIndex) {
    final List<Duration> delays = _retryDelays.isEmpty
        ? const <Duration>[Duration.zero]
        : _retryDelays;
    final Duration base = delays[retryIndex < delays.length
        ? retryIndex
        : delays.length - 1];
    return base + Duration(milliseconds: _jitter.nextInt(100));
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
