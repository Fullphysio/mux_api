import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'decode_exception.dart';
import 'exceptions.dart';
import 'query_encoding.dart';
import 'retry_policy.dart';

/// The Mux hosts a request can be addressed to.
///
/// The REST API lives on [api]; the playback helpers fetch thumbnails and
/// storyboards from [image], HLS manifests, renditions and text tracks from
/// [stream], and viewer counts from [stats]. A `baseUrl` given to the client
/// overrides all four, as it does upstream.
enum MuxHost {
  /// `https://api.mux.com`.
  api('https://api.mux.com'),

  /// `https://image.mux.com`.
  image('https://image.mux.com'),

  /// `https://stream.mux.com`.
  stream('https://stream.mux.com'),

  /// `https://stats.mux.com`.
  stats('https://stats.mux.com');

  const MuxHost(this.url);

  /// The origin, without a trailing slash.
  final String url;
}

/// Waits for [delay] before the next attempt; an injection seam for tests.
typedef MuxSleep = Future<void> Function(Duration delay);

Future<void> _realSleep(Duration delay) => Future<void>.delayed(delay);

/// Carries out HTTP requests against Mux, applying authentication, the
/// timeout, the retry policy and error mapping.
final class MuxTransport {
  /// Creates a transport authenticated with [tokenId] / [tokenSecret].
  MuxTransport({
    required String tokenId,
    required String tokenSecret,
    Uri? baseUrl,
    http.Client? httpClient,
    required this.timeout,
    required this.maxRetries,
    Random? random,
    MuxSleep? sleep,
  })  : _authorization =
            'Basic ${base64Encode(utf8.encode('$tokenId:$tokenSecret'))}',
        _baseUrl = baseUrl,
        _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null,
        _random = random,
        _sleep = sleep ?? _realSleep;

  /// The deadline for receiving response headers on each attempt.
  final Duration timeout;

  /// How many times a failed attempt is retried on top of the first one.
  final int maxRetries;

  final String _authorization;
  final Uri? _baseUrl;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final Random? _random;
  final MuxSleep _sleep;

  /// Sends a JSON request and returns the decoded body — the full envelope,
  /// exactly as Mux sent it — or `null` for an empty body.
  ///
  /// [accept] defaults to `application/json`; an operation that returns no
  /// body passes `*/*`, as upstream does.
  Future<Object?> requestJson({
    required String method,
    required String path,
    Map<String, Object?>? query,
    Object? body,
    MuxHost host = MuxHost.api,
    String accept = 'application/json',
  }) async {
    final response = await send(
      method: method,
      path: path,
      query: query,
      body: body,
      host: host,
      accept: accept,
    );
    if (response.bodyBytes.isEmpty) {
      return null;
    }
    final text = utf8.decode(response.bodyBytes);
    try {
      return jsonDecode(text);
    } on FormatException catch (error) {
      throw MuxDecodeException(
        '$method $path: response body is not JSON (${error.message})',
      );
    }
  }

  /// Sends a request whose response is text, such as a WebVTT track or a
  /// storyboard manifest, and returns the body decoded as UTF-8.
  Future<String> requestText({
    required String method,
    required String path,
    Map<String, Object?>? query,
    Object? body,
    MuxHost host = MuxHost.api,
    String accept = '*/*',
  }) async {
    final response = await send(
      method: method,
      path: path,
      query: query,
      body: body,
      host: host,
      accept: accept,
    );
    return utf8.decode(response.bodyBytes);
  }

  /// Sends a request whose response is binary, such as a thumbnail, and
  /// returns the raw body.
  Future<Uint8List> requestBytes({
    required String method,
    required String path,
    Map<String, Object?>? query,
    Object? body,
    MuxHost host = MuxHost.api,
    String accept = '*/*',
  }) async {
    final response = await send(
      method: method,
      path: path,
      query: query,
      body: body,
      host: host,
      accept: accept,
    );
    return response.bodyBytes;
  }

  /// Sends one request with retries and returns the successful response.
  ///
  /// [path] is the already-encoded request path with its leading slash;
  /// [query] is serialised by [muxQueryEncode]; [body], when given, is JSON
  /// encoded and sent with `Content-Type: application/json`. Throws the
  /// [MuxApiException] subtype for a non-2xx response once retries are
  /// exhausted or the status is not retryable, a [MuxTimeoutException] when
  /// every attempt exceeded [timeout], or a [MuxConnectionException] when no
  /// attempt produced a response.
  Future<http.Response> send({
    required String method,
    required String path,
    Map<String, Object?>? query,
    Object? body,
    required MuxHost host,
    required String accept,
  }) async {
    final uri = _buildUri(host, path, query);
    final bodyBytes = body == null ? null : utf8.encode(jsonEncode(body));

    var attempt = 0;
    while (true) {
      http.Response? response;
      Object? failure;
      var timedOut = false;
      try {
        response = await _attempt(method, uri, bodyBytes, accept);
      } on TimeoutException catch (error) {
        failure = error;
        timedOut = true;
      } on Exception catch (error) {
        failure = error;
      }

      if (response != null &&
          response.statusCode >= 200 &&
          response.statusCode < 300) {
        return response;
      }

      if (!muxShouldRetry(
        attempt: attempt,
        maxRetries: maxRetries,
        response: response,
      )) {
        if (response == null) {
          if (timedOut) {
            throw const MuxTimeoutException();
          }
          throw MuxConnectionException(cause: failure);
        }
        throw muxApiExceptionFromResponse(
          statusCode: response.statusCode,
          headers: response.headers,
          body: utf8.decode(response.bodyBytes, allowMalformed: true),
        );
      }

      await _sleep(
        muxRetryDelay(
          attempt: attempt,
          retryAfter: response == null ? null : muxRetryAfter(response.headers),
          random: _random,
        ),
      );
      attempt++;
    }
  }

  /// Closes the underlying HTTP client, if this transport created it.
  void close() {
    if (_ownsHttpClient) {
      _httpClient.close();
    }
  }

  Future<http.Response> _attempt(
    String method,
    Uri uri,
    List<int>? bodyBytes,
    String accept,
  ) async {
    final request = http.Request(method, uri)
      ..headers['Authorization'] = _authorization
      ..headers['Accept'] = accept;
    if (bodyBytes != null) {
      request
        ..bodyBytes = bodyBytes
        ..headers['Content-Type'] = 'application/json';
    }
    final pending = _httpClient.send(request);
    final http.StreamedResponse streamed;
    try {
      streamed = await pending.timeout(timeout);
    } on TimeoutException {
      _drainLate(pending);
      rethrow;
    }
    return http.Response.fromStream(streamed);
  }

  /// `Future.timeout` abandons the request but cannot cancel it; when the
  /// response does arrive, its body is read to completion so the pooled
  /// connection is released instead of staying pinned by an unread stream.
  void _drainLate(Future<http.StreamedResponse> pending) {
    unawaited(
      pending
          .then((late) => late.stream.drain<void>())
          .catchError((Object _) {}),
    );
  }

  Uri _buildUri(MuxHost host, String path, Map<String, Object?>? query) {
    final base = _baseUrl;
    final origin = base == null
        ? host.url
        : base.toString().replaceFirst(RegExp(r'/+$'), '');
    final encodedQuery = query == null ? '' : muxQueryEncode(query);
    return Uri.parse(
      '$origin$path${encodedQuery.isEmpty ? '' : '?$encodedQuery'}',
    );
  }
}
