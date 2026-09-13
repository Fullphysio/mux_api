import 'package:mux_api/src/core/crypto_util.dart';
import 'package:test/test.dart';

import '../_support/fixtures.dart';

void main() {
  test('reproduces the signature Mux computes for a delivery', () {
    final fixture = loadFixture('webhook_golden');
    final valid = casesOf(fixture).first;
    final body = mapOf(valid['input'])['body']! as String;
    expect(
      muxHmacSha256Hex('1800000000.$body', 'whsec_test_secret'),
      fixture['validSignature'],
    );
  });

  test('secure compare is exact and length-sensitive', () {
    expect(muxSecureCompare('abc', 'abc'), isTrue);
    expect(muxSecureCompare('abc', 'abd'), isFalse);
    expect(muxSecureCompare('abc', 'ab'), isFalse);
    expect(muxSecureCompare('', ''), isTrue);
  });
}
