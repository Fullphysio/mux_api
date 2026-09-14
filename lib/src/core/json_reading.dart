import 'decode_exception.dart';

/// Tolerant readers for turning a decoded JSON object into typed Dart values,
/// used throughout the generated model code.
///
/// Every reader here treats a missing key and a `null` value identically and
/// returns `null` (or an empty collection) instead of throwing — regardless
/// of what Mux's OpenAPI specification says about the field being required.
/// A third-party API adding, removing or retyping a field is ordinary drift,
/// and tolerating it here is what keeps that drift from crashing every
/// caller. The two exceptions are [requireString], reserved for `id`, and
/// [requireObject], reserved for the `data` envelope: a payload missing
/// either is not a Mux object at all.
extension MuxJsonReading on Map<String, Object?> {
  /// Reads [key] as a [String], or `null` if absent, `null`, or not a string.
  String? optString(String key) {
    final value = this[key];
    return value is String ? value : null;
  }

  /// Reads [key] as an [int], or `null` if absent or `null`.
  ///
  /// A whole-valued [double] (`1.0` for `1`) is accepted and converted, since
  /// JSON has a single numeric type and the int/double split is a decoding
  /// artefact. A fractional or non-finite double returns `null`.
  int? optInt(String key) {
    final value = this[key];
    if (value is int) {
      return value;
    }
    if (value is double && value.isFinite && value == value.roundToDouble()) {
      return value.toInt();
    }
    return null;
  }

  /// Reads [key] as a [double], widening an [int], or `null` if absent.
  double? optDouble(String key) {
    final value = this[key];
    if (value is double) {
      return value;
    }
    if (value is int) {
      return value.toDouble();
    }
    return null;
  }

  /// Reads [key] as a [bool], or `null` if absent, `null`, or not a boolean.
  bool? optBool(String key) {
    final value = this[key];
    return value is bool ? value : null;
  }

  /// Reads [key] as a nested JSON object, or `null` if absent or not an
  /// object.
  Map<String, Object?>? optObject(String key) {
    final value = this[key];
    return value is Map<String, Object?> ? value : null;
  }

  /// Reads [key] as a nested JSON object and decodes it with [fromJson].
  ///
  /// Returns `null` without calling [fromJson] if [key] is absent, `null`,
  /// or not an object. An exception thrown by [fromJson] itself propagates.
  R? optNested<R>(String key, R Function(Map<String, Object?>) fromJson) {
    final object = optObject(key);
    return object == null ? null : fromJson(object);
  }

  /// Reads [key] as a JSON array, applying [fromElement] to each raw element.
  ///
  /// Returns an empty list — never `null` — if [key] is absent, `null`, or
  /// not an array.
  List<R> optList<R>(String key, R Function(Object? element) fromElement) {
    final value = this[key];
    if (value is! List<Object?>) {
      return <R>[];
    }
    return value.map(fromElement).toList(growable: false);
  }

  /// Reads [key] as an array of JSON objects, decoding each with [fromJson].
  ///
  /// Returns an empty list if [key] is absent, `null`, or not an array. An
  /// element that is not itself an object throws a [MuxDecodeException]
  /// naming [objectName]: unlike a missing field, a list whose items are not
  /// objects is a broken invariant of the list shape, not drift.
  List<R> optObjectList<R>(
    String key,
    R Function(Map<String, Object?>) fromJson, {
    required String objectName,
  }) =>
      optList<R>(key, (element) {
        if (element is! Map<String, Object?>) {
          throw MuxDecodeException.unexpectedType(
            objectName: objectName,
            key: '$key[]',
            value: element,
          );
        }
        return fromJson(element);
      });

  /// Reads [key] as an array of strings, dropping any element that is not a
  /// string. Returns an empty list if [key] is absent or not an array.
  List<String> optStringList(String key) =>
      optList<Object?>(key, (element) => element)
          .whereType<String>()
          .toList(growable: false);

  /// Reads [key] as an array of integers, applying the same widening as
  /// [optInt] to each element and dropping anything else.
  List<int> optIntList(String key) {
    final value = this[key];
    if (value is! List<Object?>) {
      return <int>[];
    }
    final result = <int>[];
    for (final element in value) {
      if (element is int) {
        result.add(element);
      } else if (element is double &&
          element.isFinite &&
          element == element.roundToDouble()) {
        result.add(element.toInt());
      }
    }
    return result;
  }

  /// Reads [key] as an array of doubles, widening ints like [optDouble] and
  /// dropping anything else. Returns an empty list if [key] is absent.
  List<double> optDoubleList(String key) {
    final value = this[key];
    if (value is! List<Object?>) {
      return <double>[];
    }
    return value
        .whereType<num>()
        .map((n) => n.toDouble())
        .toList(growable: false);
  }

  /// Reads [key] as an array of booleans, dropping anything else. Returns an
  /// empty list if [key] is absent.
  List<bool> optBoolList(String key) =>
      optList<Object?>(key, (element) => element)
          .whereType<bool>()
          .toList(growable: false);

  /// Reads [key] as a free-form JSON object of strings, the shape of Mux's
  /// `passthrough`-style and header maps.
  ///
  /// Returns an empty map — never `null` — if [key] is absent or not an
  /// object. A non-string value is stringified rather than dropped; a `null`
  /// value is dropped.
  Map<String, String> optStringMap(String key) {
    final value = this[key];
    if (value is! Map<String, Object?>) {
      return const <String, String>{};
    }
    final result = <String, String>{};
    for (final entry in value.entries) {
      final entryValue = entry.value;
      if (entryValue == null) {
        continue;
      }
      result[entry.key] =
          entryValue is String ? entryValue : entryValue.toString();
    }
    return result;
  }

  /// Reads [key] as a string and maps it through [fromWire], the decoder of
  /// a generated open enum. Returns `null` if [key] is absent or not a
  /// string; [fromWire] itself never throws for an unknown value.
  T? optEnum<T>(String key, T Function(String wire) fromWire) {
    final value = optString(key);
    return value == null ? null : fromWire(value);
  }

  /// Reads [key], which must be present with a non-null [String] value.
  ///
  /// Reserved for `id`: a payload without one is not usable as the type
  /// [objectName] at all, so this throws a [MuxDecodeException] naming
  /// [objectName] and [key] rather than returning `null` for a caller to
  /// dereference later with no context.
  String requireString(String key, String objectName) {
    final value = this[key];
    if (value == null) {
      throw MuxDecodeException.missingRequiredKey(
        objectName: objectName,
        key: key,
      );
    }
    if (value is! String) {
      throw MuxDecodeException.unexpectedType(
        objectName: objectName,
        key: key,
        value: value,
      );
    }
    return value;
  }

  /// Reads [key], which must be present with a JSON object value.
  ///
  /// Reserved for the `data` envelope every single-object Mux response is
  /// wrapped in: a 2xx response without it is not a Mux response.
  Map<String, Object?> requireObject(String key, String objectName) {
    final value = this[key];
    if (value == null) {
      throw MuxDecodeException.missingRequiredKey(
        objectName: objectName,
        key: key,
      );
    }
    if (value is! Map<String, Object?>) {
      throw MuxDecodeException.unexpectedType(
        objectName: objectName,
        key: key,
        value: value,
      );
    }
    return value;
  }
}
