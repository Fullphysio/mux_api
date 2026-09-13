// Captures test/fixtures/jwt_golden.json: the exact tokens @mux/ts signs for
// a fixed clock and the throwaway test key pair committed under
// test/fixtures/test_keys/. RS256 is deterministic, so the Dart port must
// reproduce every token byte for byte. Each case records the `input` the Dart
// test replays: `privateKey` names which form of the test key was passed
// (`base64`, `pkcs1`, `pkcs8`, `garbage`, or null for none).

'use strict';

const fs = require('fs');
const path = require('path');
const { loadMux, writeFixture } = require('./common');

const Mux = loadMux();

const FIXED_NOW_MS = 1800000000000;
Date.now = () => FIXED_NOW_MS;

const keyDir = path.join(__dirname, '..', '..', 'test', 'fixtures', 'test_keys');
const pkcs1Pem = fs.readFileSync(path.join(keyDir, 'rsa_test_key_pkcs1.pem'), 'utf8');
const pkcs8Pem = fs.readFileSync(path.join(keyDir, 'rsa_test_key_pkcs8.pem'), 'utf8');
const pkcs1Base64 = Buffer.from(pkcs1Pem, 'utf8').toString('base64');
const KEY_FORMS = { base64: pkcs1Base64, pkcs1: pkcs1Pem, pkcs8: pkcs8Pem, garbage: 'definitely not a key' };

const KEY_ID = 'test-signing-key-id';

function decodeSegment(segment) {
  return JSON.parse(Buffer.from(segment.replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('utf8'));
}

function describeToken(token) {
  const [header, payload] = token.split('.');
  return { token, header: decodeSegment(header), payload: decodeSegment(payload) };
}

// input: { method, subject, type?, types?, paramsByType?, params?, expiration?, keyId, privateKey }
async function capture(name, input) {
  const client = new Mux({
    tokenId: 'x',
    tokenSecret: 'y',
    jwtSigningKey: input.keyId,
    jwtPrivateKey: input.privateKey === null ? null : KEY_FORMS[input.privateKey],
  });
  const config = {};
  if (input.type !== undefined) config.type = input.type;
  if (input.params !== undefined) config.params = input.params;
  if (input.expiration !== undefined) config.expiration = input.expiration;
  if (input.types !== undefined) {
    config.type = input.types.map((t) => (input.paramsByType && input.paramsByType[t] ? [t, input.paramsByType[t]] : t));
  }
  try {
    let result;
    switch (input.method) {
      case 'signPlaybackId':
        result = await client.jwt.signPlaybackId(input.subject, config);
        break;
      case 'signDrmLicense':
        result = await client.jwt.signDrmLicense(input.subject, config);
        break;
      case 'signViewerCounts':
        result = await client.jwt.signViewerCounts(input.subject, config);
        break;
      default:
        throw new Error('unknown method ' + input.method);
    }
    if (typeof result === 'string') return { name, input, expected: describeToken(result) };
    const tokens = {};
    for (const [key, token] of Object.entries(result)) tokens[key] = describeToken(token);
    return { name, input, expected: { tokens } };
  } catch (err) {
    return { name, input, expected: { error: { className: err.constructor.name, message: err.message } } };
  }
}

const base = { method: 'signPlaybackId', subject: 'playback1', keyId: KEY_ID, privateKey: 'base64' };

async function main() {
  const cases = [];
  cases.push(await capture('playback_default_video_7d', { ...base }));
  cases.push(await capture('playback_thumbnail_with_string_params', { ...base, type: 'thumbnail', params: { time: '2', width: '320' } }));
  cases.push(await capture('playback_gif_with_numeric_params', { ...base, type: 'gif', params: { start: 0, end: 5, fps: 15, width: 480 } }));
  cases.push(await capture('playback_storyboard', { ...base, type: 'storyboard' }));
  cases.push(await capture('playback_stats', { ...base, type: 'stats' }));
  cases.push(await capture('playback_drm_license_type', { ...base, type: 'drm_license' }));
  cases.push(await capture('expiration_1h', { ...base, expiration: '1h' }));
  cases.push(await capture('expiration_30m', { ...base, expiration: '30m' }));
  cases.push(await capture('expiration_2_days_with_space', { ...base, expiration: '2 days' }));
  cases.push(await capture('expiration_1w', { ...base, expiration: '1w' }));
  cases.push(await capture('expiration_1y', { ...base, expiration: '1y' }));
  cases.push(await capture('expiration_bare_number_string', { ...base, expiration: '3600' }));
  cases.push(await capture('expiration_fractional_seconds', { ...base, expiration: '1.5' }));
  cases.push(await capture('expiration_invalid', { ...base, expiration: 'soon' }));
  cases.push(await capture('params_override_standard_claims_keep_position', { ...base, params: { sub: 'ignored', custom: 'kept' } }));
  cases.push(await capture('key_pem_pkcs1', { ...base, privateKey: 'pkcs1' }));
  cases.push(await capture('key_pem_pkcs8', { ...base, privateKey: 'pkcs8' }));
  cases.push(await capture('key_id_override', { ...base, keyId: 'other-key-id' }));
  cases.push(await capture('drm_license', { ...base, method: 'signDrmLicense' }));
  cases.push(await capture('viewer_counts_default_video', { ...base, method: 'signViewerCounts', subject: 'video-id-1' }));
  cases.push(await capture('viewer_counts_asset', { ...base, method: 'signViewerCounts', subject: 'asset-id-1', type: 'asset' }));
  cases.push(await capture('viewer_counts_playback', { ...base, method: 'signViewerCounts', subject: 'playback-id-1', type: 'playback' }));
  cases.push(await capture('viewer_counts_live_stream', { ...base, method: 'signViewerCounts', subject: 'live-1', type: 'live_stream' }));
  cases.push(
    await capture('multiple_types_with_shared_and_per_type_params', {
      ...base,
      types: ['video', 'thumbnail', 'gif'],
      paramsByType: { thumbnail: { time: '3' } },
      params: { shared: 'x' },
    }),
  );
  cases.push(await capture('missing_signing_key', { ...base, keyId: null }));
  cases.push(await capture('missing_private_key', { ...base, privateKey: null }));
  cases.push(await capture('private_key_not_pem_nor_base64', { ...base, privateKey: 'garbage' }));

  writeFixture('jwt_golden', {
    seam: 'client.jwt.* with Date.now() pinned to ' + FIXED_NOW_MS + ' ms and the committed test key pair',
    fixedNowMs: FIXED_NOW_MS,
    cases,
  });
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
