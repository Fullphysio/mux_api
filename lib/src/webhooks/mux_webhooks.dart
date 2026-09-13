import 'dart:convert';

import '../core/crypto_util.dart';
import '../core/decode_exception.dart';
import '../core/exceptions.dart';
import 'mux_webhook_event.dart';

/// The name of the header Mux signs webhook deliveries with.
const String muxSignatureHeaderName = 'mux-signature';

/// The default age past which a delivery is rejected, as upstream.
const Duration muxWebhookDefaultTolerance = Duration(seconds: 300);

/// Verifies and decodes Mux webhook deliveries.
///
/// Construct one with the endpoint's signing secret, or use the top-level
/// [verifyMuxWebhookSignature] / [unwrapMuxWebhookEvent] with no client at
/// all. Always pass the **raw** request body string, never a re-encoded or
/// already-parsed one: the signature covers the exact bytes Mux sent.
final class MuxWebhooks {
  /// Creates the helper with the client's default signing secret.
  const MuxWebhooks({this.defaultSecret});

  /// The secret used when a call passes none.
  final String? defaultSecret;

  /// Verifies [rawBody] against the `mux-signature` header value
  /// [signatureHeader]; see [verifyMuxWebhookSignature].
  void verify(
    String rawBody,
    String? signatureHeader, {
    String? secret,
    Duration tolerance = muxWebhookDefaultTolerance,
    DateTime? now,
  }) =>
      verifyMuxWebhookSignature(
        rawBody,
        signatureHeader,
        secret: secret ?? defaultSecret,
        tolerance: tolerance,
        now: now,
      );

  /// Verifies then decodes [rawBody]; see [unwrapMuxWebhookEvent].
  MuxWebhookEvent unwrap(
    String rawBody,
    String? signatureHeader, {
    String? secret,
    Duration tolerance = muxWebhookDefaultTolerance,
    DateTime? now,
  }) =>
      unwrapMuxWebhookEvent(
        rawBody,
        signatureHeader,
        secret: secret ?? defaultSecret,
        tolerance: tolerance,
        now: now,
      );
}

/// Verifies that [rawBody] was sent by Mux, reproducing `@mux/ts`.
///
/// [signatureHeader] is the raw `mux-signature` value:
/// `t=<unix seconds>,v1=<hex>[,v1=<hex>…]`. The expected signature is the
/// hex HMAC-SHA256 of `"<t>.<rawBody>"` keyed with [secret]; it is compared
/// in constant time against every `v1` entry, so rotating secrets with two
/// live signatures works. Deliveries older than [tolerance] are rejected.
///
/// Throws a [MuxWebhookSignatureException] naming exactly what failed:
/// missing secret, missing header, unparsable header, no `v1` entries, no
/// matching signature, or a timestamp too old.
void verifyMuxWebhookSignature(
  String rawBody,
  String? signatureHeader, {
  required String? secret,
  Duration tolerance = muxWebhookDefaultTolerance,
  DateTime? now,
}) {
  if (secret == null || secret.isEmpty) {
    throw const MuxWebhookSignatureException.missingSecret();
  }
  if (signatureHeader == null || signatureHeader.isEmpty) {
    throw const MuxWebhookSignatureException.missingHeader();
  }

  int? timestamp;
  final signatures = <String>[];
  for (final item in signatureHeader.split(',')) {
    final separator = item.indexOf('=');
    if (separator < 0) {
      continue;
    }
    final key = item.substring(0, separator);
    final value = item.substring(separator + 1);
    if (key == 't') {
      timestamp = int.tryParse(value);
    } else if (key == 'v1') {
      signatures.add(value);
    }
  }
  if (timestamp == null) {
    throw const MuxWebhookSignatureException.unparsableHeader();
  }
  if (signatures.isEmpty) {
    throw const MuxWebhookSignatureException.noSignatures();
  }

  final expected = muxHmacSha256Hex('$timestamp.$rawBody', secret);
  if (!signatures.any((signature) => muxSecureCompare(signature, expected))) {
    throw const MuxWebhookSignatureException.noMatch();
  }

  final nowSeconds = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
  if (nowSeconds - timestamp > tolerance.inSeconds) {
    throw const MuxWebhookSignatureException.tooOld();
  }
}

/// Verifies [rawBody] with [verifyMuxWebhookSignature], then decodes it into
/// the most specific [MuxWebhookEvent] this package knows.
///
/// A body that verifies but is not a JSON object throws a
/// [MuxDecodeException].
MuxWebhookEvent unwrapMuxWebhookEvent(
  String rawBody,
  String? signatureHeader, {
  required String? secret,
  Duration tolerance = muxWebhookDefaultTolerance,
  DateTime? now,
}) {
  verifyMuxWebhookSignature(
    rawBody,
    signatureHeader,
    secret: secret,
    tolerance: tolerance,
    now: now,
  );
  final Object? decoded;
  try {
    decoded = jsonDecode(rawBody);
  } on FormatException catch (error) {
    throw MuxDecodeException('webhook body is not JSON (${error.message})');
  }
  if (decoded is! Map<String, Object?>) {
    throw MuxDecodeException(
      'webhook body is not a JSON object (${decoded.runtimeType})',
    );
  }
  return MuxWebhookEvent.fromJson(decoded);
}
