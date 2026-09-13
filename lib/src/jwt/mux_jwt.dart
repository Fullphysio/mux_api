import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

/// What a signed playback token unlocks, and the `aud` claim Mux expects for
/// it.
enum MuxPlaybackTokenType {
  /// An HLS stream: `https://stream.mux.com/{PLAYBACK_ID}.m3u8?token=…`.
  video('v', 'playback-token'),

  /// A thumbnail image from `image.mux.com`.
  thumbnail('t', 'thumbnail-token'),

  /// An animated GIF or WebP from `image.mux.com`.
  gif('g', 'gif-token'),

  /// A storyboard image or manifest from `image.mux.com`.
  storyboard('s', 'storyboard-token'),

  /// Engagement statistics for the playback id.
  stats('playback_id', 'stats-token'),

  /// A DRM licence request.
  drmLicense('d', 'drm-token');

  const MuxPlaybackTokenType(this.audience, this.tokenKey);

  /// The `aud` claim value.
  final String audience;

  /// The key this token is filed under by [signMuxPlaybackIdTokens] — the
  /// attribute name Mux Player expects, such as `playback-token`.
  final String tokenKey;
}

/// What a viewer-counts token addresses, and the `aud` claim Mux expects.
enum MuxViewerCountsType {
  /// A `video_id` as reported by Mux Data.
  video('video_id'),

  /// A Mux Video asset id.
  asset('asset_id'),

  /// A playback id.
  playback('playback_id'),

  /// A live stream id.
  liveStream('live_stream_id');

  const MuxViewerCountsType(this.audience);

  /// The `aud` claim value.
  final String audience;
}

const int _secondsPerMinute = 60;
const int _secondsPerHour = 3600;
const int _secondsPerDay = 86400;
const int _secondsPerWeek = 604800;
const int _secondsPerYear = 31536000;

final RegExp _timespan = RegExp(
  r'^(\d+)\s*(seconds?|secs?|s|minutes?|mins?|m|hours?|hrs?|h|days?|d|weeks?|w|years?|yrs?|y)$',
);

/// Converts an expiration into seconds the way `@mux/ts` does.
///
/// Accepts a whole number of seconds ([int]), a [Duration], or a [String]:
/// either a count with a unit — `60s`, `30 minutes`, `1h`, `7d`, `2w`, `1y`
/// (a year is 365 days) — or a bare number. Throws an [ArgumentError] for
/// anything else, with upstream's `Invalid time span` message.
num muxParseTimespan(Object expiration) {
  if (expiration is int) {
    return expiration;
  }
  if (expiration is Duration) {
    return expiration.inSeconds;
  }
  if (expiration is num) {
    return expiration;
  }
  if (expiration is! String) {
    throw ArgumentError.value(expiration, 'expiration', 'Invalid time span');
  }
  final trimmed = expiration.trim();
  final match = _timespan.firstMatch(trimmed);
  if (match != null) {
    final count = int.parse(match.group(1)!);
    return switch (match.group(2)![0]) {
      's' => count,
      'm' => count * _secondsPerMinute,
      'h' => count * _secondsPerHour,
      'd' => count * _secondsPerDay,
      'w' => count * _secondsPerWeek,
      _ => count * _secondsPerYear,
    };
  }
  final number = num.tryParse(trimmed);
  if (number != null) {
    return number;
  }
  throw ArgumentError('Invalid time span: $expiration');
}

/// Turns [privateKey] — a PEM, or the base64 encoding of a PEM, as Mux hands
/// signing keys out — into PEM text.
///
/// Throws an [ArgumentError] when neither form yields a `-----BEGIN` block.
String muxNormalizePrivateKey(String privateKey) {
  final trimmed = privateKey.trim();
  if (trimmed.startsWith('-----BEGIN')) {
    return trimmed;
  }
  try {
    final decoded =
        utf8.decode(base64.decode(base64.normalize(_stripWhitespace(trimmed))));
    final candidate = decoded.trim();
    if (candidate.startsWith('-----BEGIN')) {
      return candidate;
    }
  } on FormatException {
    // Not base64 either; fall through to the error below.
  }
  throw ArgumentError(
    'Specified signing key must be either a valid PKCS1 or PKCS8 PEM '
    'string or a base64 encoded PEM',
  );
}

