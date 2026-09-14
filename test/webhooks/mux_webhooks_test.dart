import 'package:mux_api/src/core/client.dart';
import 'package:mux_api/src/core/crypto_util.dart';
import 'package:mux_api/src/core/decode_exception.dart';
import 'package:mux_api/src/core/exceptions.dart';
import 'package:mux_api/src/generated/generated.dart';
import 'package:mux_api/src/webhooks/mux_webhook_event.dart';
import 'package:mux_api/src/webhooks/mux_webhooks.dart';
import 'package:test/test.dart';

import '../_support/fixtures.dart';

const String _secret = 'whsec_test_secret';

// Upstream's missing-secret message names its own env var and constructor;
// this package names MuxClient(webhookSecret:) instead.
String _dartMessageFor(String upstreamMessage) => upstreamMessage
        .startsWith('The webhook secret must')
    ? 'The webhook secret must either be set on MuxClient(webhookSecret: …) '
        'or passed to this call'
    : upstreamMessage;

String _sign(String body) => muxHmacSha256Hex('1800000000.$body', _secret);

void main() {
  final fixture = loadFixture('webhook_golden');
  final now = DateTime.fromMillisecondsSinceEpoch(
    fixture['fixedNowMs']! as int,
    isUtc: true,
  );
  final cases = casesOf(fixture);
  final validInput = mapOf(cases.first['input']);
  final validBody = validInput['body']! as String;
  final validHeader = validInput['header'] as String?;

  group('verification matches @mux/ts 15.1.0', () {
    for (final testCase in cases) {
      final input = mapOf(testCase['input']);
      final expected = mapOf(testCase['expected']);
      final verify = mapOf(expected['verify']);
      final unwrap = mapOf(expected['unwrap']);
      final webhooks =
          MuxWebhooks(defaultSecret: input['clientSecret'] as String?);
      final body = input['body']! as String;
      final header = input['header'] as String?;
      final secret = input['secret'] as String?;

      test(testCase['name']! as String, () {
        if (verify['threw'] == true) {
          final matcher = throwsA(
            isA<MuxWebhookSignatureException>().having(
              (e) => e.message,
              'message',
              _dartMessageFor(verify['message']! as String),
            ),
          );
          expect(
            () => webhooks.verify(body, header, secret: secret, now: now),
            matcher,
          );
          expect(
            () => webhooks.unwrap(body, header, secret: secret, now: now),
            matcher,
          );
          return;
        }
        expect(
          () => webhooks.verify(body, header, secret: secret, now: now),
          returnsNormally,
        );
        final event = webhooks.unwrap(body, header, secret: secret, now: now);
        expect(event, isA<VideoAssetReadyEvent>());
        expect(event.type, unwrap['type']);
        expect(event.id, unwrap['id']);
      });
    }
  });

  group('decoded event', () {
    final event = const MuxWebhooks(defaultSecret: _secret)
        .unwrap(validBody, validHeader, now: now);

    test('carries the base fields', () {
      expect(event.createdAt, '2027-01-15T08:00:00.000000Z');
      expect(event.createdAtDate, DateTime.utc(2027, 1, 15, 8));
      expect(event.object?.type, 'asset');
      expect(event.object?.id, 'asset_1');
      expect(event.environment?.name, 'Production');
      expect(event.environment?.id, 'env_1');
      expect(event.attempts, isEmpty);
      expect(event.raw['type'], 'video.asset.ready');
    });

    test('decodes the payload into the typed model', () {
      final typed = event as VideoAssetReadyEvent;
      expect(typed.data?.id, 'asset_1');
      expect(typed.data?.status?.value, 'ready');
      expect(typed.data?.playbackIds.single.policy, PlaybackPolicy.signed);
    });

    test('an unknown type keeps its payload', () {
      final body = validBody.replaceFirst(
          '"video.asset.ready"', '"video.asset.teleported"');
      final header = 't=1800000000,v1=${_sign(body)}';
      final unknown = const MuxWebhooks(defaultSecret: _secret)
          .unwrap(body, header, now: now);
      expect(unknown, isA<UnknownMuxWebhookEvent>());
      expect((unknown as UnknownMuxWebhookEvent).data['status'], 'ready');
    });
  });

  group('tolerance', () {
    test('is configurable', () {
      final old =
          cases.singleWhere((c) => c['name'] == 'too_old_by_one_second');
      final input = mapOf(old['input']);
      expect(
        () => const MuxWebhooks(defaultSecret: _secret).verify(
          input['body']! as String,
          input['header'] as String?,
          tolerance: const Duration(seconds: 301),
          now: now,
        ),
        returnsNormally,
      );
    });
  });

  group('unwrap body decoding', () {
    test('a verified body that is not JSON is a decode failure', () {
      const body = 'not json';
      expect(
        () => unwrapMuxWebhookEvent(
          body,
          't=1800000000,v1=${_sign(body)}',
          secret: _secret,
          now: now,
        ),
        throwsA(isA<MuxDecodeException>()),
      );
    });

    test('a verified JSON array is a decode failure', () {
      const body = '[1]';
      expect(
        () => unwrapMuxWebhookEvent(
          body,
          't=1800000000,v1=${_sign(body)}',
          secret: _secret,
          now: now,
        ),
        throwsA(isA<MuxDecodeException>()),
      );
    });
  });

  group('MuxWebhookAttempt', () {
    test('decodes every field tolerantly', () {
      final attempt = MuxWebhookAttempt.fromJson({
        'id': 'att_1',
        'address': 'https://example.com/hook',
        'created_at': '2027-01-15T08:00:01Z',
        'max_attempts': 30,
        'response_body': 'ok',
        'response_headers': {'content-type': 'text/plain', 'x-n': 1},
        'response_status_code': 200,
        'webhook_id': 42,
      });
      expect(attempt.id, 'att_1');
      expect(attempt.maxAttempts, 30);
      expect(
        attempt.responseHeaders,
        {'content-type': 'text/plain', 'x-n': '1'},
      );
      expect(attempt.responseStatusCode, 200);
      expect(attempt.webhookId, 42);
      expect(MuxWebhookAttempt.fromJson(const {}).responseHeaders, isEmpty);
    });
  });

  group('MuxClient wiring', () {
    test('the client secret is the default', () {
      final client = MuxClient(
        tokenId: 'id',
        tokenSecret: 'secret',
        webhookSecret: _secret,
      );
      expect(
        () => client.webhooks.verify(validBody, validHeader, now: now),
        returnsNormally,
      );
      client.close();
    });
  });
}
