import 'package:meta/meta.dart';

/// Base class for the generated string enums of the Mux API.
///
/// Emitted as classes rather than Dart `enum`s on purpose: a native enum
/// cannot carry a value Mux adds after this package was generated without
/// discarding the wire string, and its compile-time exhaustiveness would turn
/// every spec bump into a break in unrelated call sites. Each generated
/// subtype declares its known values as `static const` instances, a `values`
/// list, and a `fromWire` factory that returns the matching constant or an
/// unknown instance preserving the raw string — never throwing.
///
/// Equality is by wire [value], so `AssetStatus.fromWire('ready') ==
/// AssetStatus.ready` holds and an unknown value compares equal to another
/// unknown instance carrying the same string.
@immutable
abstract base class MuxOpenEnum {
  /// Creates an instance wrapping the wire [value].
  const MuxOpenEnum(this.value);

  /// The raw string as sent on the wire, such as `asset_created`.
  final String value;

  /// Whether [value] was one of the values known when this package was
  /// generated.
  bool get isKnown;

  @override
  bool operator ==(Object other) =>
      other is MuxOpenEnum &&
      other.runtimeType == runtimeType &&
      other.value == value;

  @override
  int get hashCode => Object.hash(runtimeType, value);

  @override
  String toString() => '$runtimeType($value)';
}
