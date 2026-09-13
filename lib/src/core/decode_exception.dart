/// Thrown when a Mux API response body cannot be decoded into a typed model.
///
/// Distinct from the `MuxException` hierarchy, which represents failures
/// *returned by* Mux or by the transport. A [MuxDecodeException] means Mux
/// answered successfully but the payload did not have the shape this package
/// expects of it. It is only ever raised for the few identifying fields a
/// payload cannot do without — `id`, and the `data` envelope around every
/// single-object response. Every other field is read tolerantly and decodes
/// to `null` when missing or malformed.
final class MuxDecodeException implements Exception {
  /// Creates a decode failure carrying [message] verbatim.
  MuxDecodeException(this.message);

  /// Creates the exception for [key] missing from — or `null` in — the JSON
  /// object for [objectName].
  MuxDecodeException.missingRequiredKey({
    required String objectName,
    required String key,
  }) : this('$objectName: required key "$key" is missing or null');

  /// Creates the exception for [key] present in the JSON object for
  /// [objectName] but holding a [value] of an unexpected type.
  MuxDecodeException.unexpectedType({
    required String objectName,
    required String key,
    required Object? value,
  }) : this(
          '$objectName: key "$key" has an unexpected type '
          '(${value.runtimeType}): ${_describe(value)}',
        );

  /// What went wrong, naming the object type and field involved.
  final String message;

  @override
  String toString() => 'MuxDecodeException: $message';
}

const int _maxDescriptionLength = 200;

String _describe(Object? value) {
  final text = '$value';
  return text.length > _maxDescriptionLength
      ? '${text.substring(0, _maxDescriptionLength)}…'
      : text;
}
