#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_BIN_DIR="${HOME}/bin"
TARGET_SCRIPT="${TARGET_BIN_DIR}/clean-ai-orphans.sh"
TARGET_AGENT_DIR="${HOME}/Library/LaunchAgents"
TARGET_AGENT="${TARGET_AGENT_DIR}/com.leeth.clean-ai-orphans.plist"
LOG_DIR="${HOME}/Library/Logs"
LABEL="com.leeth.clean-ai-orphans"
AGGRESSIVE=0
STALE_CODEX_COHORTS=0
STALE_CLAUDE_HELPERS=0
STALE_GENERIC_HELPERS=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --aggressive)
      AGGRESSIVE=1
      ;;
    --stale-codex-cohorts)
      STALE_CODEX_COHORTS=1
      ;;
    --stale-claude-helpers)
      STALE_CLAUDE_HELPERS=1
      ;;
    --stale-generic-helpers)
      STALE_GENERIC_HELPERS=1
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      exit 1
      ;;
  esac
  shift
done

mkdir -p "$TARGET_BIN_DIR" "$TARGET_AGENT_DIR" "$LOG_DIR"

cp "${ROOT_DIR}/bin/clean-ai-orphans.sh" "$TARGET_SCRIPT"
chmod +x "$TARGET_SCRIPT"

SCRIPT_COMMAND="${HOME}/bin/clean-ai-orphans.sh"
if [ "$AGGRESSIVE" -eq 1 ]; then
  SCRIPT_COMMAND="${SCRIPT_COMMAND} --aggressive"
fi
if [ "$STALE_CODEX_COHORTS" -eq 1 ]; then
  SCRIPT_COMMAND="${SCRIPT_COMMAND} --stale-codex-cohorts"
fi
if [ "$STALE_CLAUDE_HELPERS" -eq 1 ]; then
  SCRIPT_COMMAND="${SCRIPT_COMMAND} --stale-claude-helpers"
fi
if [ "$STALE_GENERIC_HELPERS" -eq 1 ]; then
  SCRIPT_COMMAND="${SCRIPT_COMMAND} --stale-generic-helpers"
fi

awk -v home="$HOME" -v script_command="$SCRIPT_COMMAND" '
  {
    gsub("__HOME__", home)
    gsub("__SCRIPT_COMMAND__", script_command)
    print
  }
' "${ROOT_DIR}/launchd/com.leeth.clean-ai-orphans.plist" >"$TARGET_AGENT"
plutil -lint "$TARGET_AGENT" >/dev/null

launchctl bootout "gui/$(id -u)" "$TARGET_AGENT" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$TARGET_AGENT"
launchctl enable "gui/$(id -u)/${LABEL}"
launchctl kickstart -k "gui/$(id -u)/${LABEL}"

echo "Installed ${LABEL}"
echo "Script: ${TARGET_SCRIPT}"
echo "LaunchAgent: ${TARGET_AGENT}"
echo "Log: ${LOG_DIR}/clean-ai-orphans.log"
echo "Aggressive mode: ${AGGRESSIVE}"
echo "Stale Codex cohorts mode: ${STALE_CODEX_COHORTS}"
echo "Stale Claude helpers mode: ${STALE_CLAUDE_HELPERS}"
echo "Stale generic helpers mode: ${STALE_GENERIC_HELPERS}"
