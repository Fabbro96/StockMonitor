import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_monitor/core/api_client.dart';

/// Risposta HTTP 200 programmata per [_ScriptedAdapter].
class _Ok {
  const _Ok(this.body);

  final String body;
}

/// Adapter Dio programmabile: restituisce le risposte/errori in sequenza e
/// conta le chiamate reali.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.script);

  final List<Object> script;
  int calls = 0;
  final List<String> methods = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final int index = calls;
    calls++;
    methods.add(options.method);
    final Object step = index < script.length ? script[index] : script.last;
    if (step is DioException) {
      throw DioException(
        requestOptions: options,
        type: step.type,
        response: _withOptions(step.response, options),
        error: step.error,
      );
    }
    final _Ok ok = step as _Ok;
    return ResponseBody.fromString(
      ok.body,
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  Response<dynamic>? _withOptions(
    Response<dynamic>? response,
    RequestOptions options,
  ) {
    if (response == null) return null;
    return Response<dynamic>(
      requestOptions: options,
      statusCode: response.statusCode,
      data: response.data,
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Errore di rete (timeout/connessione) senza risposta HTTP.
DioException _netError(DioExceptionType type) =>
    DioException(requestOptions: RequestOptions(path: '/'), type: type);

/// Errore HTTP con status (il client deve vedere lo status code).
DioException _httpError(int status) => DioException(
  requestOptions: RequestOptions(path: '/'),
  type: DioExceptionType.badResponse,
  response: Response<Map<String, dynamic>>(
    requestOptions: RequestOptions(path: '/'),
    statusCode: status,
    data: <String, dynamic>{'detail': 'errore $status'},
  ),
);

ApiClient _client(_ScriptedAdapter adapter) {
  final Dio dio = Dio()..httpClientAdapter = adapter;
  final ApiClient client = ApiClient(
    dio: dio,
    // Niente attese nei test: il backoff reale è coperto dai default.
    retryDelays: const <Duration>[Duration.zero],
  );
  client.setBaseUrl('http://localhost:8000');
  return client;
}

void main() {
  group('ApiClient retry solo-GET', () {
    test('GET fallisce una volta su timeout poi riesce (2 chiamate)', () async {
      final _ScriptedAdapter adapter = _ScriptedAdapter(<Object>[
        _netError(DioExceptionType.connectionTimeout),
        const _Ok('{"ok":true}'),
      ]);
      final dynamic data = await _client(adapter).get('/x');
      expect(data, <String, dynamic>{'ok': true});
      expect(adapter.calls, 2);
      expect(adapter.methods, <String>['GET', 'GET']);
    });

    test('GET ritenta sul 500 e riesce', () async {
      final _ScriptedAdapter adapter = _ScriptedAdapter(<Object>[
        _httpError(500),
        const _Ok('{"ok":true}'),
      ]);
      final dynamic data = await _client(adapter).get('/x');
      expect(data, <String, dynamic>{'ok': true});
      expect(adapter.calls, 2);
    });

    test('GET non ritenta il 401', () async {
      final _ScriptedAdapter adapter = _ScriptedAdapter(<Object>[
        _httpError(401),
      ]);
      final ApiClient client = _client(adapter);
      try {
        await client.get('/x');
        fail('attesa ApiException su 401');
      } on ApiException catch (error) {
        expect(error.statusCode, 401);
        expect(error.message, kSessionExpiredMessage);
      }
      expect(adapter.calls, 1);
    });

    test('GET non ritenta 404/422/429', () async {
      for (final int status in <int>[404, 422, 429]) {
        final _ScriptedAdapter adapter = _ScriptedAdapter(<Object>[
          _httpError(status),
        ]);
        try {
          await _client(adapter).get('/x');
          fail('attesa ApiException su $status');
        } on ApiException catch (error) {
          expect(error.statusCode, status);
        }
        expect(adapter.calls, 1, reason: 'status $status');
      }
    });

    test('GET esaurisce i 2 tentativi e rilancia', () async {
      final _ScriptedAdapter adapter = _ScriptedAdapter(<Object>[
        _netError(DioExceptionType.connectionError),
        _netError(DioExceptionType.connectionError),
      ]);
      try {
        await _client(adapter).get('/x');
        fail('attesa ApiException dopo 2 tentativi');
      } on ApiException {
        // atteso
      }
      expect(adapter.calls, 2);
    });

    test('POST non ritentato su errore di rete', () async {
      final _ScriptedAdapter adapter = _ScriptedAdapter(<Object>[
        _netError(DioExceptionType.connectionError),
        const _Ok('{"ok":true}'),
      ]);
      try {
        await _client(adapter).post('/x', body: <String, dynamic>{'a': 1});
        fail('attesa ApiException sul POST');
      } on ApiException {
        // atteso
      }
      expect(adapter.calls, 1);
      expect(adapter.methods, <String>['POST']);
    });

    test('PUT/DELETE non ritentati su 500', () async {
      for (final String method in <String>['PUT', 'DELETE']) {
        final _ScriptedAdapter adapter = _ScriptedAdapter(<Object>[
          _httpError(500),
          const _Ok('{"ok":true}'),
        ]);
        final ApiClient client = _client(adapter);
        try {
          if (method == 'PUT') {
            await client.put('/x');
          } else {
            await client.delete('/x');
          }
          fail('attesa ApiException su $method');
        } on ApiException catch (error) {
          expect(error.statusCode, 500);
        }
        expect(adapter.calls, 1, reason: method);
      }
    });
  });
}
