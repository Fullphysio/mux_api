import 'package:mux_api/src/core/path_encoding.dart';
import 'package:test/test.dart';

import '../_support/fixtures.dart';

void main() {
  group('path segments match @mux/ts 15.1.0', () {
    for (final testCase in casesOf(loadFixture('path_encoding_golden'))) {
      final value = testCase['value']! as String;
      final url = testCase['url'] as String?;
      final error = testCase['error'];

      if (value.isEmpty) {
        test(
          'an empty segment is rejected (deliberate divergence: upstream '
          'sends a trailing slash, which addresses the collection)',
          () => expect(() => muxPathSegment(value), throwsArgumentError),
        );
        continue;
      }
      if (error != null) {
        test('rejects "$value" like upstream', () {
          expect(() => muxPathSegment(value), throwsArgumentError);
        });
        continue;
      }
      test('encodes "$value"', () {
        expect(
          'https://api.mux.com/video/v1/assets/${muxPathSegment(value)}',
          url,
        );
      });
    }
  });
}
