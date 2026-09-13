// Captures test/fixtures/query_encoding_golden.json: the exact URL, method,
// headers and body @mux/ts produces for representative calls, including
// bracket-array query parameters and the per-endpoint host selection. Each
// case records the `input` the Dart transport must be driven with to
// reproduce the same request.

'use strict';

const { loadMux, recordingFetch, clientWith, writeFixture } = require('./common');

const Mux = loadMux();

async function capture(name, input, invoke, responseBody) {
  const { fetch, calls } = recordingFetch([{ status: 200, body: responseBody === undefined ? { data: {} } : responseBody }]);
  const client = clientWith(Mux, fetch);
  let error = null;
  try {
    await invoke(client);
  } catch (err) {
    error = { className: err.constructor.name, message: err.message };
  }
  const call = calls[0] || null;
  return {
    name,
    input: {
      method: input.method,
      host: input.host || 'api',
      path: input.path,
      query: input.query === undefined ? null : input.query,
      body: input.body === undefined ? null : input.body,
    },
    error,
    request: call && {
      url: call.url,
      method: call.method,
      contentType: call.headers['content-type'] || null,
      accept: call.headers['accept'] || null,
      authorization: call.headers['authorization'] || null,
      body: call.body,
    },
  };
}

async function main() {
  const cases = [];

  const metricsQuery = {
    filters: ['operating_system:windows', 'country:US'],
    metric_filters: ['aggregate_startup_time>=1000'],
    timeframe: ['7:days'],
    measurement: '95th',
    group_by: 'hour',
  };
  cases.push(
    await capture(
      'metrics_timeseries_bracket_arrays',
      { method: 'GET', path: '/data/v1/metrics/video_startup_time/timeseries', query: metricsQuery },
      (c) => c.data.metrics.getTimeseries('video_startup_time', metricsQuery),
    ),
  );

  const assetsQuery = { limit: 10, cursor: 'abc def/ü+x' };
  cases.push(
    await capture('assets_list_cursor_and_limit', { method: 'GET', path: '/video/v1/assets', query: assetsQuery }, (c) => c.video.assets.list(assetsQuery), {
      data: [],
      next_cursor: '',
    }),
  );

  const uploadsQuery = { page: 2, limit: 5 };
  cases.push(
    await capture('uploads_list_page_limit', { method: 'GET', path: '/video/v1/uploads', query: uploadsQuery }, (c) => c.video.uploads.list(uploadsQuery), { data: [] }),
  );

  const viewsQuery = {
    filters: ['a b', 'c&d=e', "!*'()", 'x[y]', '100%', 'é/ü'],
    viewer_id: 'viewer 1',
    order_direction: 'asc',
  };
  cases.push(
    await capture('video_views_reserved_characters', { method: 'GET', path: '/data/v1/video-views', query: viewsQuery }, (c) => c.data.videoViews.list(viewsQuery), {
      data: [],
    }),
  );

  const usageQuery = { timeframe: ['1600000000', '1600100000'], asset_id: 'asset1', page: 1, limit: 50 };
  cases.push(
    await capture(
      'delivery_usage_timeframe',
      { method: 'GET', path: '/video/v1/delivery-usage', query: usageQuery },
      (c) => c.video.deliveryUsage.list(usageQuery),
      { data: [], timeframe: [1600000000, 1600100000], page: 1, limit: 50 },
    ),
  );

  const thumbnailQuery = { width: 320, height: 180, time: 2.5, fit_mode: 'crop', token: 'tok.en' };
  cases.push(
    await capture(
      'thumbnail_image_host_numbers_and_token',
      { method: 'GET', host: 'image', path: '/pid123/thumbnail.png', query: thumbnailQuery },
      (c) => c.video.playback.thumbnail('pid123', 'png', thumbnailQuery),
      'binary',
    ),
  );

  const hlsQuery = { token: 't', max_resolution: '1080p', redundant_streams: true };
  cases.push(
    await capture('hls_stream_host', { method: 'GET', host: 'stream', path: '/pid123.m3u8', query: hlsQuery }, (c) => c.video.playback.hls('pid123', hlsQuery), '#EXTM3U'),
  );

  cases.push(
    await capture('storyboard_vtt_text', { method: 'GET', host: 'image', path: '/pid123/storyboard.vtt', query: {} }, (c) => c.video.playback.storyboardVtt('pid123', {}), 'WEBVTT'),
  );

  const uploadBody = {
    cors_origin: 'https://example.com',
    new_asset_settings: { playback_policies: ['signed'], video_quality: 'plus' },
    timeout: 3600,
  };
  cases.push(await capture('upload_create_json_body', { method: 'POST', path: '/video/v1/uploads', body: uploadBody }, (c) => c.video.uploads.create(uploadBody)));

  const masterAccessBody = { master_access: 'temporary' };
  cases.push(
    await capture(
      'asset_update_master_access_put',
      { method: 'PUT', path: '/video/v1/assets/asset1/master-access', body: masterAccessBody },
      (c) => c.video.assets.updateMasterAccess('asset1', masterAccessBody),
    ),
  );

  cases.push(await capture('asset_delete_no_body', { method: 'DELETE', path: '/video/v1/assets/asset1' }, (c) => c.video.assets.delete('asset1'), null));

  cases.push(await capture('upload_cancel_put_no_body', { method: 'PUT', path: '/video/v1/uploads/upload1/cancel' }, (c) => c.video.uploads.cancel('upload1')));

  const annotationsQuery = { timeframe: ['1700000000', '1700100000'], order_direction: 'desc', limit: 3 };
  cases.push(
    await capture(
      'annotations_list_timeframe_and_order',
      { method: 'GET', path: '/data/v1/annotations', query: annotationsQuery },
      (c) => c.data.annotations.list(annotationsQuery),
      { data: [] },
    ),
  );

  writeFixture('query_encoding_golden', {
    seam: 'the `fetch` client option, recording every request before answering it',
    cases,
  });
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
