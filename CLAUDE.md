# Conventions

This is a public package, so it does **not** follow the Fullphysio monorepo's
no-comments or 120-column rules.

- `///` dartdoc is **required** on every exported symbol. pub.dev scores it and
  IDE hovers depend on it.
- No comments on private implementation code. Name things properly instead.
- Formatting is stock `dart format` — **default width, no `--line-length`**.
  That is what `pana` and pub.dev expect with zero configuration.
  A Dart SDK from a Flutter fork or a dev channel can format differently from
  stable; CI runs official stable and is the arbiter.
- `dart analyze --fatal-infos` must be clean.

## Layout

- `lib/src/core/` — hand-written, permanent runtime: client, transport, retry
  policy, exceptions, tolerant JSON readers, page classes, query and path
  encoding, the open-enum base. Generated code compiles against this and never
  changes it.
- `lib/src/jwt/`, `lib/src/webhooks/` — hand-written, permanent.
- `lib/src/generated/` — **generated, committed**. Never edit by hand; change
  the generator or `tool/spec/resources.yaml` and regenerate.
  `webhook_events.g.dart` is a `part` of `lib/src/webhooks/mux_webhook_event.dart`.
- `tool/` — the generator, the vendored OpenAPI spec and the fixture-capture
  scripts. Not shipped (see `.pubignore`).

## Codegen

Output is committed. There is no `build_runner` — consumers must not need a
build step.

```
dart run tool/generate.dart            # regenerate
dart run tool/generate.dart --check    # CI: fail on drift
```

Bump the spec with `dart run tool/spec/update_spec.dart --tag vX.Y.Z`, where
the tag is a release of `muxinc/mux-ts` — the spec is embedded in that repo's
`scripts/mock`, it is not published anywhere else. Do not track `main`.

A regenerate is not reviewable as a text diff. The generator emits a semantic
`CHANGELOG_SPEC.md` fragment (added/removed operations, schemas, enum values,
required fields); **that** is the reviewed artifact.

## Tests

Three tiers:

- **Unit and golden conformance** — the default `dart test` run. No network.
  Fixtures in `test/fixtures/*.json` were captured from the real `@mux/ts`
  (15.1.0) through a fake `fetch`. When changing request construction,
  regenerate the fixtures against the same reference version rather than
  editing them by hand, and bump the version recorded in
  `THIRD_PARTY_NOTICES` and the README if you move to a newer upstream.
- **Mock server** (`--tags mock`) — Steady, the spec-validating mock server
  Stainless itself tests against, started by `tool/mock/run_steady.sh`. Real
  sockets, no account and no network, so it runs on every PR. Self-skips when
  `MUX_MOCK_HOST` is unset or empty.
- **Integration** (`test/integration/`, `--tags integration`) — hits the live
  Mux API. Self-skips when `MUX_TEST_TOKEN_ID` / `MUX_TEST_TOKEN_SECRET` are
  unset or empty, so a fresh checkout passes. Never runs on pull requests.

Assertions are structural. Never assert on how many assets an environment
holds, or the suite rots. GitHub Actions substitutes an empty string for an
undefined variable, so every self-skip checks `isNotEmpty`, not `!= null`.

## CI jobs that are deliberately not here yet

Each of these fails if added before its prerequisite exists (`dart test`
exits 79 when no test carries the tag), so each lands with the thing it checks.

| Job | Blocked on |
|---|---|
| `codegen` (`tool/generate.dart --check`) | the generator |
| `mock` (`--tags mock`) | generated mock tests |
| `integration.yml` | `test/integration/` |

## Conformance with @mux/ts

This package reproduces `@mux/ts` 15.1.0 behaviour deliberately, including
quirks. Before "fixing" something that looks wrong, check the reference — if
the TypeScript does it, we do it, and the reason belongs in a test name, not a
code comment.

- Query arrays use `qs` bracket format with keys encoded too:
  `filters%5B%5D=a&filters%5B%5D=b`. The RFC 3986 unreserved set is the only
  thing left unescaped — `!*'()` and `:` are percent-encoded.
- Every single-object response is wrapped in `{"data": …}`; several `data.*`
  endpoints keep the whole envelope. `tool/spec/resources.yaml` is the record.
- The `Accept` header is per operation: `application/json` for JSON, `*/*`
  for a void `DELETE`, `application/binary` for thumbnails,
  `application/vnd.apple.mpegurl` for HLS, `text/vtt` for storyboards.
- Retries: `x-should-retry` header first, then 408, 409, 429 and 5xx.
  `retry-after-ms` beats `Retry-After`; `Retry-After` is read with
  `parseFloat` semantics (a leading number wins, so an ISO date is its year in
  seconds), then as an HTTP-date; an unparsable or past date retries
  immediately, not after backoff, and there is no upper bound. There are **no
  idempotency keys** — Mux defines none, so a retried POST is exactly as eager
  as upstream.
- The error message is `"<status> <JSON body>"` (or the raw text, or
  `status code (no body)`); the exception subtype is chosen by status code
  alone and `error.type` is informational. Deliberate divergence: `raw` keeps
  the text of a non-JSON body where upstream exposes `null`.
- Path segments: `.` and `..` are rejected like upstream; an empty segment is
  rejected too (upstream would send a trailing slash and hit the collection).
- JWT: `kid` is a **payload** claim, not a header field, and there is no
  `iat`. Claim order is `params…, kid, sub, aud, exp`; a param named like a
  standard claim keeps its position but loses its value. `exp` may be
  fractional (`expiration: '1.5'`), as upstream.
- Webhook tolerance is a hard 300 s, `age > tolerance` — a delivery exactly
  300 s old passes. Nothing disables the timestamp check. Hex signatures are
  compared case-sensitively.
- `created_at` is a *string* of unix seconds on Asset, LiveStream, SigningKey,
  PlaybackRestriction and TranscriptionVocabulary; an integer on Robots jobs;
  ISO-8601 on webhooks. The wire type is kept; a derived getter converts.
- Page kind is not inferable from the response shape (`ListIncidentsResponse`
  carries `total_row_count` but upstream reads only `data`); it is pinned per
  operation in `tool/spec/resources.yaml`.

## Releasing

1. Bump `version:` in `pubspec.yaml` and add a `CHANGELOG.md` entry.
2. Merge to `main` and let CI go green.
3. Tag and push:

   ```
   git tag v1.2.3 && git push origin v1.2.3
   ```

Publishing is permanent: a version can be retracted within 7 days but never
deleted, and the number is never reusable. The `description:` in `pubspec.yaml`
must stay at or under 180 characters or pana drops the score.
