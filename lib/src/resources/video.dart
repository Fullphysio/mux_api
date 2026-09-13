import '../core/client.dart';
import 'video_uploads.dart';

/// Mux Video resources: `client.video.*`.
final class MuxVideo {
  /// Creates the namespace backed by [_client].
  const MuxVideo(this._client);

  final MuxClient _client;

  /// Direct upload operations.
  VideoUploads get uploads => VideoUploads(_client);
}
