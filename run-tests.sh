#!/usr/bin/env bash
# Builds the test runner image and runs the bats test suite in tests/.
# Exists so contributors need only Docker, not a local bats/jq install.
set -euo pipefail

cd "$(dirname "$0")"
docker build -q -t nvme-health-tests tests >/dev/null
exec docker run --rm -v "$PWD:/code:ro" -w /code nvme-health-tests "${@:-tests}"
