import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../jwt/mux_jwt.dart';
import '../resources/video.dart';
import '../webhooks/mux_webhooks.dart';
import 'transport.dart';

/// A client for the Mux API.
///
/// Wires HTTP transport — Basic authentication, timeouts, retries and error
/// mapping — to the typed resources reachable through its namespaces. One
/// instance should be reused for the lifetime of the process; call [close]
/// once it is no longer needed.
///
/// Unlike `@mux/ts`, nothing is read from environment variables: every
/// credential is passed explicitly, which is what makes the client portable
/// across Flutter apps, CLIs and Cloud Functions, and testable.
final class MuxClient {
  /// Creates a client authenticated with an access token [tokenId] /
  /// [tokenSecret] pair.
  ///
  /// [baseUrl] overrides every Mux host — for tests, or for a mock server —
  /// and defaults to the real `api.mux.com` / `image.mux.com` /
  /// `stream.mux.com` origins per request. [httpClient] is an injection seam
  /// for tests; when omitted, a fresh [http.Client] is created and owned by
  /// this instance, to be closed by [close]. [timeout] bounds each attempt
  /// and [maxRetries] caps how many times a failed attempt is retried.
  ///
  /// [webhookSecret], [jwtSigningKeyId] and [jwtPrivateKey] seed the
  /// defaults used by the webhook and JWT helpers when a call does not
  /// override them.
  MuxClient({
    required String tokenId,
    required String tokenSecret,
    Uri? baseUrl,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 60),
    this.maxRetries = 2,
    this.webhookSecret,
    this.jwtSigningKeyId,
    this.jwtPrivateKey,
  }) : _transport = MuxTransport(
          tokenId: tokenId,
          tokenSecret: tokenSecret,
          baseUrl: baseUrl,
          httpClient: httpClient,
          timeout: timeout,
          maxRetries: maxRetries,
        );

  /// The deadline for receiving response headers on each attempt.
  final Duration timeout;

  /// How many times a failed attempt is retried on top of the first one.
  final int maxRetries;

  /// The signing secret of the webhook endpoint, used by default when
  /// verifying deliveries.
  final String? webhookSecret;

  /// The id of the signing key used by default when signing playback tokens.
  final String? jwtSigningKeyId;

  /// The private key, as PEM or base64-encoded PEM, used by default when
  /// signing playback tokens.
  final String? jwtPrivateKey;

  final MuxTransport _transport;

  /// Mux Video resources: `client.video.uploads`, …
  late final MuxVideo video = MuxVideo(this);

  /// Signs playback, DRM-licence and viewer-count tokens with
  /// [jwtSigningKeyId] / [jwtPrivateKey] unless a call overrides them.
  late final MuxJwt jwt = MuxJwt(
    defaultKeyId: jwtSigningKeyId,
    defaultPrivateKey: jwtPrivateKey,
  );

  /// Verifies and decodes webhook deliveries with [webhookSecret] unless a
  /// call overrides it.
  late final MuxWebhooks webhooks = MuxWebhooks(defaultSecret: webhookSecret);

  /// Sends a JSON request and returns the decoded body, envelope included.
  ///
  /// This is the primitive the typed resources are built on, exposed as an
  /// escape hatch for an endpoint this package does not model yet. [path] is
  /// the already-encoded request path with its leading slash, such as
  /// `/video/v1/assets`; [query] follows Mux's bracket-array convention for
  /// lists; [body] is JSON-encoded when given; [accept] is the `Accept`
  /// header, `*/*` for an operation that returns no body.
  Future<Object?> requestJson({
    required String method,
    required String path,
    Map<String, Object?>? query,
    Object? body,
    MuxHost host = MuxHost.api,
    String accept = 'application/json',
  }) =>
      _transport.requestJson(
        method: method,
        path: path,
        query: query,
        body: body,
        host: host,
        accept: accept,
      );

  /// Sends a request whose response is text and returns the body.
  Future<String> requestText({
    required String method,
    required String path,
    Map<String, Object?>? query,
    Object? body,
    MuxHost host = MuxHost.api,
    String accept = '*/*',
  }) =>
      _transport.requestText(
        method: method,
        path: path,
        query: query,
        body: body,
        host: host,
        accept: accept,
      );

  /// Sends a request whose response is binary and returns the raw bytes.
  Future<Uint8List> requestBytes({
    required String method,
    required String path,
    Map<String, Object?>? query,
    Object? body,
    MuxHost host = MuxHost.api,
    String accept = '*/*',
  }) =>
      _transport.requestBytes(
        method: method,
        path: path,
        query: query,
        body: body,
        host: host,
        accept: accept,
      );

  /// Closes the underlying HTTP client, if this instance created it.
  ///
  /// Does nothing when the client was constructed with a caller-supplied
  /// `httpClient`, since that client's lifetime belongs to its caller.
  void close() => _transport.close();
}
