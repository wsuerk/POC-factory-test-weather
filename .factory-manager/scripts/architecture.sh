#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

ensure_ui_deps() {
  if [ ! -d "$ROOT/ui/node_modules" ]; then
    (cd "$ROOT/ui" && npm ci --no-audit --no-fund)
  fi
}

echo "== api: ArchUnit rules =="
(cd "$ROOT/api" && sh ./mvnw -B test -Dtest='**/architecture/**' -Dsurefire.failIfNoSpecifiedTests=false)

echo "== ui: dependency-cruiser rules =="
ensure_ui_deps
(cd "$ROOT/ui" && npm run architecture)
