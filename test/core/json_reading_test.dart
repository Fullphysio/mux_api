import 'package:mux_api/src/core/decode_exception.dart';
import 'package:mux_api/src/core/json_reading.dart';
import 'package:test/test.dart';

void main() {
  const json = <String, Object?>{
    'string': 'text',
    'int': 3,
    'wholeDouble': 4.0,
    'fractional': 4.5,
    'bool': true,
    'nullValue': null,
    'object': {'id': 'nested'},
    'list': [1, 2.0, 'x', null],
    'objects': [
      {'id': 'a'},
      {'id': 'b'}
    ],
    'strings': ['a', 1, 'b'],
    'stringMap': {'k': 'v', 'n': 1, 'gone': null},
  };

  group('optional readers treat missing and null alike', () {
    test('optString', () {
      expect(json.optString('string'), 'text');
      expect(json.optString('int'), isNull);
      expect(json.optString('nullValue'), isNull);
      expect(json.optString('absent'), isNull);
    });

    test('optInt accepts whole doubles only', () {
      expect(json.optInt('int'), 3);
      expect(json.optInt('wholeDouble'), 4);
      expect(json.optInt('fractional'), isNull);
      expect(json.optInt('string'), isNull);
      expect(json.optInt('absent'), isNull);
    });

    test('optDouble widens ints', () {
      expect(json.optDouble('int'), 3.0);
      expect(json.optDouble('fractional'), 4.5);
      expect(json.optDouble('string'), isNull);
    });

    test('optBool', () {
      expect(json.optBool('bool'), isTrue);
      expect(json.optBool('string'), isNull);
    });

    test('optObject and optNested', () {
      expect(json.optObject('object'), {'id': 'nested'});
      expect(json.optObject('string'), isNull);
      expect(json.optNested('object', (o) => o['id']), 'nested');
      expect(json.optNested('absent', (o) => o['id']), isNull);
    });

    test('optList returns raw elements and never null', () {
      expect(json.optList('list', (e) => e), [1, 2.0, 'x', null]);
      expect(json.optList('absent', (e) => e), isEmpty);
      expect(json.optList('string', (e) => e), isEmpty);
    });

    test('optObjectList decodes objects and rejects other elements', () {
      expect(
        json.optObjectList('objects', (o) => o['id'], objectName: 'T'),
        ['a', 'b'],
      );
      expect(
        () => json.optObjectList('list', (o) => o, objectName: 'T'),
        throwsA(isA<MuxDecodeException>()),
      );
    });

    test('optStringList and optIntList drop foreign elements', () {
      expect(json.optStringList('strings'), ['a', 'b']);
      expect(json.optIntList('list'), [1, 2]);
      expect(json.optIntList('absent'), isEmpty);
    });

    test('optStringMap stringifies values and drops nulls', () {
      expect(json.optStringMap('stringMap'), {'k': 'v', 'n': '1'});
      expect(json.optStringMap('string'), isEmpty);
    });

    test('optEnum maps through fromWire', () {
      expect(json.optEnum('string', (w) => w.toUpperCase()), 'TEXT');
      expect(json.optEnum('int', (w) => w), isNull);
    });
  });

  group('required readers', () {
    test('requireString returns the value', () {
      expect(json.requireString('string', 'T'), 'text');
    });

    test('requireString names the object and key when missing', () {
      expect(
        () => json.requireString('absent', 'Upload'),
        throwsA(
          isA<MuxDecodeException>().having(
            (e) => e.message,
            'message',
            'Upload: required key "absent" is missing or null',
          ),
        ),
      );
    });

    test('requireString rejects a non-string', () {
      expect(
        () => json.requireString('int', 'Upload'),
        throwsA(isA<MuxDecodeException>()),
      );
    });

    test('requireObject returns the envelope and rejects anything else', () {
      expect(json.requireObject('object', 'T'), {'id': 'nested'});
      expect(
        () => json.requireObject('string', 'T'),
        throwsA(isA<MuxDecodeException>()),
      );
      expect(
        () => json.requireObject('absent', 'T'),
        throwsA(isA<MuxDecodeException>()),
      );
    });
  });
}
