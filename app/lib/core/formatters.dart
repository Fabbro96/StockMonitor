/// Centralised `it-IT` formatting helpers.
///
/// These functions intentionally do not depend on `BuildContext`: widgets pass
/// plain values and receive display strings (or `-` when missing).
library;

import 'package:intl/intl.dart';

import 'models/parse_utils.dart' as parsing;

/// Formats a currency amount with two decimals.
///
/// Only `EUR` (€) and `USD` ($) are rendered; any other currency — and any
/// null/NaN value — yields `-`.
String formatCurrency(num? value, {String currency = 'EUR'}) {
  final amount = _finite(value);
  if (amount == null) return '-';

  final symbol = _currencySymbol(currency);
  if (symbol == null) return '-';

  return NumberFormat.currency(
    locale: 'it_IT',
    symbol: symbol,
    decimalDigits: 2,
  ).format(amount);
}

/// Formats a percentage with two decimals, prefixing `+` only when positive.
String formatPercent(num? value) {
  final amount = _finite(value);
  if (amount == null) return '-';
  final sign = amount > 0 ? '+' : '';
  return '$sign${NumberFormat('#,##0.00', 'it_IT').format(amount)}%';
}

/// Formats a number in compact notation (e.g. `1,23 Mln`), `-` when null/zero.
String formatCompactNumber(num? value) {
  final amount = _finite(value);
  if (amount == null || amount == 0) return '-';
  final formatter = NumberFormat.compact(locale: 'it_IT')
    ..maximumFractionDigits = 2;
  return formatter.format(amount);
}

/// Formats a date as `gg/mm/aaaa`, `-` when null.
String formatDate(DateTime? value) {
  if (value == null) return '-';
  return DateFormat('dd/MM/yyyy').format(value);
}

/// Formats a date and time as `gg/mm/aaaa, HH:MM`, `-` when null.
String formatDateTime(DateTime? value) {
  if (value == null) return '-';
  return DateFormat('dd/MM/yyyy, HH:mm').format(value);
}

/// Parses a date-only server value (`YYYY-MM-DD`) without UTC conversion.
DateTime? parseServerDate(String? value) => parsing.parseServerDate(value);

/// Serialises a [DateTime] as a local `yyyy-MM-dd` API value.
///
/// Deliberately avoids `toIso8601String()`/UTC conversion: the backend stores
/// transaction dates as local calendar days (bug fix from the migration plan).
String dateToApi(DateTime value) {
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

double? _finite(num? value) {
  if (value == null) return null;
  final amount = value.toDouble();
  return (amount.isNaN || amount.isInfinite) ? null : amount;
}

String? _currencySymbol(String currency) {
  switch (currency.trim().toUpperCase()) {
    case 'EUR':
      return '€';
    case 'USD':
      return r'$';
    default:
      return null;
  }
}
