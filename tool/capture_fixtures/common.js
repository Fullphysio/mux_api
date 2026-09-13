// Shared helpers for the fixture-capture scripts. Each script drives the REAL
// `@mux/ts` client through its `fetch` option with canned responses and
// records what it produced, so the Dart tests compare against upstream
// behaviour rather than against what we believe it to be.
//
//   mkdir -p /tmp/mux-ref && cd /tmp/mux-ref && npm install @mux/ts@15.1.0
//   node /path/to/mux_api/tool/capture_fixtures/<script>.js
//
// `require('@mux/ts')` is resolved against the current working directory.

'use strict';

const fs = require('fs');
const path = require('path');

const MUX_TS_VERSION = '15.1.0';

function loadMux() {
  let resolved;
  try {
    resolved = require.resolve('@mux/ts', { paths: [process.cwd()] });
  } catch (e) {
    throw new Error(
      'Could not resolve "@mux/ts" from ' +
        process.cwd() +
        '. Run this script from a directory with @mux/ts ' +
        MUX_TS_VERSION +
        ' installed, e.g.:\n' +
        '  mkdir -p /tmp/mux-ref && cd /tmp/mux-ref\n' +
        '  npm install @mux/ts@' +
        MUX_TS_VERSION,
    );
  }
  const installed = installedVersion(resolved);
  if (installed !== MUX_TS_VERSION) {
    throw new Error('Installed @mux/ts is ' + installed + ', expected ' + MUX_TS_VERSION);
  }
  return require(resolved);
}

function installedVersion(resolvedEntry) {
  let dir = path.dirname(resolvedEntry);
  for (let i = 0; i < 6; i++) {
    const candidate = path.join(dir, 'package.json');
    if (fs.existsSync(candidate)) {
      const pkg = JSON.parse(fs.readFileSync(candidate, 'utf8'));
      if (pkg.name === '@mux/ts') return pkg.version;
    }
    dir = path.dirname(dir);
  }
  throw new Error('Could not locate @mux/ts package.json from ' + resolvedEntry);
}

function headersToObject(headers) {
  const out = {};
  for (const [key, value] of new Headers(headers).entries()) out[key] = value;
  return out;
}

// Builds a `fetch` that answers each call with the next canned response and
// records every request it saw. `responses` entries are
// `{ status, body, headers }` or a function `(callIndex) => entry`; an entry
// with `throw: 'message'` makes fetch reject, simulating a connection error.
function recordingFetch(responses) {
  const calls = [];
  let index = 0;
  const fetch = async (url, init) => {
    const spec = typeof responses === 'function' ? responses(index) : responses[Math.min(index, responses.length - 1)];
    index += 1;
    calls.push({
      url: String(url),
      method: init && init.method ? String(init.method) : 'GET',
      headers: init && init.headers ? headersToObject(init.headers) : {},
      body: init && init.body != null ? String(init.body) : null,
    });
    if (spec.throw) throw new TypeError(spec.throw);
    const body = spec.body === undefined || spec.body === null ? null : typeof spec.body === 'string' ? spec.body : JSON.stringify(spec.body);
    return new Response(body, {
      status: spec.status,
      headers: Object.assign(body !== null && typeof spec.body !== 'string' ? { 'content-type': 'application/json' } : {}, spec.headers || {}),
    });
  };
  return { fetch, calls };
}

function clientWith(Mux, fetch, options) {
  return new Mux(Object.assign({ tokenId: 'capture-token-id', tokenSecret: 'capture-token-secret', fetch, maxRetries: 0 }, options));
}

function writeFixture(name, fixture) {
  const outPath = path.join(__dirname, '..', '..', 'test', 'fixtures', name + '.json');
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(
    outPath,
    JSON.stringify(Object.assign({ capturedFrom: { package: '@mux/ts', version: MUX_TS_VERSION } }, fixture), null, 2) + '\n',
  );
  console.log('Wrote ' + outPath);
}

function orNull(value) {
  return value === undefined ? null : value;
}

module.exports = { MUX_TS_VERSION, loadMux, recordingFetch, clientWith, writeFixture, headersToObject, orNull };
