import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mux_api/src/core/query_encoding.dart';
import 'package:mux_api/src/core/transport.dart';
import 'package:test/test.dart';

import '../_support/fixtures.dart';

void main() {
  group('requests match @mux/ts 15.1.0 byte for byte', () {
    for (final testCase in casesOf(loadFixture('query_encoding_golden'))) {
      final input = mapOf(testCase['input']);
      final expected = mapOf(testCase['request']);
      test(testCase['name']! as String, () async {
        http.Request? captured;
        final transport = MuxTransport(
          tokenId: 'capture-token-id',
          tokenSecret: 'capture-token-secret',
          timeout: const Duration(seconds: 5),
          maxRetries: 0,
          httpClient: MockClient((request) async {
            captured = request;
            return http.Response('{}', 200);
          }),
        );

        await transport.send(
          method: input['method']! as String,
          path: input['path']! as String,
          query: input['query'] as Map<String, Object?>?,
          body: input['body'],
          host: MuxHost.values.byName(input['host']! as String),
          accept: expected['accept']! as String,
        );

        final request = captured!;
        expect(request.url.toString(), expected['url']);
        expect(request.method, expected['method']);
        expect(request.headers['content-type'], expected['contentType']);
        expect(request.headers['accept'], expected['accept']);
        expect(request.headers['authorization'], expected['authorization']);
        expect(request.body.isEmpty ? null : request.body, expected['body']);
      });
    }
  });

  group('muxQueryEncode', () {
    test('a null value is an empty value, not an absent key', () {
      expect(muxQueryEncode({'a': null}), 'a=');
    });

    test('an empty list contributes nothing', () {
      expect(muxQueryEncode({'a': <Object?>[], 'b': 1}), 'b=1');
    });

    test('a nested map uses bracket keys', () {
      expect(
          muxQueryEncode({
            'a': {'b': 'c'}
          }),
          'a%5Bb%5D=c');
    });

    test('a list of maps combines both bracket forms', () {
      expect(
        muxQueryEncode({
          'a': [
            {'b': 1}
          ]
        }),
        'a%5B%5D%5Bb%5D=1',
      );
    });

    test('a DateTime is written like Date.prototype.toISOString', () {
      expect(
        muxQueryEncode({'at': DateTime.utc(2020, 1, 2, 3, 4, 5, 6, 789)}),
        'at=2020-01-02T03%3A04%3A05.006Z',
      );
    });

    test('a whole-valued double is written as an integer', () {
      expect(
          muxQueryEncode({'a': 3.0, 'b': 2.5, 'c': true}), 'a=3&b=2.5&c=true');
    });

    test('keeps insertion order', () {
      expect(muxQueryEncode({'z': 1, 'a': 2}), 'z=1&a=2');
    });

    test('an empty map is an empty string', () {
      expect(muxQueryEncode({}), '');
    });
  });
}
