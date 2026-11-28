#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Builds and tests every part. JUnit XML reports land in api/target/surefire-reports/ and ui/test-results/.

echo "== api: build and test (Maven) =="
(cd "$ROOT/api" && sh ./mvnw -B verify)

echo "== ui: install, build and test (npm) =="
(cd "$ROOT/ui" && npm ci --no-audit --no-fund && npm run build && npm run test:ci)
