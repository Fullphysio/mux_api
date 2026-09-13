import 'package:mux_api/src/core/open_enum.dart';
import 'package:test/test.dart';

final class _Status extends MuxOpenEnum {
  const _Status._(super.value);

  const _Status.unknown(super.value);

  static const ready = _Status._('ready');
  static const errored = _Status._('errored');
  static const values = [ready, errored];

  factory _Status.fromWire(String value) => values.firstWhere(
        (known) => known.value == value,
        orElse: () => _Status.unknown(value),
      );

  @override
  bool get isKnown => values.contains(this);
}

final class _Other extends MuxOpenEnum {
  const _Other(super.value);

  @override
  bool get isKnown => true;
}

void main() {
  test('a known wire value resolves to its constant', () {
    expect(_Status.fromWire('ready'), same(_Status.ready));
    expect(_Status.fromWire('ready').isKnown, isTrue);
  });

  test('an unknown wire value is preserved, not rejected', () {
    final unknown = _Status.fromWire('paused');
    expect(unknown.value, 'paused');
    expect(unknown.isKnown, isFalse);
    expect(unknown, _Status.fromWire('paused'));
  });

  test('equality is by value within the same enum', () {
    expect(_Status.fromWire('ready'), _Status.ready);
    expect(_Status.ready.hashCode, _Status.fromWire('ready').hashCode);
    expect(_Status.ready, isNot(_Status.errored));
    expect(_Status.ready, isNot(const _Other('ready')));
  });

  test('toString names the enum and the wire value', () {
    expect(_Status.ready.toString(), '_Status(ready)');
  });
}
