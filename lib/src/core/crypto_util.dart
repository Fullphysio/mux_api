import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Computes an HMAC-SHA256 signature over the UTF-8 encoding of [payload],
/// keyed with the UTF-8 encoding of [secret], as lowercase hexadecimal — the
/// format Mux sends in the `mux-signature` webhook header.
String muxHmacSha256Hex(String payload, String secret) {
  final hmac = Hmac(sha256, utf8.encode(secret));
  return hmac.convert(utf8.encode(payload)).toString();
}

/// Compares [a] and [b] for equality in constant time, so a forged webhook
/// signature cannot be refined one byte at a time from response timing.
///
/// Every character pair is inspected via XOR-accumulation; the work done
/// depends only on the lengths of [a] and [b], never on where they differ.
bool muxSecureCompare(String a, String b) {
  if (a.length != b.length) {
    return false;
  }
  var result = 0;
  for (var i = 0; i < a.length; i++) {
    result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return result == 0;
}
