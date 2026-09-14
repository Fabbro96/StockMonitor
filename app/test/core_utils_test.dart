import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_monitor/core/api_client.dart';
import 'package:stock_monitor/core/config.dart';

void main() {
  group('AppConfig.normalizeOrigin', () {
    test('aggiunge http:// quando manca lo schema', () {
      expect(
        AppConfig.normalizeOrigin('192.168.1.10:8000'),
        'http://192.168.1.10:8000',
      );
      expect(
        AppConfig.normalizeOrigin('localhost:8000'),
        'http://localhost:8000',
      );
      expect(AppConfig.normalizeOrigin('nas.local'), 'http://nas.local');
    });

    test('rimuove gli slash finali', () {
      expect(AppConfig.normalizeOrigin('http://nas:8000/'), 'http://nas:8000');
      expect(
        AppConfig.normalizeOrigin('http://nas:8000///'),
        'http://nas:8000',
      );
    });

    test('rimuove il suffisso /api', () {
      expect(
        AppConfig.normalizeOrigin('http://nas:8000/api'),
        'http://nas:8000',
      );
      expect(
        AppConfig.normalizeOrigin('http://nas:8000/api/'),
        'http://nas:8000',
      );
      expect(
        AppConfig.normalizeOrigin('192.168.1.10:8000/api'),
        'http://192.168.1.10:8000',
      );
    });

    test('preserva un path che non è /api', () {
      expect(
        AppConfig.normalizeOrigin('http://host:8000/stock'),
        'http://host:8000/stock',
      );
      expect(
        AppConfig.normalizeOrigin('http://host:8000/stock/api'),
        'http://host:8000/stock',
      );
      expect(
        AppConfig.normalizeOrigin('http://host:8000/api/v1'),
        'http://host:8000/api/v1',
      );
    });

    test('normalizza schema maiuscolo e host', () {
      expect(
        AppConfig.normalizeOrigin('HTTP://Host:8000/API/'),
        'http://host:8000',
      );
    });

    test('ignora whitespace iniziale/finale', () {
      expect(
        AppConfig.normalizeOrigin('  http://nas:8000  '),
        'http://nas:8000',
      );
      expect(AppConfig.normalizeOrigin('   '), '');
      expect(AppConfig.normalizeOrigin(''), '');
    });
  });

  group('AppConfig.isValidOrigin', () {
    test('accetta host, host:porta e path /api', () {
      expect(AppConfig.isValidOrigin('192.168.1.10'), isTrue);
      expect(AppConfig.isValidOrigin('192.168.1.10:8000'), isTrue);
      expect(AppConfig.isValidOrigin('http://nas:8000/api/'), isTrue);
      expect(AppConfig.isValidOrigin('https://example.com'), isTrue);
    });

    test('rifiuta stringhe vuote e schemi non http(s)', () {
      expect(AppConfig.isValidOrigin(''), isFalse);
      expect(AppConfig.isValidOrigin('   '), isFalse);
      expect(AppConfig.isValidOrigin('http://'), isFalse);
      expect(AppConfig.isValidOrigin('ftp://nas:21'), isFalse);
    });
  });

  group('ApiClient.apiErrorMessageFor', () {
    test('usa detail stringa', () {
      expect(
        ApiClient.apiErrorMessageFor(400, {
          'detail': 'Credenziali non corrette.',
        }),
        'Credenziali non corrette.',
      );
    });

    test('unisce i msg di una detail lista (422)', () {
      expect(
        ApiClient.apiErrorMessageFor(422, {
          'detail': [
            {
              'loc': ['body', 'username'],
              'msg': 'Field required',
              'type': 'missing',
            },
            {'msg': 'String should have at least 3 characters'},
          ],
        }),
        'Field required; String should have at least 3 characters',
      );
    });

    test('serializza una detail oggetto', () {
      expect(
        ApiClient.apiErrorMessageFor(500, {
          'detail': {'code': 'E1', 'info': 'boom'},
        }),
        jsonEncode({'code': 'E1', 'info': 'boom'}),
      );
    });

    test('ricade su message quando detail è assente', () {
      expect(
        ApiClient.apiErrorMessageFor(400, {'message': 'Richiesta non valida'}),
        'Richiesta non valida',
      );
    });

    test('senza detail né message usa API Error: status', () {
      expect(
        ApiClient.apiErrorMessageFor(500, <String, dynamic>{}),
        'API Error: 500',
      );
      expect(ApiClient.apiErrorMessageFor(503, null), 'API Error: 503');
    });

    test('senza status né body usa il fallback di rete', () {
      expect(ApiClient.apiErrorMessageFor(null, null), 'Errore di rete.');
    });
  });
}
