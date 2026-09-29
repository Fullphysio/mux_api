## 1.0.0

- First stable release. The public API is now covered by semantic versioning.
- Add CONTRIBUTING.md, a pub badge and a token-secret warning to the README.

## 0.1.0

- Initial release: the hand-written runtime ported from `@mux/ts` 15.1.0
  (transport, retries, error mapping, pagination, query and path encoding);
  every `video`, `data`, `system` and `robots` operation with its models,
  parameters, enums and unions generated from the Mux OpenAPI specification
  embedded in that release; typed webhook events with signature
  verification; JWT signing for playback, DRM-licence and viewer-count
  tokens.
