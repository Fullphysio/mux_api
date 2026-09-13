import '../core/json_reading.dart';

part '../generated/webhook_events.g.dart';

/// Decodes one webhook event type from its JSON payload.
typedef MuxWebhookEventDecoder = MuxWebhookEvent Function(
  Map<String, Object?> json,
);

/// A webhook delivery from Mux, decoded.
///
/// Concrete subtypes are generated, one per event `type`, each narrowing
/// `data` to the resource the event describes. A `type` this package version
/// does not know decodes to [UnknownMuxWebhookEvent] rather than failing:
/// Mux's event catalogue is an open world.
sealed class MuxWebhookEvent {
  /// Creates an event from already-decoded fields.
  const MuxWebhookEvent({
    required this.id,
    required this.type,
    required this.createdAt,
    required this.object,
    required this.environment,
    required this.attempts,
    required this.raw,
  });

  /// Decodes [json], dispatching on its `type`.
  factory MuxWebhookEvent.fromJson(Map<String, Object?> json) {
    final type = json.requireString('type', 'MuxWebhookEvent');
    final decoder = _muxWebhookEventDecoders[type];
    return decoder == null
        ? UnknownMuxWebhookEvent.fromJson(json)
        : decoder(json);
  }

  /// Unique identifier for the event.
  final String id;

  /// The event type, such as `video.asset.ready`.
  final String type;

  /// When the event was created, as the ISO-8601 string Mux sent.
  final String? createdAt;

  /// The resource the event is about.
  final MuxWebhookObject? object;

  /// The Mux environment the event was raised in.
  final MuxWebhookEnvironment? environment;

  /// The delivery attempts Mux has made for this event.
  final List<MuxWebhookAttempt> attempts;

  /// The whole decoded payload, for fields not promoted to a property.
  final Map<String, Object?> raw;

  /// [createdAt] parsed, or `null` when absent or not an ISO-8601 instant.
  DateTime? get createdAtDate {
    final value = createdAt;
    return value == null ? null : DateTime.tryParse(value);
  }
}

/// An event whose `type` was not known when this package was generated.
final class UnknownMuxWebhookEvent extends MuxWebhookEvent {
  /// Creates an unknown event carrying its undecoded [data].
  const UnknownMuxWebhookEvent({
    required super.id,
    required super.type,
    required super.createdAt,
    required super.object,
    required super.environment,
    required super.attempts,
    required super.raw,
    required this.data,
  });

  /// Decodes the base fields of [json] and keeps `data` as-is.
  factory UnknownMuxWebhookEvent.fromJson(Map<String, Object?> json) =>
      UnknownMuxWebhookEvent(
        id: json.requireString('id', 'UnknownMuxWebhookEvent'),
        type: json.requireString('type', 'UnknownMuxWebhookEvent'),
        createdAt: json.optString('created_at'),
        object: json.optNested('object', MuxWebhookObject.fromJson),
        environment:
            json.optNested('environment', MuxWebhookEnvironment.fromJson),
        attempts: json.optObjectList(
          'attempts',
          MuxWebhookAttempt.fromJson,
          objectName: 'UnknownMuxWebhookEvent',
        ),
        raw: json,
        data: json.optObject('data') ?? const {},
      );

  /// The event payload, undecoded.
  final Map<String, Object?> data;
}

/// The resource a webhook event is about.
final class MuxWebhookObject {
  /// Creates the reference.
  const MuxWebhookObject({this.type, this.id});

  /// Decodes a `{"type": …, "id": …}` object.
  factory MuxWebhookObject.fromJson(Map<String, Object?> json) =>
      MuxWebhookObject(type: json.optString('type'), id: json.optString('id'));

  /// The resource type, such as `asset`.
  final String? type;

  /// The resource id.
  final String? id;
}

/// The Mux environment a webhook event was raised in.
final class MuxWebhookEnvironment {
  /// Creates the environment reference.
  const MuxWebhookEnvironment({this.name, this.id});

  /// Decodes a `{"name": …, "id": …}` object.
  factory MuxWebhookEnvironment.fromJson(Map<String, Object?> json) =>
      MuxWebhookEnvironment(
        name: json.optString('name'),
        id: json.optString('id'),
      );

  /// The environment name, such as `Production`.
  final String? name;

  /// The environment id.
  final String? id;
}

/// One attempt Mux made to deliver a webhook event.
final class MuxWebhookAttempt {
  /// Creates an attempt record.
  const MuxWebhookAttempt({
    this.id,
    this.address,
    this.createdAt,
    this.maxAttempts,
    this.responseBody,
    this.responseHeaders = const {},
    this.responseStatusCode,
    this.webhookId,
  });

  /// Decodes an entry of the event's `attempts` array.
  factory MuxWebhookAttempt.fromJson(Map<String, Object?> json) =>
      MuxWebhookAttempt(
        id: json.optString('id'),
        address: json.optString('address'),
        createdAt: json.optString('created_at'),
        maxAttempts: json.optInt('max_attempts'),
        responseBody: json.optString('response_body'),
        responseHeaders: json.optStringMap('response_headers'),
        responseStatusCode: json.optInt('response_status_code'),
        webhookId: json.optInt('webhook_id'),
      );

  /// Unique identifier for the attempt.
  final String? id;

  /// The URL the event was delivered to.
  final String? address;

  /// When the attempt was made, as the ISO-8601 string Mux sent.
  final String? createdAt;

  /// How many attempts Mux will make in total.
  final int? maxAttempts;

  /// The body your endpoint answered with.
  final String? responseBody;

  /// The headers your endpoint answered with.
  final Map<String, String> responseHeaders;

  /// The status code your endpoint answered with.
  final int? responseStatusCode;

  /// The id of the webhook configuration that produced the attempt.
  final int? webhookId;
}
