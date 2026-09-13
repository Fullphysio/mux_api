# mux_api

A pure Dart client for the [Mux](https://www.mux.com) API. Runs on Dart
servers, CLIs and Flutter apps — there is no Flutter dependency, and no code
generation step for you.

```dart
final mux = MuxClient(tokenId: tokenId, tokenSecret: tokenSecret);

final upload = await mux.video.uploads.create(
  const UploadCreateParams(
    corsOrigin: 'https://example.com',
    newAssetSettings: AssetOptions(playbackPolicies: [PlaybackPolicy.signed]),
  ),
);
// PUT the file to upload.url, then:
final ready = await mux.video.uploads.retrieve(upload.id);
if (ready.status == UploadStatus.assetCreated) {
  final token = mux.jwt.signPlaybackId(playbackId, expiration: '24h');
  final url = 'https://stream.mux.com/$playbackId.m3u8?token=$token';
}
```

## Why this exists

No Dart package covers the Mux REST API; the ones on pub.dev are Flutter
player widgets. This package is a port of the official TypeScript client,
`@mux/ts`: the runtime — transport, retries, error mapping, pagination, JWT
signing and webhook verification — is a hand port, and every model and
resource method is generated from Mux's own OpenAPI specification by a
generator that lives in this repository. Following a new Mux release is a
command, not a rewrite.

## Signed playback

Tokens need no client — just the signing key pair from the Mux dashboard, as
PEM or as the base64 PEM Mux hands out:

```dart
final token = signMuxPlaybackId(
  playbackId,
  type: MuxPlaybackTokenType.gif,
  params: {'start': 0, 'end': 5, 'fps': 15, 'width': 480},
  expiration: '48h',
  keyId: signingKeyId,
  privateKey: privateKeyBase64,
);
```

`signMuxPlaybackIdTokens` returns the `playback-token` / `thumbnail-token` /
`storyboard-token` map Mux Player takes; `signMuxDrmLicense` and
`signMuxViewerCounts` cover the other audiences.

## Webhooks

Verification is static too:

```dart
final event = unwrapMuxWebhookEvent(
  request.rawBody,
  request.headers['mux-signature'],
  secret: endpointSecret,
);
```

Pass the **raw** request body, never a re-encoded or already-parsed one.
Verification uses a constant-time comparison, accepts any one of the signatures
in the header (so secret rotation works), and rejects timestamps older than
300 seconds. `unwrap` returns a typed `MuxWebhookEvent`; a type this version
does not know decodes to `UnknownMuxWebhookEvent` with its payload intact.

## Errors

Every failure is a `MuxException`, a sealed hierarchy:

| Exception | When |
|---|---|
| `MuxBadRequestException` … `MuxInternalServerException` | a 400, 401, 403, 404, 409, 422, 429 or 5xx response, with Mux's `errorType` and `messages` |
| `MuxUnexpectedStatusException` | any other non-2xx status |
| `MuxConnectionException`, `MuxTimeoutException` | the request never produced a response |
| `MuxWebhookSignatureException` | a delivery that failed verification |

`MuxDecodeException` (outside the hierarchy) means Mux answered successfully
but the payload was missing its `id` or `data` envelope.

## Fidelity to @mux/ts

This client reproduces `@mux/ts` 15.1.0's observable behaviour, including
details that are easy to get subtly wrong:

- Retries on 408, 409, 429, 5xx and connection failures — twice by default —
  honouring `x-should-retry`, `retry-after-ms` and `Retry-After` (seconds or
  HTTP-date) over a 0.5 s-doubling backoff capped at 8 s with up to 25 %
  jitter. Mux defines no idempotency keys, so a retried `POST` is exactly as
  eager as upstream.
- Query arrays use bracket notation, `filters[]=a&filters[]=b`, percent-encoded
  with the RFC 3986 unreserved set.
- JWT claims are `params…, kid, sub, aud, exp` — `kid` in the payload, no `iat`.

Conformance is enforced by golden tests whose fixtures were captured from the
real `@mux/ts`, not written by hand; the JWT fixtures match byte for byte.

## Scope

**Covered.** The runtime above, `video.uploads`, and JWT signing and webhook
verification. Every enum tolerates values Mux adds later.

**Not covered yet.** The rest of `video.*`, `data.*`, `system.*` and
`robots.*`, and typed webhook event classes — these come from the generator
in the next releases. Until then `MuxClient.requestJson` reaches any endpoint
with the same authentication, retries and error mapping.

Never covered: reading credentials from environment variables (pass them
in), request cancellation, and playback URL builders (`stream.mux.com` and
`image.mux.com` URLs are one string interpolation away, as upstream leaves
them).

## Relationship to @mux/ts and to Mux

This is an independent port, not an official Mux product and not endorsed by
Mux. See `THIRD_PARTY_NOTICES` for the licence of `@mux/ts` and of the OpenAPI
specification this package is derived from.
