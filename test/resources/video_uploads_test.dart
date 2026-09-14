import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mux_api/mux_api.dart';
import 'package:test/test.dart';

import '../_support/fixtures.dart';

const Map<String, Object?> _uploadJson = {
  'id': 'upload1',
  'status': 'waiting',
  'url': 'https://storage.googleapis.com/video-storage/upload1',
  'cors_origin': 'https://example.com',
  'timeout': 3600,
  'new_asset_settings': {
    'playback_policies': ['signed'],
    'video_quality': 'plus',
    'future_setting': true,
  },
  'test': false,
};

MuxClient _client(http.Client httpClient) => MuxClient(
      tokenId: 'id',
      tokenSecret: 'secret',
      maxRetries: 0,
      httpClient: httpClient,
    );

void main() {
  group('create', () {
    test('sends the exact body @mux/ts sends', () async {
      final golden = casesOf(loadFixture('query_encoding_golden'))
          .singleWhere((c) => c['name'] == 'upload_create_json_body');
      final expected = mapOf(golden['request']);

      http.Request? captured;
      final client = _client(MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode({'data': _uploadJson}), 201);
      }));

      final upload = await client.video.uploads.create(
        const UploadCreateParams(
          corsOrigin: 'https://example.com',
          newAssetSettings: AssetOptions(
            playbackPolicies: [PlaybackPolicy.signed],
            videoQuality: AssetVideoQuality.plus,
          ),
          timeout: 3600,
        ),
      );

      expect(captured!.url.toString(), expected['url']);
      expect(captured!.method, 'POST');
      expect(captured!.body, expected['body']);
      expect(captured!.headers['content-type'], 'application/json');
      expect(upload.id, 'upload1');
      expect(
          upload.url, 'https://storage.googleapis.com/video-storage/upload1');
    });
  });

  group('retrieve', () {
    test('decodes every field, tolerating unknown values', () async {
      final client = _client(MockClient((request) async {
        expect(
          request.url.toString(),
          'https://api.mux.com/video/v1/uploads/upload%201',
        );
        return http.Response(
          jsonEncode({
            'data': {
              ..._uploadJson,
              'status': 'a_new_status',
              'asset_id': 'asset1',
              'error': {'type': 'invalid_input', 'message': 'Bad file'},
            }
          }),
          200,
        );
      }));

      final upload = await client.video.uploads.retrieve('upload 1');
      expect(upload.status, UploadStatus.unknown('a_new_status'));
      expect(upload.status!.isKnown, isFalse);
      expect(upload.assetId, 'asset1');
      expect(upload.corsOrigin, 'https://example.com');
      expect(upload.timeout, 3600);
      expect(upload.test, isFalse);
      expect(upload.error?.type, 'invalid_input');
      expect(upload.error?.message, 'Bad file');
      expect(
          upload.newAssetSettings?.playbackPolicies, [PlaybackPolicy.signed]);
      expect(upload.newAssetSettings?.videoQuality, AssetVideoQuality.plus);
      expect(upload.newAssetSettings?.raw['future_setting'], isTrue);
      expect(upload.raw['status'], 'a_new_status');
    });

    test('a known status resolves to its constant', () async {
      final client = _client(MockClient(
        (_) async => http.Response(jsonEncode({'data': _uploadJson}), 200),
      ));
      final upload = await client.video.uploads.retrieve('upload1');
      expect(upload.status, same(UploadStatus.waiting));
    });

    test('a response without data is a decode failure', () {
      final client = _client(MockClient(
        (_) async => http.Response('{"unexpected":true}', 200),
      ));
      expect(
        client.video.uploads.retrieve('upload1'),
        throwsA(isA<MuxDecodeException>()),
      );
    });

    test('a 404 surfaces as MuxNotFoundException', () {
      final client = _client(MockClient(
        (_) async => http.Response(
          '{"error":{"type":"not_found","messages":["Upload not found"]}}',
          404,
        ),
      ));
      expect(
        client.video.uploads.retrieve('missing'),
        throwsA(
          isA<MuxNotFoundException>()
              .having((e) => e.messages, 'messages', ['Upload not found']),
        ),
      );
    });
  });

  group('cancel', () {
    test('is a bodyless PUT', () async {
      http.Request? captured;
      final client = _client(MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'data': {..._uploadJson, 'status': 'cancelled'}
          }),
          200,
        );
      }));
      final upload = await client.video.uploads.cancel('upload1');
      expect(
        captured!.url.toString(),
        'https://api.mux.com/video/v1/uploads/upload1/cancel',
      );
      expect(captured!.method, 'PUT');
      expect(captured!.body, isEmpty);
      expect(captured!.headers['content-type'], isNull);
      expect(upload.status, UploadStatus.cancelled);
    });
  });

  group('list', () {
    test('pages with page and limit until a page comes back empty', () async {
      final urls = <String>[];
      var calls = 0;
      final client = _client(MockClient((request) async {
        urls.add(request.url.toString());
        calls++;
        final data = calls == 1
            ? [
                {'id': 'u1'},
                {'id': 'u2'}
              ]
            : <Object?>[];
        return http.Response(jsonEncode({'data': data}), 200);
      }));

      final page = await client.video.uploads.list(limit: 2);
      expect(page.data.map((u) => u.id), ['u1', 'u2']);
      expect(page.hasNextPage, isTrue);
      final all = await page.autoPaging().map((u) => u.id).toList();
      expect(all, ['u1', 'u2']);
      expect(urls, [
        'https://api.mux.com/video/v1/uploads?limit=2',
        'https://api.mux.com/video/v1/uploads?limit=2&page=2',
      ]);
    });
  });

  group('AssetOptions', () {
    test('round-trips known settings and keeps unknown ones in raw', () {
      final options = AssetOptions.fromJson(const {
        'playback_policies': ['public', 'holographic'],
        'master_access': 'temporary',
        'normalize_audio': true,
        'passthrough': 'p',
        'new_thing': {'a': 1},
      });
      expect(options.playbackPolicies, [
        PlaybackPolicy.public,
        PlaybackPolicy.unknown('holographic'),
      ]);
      expect(options.masterAccess, MasterAccess.temporary);
      expect(options.raw['new_thing'], {'a': 1});
      expect(options.toJson(), {
        'playback_policies': ['public', 'holographic'],
        'master_access': 'temporary',
        'normalize_audio': true,
        'passthrough': 'p',
      });
    });
  });
}
