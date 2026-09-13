import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mux_api/src/core/decode_exception.dart';
import 'package:mux_api/src/core/exceptions.dart';
import 'package:mux_api/src/core/transport.dart';
import 'package:test/test.dart';

import '../_support/fixtures.dart';

final Map<String, Matcher> _upstreamClass = {
  'InternalServerError': isA<MuxInternalServerException>(),
  'BadRequestError': isA<MuxBadRequestException>(),
  'NotFoundError': isA<MuxNotFoundException>(),
  'APIConnectionError': isA<MuxConnectionException>(),
};

MuxTransport _transport(
  http.Client client, {
  int maxRetries = 0,
  Duration timeout = const Duration(seconds: 5),
  Uri? baseUrl,
  List<Duration>? delays,
}) =>
    MuxTransport(
      tokenId: 'id',
      tokenSecret: 'secret',
      httpClient: client,
      timeout: timeout,
      maxRetries: maxRetries,
      baseUrl: baseUrl,
      random: Random(1),
      sleep: (delay) async => delays?.add(delay),
    );

final class _TrackingClient extends http.BaseClient {
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);

  @override
  void close() {
    closed = true;
  }
}

void main() {
  group('retry behaviour matches @mux/ts 15.1.0', () {
    for (final testCase in casesOf(loadFixture('retry_golden'))) {
      final name = testCase['name']! as String;
      final responses = (testCase['responses']! as List<Object?>)
          .cast<Map<String, Object?>>();
      final expected = mapOf(testCase['expected']);
      test(name, () async {
        var calls = 0;
        final delays = <Duration>[];
        final client = MockClient((request) async {
          final spec = responses[min(calls, responses.length - 1)];
          calls++;
          if (spec['throws'] == true) {
            throw http.ClientException('fetch failed', request.url);
          }
          final status = spec['status']! as int;
          final body = status == 200
              ? '{"data":{"id":"asset1"}}'
              : '{"error":{"type":"t","messages":["m"]}}';
          return http.Response(
            body,
            status,
            headers: {
              'content-type': 'application/json',
              ...mapOf(spec['headers']).cast<String, String>(),
            },
          );
        });
        final transport = _transport(
          client,
          maxRetries: name == 'max_retries_zero' ? 0 : 2,
          delays: delays,
        );

        Future<Object?> run() => transport.requestJson(
              method: 'GET',
              path: '/video/v1/assets/asset1',
            );

        if (expected['threw'] == true) {
          await expectLater(
            run(),
            throwsA(
              allOf(
                _upstreamClass[expected['className']]!,
                isA<MuxException>().having(
                  (e) => e.message,
                  'message',
                  expected['message'],
                ),
              ),
            ),
          );
        } else {
          final result = mapOf(await run());
          expect(mapOf(result['data'])['id'], expected['resultId']);
        }
        expect(calls, testCase['attempts']);
        expect(delays.length, calls - 1);

        switch (name) {
          case 'retry_after_ms_beats_retry_after':
            expect(delays, [const Duration(milliseconds: 50)]);
          case 'retry_after_seconds_honoured':
            expect(delays, [const Duration(seconds: 1)]);
          case 'retry_after_http_date_in_past':
          case 'retry_after_unparsable_retries_immediately':
            expect(delays, [Duration.zero]);
          case 'connection_error_then_success':
            expect(delays.single,
                greaterThanOrEqualTo(const Duration(milliseconds: 375)));
            expect(delays.single,
                lessThanOrEqualTo(const Duration(milliseconds: 500)));
          case 'connection_error_exhausts_retries':
            expect(delays[1],
                greaterThanOrEqualTo(const Duration(milliseconds: 750)));
            expect(delays[1], lessThanOrEqualTo(const Duration(seconds: 1)));
          default:
            for (final delay in delays) {
              expect(delay, const Duration(milliseconds: 1));
            }
        }
      });
    }
  });

  group('timeouts', () {
    test('an attempt exceeding the timeout throws MuxTimeoutException', () {
      final client = MockClient((_) => Completer<http.Response>().future);
      final transport =
          _transport(client, timeout: const Duration(milliseconds: 20));
      expect(
        transport.requestJson(method: 'GET', path: '/video/v1/assets'),
        throwsA(isA<MuxTimeoutException>()),
      );
    });
  });

  group('response decoding', () {
    test('an empty 2xx body decodes to null', () async {
      final transport =
          _transport(MockClient((_) async => http.Response('', 204)));
      expect(
        await transport.requestJson(
            method: 'DELETE', path: '/x', accept: '*/*'),
        isNull,
      );
    });

    test('a non-JSON 2xx body is a decode failure, not silently null', () {
      final transport = _transport(
        MockClient((_) async => http.Response('<html>', 200)),
      );
      expect(
        transport.requestJson(method: 'GET', path: '/x'),
        throwsA(isA<MuxDecodeException>()),
      );
    });

    test('requestText decodes the body as UTF-8', () async {
      final transport = _transport(MockClient(
        (_) async => http.Response.bytes(utf8.encode('WEBVTT é'), 200),
      ));
      expect(
        await transport.requestText(method: 'GET', path: '/x'),
        'WEBVTT é',
      );
    });

    test('requestBytes returns the raw body', () async {
      final transport = _transport(
        MockClient((_) async => http.Response.bytes([1, 2, 3], 200)),
      );
      expect(
          await transport.requestBytes(method: 'GET', path: '/x'), [1, 2, 3]);
    });
  });

  group('hosts', () {
    test('each MuxHost has its own origin by default', () async {
      final urls = <String>[];
      final transport = _transport(MockClient((request) async {
        urls.add(request.url.toString());
        return http.Response('{}', 200);
      }));
      await transport.requestJson(method: 'GET', path: '/video/v1/assets');
      await transport.requestBytes(
        method: 'GET',
        path: '/pid/thumbnail.png',
        host: MuxHost.image,
      );
      await transport.requestBytes(
        method: 'GET',
        path: '/pid.m3u8',
        host: MuxHost.stream,
      );
      expect(urls, [
        'https://api.mux.com/video/v1/assets',
        'https://image.mux.com/pid/thumbnail.png',
        'https://stream.mux.com/pid.m3u8',
      ]);
    });

    test('an explicit baseUrl overrides every host, as upstream', () async {
      final urls = <String>[];
      final transport = _transport(
        MockClient((request) async {
          urls.add(request.url.toString());
          return http.Response('{}', 200);
        }),
        baseUrl: Uri.parse('http://127.0.0.1:4010/prefix/'),
      );
      await transport.requestJson(method: 'GET', path: '/video/v1/assets');
      await transport.requestBytes(
        method: 'GET',
        path: '/pid/thumbnail.png',
        host: MuxHost.image,
      );
      expect(urls, [
        'http://127.0.0.1:4010/prefix/video/v1/assets',
        'http://127.0.0.1:4010/prefix/pid/thumbnail.png',
      ]);
    });
  });

  group('close', () {
    test('does not close a caller-supplied client', () {
      final client = _TrackingClient();
      _transport(client).close();
      expect(client.closed, isFalse);
    });

    test('closes the client it created', () {
      final transport = MuxTransport(
        tokenId: 'id',
        tokenSecret: 'secret',
        timeout: const Duration(seconds: 1),
        maxRetries: 0,
      );
      expect(transport.close, returnsNormally);
    });
  });
}
