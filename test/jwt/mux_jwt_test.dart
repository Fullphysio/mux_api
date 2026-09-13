import 'dart:convert';
import 'dart:io';

import 'package:mux_api/src/jwt/mux_jwt.dart';
import 'package:test/test.dart';

import '../_support/fixtures.dart';

final String _pkcs1 =
    File('test/fixtures/test_keys/rsa_test_key_pkcs1.pem').readAsStringSync();
final String _pkcs8 =
    File('test/fixtures/test_keys/rsa_test_key_pkcs8.pem').readAsStringSync();

String? _privateKeyFor(Object? form) => switch (form) {
      'base64' => base64Encode(utf8.encode(_pkcs1)),
      'pkcs1' => _pkcs1,
      'pkcs8' => _pkcs8,
      'garbage' => 'definitely not a key',
      null => null,
      _ => throw StateError('unknown key form $form'),
    };

const Map<String, MuxPlaybackTokenType> _playbackTypes = {
  'video': MuxPlaybackTokenType.video,
  'thumbnail': MuxPlaybackTokenType.thumbnail,
  'gif': MuxPlaybackTokenType.gif,
  'storyboard': MuxPlaybackTokenType.storyboard,
  'stats': MuxPlaybackTokenType.stats,
  'drm_license': MuxPlaybackTokenType.drmLicense,
};

const Map<String, MuxViewerCountsType> _viewerTypes = {
  'video': MuxViewerCountsType.video,
  'asset': MuxViewerCountsType.asset,
  'playback': MuxViewerCountsType.playback,
  'live_stream': MuxViewerCountsType.liveStream,
};

Object _replay(Map<String, Object?> input, DateTime now) {
  final jwt = MuxJwt(
    defaultKeyId: input['keyId'] as String?,
    defaultPrivateKey: _privateKeyFor(input['privateKey']),
  );
  final subject = input['subject']! as String;
  final params = (input['params'] as Map<String, Object?>?) ?? const {};
  final expiration = input['expiration'] ?? '7d';
  switch (input['method']) {
    case 'signPlaybackId':
      final types = input['types'] as List<Object?>?;
      if (types != null) {
        final byType = (input['paramsByType'] as Map<String, Object?>?) ??
            const <String, Object?>{};
        return jwt.signPlaybackIdTokens(
          subject,
          types: types.map((type) => _playbackTypes[type]!),
          params: params,
          paramsByType: {
            for (final entry in byType.entries)
              _playbackTypes[entry.key]!: mapOf(entry.value),
          },
          expiration: expiration,
          now: now,
        );
      }
      return jwt.signPlaybackId(
        subject,
        type: _playbackTypes[input['type'] ?? 'video']!,
        params: params,
        expiration: expiration,
        now: now,
      );
    case 'signDrmLicense':
      return jwt.signDrmLicense(
        subject,
        params: params,
        expiration: expiration,
        now: now,
      );
    case 'signViewerCounts':
      return jwt.signViewerCounts(
        subject,
        type: _viewerTypes[input['type'] ?? 'video']!,
        params: params,
        expiration: expiration,
        now: now,
      );
    default:
      throw StateError('unknown method ${input['method']}');
  }
}

Map<String, Object?> _decodeSegment(String segment) =>
    jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(segment))))
        as Map<String, Object?>;

String _dartMessageFor(String upstreamMessage) {
  if (upstreamMessage.startsWith('Signing key required')) {
    return 'Signing key required';
  }
  if (upstreamMessage.startsWith('Private key required')) {
    return 'Private key required';
  }
  if (upstreamMessage.startsWith('Specified signing key')) {
    return 'Specified signing key must be either a valid PKCS1 or PKCS8 PEM';
  }
  return upstreamMessage;
}

void main() {
  final fixture = loadFixture('jwt_golden');
  final now = DateTime.fromMillisecondsSinceEpoch(
    fixture['fixedNowMs']! as int,
    isUtc: true,
  );

  group('tokens match @mux/ts 15.1.0 byte for byte', () {
    for (final testCase in casesOf(fixture)) {
      final input = mapOf(testCase['input']);
      final expected = mapOf(testCase['expected']);
      final error = expected['error'] as Map<String, Object?>?;

      test(testCase['name']! as String, () {
        if (error != null) {
          final message = _dartMessageFor(error['message']! as String);
          expect(
            () => _replay(input, now),
            throwsA(
              predicate<Object>(
                (e) =>
                    (e is ArgumentError || e is StateError) &&
                    e.toString().contains(message),
                'an ArgumentError or StateError mentioning "$message"',
              ),
            ),
          );
          return;
        }
        final result = _replay(input, now);
        if (result is String) {
          expect(result, expected['token']);
          final segments = result.split('.');
          expect(_decodeSegment(segments[0]), expected['header']);
          expect(_decodeSegment(segments[1]), expected['payload']);
        } else {
          final tokens = mapOf(expected['tokens']);
          final actual = result as Map<String, String>;
          expect(actual.keys.toList(), tokens.keys.toList());
          for (final entry in tokens.entries) {
            expect(actual[entry.key], mapOf(entry.value)['token']);
          }
        }
      });
    }
  });

  group('muxParseTimespan', () {
    test('accepts seconds, durations and unit strings', () {
      expect(muxParseTimespan(60), 60);
      expect(muxParseTimespan(const Duration(hours: 2)), 7200);
      expect(muxParseTimespan('45s'), 45);
      expect(muxParseTimespan('2 mins'), 120);
      expect(muxParseTimespan('3 hrs'), 10800);
      expect(muxParseTimespan('1 day'), 86400);
      expect(muxParseTimespan('2w'), 1209600);
      expect(muxParseTimespan('1 year'), 31536000);
      expect(muxParseTimespan(' 7d '), 604800);
    });

    test('rejects anything else with the upstream message', () {
      expect(
        () => muxParseTimespan('soon'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'Invalid time span: soon',
          ),
        ),
      );
      expect(() => muxParseTimespan(true), throwsArgumentError);
    });
  });

  group('muxNormalizePrivateKey', () {
    test('accepts a PEM as is, trimmed', () {
      expect(muxNormalizePrivateKey('\n$_pkcs1\n'), _pkcs1.trim());
    });

    test('accepts a base64 PEM, even with whitespace or missing padding', () {
      final encoded = base64Encode(utf8.encode(_pkcs8));
      final wrapped = encoded.replaceAllMapped(
        RegExp('.{64}'),
        (match) => '${match.group(0)}\n',
      );
      expect(muxNormalizePrivateKey(wrapped), _pkcs8.trim());
      expect(
        muxNormalizePrivateKey(encoded.replaceAll('=', '')),
        _pkcs8.trim(),
      );
    });

    test('rejects text that is neither', () {
      expect(() => muxNormalizePrivateKey('nope'), throwsArgumentError);
      expect(
        () => muxNormalizePrivateKey(base64Encode(utf8.encode('nope'))),
        throwsArgumentError,
      );
    });
  });

  group('MuxJwt defaults', () {
    test('a call-site key wins over the client default', () {
      const jwt = MuxJwt(defaultKeyId: 'default-key');
      final token = jwt.signPlaybackId(
        'pb',
        keyId: 'call-key',
        privateKey: _pkcs1,
        now: now,
      );
      expect(_decodeSegment(token.split('.')[1])['kid'], 'call-key');
    });
  });
}
