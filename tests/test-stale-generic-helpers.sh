#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE="${ROOT_DIR}/tests/stale-generic-helpers-fixture.tsv"
SCRIPT="${ROOT_DIR}/bin/clean-ai-orphans.sh"

output="$(
  CLEAN_AI_ORPHANS_PROCESS_FIXTURE="$FIXTURE" \
    "$SCRIPT" --dry-run --verbose --stale-generic-helpers
)"

printf '%s\n' "$output"

grep -q 'candidate pid=3101 type=stale-generic-helper family=generic-typescript-language-server' <<<"$output"
grep -q 'candidate pid=3201 type=stale-generic-helper family=generic-tsserver' <<<"$output"
grep -q 'candidate pid=3301 type=stale-generic-helper family=generic-playwright-launch' <<<"$output"

if grep -q 'candidate pid=3401 ' <<<"$output"; then
  echo "Codex-specific helper should not be selected by generic mode" >&2
  exit 1
fi

if grep -q 'candidate pid=3501 ' <<<"$output"; then
  echo "busy generic helper should not be selected" >&2
  exit 1
fi

echo "TEST_OK"
