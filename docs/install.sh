#!/usr/bin/env bash
# One-line style installer placeholder.
# After hosting a notarized DMG/ZIP, point INSTALL_URL at it.
set -euo pipefail
INSTALL_URL="${INSTALL_URL:-https://sideprompt.app/downloads/SidePrompt-latest.dmg}"
TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

echo "Downloading SidePrompt…"
curl -fsSL "$INSTALL_URL" -o "$TMP/SidePrompt.dmg"
echo "Mounting…"
MOUNT="$(hdiutil attach "$TMP/SidePrompt.dmg" -nobrowse | awk 'END{print $3}')"
ditto "$MOUNT/SidePrompt.app" "/Applications/SidePrompt.app"
hdiutil detach "$MOUNT" >/dev/null
echo "Installed to /Applications/SidePrompt.app"
open "/Applications/SidePrompt.app"
