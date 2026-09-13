// Captures test/fixtures/path_encoding_golden.json: how @mux/ts percent-encodes
// a path parameter, and which values it refuses outright.

'use strict';

const { loadMux, recordingFetch, clientWith, writeFixture } = require('./common');

const Mux = loadMux();

async function capture(value) {
  const { fetch, calls } = recordingFetch([{ status: 200, body: { data: { id: 'x' } } }]);
  const client = clientWith(Mux, fetch);
  let error = null;
  try {
    await client.video.assets.retrieve(value);
  } catch (err) {
    error = { className: err.constructor.name, message: err.message };
  }
  return { value, url: calls[0] ? calls[0].url : null, error };
}

async function main() {
  const values = [
    'plainAssetId123',
    'a b',
    'a/b',
    'a?b',
    'a#b',
    '100%',
    'é ü 日本',
    "!$&'()*+,;=:@",
    '-._~',
    '.',
    '..',
    '',
  ];
  const cases = [];
  for (const value of values) cases.push(await capture(value));
  writeFixture('path_encoding_golden', {
    seam: 'video.assets.retrieve(value) through the `fetch` client option',
    cases,
  });
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
