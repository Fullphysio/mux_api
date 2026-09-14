import '../ir/model.dart';

String dartType(IrType type) => switch (type) {
      IrString() => 'String',
      IrInt() => 'int',
      IrDouble() => 'double',
      IrBool() => 'bool',
      IrJson() => 'Object?',
      IrStringMap() => 'Map<String, String>',
      IrJsonMap() => 'Map<String, Object?>',
      IrList(:final element) => 'List<${dartType(element)}>',
      IrRef(:final className) => className,
      IrEnumRef(:final enumName) => enumName,
      IrUnionRef(:final unionName) => unionName,
    };

bool _defaultsToEmpty(IrType type) => type is IrList || type is IrStringMap;

String fieldDartType(FieldIr field, ClassKind kind) {
  final base = dartType(field.type);
  if (field.required) return base;
  if (kind == ClassKind.model && _defaultsToEmpty(field.type)) return base;
  return '$base?';
}

bool fieldIsNullable(FieldIr field, ClassKind kind) =>
    !field.required &&
    !(kind == ClassKind.model && _defaultsToEmpty(field.type));

Set<String> referencedTypeNames(IrType type) => switch (type) {
      IrList(:final element) => referencedTypeNames(element),
      IrRef(:final className) => {className},
      IrEnumRef(:final enumName) => {enumName},
      IrUnionRef(:final unionName) => {unionName},
      _ => const {},
    };

String decodeField(FieldIr field, String owner, ClassKind kind) {
  final key = dartStringLiteral(field.wireName);
  if (field.isId) {
    return 'json.requireString($key, ${dartStringLiteral(owner)})';
  }
  final expression = _decodeValue(field.type, key, owner);
  final missing =
      'throw MuxDecodeException.missingRequiredKey(objectName: ${dartStringLiteral(owner)}, key: $key)';
  if (field.required && field.type is! IrJson) {
    if (field.type is IrString) {
      return 'json.requireString($key, ${dartStringLiteral(owner)})';
    }
    if (_defaultsToEmpty(field.type)) {
      return 'json.containsKey($key) ? $expression : ($missing)';
    }
    return '$expression ?? ($missing)';
  }
  if (kind == ClassKind.params && _defaultsToEmpty(field.type)) {
    return 'json.containsKey($key) ? $expression : null';
  }
  return expression;
}

bool needsDecodeException(ClassIr c) => c.fields.any((field) =>
    field.required &&
    !field.isId &&
    field.type is! IrJson &&
    field.type is! IrString);

String _decodeValue(IrType type, String key, String owner) => switch (type) {
      IrString() => 'json.optString($key)',
      IrInt() => 'json.optInt($key)',
      IrDouble() => 'json.optDouble($key)',
      IrBool() => 'json.optBool($key)',
      IrJson() => 'json[$key]',
      IrStringMap() => 'json.optStringMap($key)',
      IrJsonMap() => 'json.optObject($key)',
      IrRef(:final className) => 'json.optNested($key, $className.fromJson)',
      IrUnionRef(:final unionName) =>
        'json.optNested($key, $unionName.fromJson)',
      IrEnumRef(:final enumName) => 'json.optEnum($key, $enumName.fromWire)',
      IrList(:final element) => _decodeList(element, key, owner),
    };

String _decodeList(IrType element, String key, String owner) =>
    switch (element) {
      IrString() => 'json.optStringList($key)',
      IrInt() => 'json.optIntList($key)',
      IrDouble() => 'json.optDoubleList($key)',
      IrBool() => 'json.optBoolList($key)',
      IrJson() => 'json.optList($key, (element) => element)',
      IrJsonMap() =>
        'json.optList($key, (element) => element is Map<String, Object?> ? element : <String, Object?>{})',
      IrStringMap() =>
        'json.optList($key, (element) => element is Map<String, Object?> ? element.map((k, v) => MapEntry(k, v.toString())) : <String, String>{})',
      IrRef(:final className) =>
        'json.optObjectList($key, $className.fromJson, objectName: ${dartStringLiteral(owner)})',
      IrUnionRef(:final unionName) =>
        'json.optObjectList($key, $unionName.fromJson, objectName: ${dartStringLiteral(owner)})',
      IrEnumRef(:final enumName) =>
        'json.optStringList($key).map($enumName.fromWire).toList(growable: false)',
      IrList(element: IrJson()) =>
        'json.optList($key, (element) => element is List<Object?> ? element : const <Object?>[])',
      IrList(element: IrString()) =>
        'json.optList($key, (element) => element is List<Object?> ? element.whereType<String>().toList(growable: false) : const <String>[])',
      IrList(element: IrInt()) =>
        'json.optList($key, (element) => element is List<Object?> ? element.whereType<int>().toList(growable: false) : const <int>[])',
      IrList(element: IrDouble()) =>
        'json.optList($key, (element) => element is List<Object?> ? element.whereType<num>().map((n) => n.toDouble()).toList(growable: false) : const <double>[])',
      IrList() => throw StateError(
          'nested list of ${dartType(element)} is not supported by the generator'),
    };

String encodeValue(IrType type, String expression) => switch (type) {
      IrRef() || IrUnionRef() => '$expression.toJson()',
      IrEnumRef() => '$expression.value',
      IrList(element: IrRef() || IrUnionRef()) =>
        '[for (final item in $expression) item.toJson()]',
      IrList(element: IrEnumRef()) =>
        '[for (final item in $expression) item.value]',
      _ => expression,
    };

String dartStringLiteral(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$')
      .replaceAll('\n', r'\n');
  return "'$escaped'";
}
