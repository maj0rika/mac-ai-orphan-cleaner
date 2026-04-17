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

while [ "$#" -gt 0 ]; do
  case "$1" in
    --aggressive)
      AGGRESSIVE=1
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

EXTRA_PROGRAM_ARGUMENTS=""
if [ "$AGGRESSIVE" -eq 1 ]; then
  EXTRA_PROGRAM_ARGUMENTS='    <string>--aggressive</string>'
fi

awk -v home="$HOME" -v extra="$EXTRA_PROGRAM_ARGUMENTS" '
  {
    gsub("__HOME__", home)
    if ($0 ~ /__EXTRA_PROGRAM_ARGUMENTS__/) {
      if (extra != "") {
        print extra
      }
      next
    }
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
