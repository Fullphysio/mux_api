import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:mux_api/src/core/retry_policy.dart';
import 'package:test/test.dart';

http.Response _response(int statusCode, {Map<String, String>? headers}) =>
    http.Response('', statusCode, headers: headers ?? const {});

void main() {
  group('muxShouldRetry', () {
    test('never retries once the retry budget is exhausted', () {
      expect(
        muxShouldRetry(attempt: 2, maxRetries: 2, response: _response(500)),
        isFalse,
      );
    });

    test('budget exhaustion wins even when x-should-retry says true', () {
      expect(
        muxShouldRetry(
          attempt: 2,
          maxRetries: 2,
          response: _response(200, headers: {'x-should-retry': 'true'}),
        ),
        isFalse,
      );
    });

    test('obeys x-should-retry: true on a status that would not retry', () {
      expect(
        muxShouldRetry(
          attempt: 0,
          maxRetries: 2,
          response: _response(400, headers: {'x-should-retry': 'true'}),
        ),
        isTrue,
      );
    });

    test('obeys x-should-retry: false on a status that would retry', () {
      expect(
        muxShouldRetry(
          attempt: 0,
          maxRetries: 2,
          response: _response(500, headers: {'x-should-retry': 'false'}),
        ),
        isFalse,
      );
    });

    for (final status in [408, 409, 429, 500, 503]) {
      test('retries a $status with no header', () {
        expect(
          muxShouldRetry(
            attempt: 0,
            maxRetries: 2,
            response: _response(status),
          ),
          isTrue,
        );
      });
    }

    for (final status in [400, 401, 403, 404, 422]) {
      test('does not retry a $status with no header', () {
        expect(
          muxShouldRetry(
            attempt: 0,
            maxRetries: 2,
            response: _response(status),
          ),
          isFalse,
        );
      });
    }

    test('retries when there is no response at all, subject to budget', () {
      expect(muxShouldRetry(attempt: 0, maxRetries: 2), isTrue);
      expect(muxShouldRetry(attempt: 2, maxRetries: 2), isFalse);
    });
  });

  group('muxRetryAfter', () {
    final now = DateTime.utc(2026, 9, 13, 12);

    test('is null without either header', () {
      expect(muxRetryAfter(const {}), isNull);
    });

    test('reads retry-after-ms as milliseconds', () {
      expect(
        muxRetryAfter(const {'retry-after-ms': '50'}),
        const Duration(milliseconds: 50),
      );
    });

    test('retry-after-ms beats retry-after', () {
      expect(
        muxRetryAfter(const {'retry-after-ms': '50', 'retry-after': '3'}),
        const Duration(milliseconds: 50),
      );
    });

    test('a zero retry-after-ms falls through to retry-after', () {
      expect(
        muxRetryAfter(const {'retry-after-ms': '0', 'retry-after': '2'}),
        const Duration(seconds: 2),
      );
    });

    test('a zero retry-after-ms alone means an immediate retry', () {
      expect(muxRetryAfter(const {'retry-after-ms': '0'}), Duration.zero);
    });

    test('an unparsable retry-after-ms is ignored', () {
      expect(
        muxRetryAfter(const {'retry-after-ms': 'abc', 'retry-after': '2'}),
        const Duration(seconds: 2),
      );
      expect(muxRetryAfter(const {'retry-after-ms': 'abc'}), isNull);
    });

    test('reads retry-after as delay seconds, fractional included', () {
      expect(
        muxRetryAfter(const {'retry-after': '1.5'}),
        const Duration(milliseconds: 1500),
      );
    });

    test('parses a leading numeric prefix like parseFloat', () {
      expect(
        muxRetryAfter(const {'retry-after': '5 seconds'}),
        const Duration(seconds: 5),
      );
    });

    test('reads retry-after as an HTTP-date relative to now', () {
      expect(
        muxRetryAfter(
          const {'retry-after': 'Sun, 13 Sep 2026 12:00:30 GMT'},
          now: now,
        ),
        const Duration(seconds: 30),
      );
    });

    test('an HTTP-date in the past is an immediate retry', () {
      expect(
        muxRetryAfter(
          const {'retry-after': 'Wed, 21 Oct 2015 07:28:00 GMT'},
          now: now,
        ),
        Duration.zero,
      );
    });

    test('an unparsable retry-after is an immediate retry, as upstream', () {
      expect(muxRetryAfter(const {'retry-after': 'soon'}), Duration.zero);
    });

    test(
        'an ISO-8601 instant is read as its leading number of seconds, '
        'exactly as parseFloat does upstream', () {
      expect(
        muxRetryAfter(const {'retry-after': '2026-09-13T12:01:00Z'}, now: now),
        const Duration(seconds: 2026),
      );
    });
  });

  group('muxRetryDelay', () {
    test('honours retryAfter without any cap', () {
      expect(
        muxRetryDelay(attempt: 0, retryAfter: const Duration(seconds: 120)),
        const Duration(seconds: 120),
      );
      expect(
        muxRetryDelay(attempt: 0, retryAfter: Duration.zero),
        Duration.zero,
      );
    });

    test('backs off exponentially from 500 ms and caps at 8 s', () {
      Duration delayFor(int attempt) =>
          muxRetryDelay(attempt: attempt, random: Random(1));

      final first = delayFor(0);
      final second = delayFor(1);
      final third = delayFor(2);
      final farOut = delayFor(10);

      expect(first, greaterThanOrEqualTo(const Duration(milliseconds: 375)));
      expect(first, lessThanOrEqualTo(const Duration(milliseconds: 500)));
      expect(second, greaterThan(first));
      expect(third, greaterThan(second));
      expect(farOut, lessThanOrEqualTo(const Duration(seconds: 8)));
      expect(farOut, greaterThanOrEqualTo(const Duration(seconds: 6)));
    });

    test('jitter only ever shortens the delay, by at most 25 %', () {
      final random = Random(7);
      final delays = List<Duration>.generate(
        200,
        (_) => muxRetryDelay(attempt: 3, random: random),
      );
      const unjittered = Duration(seconds: 4);
      for (final delay in delays) {
        expect(delay, greaterThanOrEqualTo(unjittered * 0.75));
        expect(delay, lessThanOrEqualTo(unjittered));
      }
      expect(delays.toSet().length, greaterThan(1));
    });
  });
}
