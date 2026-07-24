#!/bin/sh
set -e

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required but not installed." >&2
  exit 1
fi

INSTALL_DIR="$HOME/.local/share/agy-statusline"
mkdir -p "$INSTALL_DIR"
cp statusline.sh "$INSTALL_DIR/statusline.sh"
chmod +x "$INSTALL_DIR/statusline.sh"

SETTINGS_DIR="$HOME/.gemini/antigravity-cli"
SETTINGS_FILE="$SETTINGS_DIR/settings.json"
SETTINGS_BAK="$SETTINGS_DIR/settings.json.bak"

mkdir -p "$SETTINGS_DIR"

if [ -f "$SETTINGS_FILE" ]; then
  cp "$SETTINGS_FILE" "$SETTINGS_BAK"
else
  echo "{}" > "$SETTINGS_FILE"
fi

STATUSLINE_CMD="$INSTALL_DIR/statusline.sh"
jq --arg cmd "$STATUSLINE_CMD" '. + {statusLine: {type: "", command: $cmd, enabled: true}}' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"

echo "Installation successful!"
