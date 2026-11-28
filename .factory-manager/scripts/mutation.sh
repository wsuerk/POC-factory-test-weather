#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# The factory passes its mutation minimum (a percentage) in FM_MUTATION_MIN.
: "${FM_MUTATION_MIN:=80}"

ensure_ui_deps() {
  if [ ! -d "$ROOT/ui/node_modules" ]; then
    (cd "$ROOT/ui" && npm ci --no-audit --no-fund)
  fi
}

echo "== api: PIT mutation testing (minimum ${FM_MUTATION_MIN}%) =="
(cd "$ROOT/api" && sh ./mvnw -B test-compile org.pitest:pitest-maven:mutationCoverage -DmutationThreshold="$FM_MUTATION_MIN")

echo "== ui: Stryker mutation testing (minimum ${FM_MUTATION_MIN}%) =="
ensure_ui_deps
(cd "$ROOT/ui" && npm run mutation -- --thresholds.break "$FM_MUTATION_MIN")
