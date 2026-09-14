import 'decode_exception.dart';

/// Asserts that a decoded response [body] is a JSON object and returns it.
///
/// Every JSON endpoint of the Mux API answers with an object — either the
/// `{"data": …}` envelope or a full response document — so anything else on
/// a 2xx is not drift but a payload this package cannot interpret as
/// [objectName], and it fails loudly.
Map<String, Object?> muxEnvelope(Object? body, String objectName) {
  if (body is Map<String, Object?>) {
    return body;
  }
  throw MuxDecodeException(
    '$objectName: expected a JSON object response, got ${body.runtimeType}',
  );
}