String _stripWhitespace(String text) => text.replaceAll(RegExp(r'\s'), '');

/// Signs an RS256 JWT with exactly the claims `@mux/ts` produces:
/// `{...params, kid, sub, aud, exp}`, in that order, with no `iat`.
///
/// [now] is an injection seam for deterministic tests; `exp` is
/// `floor(now / 1000) + expiration` in seconds.
String muxSignJwt({
  required String subject,
  required String audience,
  required String keyId,
  required String privateKey,
  Object expiration = '7d',
  Map<String, Object?> params = const {},
  DateTime? now,
}) {
  final nowSeconds = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
  final claims = <String, Object?>{
    ...params,
    'kid': keyId,
    'sub': subject,
    'aud': audience,
    'exp': nowSeconds + muxParseTimespan(expiration),
  };
  return JWT(claims).sign(
    RSAPrivateKey(muxNormalizePrivateKey(privateKey)),
    algorithm: JWTAlgorithm.RS256,
    noIssueAt: true,
  );
}

/// Signs a token for [playbackId] of the given [type].
///
/// [params] are extra claims Mux reads for that type — `time`, `width`,
/// `height` for thumbnails; `start`, `end`, `fps`, `width` for GIFs — and
/// are placed before the standard claims, as upstream does. [expiration]
/// follows [muxParseTimespan]; the default is seven days.
String signMuxPlaybackId(
  String playbackId, {
  MuxPlaybackTokenType type = MuxPlaybackTokenType.video,
  Object expiration = '7d',
  Map<String, Object?> params = const {},
  required String keyId,
  required String privateKey,
  DateTime? now,
}) =>
    muxSignJwt(
      subject: playbackId,
      audience: type.audience,
      keyId: keyId,
      privateKey: privateKey,
      expiration: expiration,
      params: params,
      now: now,
    );

/// Signs one token per entry of [types] and files each under its
/// [MuxPlaybackTokenType.tokenKey] — the map Mux Player consumes.
///
/// [params] apply to every token; [paramsByType] adds or overrides claims for
/// one type, as `['thumbnail', { time: '2' }]` does upstream.
Map<String, String> signMuxPlaybackIdTokens(
  String playbackId, {
  required Iterable<MuxPlaybackTokenType> types,
  Object expiration = '7d',
  Map<String, Object?> params = const {},
  Map<MuxPlaybackTokenType, Map<String, Object?>> paramsByType = const {},
  required String keyId,
  required String privateKey,
  DateTime? now,
}) =>
    {
      for (final type in types)
        type.tokenKey: signMuxPlaybackId(
          playbackId,
          type: type,
          expiration: expiration,
          params: {...params, ...?paramsByType[type]},
          keyId: keyId,
          privateKey: privateKey,
          now: now,
        ),
    };

/// Signs a token for a DRM licence request for [playbackId] (`aud: d`).
String signMuxDrmLicense(
  String playbackId, {
  Object expiration = '7d',
  Map<String, Object?> params = const {},
  required String keyId,
  required String privateKey,
  DateTime? now,
}) =>
    signMuxPlaybackId(
      playbackId,
      type: MuxPlaybackTokenType.drmLicense,
      expiration: expiration,
      params: params,
      keyId: keyId,
      privateKey: privateKey,
      now: now,
    );

