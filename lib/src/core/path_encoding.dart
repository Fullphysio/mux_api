import 'dart:convert';

/// Percent-encodes [value] for use as one path segment of a Mux API URL.
///
/// Reproduces `@mux/ts`'s path encoder: every byte outside RFC 3986's `pchar`
/// production — unreserved characters, sub-delimiters, `:` and `@` — is
/// percent-encoded from its UTF-8 bytes, so a `/`, `?`, `#`, `%` or space in
/// an identifier can never change the meaning of the path. Safe characters
/// are left as they are.
///
/// Throws an [ArgumentError] for an empty string, `.` or `..`, none of which
/// can be a Mux identifier and all of which would resolve to a different
/// resource than the caller intended.
String muxPathSegment(String value) {
  if (value.isEmpty || value == '.' || value == '..') {
    throw ArgumentError.value(value, 'value', 'is not a valid path segment');
  }
  final buffer = StringBuffer();
  for (final byte in utf8.encode(value)) {
    if (_isPchar(byte)) {
      buffer.writeCharCode(byte);
    } else {
      buffer
        ..write('%')
        ..write(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
    }
  }
  return buffer.toString();
}

bool _isPchar(int byte) =>
    (byte >= 0x41 && byte <= 0x5a) ||
    (byte >= 0x61 && byte <= 0x7a) ||
    (byte >= 0x30 && byte <= 0x39) ||
    _pcharPunctuation.contains(byte);

const Set<int> _pcharPunctuation = {
  0x2d, // -
  0x2e, // .
  0x5f, // _
  0x7e, // ~
  0x21, // !
  0x24, // $
  0x26, // &
  0x27, // '
  0x28, // (
  0x29, // )
  0x2a, // *
  0x2b, // +
  0x2c, // ,
  0x3b, // ;
  0x3d, // =
  0x3a, // :
  0x40, // @
};
