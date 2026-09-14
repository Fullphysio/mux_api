@Tags(['integration'])
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mux_api/mux_api.dart';
import 'package:test/test.dart';

/// Read-mostly smoke test against the live Mux API.
///
/// Everything here is safe to run against any environment: it lists and
/// retrieves what already exists, creates one direct upload and cancels it
/// before anything is uploaded, and signs playback tokens for an existing
/// signed asset. Assertions are structural — nothing depends on how many
/// assets the environment holds.
void main() {
  final env = Platform.environment;
  final tokenId = env['MUX_TEST_TOKEN_ID'] ?? '';
  final tokenSecret = env['MUX_TEST_TOKEN_SECRET'] ?? '';
  final signingKeyId = env['MUX_TEST_SIGNING_KEY_ID'] ?? '';
  final signingPrivateKey = env['MUX_TEST_SIGNING_PRIVATE_KEY'] ?? '';
  final canSign = signingKeyId.isNotEmpty && signingPrivateKey.isNotEmpty;

  late MuxClient mux;
  late http.Client web;

  setUpAll(() {
    if (tokenId.isEmpty || tokenSecret.isEmpty) {
      fail(
        'MUX_TEST_TOKEN_ID and MUX_TEST_TOKEN_SECRET are empty; export a Mux '
        'access token pair to run the integration tier.',
      );
    }
    mux = MuxClient(
      tokenId: tokenId,
      tokenSecret: tokenSecret,
      jwtSigningKeyId: canSign ? signingKeyId : null,
      jwtPrivateKey: canSign ? signingPrivateKey : null,
    );
    web = http.Client();
  });

  tearDownAll(() {
    mux.close();
    web.close();
  });

  group('video.assets', () {
    test('lists real assets, decodes every one and pages by cursor', () async {
      final first = await mux.video.assets.list(limit: 100);
      for (final asset in first.data) {
        expect(asset.id, isNotEmpty);
        expect(asset.raw['id'], asset.id);
        expect(asset.toJson(), isA<Map<String, Object?>>());
      }
      if (!first.hasNextPage) {
        return;
      }
      final second = await first.nextPage();
      expect(second.data, isNotEmpty);
      final firstIds = first.data.map((asset) => asset.id).toSet();
      expect(
        second.data.map((asset) => asset.id).any(firstIds.contains),
        isFalse,
      );
    });

    test('autoPaging walks across page boundaries without repeating', () async {
      final page = await mux.video.assets.list(limit: 3);
      final ids = await page.autoPaging().take(7).map((a) => a.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('retrieves an asset by id when the environment has one', () async {
      final page = await mux.video.assets.list(limit: 1);
      if (page.data.isEmpty) {
        markTestSkipped('The environment holds no assets.');
        return;
      }
      final asset = await mux.video.assets.retrieve(page.data.first.id);
      expect(asset.id, page.data.first.id);
      expect(asset.status, isNotNull);
      expect(asset.createdAtDate, isNotNull);
    });

    test('maps a 404 to MuxNotFoundException carrying the Mux error payload',
        () async {
      await expectLater(
        mux.video.assets.retrieve('does-not-exist-00000000'),
        throwsA(
          isA<MuxNotFoundException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having((e) => e.errorType, 'errorType', isNotNull)
              .having((e) => e.messages, 'messages', isNotEmpty),
        ),
      );
    });
  });

  group('authentication', () {
    test('maps rejected credentials to MuxAuthenticationException', () async {
      final bad = MuxClient(
        tokenId: 'not-a-token',
        tokenSecret: 'not-a-secret',
        maxRetries: 0,
      );
      addTearDown(bad.close);
      await expectLater(
        bad.video.assets.list(limit: 1),
        throwsA(
          isA<MuxAuthenticationException>()
              .having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });
  });

  group('video.uploads', () {
    test('creates, retrieves and cancels a direct upload', () async {
      final upload = await mux.video.uploads.create(
        const UploadCreateParams(
          corsOrigin: 'https://example.com',
          newAssetSettings: AssetOptions(
            playbackPolicies: [PlaybackPolicy.signed],
          ),
          timeout: 60,
        ),
      );
      expect(upload.id, isNotEmpty);
      expect(upload.url, startsWith('https://'));
      expect(upload.status, UploadStatus.waiting);
      expect(
        upload.newAssetSettings?.playbackPolicies,
        contains(PlaybackPolicy.signed),
      );

      final again = await mux.video.uploads.retrieve(upload.id);
      expect(again.id, upload.id);

      final cancelled = await mux.video.uploads.cancel(upload.id);
      expect(cancelled.status, UploadStatus.cancelled);
    });
  });

  group('system.signingKeys', () {
    test('lists signing keys and reads created_at as a date', () async {
      final page = await mux.system.signingKeys.list(limit: 5);
      for (final key in page.data) {
        expect(key.id, isNotEmpty);
        expect(key.createdAtDate, isNotNull);
      }
    });
  });

  group('data', () {
    test('lists video views over a timeframe (bracket-array query)', () async {
      final page = await mux.data.videoViews.list(
        limit: 1,
        timeframe: ['7:days'],
      );
      expect(page.data, isA<List<AbridgedVideoView>>());
    });

    test('lists dimensions (whole-envelope response)', () async {
      final response = await mux.data.dimensions.list();
      expect(response.data, isNotNull);
    });
  });

  group('jwt', () {
    test('Mux accepts playback and thumbnail tokens for a signed asset',
        () async {
      if (!canSign) {
        markTestSkipped(
          'MUX_TEST_SIGNING_KEY_ID / MUX_TEST_SIGNING_PRIVATE_KEY are empty.',
        );
        return;
      }
      final playbackId = await _findReadySignedPlaybackId(mux);
      if (playbackId == null) {
        markTestSkipped('No ready asset with a signed playback id found.');
        return;
      }

      final token = mux.jwt.signPlaybackId(playbackId, expiration: '10m');
      final manifest = await web.get(
        Uri.parse('https://stream.mux.com/$playbackId.m3u8?token=$token'),
      );
      expect(manifest.statusCode, 200, reason: manifest.body);
      expect(manifest.body, startsWith('#EXTM3U'));

      final unsigned = await web.get(
        Uri.parse('https://stream.mux.com/$playbackId.m3u8'),
      );
      expect(unsigned.statusCode, isNot(200));

      final thumbnailToken = mux.jwt.signPlaybackId(
        playbackId,
        type: MuxPlaybackTokenType.thumbnail,
        expiration: '10m',
        params: {'time': 1},
      );
      final thumbnail = await web.get(
        Uri.parse(
          'https://image.mux.com/$playbackId/thumbnail.jpg'
          '?token=$thumbnailToken',
        ),
      );
      expect(thumbnail.statusCode, 200, reason: thumbnail.body);
      expect(thumbnail.headers['content-type'], startsWith('image/'));
    });
  });
}

Future<String?> _findReadySignedPlaybackId(MuxClient mux) async {
  final page = await mux.video.assets.list(limit: 100);
  await for (final asset in page.autoPaging().take(300)) {
    if (asset.status != AssetStatus.ready) {
      continue;
    }
    for (final playback in asset.playbackIds) {
      if (playback.policy == PlaybackPolicy.signed) {
        return playback.id;
      }
    }
  }
  return null;
}
