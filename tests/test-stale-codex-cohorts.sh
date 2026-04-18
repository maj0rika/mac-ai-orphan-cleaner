#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE="${ROOT_DIR}/tests/stale-codex-cohorts-fixture.tsv"
SCRIPT="${ROOT_DIR}/bin/clean-ai-orphans.sh"

output="$(
  CLEAN_AI_ORPHANS_PROCESS_FIXTURE="$FIXTURE" \
    "$SCRIPT" --dry-run --verbose --stale-codex-cohorts
)"

printf '%s\n' "$output"

grep -q 'candidate pid=1101 type=stale-codex-cohort family=codex-mcp-state' <<<"$output"
grep -q 'candidate pid=1102 type=stale-codex-cohort family=codex-mcp-state' <<<"$output"
grep -q 'candidate pid=1301 type=stale-codex-cohort family=codex-mcp-context7-launch' <<<"$output"

if grep -q 'candidate pid=1103 ' <<<"$output"; then
  echo "newer state-server cohort should have been preserved" >&2
  exit 1
fi

if grep -q 'candidate pid=1104 ' <<<"$output"; then
  echo "newest state-server cohort should have been preserved" >&2
  exit 1
fi

if grep -q 'candidate pid=1201 ' <<<"$output"; then
  echo "non-direct Codex descendant should not be selected" >&2
  exit 1
fi

if grep -q 'candidate pid=1401 ' <<<"$output"; then
  echo "non-matching Codex helper should not be selected" >&2
  exit 1
fi

echo "TEST_OK"
