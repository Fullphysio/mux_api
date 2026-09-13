import 'dart:convert';

/// Base class for every failure this package raises while talking to Mux.
///
/// Sealed, so a `switch` over a caught [MuxException] is exhaustive. Three
/// families exist: an error status returned by the API ([MuxApiException]
/// and its subtypes), a request that never produced a response
/// ([MuxConnectionException], [MuxTimeoutException]), and a webhook payload
/// that failed verification ([MuxWebhookSignatureException]). A successful
/// response whose body does not have the expected shape is deliberately
/// outside this hierarchy — see `MuxDecodeException`.
sealed class MuxException implements Exception {
  /// Creates an exception carrying [message].
  const MuxException(this.message);

  /// What went wrong, in one line.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// A non-2xx response from the Mux API, raised once retries are exhausted or
/// the status was not retryable in the first place.
///
/// The concrete subtype is chosen by HTTP status code alone, exactly as
/// `@mux/ts` does. Mux's error body, `{"error": {"type": "…", "messages":
/// ["…"]}}`, is surfaced through [errorType] and [messages] but never
/// participates in choosing the subtype.
sealed class MuxApiException extends MuxException {
  /// Creates an API exception from a decoded error response.
  const MuxApiException({
    required String message,
    required this.statusCode,
    required this.headers,
    this.errorType,
    this.messages = const [],
    this.raw,
  }) : super(message);

  /// The HTTP status code of the response.
  final int statusCode;

  /// The response headers, lower-cased keys.
  final Map<String, String> headers;

  /// Mux's `error.type` label, such as `invalid_parameters`, when the body
  /// carried one.
  final String? errorType;

  /// Mux's `error.messages`, human-readable explanations, when the body
  /// carried them. Empty otherwise; entries that are not strings are left to
  /// [raw].
  final List<String> messages;

  /// The decoded JSON body when it was JSON, the raw text otherwise, or
  /// `null` for an empty body.
  final Object? raw;
}

/// HTTP 400.
final class MuxBadRequestException extends MuxApiException {
  /// Creates the exception for a 400 response.
  const MuxBadRequestException({
    required super.message,
    required super.statusCode,
    required super.headers,
    super.errorType,
    super.messages,
    super.raw,
  });
}

/// HTTP 401: the token id / secret pair was rejected.
final class MuxAuthenticationException extends MuxApiException {
  /// Creates the exception for a 401 response.
  const MuxAuthenticationException({
    required super.message,
    required super.statusCode,
    required super.headers,
    super.errorType,
    super.messages,
    super.raw,
  });
}

/// HTTP 403: the token lacks permission for this operation.
final class MuxPermissionDeniedException extends MuxApiException {
  /// Creates the exception for a 403 response.
  const MuxPermissionDeniedException({
    required super.message,
    required super.statusCode,
    required super.headers,
    super.errorType,
    super.messages,
    super.raw,
  });
}

/// HTTP 404.
final class MuxNotFoundException extends MuxApiException {
  /// Creates the exception for a 404 response.
  const MuxNotFoundException({
    required super.message,
    required super.statusCode,
    required super.headers,
    super.errorType,
    super.messages,
    super.raw,
  });
}

/// HTTP 409. Retried by default before it is thrown.
final class MuxConflictException extends MuxApiException {
  /// Creates the exception for a 409 response.
  const MuxConflictException({
    required super.message,
    required super.statusCode,
    required super.headers,
    super.errorType,
    super.messages,
    super.raw,
  });
}

/// HTTP 422.
final class MuxUnprocessableEntityException extends MuxApiException {
  /// Creates the exception for a 422 response.
  const MuxUnprocessableEntityException({
    required super.message,
    required super.statusCode,
    required super.headers,
    super.errorType,
    super.messages,
    super.raw,
  });
}

/// HTTP 429. Retried by default, honouring `Retry-After`, before it is
/// thrown.
final class MuxRateLimitException extends MuxApiException {
  /// Creates the exception for a 429 response.
  const MuxRateLimitException({
    required super.message,
    required super.statusCode,
    required super.headers,
    super.errorType,
    super.messages,
    super.raw,
  });
}

/// Any 5xx. Retried by default before it is thrown.
final class MuxInternalServerException extends MuxApiException {
  /// Creates the exception for a 5xx response.
  const MuxInternalServerException({
    required super.message,
    required super.statusCode,
    required super.headers,
    super.errorType,
    super.messages,
    super.raw,
  });
}

/// A non-2xx status none of the other subtypes claims, such as 402 or 418.
final class MuxUnexpectedStatusException extends MuxApiException {
  /// Creates the exception for an unclassified error status.
  const MuxUnexpectedStatusException({
    required super.message,
    required super.statusCode,
    required super.headers,
    super.errorType,
    super.messages,
    super.raw,
  });
}

/// The request never produced a response: DNS failure, connection reset, TLS
/// error. Retried by default before it is thrown.
final class MuxConnectionException extends MuxException {
  /// Creates a connection failure, optionally wrapping the transport-level
  /// [cause].
  const MuxConnectionException({
    String message = 'Connection error.',
    this.cause,
  }) : super(message);

