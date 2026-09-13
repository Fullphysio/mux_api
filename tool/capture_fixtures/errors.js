// Captures test/fixtures/error_golden.json: the exception class and message
// @mux/ts raises for each error status and body shape.

'use strict';

const { loadMux, recordingFetch, clientWith, writeFixture, orNull } = require('./common');

const Mux = loadMux();

async function capture(name, statusCode, body, headers) {
  const { fetch } = recordingFetch([{ status: statusCode, body, headers }]);
  const client = clientWith(Mux, fetch);
  let outcome;
  try {
    await client.video.assets.retrieve('asset1');
    outcome = { threw: false };
  } catch (err) {
    outcome = {
      threw: true,
      className: err.constructor.name,
      message: err.message,
      status: orNull(err.status),
      error: orNull(err.error),
    };
  }
  return { name, input: { statusCode, body: body === undefined ? null : body, headers: headers || {} }, expected: outcome };
}

async function main() {
  const muxError = (type, messages) => ({ error: { type, messages } });
  const cases = [];
  cases.push(await capture('bad_request_400', 400, muxError('invalid_parameters', ['Bad request'])));
  cases.push(await capture('unauthorized_401', 401, muxError('unauthorized', ['Unauthorized'])));
  cases.push(await capture('forbidden_403', 403, muxError('forbidden', ['Forbidden'])));
  cases.push(await capture('not_found_404', 404, muxError('not_found', ['Asset not found'])));
  cases.push(await capture('conflict_409', 409, muxError('conflict', ['Conflict'])));
  cases.push(await capture('unprocessable_422', 422, muxError('invalid_parameters', ['a', 'b'])));
  cases.push(await capture('rate_limited_429', 429, muxError('rate_limited', ['Too many requests'])));
  cases.push(await capture('internal_500', 500, muxError('internal_error', ['Oops'])));
  cases.push(await capture('bad_gateway_502_html', 502, '<html><body>Bad Gateway</body></html>', { 'content-type': 'text/html' }));
  cases.push(await capture('teapot_418_unmapped', 418, muxError('teapot', ['short and stout'])));
  cases.push(await capture('payment_required_402_unmapped', 402, { error: { type: 'payment_required', messages: [] } }));
  cases.push(await capture('empty_body_500', 500, ''));
  cases.push(await capture('top_level_string_message', 400, { message: 'Top-level message wins' }));
  cases.push(await capture('top_level_object_message', 400, { message: { detail: 'nested' } }));
  cases.push(await capture('json_array_body', 400, ['not', 'an', 'object']));
  cases.push(await capture('error_without_messages', 400, { error: { type: 'weird' } }));
  cases.push(await capture('non_string_messages', 400, { error: { type: 't', messages: ['a', 1, null, { k: 'v' }] } }));

  writeFixture('error_golden', {
    seam: 'video.assets.retrieve through the `fetch` client option with maxRetries: 0',
    cases,
  });
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
