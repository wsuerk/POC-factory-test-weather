#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

ensure_ui_deps() {
  if [ ! -d "$ROOT/ui/node_modules" ]; then
    (cd "$ROOT/ui" && npm ci --no-audit --no-fund)
  fi
}

echo "== api: PIT mutation testing =="
(cd "$ROOT/api" && sh ./mvnw -B test-compile org.pitest:pitest-maven:mutationCoverage)

echo "== ui: Stryker mutation testing =="
ensure_ui_deps
(cd "$ROOT/ui" && npm run mutation)
