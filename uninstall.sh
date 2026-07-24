#!/bin/sh

set -e

TARGET_DIR="$HOME/.local/share/agy-statusline"

echo "Removing statusline script..."
if [ -f "$TARGET_DIR/statusline.sh" ]; then
  rm -f "$TARGET_DIR/statusline.sh"
fi

if [ -d "$TARGET_DIR" ]; then
  # Only attempt to remove if empty
  rmdir "$TARGET_DIR" 2>/dev/null || true
fi

SETTINGS_DIR="$HOME/.gemini/antigravity-cli"
SETTINGS_FILE="$SETTINGS_DIR/settings.json"
SETTINGS_BAK="$SETTINGS_DIR/settings.json.bak"

echo "Reverting settings changes..."
if [ -f "$SETTINGS_BAK" ]; then
  cp "$SETTINGS_BAK" "$SETTINGS_FILE"
  rm -f "$SETTINGS_BAK"
elif [ -f "$SETTINGS_FILE" ]; then
  if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is required to update settings.json" >&2
    exit 1
  fi
  jq '.statusLine.enabled = false' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp"
  mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
fi

echo "Uninstall successful!"
