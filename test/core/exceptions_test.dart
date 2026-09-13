import 'dart:convert';

import 'package:mux_api/src/core/exceptions.dart';
import 'package:test/test.dart';

import '../_support/fixtures.dart';

final Map<String, Matcher> _upstreamClass = {
  'BadRequestError': isA<MuxBadRequestException>(),
  'AuthenticationError': isA<MuxAuthenticationException>(),
  'PermissionDeniedError': isA<MuxPermissionDeniedException>(),
  'NotFoundError': isA<MuxNotFoundException>(),
  'ConflictError': isA<MuxConflictException>(),
  'UnprocessableEntityError': isA<MuxUnprocessableEntityException>(),
  'RateLimitError': isA<MuxRateLimitException>(),
  'InternalServerError': isA<MuxInternalServerException>(),
  'APIError': isA<MuxUnexpectedStatusException>(),
};

String _bodyText(Object? body) => body is String ? body : jsonEncode(body);

// Upstream exposes `null` for a body that is not JSON; this package keeps the
// raw text instead, so an HTML error page stays inspectable.
String? _rawText(Map<String, Object?> input) {
  final body = input['body'];
  return body is String && body.isNotEmpty ? body : null;
}

void main() {
  group('golden fixtures captured from @mux/ts 15.1.0', () {
    for (final testCase in casesOf(loadFixture('error_golden'))) {
      final input = mapOf(testCase['input']);
      final expected = mapOf(testCase['expected']);
      test(testCase['name']! as String, () {
        final exception = muxApiExceptionFromResponse(
          statusCode: input['statusCode']! as int,
          headers: mapOf(input['headers']).cast<String, String>(),
          body: _bodyText(input['body']),
        );
        expect(exception, _upstreamClass[expected['className']]!);
        expect(exception.message, expected['message']);
        expect(exception.statusCode, expected['status']);
        expect(exception.raw, equals(expected['error'] ?? _rawText(input)));
      });
    }
  });

  group('Mux error body', () {
    test('surfaces type and string messages', () {
      final exception = muxApiExceptionFromResponse(
        statusCode: 400,
        headers: const {},
        body: '{"error":{"type":"invalid_parameters","messages":["a","b"]}}',
      );
      expect(exception.errorType, 'invalid_parameters');
      expect(exception.messages, ['a', 'b']);
    });

    test('keeps only string messages, leaving the rest to raw', () {
      final exception = muxApiExceptionFromResponse(
        statusCode: 400,
        headers: const {},
        body: '{"error":{"type":"t","messages":["a",1,null,{"k":"v"}]}}',
      );
      expect(exception.messages, ['a']);
      expect(
        exception.raw,
        {
          'error': {
            'type': 't',
            'messages': [
              'a',
              1,
              null,
              {'k': 'v'}
            ]
          }
        },
      );
    });

    test('has no type or messages for a non-Mux body', () {
      final exception = muxApiExceptionFromResponse(
        statusCode: 502,
        headers: const {'content-type': 'text/html'},
        body: '<html></html>',
      );
      expect(exception.errorType, isNull);
      expect(exception.messages, isEmpty);
      expect(exception.raw, '<html></html>');
    });

    test('keeps the headers it was built from', () {
      final exception = muxApiExceptionFromResponse(
        statusCode: 429,
        headers: const {'retry-after': '3'},
        body: '',
      );
      expect(exception.headers, {'retry-after': '3'});
      expect(exception.raw, isNull);
    });
  });

  group('transport failures', () {
    test('a connection failure wraps its cause', () {
      final cause = Exception('socket closed');
      final exception = MuxConnectionException(cause: cause);
      expect(exception.message, 'Connection error.');
      expect(exception.cause, same(cause));
    });

    test('a timeout carries the upstream message', () {
      expect(const MuxTimeoutException().message, 'Request timed out.');
    });
  });

  group('webhook signature failures', () {
    test('name what went wrong', () {
      expect(
        const MuxWebhookSignatureException.missingHeader().message,
        'Could not find a mux-signature header',
      );
      expect(
        const MuxWebhookSignatureException.tooOld().message,
        'Webhook timestamp is too old',
      );
    });
  });

  group('sealed hierarchy', () {
    test('every concrete subtype is reachable from an exhaustive switch', () {
      String describe(MuxException exception) => switch (exception) {
            MuxBadRequestException() => '400',
            MuxAuthenticationException() => '401',
            MuxPermissionDeniedException() => '403',
            MuxNotFoundException() => '404',
            MuxConflictException() => '409',
            MuxUnprocessableEntityException() => '422',
            MuxRateLimitException() => '429',
            MuxInternalServerException() => '5xx',
            MuxUnexpectedStatusException() => 'other',
            MuxConnectionException() => 'connection',
            MuxTimeoutException() => 'timeout',
            MuxWebhookSignatureException() => 'webhook',
          };

      expect(describe(const MuxTimeoutException()), 'timeout');
      expect(
        describe(const MuxWebhookSignatureException.noMatch()),
        'webhook',
      );
    });

    test('toString is a one-line "ClassName: message" summary', () {
      expect(
        const MuxTimeoutException().toString(),
        'MuxTimeoutException: Request timed out.',
      );
    });
  });
}
