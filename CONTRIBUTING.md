# Contributing

## Reporting a bug

Open an issue with the package version, the call you made, and what Mux
returned (redact keys and personal data). A failing request is most useful
with its HTTP status and the exception's message.

Behaviour follows the official `@mux/ts` client. If this package differs from it,
that is a bug unless the README lists it as a deliberate divergence.

## Running the tests

```
dart pub get
dart analyze --fatal-infos
dart test                      # unit and golden conformance, no network
dart test --tags integration --run-skipped   # live API, needs `MUX_TEST_TOKEN_ID` and `MUX_TEST_TOKEN_SECRET`
```

## Generated code

`lib/src/generated/` (models, params, resources) is generated from Mux's OpenAPI
specification and committed. Never edit it by hand — change the generator in
`tool/` and regenerate:

```
dart run tool/generate.dart           # regenerate
dart run tool/generate.dart --check   # what CI runs: fails on drift
dart run tool/spec/update_spec.dart   # bump the vendored spec
```

## Pull requests

- Keep `dart format` (default width) and `dart analyze --fatal-infos` clean.
- Every exported symbol needs `///` dartdoc.
- Add a `CHANGELOG.md` entry under an `## Unreleased` heading.
