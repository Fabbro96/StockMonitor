/// Tolerant JSON parsing helpers shared by all API models.
///
/// The backend payloads are mostly stable but historically expose mixed
/// representations (numbers sent as strings, `null` where a value is expected,
/// timestamps with a space or a `T` separator, with or without timezone).
/// These helpers never throw: an unparsable value becomes `null` (or the
/// provided fallback) so a single odd field cannot break a whole screen.
library;

/// Returns [value] as a finite `double`, or `null`.
double? asDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) {
    final d = value.toDouble();
    return (d.isNaN || d.isInfinite) ? null : d;
  }
  if (value is String) {
    final s = value.trim();
    if (s.isEmpty) return null;
    final d = double.tryParse(s);
    return (d == null || d.isNaN || d.isInfinite) ? null : d;
  }
  return null;
}

/// Returns [value] as an `int`, or `null`.
int? asInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) {
    if (value.isNaN || value.isInfinite) return null;
    return value.toInt();
  }
  if (value is String) {
    final s = value.trim();
    if (s.isEmpty) return null;
    final i = int.tryParse(s);
    if (i != null) return i;
    return asDouble(s)?.toInt();
  }
  if (value is bool) return value ? 1 : 0;
  return null;
}

/// Returns [value] as a `String`, or [fallback] when it is null/unparsable.
String asString(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  if (value is String) return value;
  if (value is num || value is bool) return value.toString();
  return fallback;
}

/// Returns [value] as a `bool`, accepting `true/false`, `1/0`, `yes/no`.
bool asBool(dynamic value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    switch (value.trim().toLowerCase()) {
      case 'true':
      case '1':
      case 'yes':
      case 'on':
        return true;
      case 'false':
      case '0':
      case 'no':
      case 'off':
        return false;
    }
  }
  return fallback;
}

/// Returns [value] as a `Map<String, dynamic>` (empty map when unparsable).
Map<String, dynamic> asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const <String, dynamic>{};
}

/// Returns [value] as a list of maps, skipping non-object entries.
List<Map<String, dynamic>> asMapList(dynamic value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  return <Map<String, dynamic>>[
    for (final item in value)
      if (item is Map) asMap(item),
  ];
}

/// Returns [value] as a list of strings.
///
/// Accepts a list (any element is stringified) or a comma separated string,
/// mirroring the backend columns `markets` / `advice_times`.
List<String> asStringList(dynamic value) {
  if (value is String) {
    return value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  if (value is List) {
    return <String>[
      for (final item in value)
        if (item != null) item.toString(),
    ];
  }
  return const <String>[];
}

/// Parses a date-only server string (`YYYY-MM-DD`) without any UTC shift.
DateTime? parseServerDate(String? raw) {
  if (raw == null) return null;
  final value = raw.trim();
  if (value.isEmpty) return null;

  // Accept the leading date of a full timestamp too (first 10 chars).
  final datePart = value.length >= 10 ? value.substring(0, 10) : value;
  final parsed = DateTime.tryParse(datePart);
  if (parsed != null) return DateTime(parsed.year, parsed.month, parsed.day);
  return null;
}

/// Parses a server timestamp tolerantly.
///
/// Handles `YYYY-MM-DDTHH:MM:SS(.ffffff)`, `YYYY-MM-DD HH:MM:SS(.ffffff)` and
/// optional timezone suffixes (`Z`, `+00:00`). Fractions longer than 6 digits
/// are truncated. Values without timezone are interpreted as-is (local time),
/// which matches the legacy frontend behaviour.
DateTime? parseServerDateTime(String? raw) {
  if (raw == null) return null;
  var value = raw.trim();
  if (value.isEmpty) return null;

  // Truncate sub-microsecond digits (Dart handles up to 6).
  value = value.replaceFirstMapped(
    RegExp(r'\.(\d{6})\d+'),
    (match) => '.${match[1]}',
  );

  // Space separated timestamp -> ISO 8601 `T` separator.
  if (value.length > 10 && value[10] == ' ') {
    value = '${value.substring(0, 10)}T${value.substring(11)}';
  }
  return DateTime.tryParse(value);
}
