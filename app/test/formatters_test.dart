import 'package:flutter_test/flutter_test.dart';
import 'package:stock_monitor/core/formatters.dart';

void main() {
  group('formatCurrency', () {
    test('null e valori non finiti restituiscono -', () {
      expect(formatCurrency(null), '-');
      expect(formatCurrency(double.nan), '-');
      expect(formatCurrency(double.infinity), '-');
    });

    test('EUR usa simbolo e 2 decimali (it-IT)', () {
      final out = formatCurrency(1234.5);
      expect(out, contains('1.234,50'));
      expect(out, contains('€'));
    });

    test('USD usa il simbolo dollaro', () {
      final out = formatCurrency(10, currency: 'USD');
      expect(out, contains(r'$'));
      expect(out, contains('10,00'));
    });

    test('valuta non supportata restituisce - anche con valore valido', () {
      expect(formatCurrency(10, currency: 'GBP'), '-');
      expect(formatCurrency(10, currency: 'CHF'), '-');
    });

    test('importo negativo conserva il segno', () {
      final out = formatCurrency(-50.25);
      expect(out, contains('-'));
      expect(out, contains('50,25'));
    });

    test('zero formattato con due decimali', () {
      final out = formatCurrency(0);
      expect(out, contains('0,00'));
    });
  });

  group('formatPercent', () {
    test('null e NaN restituiscono -', () {
      expect(formatPercent(null), '-');
      expect(formatPercent(double.nan), '-');
    });

    test('zero senza segno +', () {
      expect(formatPercent(0), '0,00%');
    });

    test('positivo con segno + e 2 decimali', () {
      expect(formatPercent(1.234), '+1,23%');
    });

    test('negativo con segno - e 2 decimali', () {
      expect(formatPercent(-2.5), '-2,50%');
    });
  });

  group('formatCompactNumber', () {
    test('null e zero restituiscono -', () {
      expect(formatCompactNumber(null), '-');
      expect(formatCompactNumber(0), '-');
    });

    test('numero compatto non vuoto', () {
      final out = formatCompactNumber(1500000);
      expect(out, isNotEmpty);
      expect(out, isNot('-'));
    });

    test('valore piccolo resta leggibile', () {
      expect(formatCompactNumber(1250), isNotEmpty);
    });
  });

  group('date', () {
    test('formatDate gestisce null e gg/mm/aaaa', () {
      expect(formatDate(null), '-');
      expect(formatDate(DateTime(2026, 9, 13)), '13/09/2026');
    });

    test('formatDateTime gestisce null e gg/mm/aaaa, HH:MM', () {
      expect(formatDateTime(null), '-');
      expect(
        formatDateTime(DateTime(2026, 9, 13, 8, 5)),
        '13/09/2026, 08:05',
      );
    });

    test('parseServerDate tollera null, stringa vuota e timestamp completo',
        () {
      expect(parseServerDate(null), isNull);
      expect(parseServerDate(''), isNull);
      expect(parseServerDate('non-una-data'), isNull);
      expect(parseServerDate('2026-09-13'), DateTime(2026, 9, 13));
      expect(parseServerDate('2026-09-13T10:00:00'), DateTime(2026, 9, 13));
    });

    test('dateToApi usa la data locale senza shift UTC', () {
      expect(dateToApi(DateTime(2026, 1, 2, 23, 30)), '2026-01-02');
      expect(dateToApi(DateTime(2026, 12, 31)), '2026-12-31');
    });
  });
}
