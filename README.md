# mux_api

A pure Dart client for the [Mux](https://www.mux.com) API. Runs on Dart
servers, CLIs and Flutter apps — there is no Flutter dependency, and no code
generation step for you.

```dart
final mux = MuxClient(tokenId: tokenId, tokenSecret: tokenSecret);

final upload = await mux.video.uploads.create(
  UploadCreateParams(
    corsOrigin: 'https://example.com',
    newAssetSettings: AssetOptions(playbackPolicies: [PlaybackPolicy.signed]),
  ),
);
```

## Why this exists

No Dart package covers the Mux REST API; the ones on pub.dev are Flutter
player widgets. This package is a port of the official TypeScript client,
`@mux/ts`: the runtime — transport, retries, error mapping, pagination, JWT
signing and webhook verification — is a hand port, and every model and
resource method is generated from Mux's own OpenAPI specification by a
generator that lives in this repository. Following a new Mux release is a
command, not a rewrite.

## Relationship to `@mux/ts` and to Mux

This is an independent port, not an official Mux product and not endorsed by
Mux. See `THIRD_PARTY_NOTICES` for the licence of `@mux/ts` and the OpenAPI
specification this package is derived from.