  /// The underlying error thrown by the HTTP client, when there was one.
  final Object? cause;
}

/// The request exceeded the client's timeout. Retried by default before it
/// is thrown.
final class MuxTimeoutException extends MuxException {
  /// Creates a timeout failure.
  const MuxTimeoutException({String message = 'Request timed out.'})
      : super(message);
}

/// A webhook payload that could not be verified against the signing secret.
///
/// Declared here rather than beside the webhook code because [MuxException]
/// is `sealed`, which confines its subtypes to this library. The named
/// constructors reproduce the failure messages of `@mux/ts`.
final class MuxWebhookSignatureException extends MuxException {
  /// No secret was configured on the client or passed to the call.
  const MuxWebhookSignatureException.missingSecret()
      : super(
          'The webhook secret must either be set on '
          'MuxClient(webhookSecret: …) or passed to this call',
        );

  /// The request carried no `mux-signature` header.
  const MuxWebhookSignatureException.missingHeader()
      : super('Could not find a mux-signature header');

  /// The header did not contain a `t=<timestamp>` component.
  const MuxWebhookSignatureException.unparsableHeader()
      : super('Unable to extract timestamp and signatures from header');

  /// The header contained no `v1=<signature>` component.
  const MuxWebhookSignatureException.noSignatures()
      : super('No v1 signatures found');

  /// None of the `v1` signatures matched the payload.
  const MuxWebhookSignatureException.noMatch()
      : super(
            'No signatures found matching the expected signature for payload.');

  /// The signature was valid but its timestamp is older than the tolerance.
  const MuxWebhookSignatureException.tooOld()
      : super('Webhook timestamp is too old');
}

/// Builds the [MuxApiException] subtype for a non-2xx response, reproducing
/// how `@mux/ts` formats the message and dispatches on status.
///
/// The message is `"<status> <detail>"`, where the detail is the body's
/// top-level `message` when it has one, otherwise the JSON body re-encoded
/// compactly, otherwise the raw text; an empty body yields
/// `"<status> status code (no body)"`. [body] is the raw response text,
/// never pre-parsed.
MuxApiException muxApiExceptionFromResponse({
  required int statusCode,
  required Map<String, String> headers,
  required String body,
}) {
  final decoded = _decodeJson(body);
  final detail = _detailOf(decoded, body);
  final message = detail == null || detail.isEmpty
      ? '$statusCode status code (no body)'
      : '$statusCode $detail';
  final error = decoded is Map<String, Object?> ? decoded['error'] : null;
  final errorType = error is Map<String, Object?> && error['type'] is String
      ? error['type'] as String
      : null;
  final messages = error is Map<String, Object?> && error['messages'] is List
      ? (error['messages'] as List<Object?>)
          .whereType<String>()
          .toList(growable: false)
      : const <String>[];
  final raw = decoded ?? (body.isEmpty ? null : body);

  return switch (statusCode) {
    400 => MuxBadRequestException(
        message: message,
        statusCode: statusCode,
        headers: headers,
        errorType: errorType,
        messages: messages,
        raw: raw,
      ),
    401 => MuxAuthenticationException(
        message: message,
        statusCode: statusCode,
        headers: headers,
        errorType: errorType,
        messages: messages,
        raw: raw,
      ),
    403 => MuxPermissionDeniedException(
        message: message,
        statusCode: statusCode,
        headers: headers,
        errorType: errorType,
        messages: messages,
        raw: raw,
      ),
    404 => MuxNotFoundException(
        message: message,
        statusCode: statusCode,
        headers: headers,
        errorType: errorType,
        messages: messages,
        raw: raw,
      ),
    409 => MuxConflictException(
        message: message,
        statusCode: statusCode,
        headers: headers,
        errorType: errorType,
        messages: messages,
        raw: raw,
      ),
    422 => MuxUnprocessableEntityException(
        message: message,
        statusCode: statusCode,
        headers: headers,
        errorType: errorType,
        messages: messages,
        raw: raw,
      ),
    429 => MuxRateLimitException(
        message: message,
        statusCode: statusCode,
        headers: headers,
        errorType: errorType,
        messages: messages,
        raw: raw,
      ),
    >= 500 => MuxInternalServerException(
        message: message,
        statusCode: statusCode,
        headers: headers,
        errorType: errorType,
        messages: messages,
        raw: raw,
      ),
    _ => MuxUnexpectedStatusException(
        message: message,
        statusCode: statusCode,
        headers: headers,
        errorType: errorType,
        messages: messages,
        raw: raw,
      ),
  };
}

Object? _decodeJson(String body) {
  if (body.isEmpty) {
    return null;
  }
  try {
    return jsonDecode(body);
  } on FormatException {
    return null;
  }
}

String? _detailOf(Object? decoded, String body) {
  if (decoded is Map<String, Object?>) {
    final message = decoded['message'];
    if (message != null) {
      return message is String ? message : jsonEncode(message);
    }
  }
  if (decoded != null) {
    return jsonEncode(decoded);
  }
  return body;
}
