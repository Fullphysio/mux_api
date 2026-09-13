import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

/// Decides whether a Mux request attempt should be retried.
///
/// Reproduces `@mux/ts` 15.1.0's decision, checked in this strict precedence
/// order:
///
/// 1. [attempt] has already reached [maxRetries] — never retry.
/// 2. [response] carries an `x-should-retry` header — obey it exactly,
///    whether it says `true` or `false`, regardless of the status code.
/// 3. There is no [response] at all — a connection failure or timeout — so
///    retry, since the request may never have reached Mux.
/// 4. Otherwise retry on 408, 409, 429 and any 5xx; leave every other status
///    alone.
///
/// Mux defines no idempotency-key mechanism, so a retried `POST` is exactly
/// as eager here as upstream. That is inherited, not introduced.
bool muxShouldRetry({
  required int attempt,
  required int maxRetries,
  http.Response? response,
}) {
  if (attempt >= maxRetries) {
    return false;
  }
  final shouldRetryHeader = response?.headers['x-should-retry'];
  if (shouldRetryHeader == 'true') {
    return true;
  }
  if (shouldRetryHeader == 'false') {
    return false;
  }
  if (response == null) {
    return true;
  }
  final status = response.statusCode;
  return status == 408 || status == 409 || status == 429 || status >= 500;
}

/// Resolves the delay a response asked for, or `null` when it asked for none.
///
/// Reproduces `@mux/ts`: the non-standard `retry-after-ms` header is read
/// first as a millisecond count; when it is absent, unparsable or zero, the
/// standard `retry-after` header is read as delay-seconds and, failing that,
/// as an HTTP-date relative to [now]. Upstream parses with `parseFloat`, so a
/// leading numeric prefix counts (`"5 seconds"` is 5, and an ISO-8601 date
/// is its year in seconds); an HTTP-date that does not parse, or one already
/// in the past, yields [Duration.zero] — an immediate retry — exactly as
/// upstream sleeps for `NaN` or a negative number. There is no upper bound:
/// whatever Mux asks for is honoured.
Duration? muxRetryAfter(Map<String, String> headers, {DateTime? now}) {
  final millisHeader = headers['retry-after-ms'];
  final millis = millisHeader == null ? null : _parseFloat(millisHeader);
  if (millis != null && millis != 0) {
    return _fromMillis(millis);
  }
  final secondsHeader = headers['retry-after'];
  if (secondsHeader != null) {
    final seconds = _parseFloat(secondsHeader);
    if (seconds != null) {
      return _fromMillis(seconds * 1000);
    }
    final date = _parseDate(secondsHeader);
    if (date == null) {
      return Duration.zero;
    }
    return _fromMillis(
      date.difference(now ?? DateTime.now()).inMilliseconds.toDouble(),
    );
  }
  return millis == null ? null : Duration.zero;
}

/// Computes how long to wait before the retry numbered [attempt] (zero-based).
///
/// A [retryAfter] resolved by [muxRetryAfter] is honoured as is. Otherwise
/// the delay is `min(500 ms × 2^attempt, 8 s)`, shortened by a random jitter
/// of up to 25 % — Stainless's default backoff, which only ever shortens the
/// wait, never lengthens it. [random] is an injection seam for deterministic
/// tests.
Duration muxRetryDelay({
  required int attempt,
  Duration? retryAfter,
  Random? random,
}) {
  if (retryAfter != null) {
    return retryAfter;
  }
  const initialSeconds = 0.5;
  const maxSeconds = 8.0;
  final sleepSeconds = min(initialSeconds * pow(2, attempt), maxSeconds);
  final jitter = 1 - (random ?? Random()).nextDouble() * 0.25;
  return Duration(microseconds: (sleepSeconds * jitter * 1000000).round());
}

Duration _fromMillis(double millis) => millis <= 0
    ? Duration.zero
    : Duration(microseconds: (millis * 1000).round());

final RegExp _leadingNumber =
    RegExp(r'^\s*[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?');

double? _parseFloat(String text) {
  final match = _leadingNumber.firstMatch(text);
  return match == null ? null : double.tryParse(match.group(0)!.trim());
}

DateTime? _parseDate(String text) {
  final trimmed = text.trim();
  final iso = DateTime.tryParse(trimmed);
  if (iso != null) {
    return iso;
  }
  try {
    return parseHttpDate(trimmed);
  } on FormatException {
    return null;
  }
}
