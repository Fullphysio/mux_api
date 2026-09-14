import 'dart:io';

import 'package:mux_api/mux_api.dart';

/// Creates a direct upload, polls it, and signs a playback URL for the asset
/// it produced — the flow a backend runs behind a "upload a video" button.
///
/// Reads MUX_TOKEN_ID, MUX_TOKEN_SECRET, MUX_SIGNING_KEY_ID and
/// MUX_SIGNING_PRIVATE_KEY (PEM or base64 PEM) from the environment.
Future<void> main() async {
  final env = Platform.environment;
  final tokenId = env['MUX_TOKEN_ID'];
  final tokenSecret = env['MUX_TOKEN_SECRET'];
  if (tokenId == null || tokenSecret == null) {
    stderr.writeln('Set MUX_TOKEN_ID and MUX_TOKEN_SECRET to run the example.');
    exitCode = 64;
    return;
  }

  final mux = MuxClient(
    tokenId: tokenId,
    tokenSecret: tokenSecret,
    jwtSigningKeyId: env['MUX_SIGNING_KEY_ID'],
    jwtPrivateKey: env['MUX_SIGNING_PRIVATE_KEY'],
  );

  try {
    final upload = await mux.video.uploads.create(
      const UploadCreateParams(
        corsOrigin: '*',
        newAssetSettings: AssetOptions(
          playbackPolicies: [PlaybackPolicy.signed],
          videoQuality: AssetVideoQuality.plus,
        ),
        timeout: 3600,
      ),
    );
    stdout.writeln('Upload ${upload.id}: PUT your file to ${upload.url}');

    final current = await mux.video.uploads.retrieve(upload.id);
    stdout.writeln('Status: ${current.status?.value}');

    if (current.status == UploadStatus.assetCreated) {
      final assetEnvelope = await mux.requestJson(
        method: 'GET',
        path: '/video/v1/assets/${current.assetId}',
      );
      final asset = (assetEnvelope as Map<String, Object?>)
          .requireObject('data', 'Asset');
      final playbackIds = asset.optObjectList('playback_ids', (json) => json,
          objectName: 'Asset');
      final signed = playbackIds.firstWhere(
        (playback) => playback['policy'] == PlaybackPolicy.signed.value,
      );
      final token = mux.jwt.signPlaybackId(
        signed['id']! as String,
        expiration: '24h',
      );
      stdout.writeln(
        'Play: https://stream.mux.com/${signed['id']}.m3u8?token=$token',
      );
    } else {
      await mux.video.uploads.cancel(upload.id);
      stdout.writeln('Cancelled the unused upload.');
    }
  } on MuxApiException catch (error) {
    stderr.writeln('Mux answered ${error.statusCode}: ${error.messages}');
    exitCode = 1;
  } finally {
    mux.close();
  }
}
