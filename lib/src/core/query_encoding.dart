import 'dart:convert';

/// Serialises [query] into a URL query string the way `@mux/ts` does.
///
/// Reproduces the `qs` package with `arrayFormat: 'brackets'` and its RFC 3986
/// defaults, which is what every Mux list and filter endpoint expects:
///
/// - a `List` value repeats the key with a `[]` suffix per element —
///   `filters[]=a&filters[]=b` — and an empty list contributes nothing;
/// - a nested `Map` becomes `key[sub]=value`;
/// - `null` becomes `key=` (an empty value, not an absent key — omit the key
///   from [query] to send nothing);
/// - `bool`, `num` and `String` are written as their JS `String()` form, so a
///   whole-valued `double` is written without a fractional part;
/// - a [DateTime] is written as an ISO-8601 UTC instant with millisecond
///   precision, like `Date.prototype.toISOString`.
///
/// Both keys and values are percent-encoded with the RFC 3986 unreserved set
/// (`A–Z a–z 0–9 - . _ ~`); everything else, including the brackets and
/// `!*'()`, is escaped from its UTF-8 bytes. Pairs keep the insertion order
/// of [query].
String muxQueryEncode(Map<String, Object?> query) {
  final pairs = <String>[];
  for (final entry in query.entries) {
    _write(entry.key, entry.value, pairs);
  }
  return pairs.join('&');
}

void _write(String prefix, Object? value, List<String> pairs) {
  if (value == null) {
    pairs.add('${_encode(prefix)}=');
    return;
  }
  if (value is List<Object?>) {
    for (final element in value) {
      _write('$prefix[]', element, pairs);
    }
    return;
  }
  if (value is Map<String, Object?>) {
    for (final entry in value.entries) {
      _write('$prefix[${entry.key}]', entry.value, pairs);
    }
    return;
  }
  pairs.add('${_encode(prefix)}=${_encode(_scalarToString(value))}');
}

String _scalarToString(Object value) => switch (value) {
      final DateTime date => _isoString(date.toUtc()),
      final bool flag => '$flag',
      final int number => '$number',
      final double number => _doubleToString(number),
      final String text => text,
      _ => value.toString(),
    };

String _doubleToString(double number) {
  if (number.isFinite && number == number.roundToDouble()) {
    return number.toInt().toString();
  }
  return number.toString();
}

String _isoString(DateTime utc) {
  String pad(int value, int width) => value.toString().padLeft(width, '0');
  return '${pad(utc.year, 4)}-${pad(utc.month, 2)}-${pad(utc.day, 2)}'
      'T${pad(utc.hour, 2)}:${pad(utc.minute, 2)}:${pad(utc.second, 2)}'
      '.${pad(utc.millisecond, 3)}Z';
}

String _encode(String text) {
  final buffer = StringBuffer();
  for (final byte in utf8.encode(text)) {
    if (_isUnreserved(byte)) {
      buffer.writeCharCode(byte);
    } else {
      buffer
        ..write('%')
        ..write(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
    }
  }
  return buffer.toString();
}

bool _isUnreserved(int byte) =>
    (byte >= 0x41 && byte <= 0x5a) ||
    (byte >= 0x61 && byte <= 0x7a) ||
    (byte >= 0x30 && byte <= 0x39) ||
    byte == 0x2d ||
    byte == 0x2e ||
    byte == 0x5f ||
    byte == 0x7e;
