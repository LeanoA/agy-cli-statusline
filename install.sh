#!/bin/sh
set -e

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required but not installed." >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
  echo "Error: Either curl or wget is required but neither is installed." >&2
  exit 1
fi

download_file() {
  url="$1"
  dest="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$dest"
  else
    wget -qO "$dest" "$url"
  fi
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/.local/share/agy-statusline"
mkdir -p "$INSTALL_DIR"

if [ -f "$SCRIPT_DIR/statusline.sh" ] && [ -f "$SCRIPT_DIR/uninstall.sh" ]; then
  cp "$SCRIPT_DIR/statusline.sh" "$INSTALL_DIR/statusline.sh"
  cp "$SCRIPT_DIR/uninstall.sh" "$INSTALL_DIR/uninstall.sh"
else
  BASE_URL="https://raw.githubusercontent.com/LeanoA/agy-cli-statusline/main"
  download_file "${BASE_URL}/statusline.sh" "$INSTALL_DIR/statusline.sh"
  download_file "${BASE_URL}/uninstall.sh" "$INSTALL_DIR/uninstall.sh"
fi
chmod +x "$INSTALL_DIR/statusline.sh" "$INSTALL_DIR/uninstall.sh"

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
