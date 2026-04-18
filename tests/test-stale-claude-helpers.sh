#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE="${ROOT_DIR}/tests/stale-claude-helpers-fixture.tsv"
SCRIPT="${ROOT_DIR}/bin/clean-ai-orphans.sh"

output="$(
  CLEAN_AI_ORPHANS_PROCESS_FIXTURE="$FIXTURE" \
    "$SCRIPT" --dry-run --verbose --stale-claude-helpers
)"

printf '%s\n' "$output"

grep -q 'candidate pid=2101 type=stale-claude-helper family=claude-extension-chrome-control' <<<"$output"
grep -q 'candidate pid=2301 type=stale-claude-helper family=claude-kmsg' <<<"$output"

if grep -q 'candidate pid=2102 ' <<<"$output"; then
  echo "newer Claude extension wrapper should have been preserved" >&2
  exit 1
fi

if grep -q 'candidate pid=2302 ' <<<"$output"; then
  echo "newer Claude kmsg helper should have been preserved" >&2
  exit 1
fi

if grep -q 'candidate pid=2401 ' <<<"$output"; then
  echo "Claude utility process should not be selected" >&2
  exit 1
fi

echo "TEST_OK"
