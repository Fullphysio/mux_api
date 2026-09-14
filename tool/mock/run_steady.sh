#!/usr/bin/env bash
# Starts Steady, the spec-validating mock server Stainless tests @mux/ts
# against, on the vendored Mux specification. Requests that violate the spec
# are rejected with a validation report; valid ones get the spec's examples.
#
#   tool/mock/run_steady.sh &
#   MUX_MOCK_HOST=127.0.0.1:4010 dart test --tags mock --run-skipped
set -euo pipefail
cd "$(dirname "$0")/../.."
exec npm exec --yes --package=@stdy/cli@0.22.1 -- steady tool/spec/mux-openapi.json \
  --host 127.0.0.1 -p "${MUX_MOCK_PORT:-4010}" \
  --validator-query-array-format=brackets --validator-form-array-format=brackets \
  --validator-query-object-format=brackets --validator-form-object-format=brackets "$@"
