#!/bin/bash

set -euo pipefail

TARGET_SCRIPT="${HOME}/bin/clean-ai-orphans.sh"
TARGET_AGENT="${HOME}/Library/LaunchAgents/com.leeth.clean-ai-orphans.plist"
LABEL="com.leeth.clean-ai-orphans"

launchctl bootout "gui/$(id -u)" "$TARGET_AGENT" 2>/dev/null || true
launchctl disable "gui/$(id -u)/${LABEL}" 2>/dev/null || true

rm -f "$TARGET_AGENT"
rm -f "$TARGET_SCRIPT"

echo "Removed ${LABEL}"
echo "Log file is kept at ${HOME}/Library/Logs/clean-ai-orphans.log"
