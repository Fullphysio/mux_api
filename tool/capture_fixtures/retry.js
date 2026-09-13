// Captures test/fixtures/retry_golden.json: how many attempts @mux/ts makes
// for each status / header combination with maxRetries: 2, and what it
// finally throws or returns. Retry-After headers are set to tiny values so the
// capture runs quickly; the recorded `elapsedMs` shows they were honoured.

'use strict';

const { loadMux, recordingFetch, clientWith, writeFixture } = require('./common');

const Mux = loadMux();

async function capture(name, responses, options) {
  const { fetch, calls } = recordingFetch(responses);
  const client = clientWith(Mux, fetch, Object.assign({ maxRetries: 2 }, options));
  const started = Date.now();
  let outcome;
  try {
    const result = await client.video.assets.retrieve('asset1');
    outcome = { threw: false, resultId: result && result.id ? result.id : null };
  } catch (err) {
    outcome = { threw: true, className: err.constructor.name, message: err.message };
  }
  return {
    name,
    responses: responses.map((r) => ({ status: r.status || null, headers: r.headers || {}, throws: !!r.throw })),
    attempts: calls.length,
    elapsedMs: Date.now() - started,
    expected: outcome,
  };
}

async function main() {
  const ok = { status: 200, body: { data: { id: 'asset1' } } };
  const fast = { 'retry-after-ms': '1' };
  const failure = (status, headers) => ({ status, body: { error: { type: 't', messages: ['m'] } }, headers });

  const cases = [];
  cases.push(await capture('500_then_success', [failure(500, fast), ok]));
  cases.push(await capture('500_exhausts_two_retries', [failure(500, fast), failure(500, fast), failure(500, fast)]));
  cases.push(await capture('408_retried', [failure(408, fast), ok]));
  cases.push(await capture('409_retried', [failure(409, fast), ok]));
  cases.push(await capture('429_retried', [failure(429, fast), ok]));
  cases.push(await capture('400_not_retried', [failure(400, fast), ok]));
  cases.push(await capture('404_not_retried', [failure(404, fast), ok]));
  cases.push(await capture('500_with_x_should_retry_false', [failure(500, Object.assign({ 'x-should-retry': 'false' }, fast)), ok]));
  cases.push(await capture('400_with_x_should_retry_true', [failure(400, Object.assign({ 'x-should-retry': 'true' }, fast)), ok]));
  cases.push(await capture('connection_error_then_success', [{ throw: 'fetch failed' }, ok]));
  cases.push(await capture('connection_error_exhausts_retries', [{ throw: 'fetch failed' }, { throw: 'fetch failed' }, { throw: 'fetch failed' }]));
  cases.push(await capture('retry_after_seconds_honoured', [failure(503, { 'retry-after': '1' }), ok]));
  cases.push(await capture('retry_after_ms_beats_retry_after', [failure(503, { 'retry-after-ms': '50', 'retry-after': '3' }), ok]));
  cases.push(await capture('retry_after_http_date_in_past', [failure(503, { 'retry-after': 'Wed, 21 Oct 2015 07:28:00 GMT' }), ok]));
  cases.push(await capture('retry_after_unparsable_retries_immediately', [failure(503, { 'retry-after': 'soon' }), ok]));
  cases.push(await capture('max_retries_zero', [failure(500, fast), ok], { maxRetries: 0 }));

  writeFixture('retry_golden', {
    seam: 'video.assets.retrieve through the `fetch` client option; maxRetries: 2 unless stated',
    cases,
  });
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
