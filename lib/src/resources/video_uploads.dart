import '../core/client.dart';
import '../core/json_reading.dart';
import '../core/open_enum.dart';
import '../core/page.dart';
import '../core/path_encoding.dart';
import 'asset_options.dart';

/// The state of a direct upload.
final class UploadStatus extends MuxOpenEnum {
  const UploadStatus._(super.value);

  /// Wraps a value this package does not know.
  const UploadStatus.unknown(super.value);

  /// Waiting for a file to be uploaded to the signed URL.
  static const waiting = UploadStatus._('waiting');

  /// The uploaded file was used to create an asset.
  static const assetCreated = UploadStatus._('asset_created');

  /// Asset creation failed; see [Upload.error].
  static const errored = UploadStatus._('errored');

  /// The upload was cancelled before a file arrived.
  static const cancelled = UploadStatus._('cancelled');

  /// No file arrived before the upload's timeout.
  static const timedOut = UploadStatus._('timed_out');

  /// The values known when this package was generated.
  static const values = [waiting, assetCreated, errored, cancelled, timedOut];

  /// Decodes a wire value, preserving one this package does not know.
  factory UploadStatus.fromWire(String value) => values.firstWhere(
        (known) => known.value == value,
        orElse: () => UploadStatus.unknown(value),
      );

  @override
  bool get isKnown => values.contains(this);
}

/// A direct upload: a short-lived signed URL a source file is uploaded to,
/// from which Mux creates an asset.
final class Upload {
  /// Creates an upload from already-decoded fields.
  const Upload({
    required this.id,
    this.status,
    this.url,
    this.corsOrigin,
    this.timeout,
    this.assetId,
    this.error,
    this.newAssetSettings,
    this.test,
    required this.raw,
  });

  /// Decodes the `data` object of an upload response.
  factory Upload.fromJson(Map<String, Object?> json) => Upload(
        id: json.requireString('id', 'Upload'),
        status: json.optEnum('status', UploadStatus.fromWire),
        url: json.optString('url'),
        corsOrigin: json.optString('cors_origin'),
        timeout: json.optInt('timeout'),
        assetId: json.optString('asset_id'),
        error: json.optNested('error', UploadError.fromJson),
        newAssetSettings:
            json.optNested('new_asset_settings', AssetOptions.fromJson),
        test: json.optBool('test'),
        raw: json,
      );

  /// Unique identifier for the upload.
  final String id;

  /// The upload's state.
  final UploadStatus? status;

  /// The URL to `PUT` the source file to. Present while the upload is
  /// [UploadStatus.waiting].
  final String? url;

  /// The origin the signed URL's CORS headers were issued for.
  final String? corsOrigin;

  /// How long, in seconds, the signed URL stays valid.
  final int? timeout;

  /// The created asset's id, once the upload is
  /// [UploadStatus.assetCreated].
  final String? assetId;

  /// Why asset creation failed, when [status] is [UploadStatus.errored].
  final UploadError? error;

  /// The settings the asset is created with.
  final AssetOptions? newAssetSettings;

  /// Whether this is a test upload, producing a test asset.
  final bool? test;

  /// The whole decoded object, for fields not promoted to a property.
  final Map<String, Object?> raw;
}

/// Why an upload failed to produce an asset.
final class UploadError {
  /// Creates an error from already-decoded fields.
  const UploadError({this.type, this.message});

  /// Decodes an upload's `error` object.
  factory UploadError.fromJson(Map<String, Object?> json) => UploadError(
        type: json.optString('type'),
        message: json.optString('message'),
      );

  /// A label for the kind of failure.
  final String? type;

  /// A human-readable explanation.
  final String? message;
}

/// Parameters for [VideoUploads.create].
final class UploadCreateParams {
  /// Creates the parameters. [corsOrigin] is required so the signed URL gets
  /// the right CORS headers for the browser that will upload to it; pass `*`
  /// for a non-browser uploader.
  const UploadCreateParams({
    required this.corsOrigin,
    this.newAssetSettings,
    this.timeout,
    this.test,
  });

  /// The origin the upload will be made from.
  final String corsOrigin;

  /// The settings for the asset created from the upload.
  final AssetOptions? newAssetSettings;

  /// How long, in seconds, the signed URL stays valid. Defaults to an hour.
  final int? timeout;

  /// Whether to create a test asset.
  final bool? test;

  /// Encodes the parameters for the request body, omitting absent fields.
  Map<String, Object?> toJson() => {
        'cors_origin': corsOrigin,
        if (newAssetSettings != null)
          'new_asset_settings': newAssetSettings!.toJson(),
        if (timeout != null) 'timeout': timeout,
        if (test != null) 'test': test,
      };
}

/// Direct upload operations: `client.video.uploads.*`.
final class VideoUploads {
  /// Creates the resource backed by [_client].
  const VideoUploads(this._client);

  final MuxClient _client;

  /// `POST /video/v1/uploads` — creates a direct upload and returns the
  /// signed URL to upload the source file to.
  Future<Upload> create(UploadCreateParams params) async {
    final envelope = await _client.requestJson(
      method: 'POST',
      path: '/video/v1/uploads',
      body: params.toJson(),
    );
    return _unwrap(envelope);
  }

  /// `GET /video/v1/uploads/{UPLOAD_ID}` — fetches one direct upload.
  Future<Upload> retrieve(String uploadId) async {
    final envelope = await _client.requestJson(
      method: 'GET',
      path: '/video/v1/uploads/${muxPathSegment(uploadId)}',
    );
    return _unwrap(envelope);
  }

  /// `PUT /video/v1/uploads/{UPLOAD_ID}/cancel` — cancels an upload that is
  /// still [UploadStatus.waiting], so no asset is created if a file arrives
  /// later.
  Future<Upload> cancel(String uploadId) async {
    final envelope = await _client.requestJson(
      method: 'PUT',
      path: '/video/v1/uploads/${muxPathSegment(uploadId)}/cancel',
    );
    return _unwrap(envelope);
  }

  /// `GET /video/v1/uploads` — lists direct uploads, page by page.
  Future<MuxBasePage<Upload>> list({int? limit, int? page}) => _list(
      {if (limit != null) 'limit': limit, if (page != null) 'page': page});

  Future<MuxBasePage<Upload>> _list(Map<String, Object?> query) async {
    final envelope = await _client.requestJson(
      method: 'GET',
      path: '/video/v1/uploads',
      query: query,
    );
    return MuxBasePage<Upload>.fromEnvelope(
      _envelope(envelope),
      itemFromJson: Upload.fromJson,
      query: query,
      fetchPage: _list,
      objectName: 'Upload',
    );
  }

  Upload _unwrap(Object? envelope) =>
      Upload.fromJson(_envelope(envelope).requireObject('data', 'Upload'));

  Map<String, Object?> _envelope(Object? envelope) =>
      (envelope as Map<String, Object?>?) ?? const {};
}
