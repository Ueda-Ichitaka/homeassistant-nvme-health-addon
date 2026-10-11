# Test runner image: bats-core plus the tools the add-on scripts depend on (jq).
# Exists so the bats suite runs identically on any machine with Docker.
FROM bats/bats:1.14.0

RUN apk add --no-cache jq