/// Signs a token for a signed viewer-counts request about [id], a
/// [MuxViewerCountsType.video] id by default.
String signMuxViewerCounts(
  String id, {
  MuxViewerCountsType type = MuxViewerCountsType.video,
  Object expiration = '7d',
  Map<String, Object?> params = const {},
  required String keyId,
  required String privateKey,
  DateTime? now,
}) =>
    muxSignJwt(
      subject: id,
      audience: type.audience,
      keyId: keyId,
      privateKey: privateKey,
      expiration: expiration,
      params: params,
      now: now,
    );

/// JWT signing scoped to a client, falling back to the signing key it was
/// configured with.
///
/// Every method is also available as a top-level function
/// ([signMuxPlaybackId], [signMuxPlaybackIdTokens], [signMuxDrmLicense],
/// [signMuxViewerCounts]) for callers that have a key but no client.
final class MuxJwt {
  /// Creates the helper with the client's default signing key.
  const MuxJwt({this.defaultKeyId, this.defaultPrivateKey});

  /// The signing key id used when a call passes none.
  final String? defaultKeyId;

  /// The private key, PEM or base64 PEM, used when a call passes none.
  final String? defaultPrivateKey;

  /// See [signMuxPlaybackId].
  String signPlaybackId(
    String playbackId, {
    MuxPlaybackTokenType type = MuxPlaybackTokenType.video,
    Object expiration = '7d',
    Map<String, Object?> params = const {},
    String? keyId,
    String? privateKey,
    DateTime? now,
  }) =>
      signMuxPlaybackId(
        playbackId,
        type: type,
        expiration: expiration,
        params: params,
        keyId: keyId ?? _requireKeyId(),
        privateKey: privateKey ?? _requirePrivateKey(),
        now: now,
      );

  /// See [signMuxPlaybackIdTokens].
  Map<String, String> signPlaybackIdTokens(
    String playbackId, {
    required Iterable<MuxPlaybackTokenType> types,
    Object expiration = '7d',
    Map<String, Object?> params = const {},
    Map<MuxPlaybackTokenType, Map<String, Object?>> paramsByType = const {},
    String? keyId,
    String? privateKey,
    DateTime? now,
  }) =>
      signMuxPlaybackIdTokens(
        playbackId,
        types: types,
        expiration: expiration,
        params: params,
        paramsByType: paramsByType,
        keyId: keyId ?? _requireKeyId(),
        privateKey: privateKey ?? _requirePrivateKey(),
        now: now,
      );

  /// See [signMuxDrmLicense].
  String signDrmLicense(
    String playbackId, {
    Object expiration = '7d',
    Map<String, Object?> params = const {},
    String? keyId,
    String? privateKey,
    DateTime? now,
  }) =>
      signMuxDrmLicense(
        playbackId,
        expiration: expiration,
        params: params,
        keyId: keyId ?? _requireKeyId(),
        privateKey: privateKey ?? _requirePrivateKey(),
        now: now,
      );

  /// See [signMuxViewerCounts].
  String signViewerCounts(
    String id, {
    MuxViewerCountsType type = MuxViewerCountsType.video,
    Object expiration = '7d',
    Map<String, Object?> params = const {},
    String? keyId,
    String? privateKey,
    DateTime? now,
  }) =>
      signMuxViewerCounts(
        id,
        type: type,
        expiration: expiration,
        params: params,
        keyId: keyId ?? _requireKeyId(),
        privateKey: privateKey ?? _requirePrivateKey(),
        now: now,
      );

  String _requireKeyId() {
    final keyId = defaultKeyId;
    if (keyId == null || keyId.isEmpty) {
      throw StateError(
        'Signing key required; pass keyId to the sign call or '
        'jwtSigningKeyId to MuxClient()',
      );
    }
    return keyId;
  }

  String _requirePrivateKey() {
    final privateKey = defaultPrivateKey;
    if (privateKey == null || privateKey.isEmpty) {
      throw StateError(
        'Private key required; pass privateKey to the sign call or '
        'jwtPrivateKey to MuxClient()',
      );
    }
    return privateKey;
  }
}
