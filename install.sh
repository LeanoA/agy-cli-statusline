#!/bin/sh

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required but not installed." >&2
  exit 1
fi

mkdir -p "$HOME/.local/bin"

cp statusline.sh "$HOME/.local/bin/agy-statusline"
chmod +x "$HOME/.local/bin/agy-statusline"

echo "Installation successful!"
echo "Please add the following line to your ~/.zshrc or ~/.bashrc:"
echo 'export PATH="$HOME/.local/bin:$PATH"'
