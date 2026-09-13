// Captures test/fixtures/webhook_golden.json: how @mux/ts verifies the
// mux-signature header for a fixed clock, secret and body, including the
// exact failure it raises for each malformed input.

'use strict';

const crypto = require('crypto');
const { loadMux, writeFixture } = require('./common');

const Mux = loadMux();

const FIXED_NOW_MS = 1800000000000;
const NOW_SECONDS = Math.floor(FIXED_NOW_MS / 1000);
Date.now = () => FIXED_NOW_MS;

const SECRET = 'whsec_test_secret';
const BODY = JSON.stringify({
  type: 'video.asset.ready',
  id: 'evt_1',
  created_at: '2027-01-15T08:00:00.000000Z',
  object: { type: 'asset', id: 'asset_1' },
  environment: { name: 'Production', id: 'env_1' },
  data: { id: 'asset_1', status: 'ready', playback_ids: [{ id: 'pb_1', policy: 'signed' }] },
  attempts: [],
});

function sign(timestamp, body, secret) {
  return crypto.createHmac('sha256', secret).update(`${timestamp}.${body}`, 'utf8').digest('hex');
}

async function capture(name, { body, header, secret, clientSecret }) {
  const client = new Mux({ tokenId: 'x', tokenSecret: 'y', webhookSecret: clientSecret === undefined ? SECRET : clientSecret });
  const headers = header === null ? {} : { 'mux-signature': header };
  let verify;
  try {
    await client.webhooks.verifySignature(body, headers, secret);
    verify = { threw: false };
  } catch (err) {
    verify = { threw: true, message: err.message };
  }
  let unwrap;
  try {
    const event = await client.webhooks.unwrap(body, headers, secret);
    unwrap = { threw: false, type: event.type, id: event.id };
  } catch (err) {
    unwrap = { threw: true, message: err.message };
  }
  return { name, input: { body, header, secret: secret === undefined ? null : secret, clientSecret: clientSecret === undefined ? SECRET : clientSecret }, expected: { verify, unwrap } };
}

async function main() {
  const valid = sign(NOW_SECONDS, BODY, SECRET);
  const cases = [];
  cases.push(await capture('valid', { body: BODY, header: `t=${NOW_SECONDS},v1=${valid}` }));
  cases.push(await capture('valid_second_of_two_signatures', { body: BODY, header: `t=${NOW_SECONDS},v1=${'0'.repeat(64)},v1=${valid}` }));
  cases.push(await capture('valid_at_exact_tolerance', { body: BODY, header: `t=${NOW_SECONDS - 300},v1=${sign(NOW_SECONDS - 300, BODY, SECRET)}` }));
  cases.push(await capture('valid_timestamp_in_future', { body: BODY, header: `t=${NOW_SECONDS + 100},v1=${sign(NOW_SECONDS + 100, BODY, SECRET)}` }));
  cases.push(await capture('too_old_by_one_second', { body: BODY, header: `t=${NOW_SECONDS - 301},v1=${sign(NOW_SECONDS - 301, BODY, SECRET)}` }));
  cases.push(await capture('wrong_signature', { body: BODY, header: `t=${NOW_SECONDS},v1=${'a'.repeat(64)}` }));
  cases.push(await capture('signature_for_other_body', { body: BODY, header: `t=${NOW_SECONDS},v1=${sign(NOW_SECONDS, BODY + ' ', SECRET)}` }));
  cases.push(await capture('uppercase_hex_rejected', { body: BODY, header: `t=${NOW_SECONDS},v1=${valid.toUpperCase()}` }));
  cases.push(await capture('missing_header', { body: BODY, header: null }));
  cases.push(await capture('empty_header', { body: BODY, header: '' }));
  cases.push(await capture('header_without_timestamp', { body: BODY, header: `v1=${valid}` }));
  cases.push(await capture('header_without_v1', { body: BODY, header: `t=${NOW_SECONDS},v0=${valid}` }));
  cases.push(await capture('unknown_scheme_ignored', { body: BODY, header: `t=${NOW_SECONDS},v0=deadbeef,v1=${valid}` }));
  cases.push(await capture('missing_secret', { body: BODY, header: `t=${NOW_SECONDS},v1=${valid}`, clientSecret: null }));
  cases.push(await capture('empty_secret', { body: BODY, header: `t=${NOW_SECONDS},v1=${valid}`, clientSecret: '' }));
  cases.push(await capture('secret_argument_overrides_client', { body: BODY, header: `t=${NOW_SECONDS},v1=${sign(NOW_SECONDS, BODY, 'other')}`, secret: 'other' }));
  cases.push(await capture('secret_argument_wrong', { body: BODY, header: `t=${NOW_SECONDS},v1=${valid}`, secret: 'other' }));

  writeFixture('webhook_golden', {
    seam: 'client.webhooks.verifySignature / unwrap with Date.now() pinned to ' + FIXED_NOW_MS + ' ms',
    fixedNowMs: FIXED_NOW_MS,
    validSignature: valid,
    cases,
  });
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
