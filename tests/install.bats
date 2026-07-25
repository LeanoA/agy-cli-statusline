#!/usr/bin/env bats

setup() {
  export INSTALL_SCRIPT="$(pwd)/install.sh"
  export MOCK_HOME="$(mktemp -d)"
  export HOME="$MOCK_HOME"
}

teardown() {
  rm -rf "$MOCK_HOME"
}

@test "Fails if jq is missing" {
  export FAKE_PATH="$(mktemp -d)"
  ln -s $(which curl) "$FAKE_PATH/curl"
  run env PATH="$FAKE_PATH" "$INSTALL_SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error: jq is required but not installed."* ]]
  rm -rf "$FAKE_PATH"
}

@test "Fails if neither curl nor wget is missing" {
  export FAKE_PATH="$(mktemp -d)"
  ln -s $(which jq) "$FAKE_PATH/jq"
  run env PATH="$FAKE_PATH" "$INSTALL_SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error: Either curl or wget is required but neither is installed."* ]]
  rm -rf "$FAKE_PATH"
}

@test "Creates ~/.local/share/agy-statusline and copies executables" {
  run "$INSTALL_SCRIPT"
  [ "$status" -eq 0 ]
  [ -d "$HOME/.local/share/agy-statusline" ]
  [ -f "$HOME/.local/share/agy-statusline/statusline.sh" ]
  [ -x "$HOME/.local/share/agy-statusline/statusline.sh" ]
  [ -f "$HOME/.local/share/agy-statusline/uninstall.sh" ]
  [ -x "$HOME/.local/share/agy-statusline/uninstall.sh" ]
}

@test "Scaffolds settings.json from scratch if it did not exist" {
  run "$INSTALL_SCRIPT"
  [ "$status" -eq 0 ]
  [ -d "$HOME/.gemini/antigravity-cli" ]
  [ -f "$HOME/.gemini/antigravity-cli/settings.json" ]
  
  run jq -c '.statusLine' "$HOME/.gemini/antigravity-cli/settings.json"
  [[ "$output" == '{"type":"","command":"'"$HOME"'/.local/share/agy-statusline/statusline.sh","enabled":true}' ]]
}

@test "Creates settings.json.bak and patches existing settings.json" {
  mkdir -p "$HOME/.gemini/antigravity-cli"
  echo '{"existingKey": "existingValue"}' > "$HOME/.gemini/antigravity-cli/settings.json"
  
  run "$INSTALL_SCRIPT"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.gemini/antigravity-cli/settings.json.bak" ]
  
  run cat "$HOME/.gemini/antigravity-cli/settings.json.bak"
  [[ "$output" == '{"existingKey": "existingValue"}' ]]
  
  run jq -c '.existingKey' "$HOME/.gemini/antigravity-cli/settings.json"
  [[ "$output" == '"existingValue"' ]]
  
  run jq -c '.statusLine.enabled' "$HOME/.gemini/antigravity-cli/settings.json"
  [[ "$output" == "true" ]]
}

@test "Does not print instructions to modify shell profile" {
  run "$INSTALL_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Installation successful!"* ]]
  [[ "$output" != *".zshrc"* ]]
  [[ "$output" != *".bashrc"* ]]
  [[ "$output" != *"export PATH"* ]]
}

@test "Downloads files from GitHub if not found locally" {
  export TEST_DIR="$(mktemp -d)"
  cp "$INSTALL_SCRIPT" "$TEST_DIR/install.sh"
  
  export FAKE_PATH="$(mktemp -d)"
  for cmd in jq mkdir cp chmod mv rm cat dirname pwd sh; do
    if which $cmd >/dev/null 2>&1; then
      ln -s $(which $cmd) "$FAKE_PATH/$cmd"
    fi
  done
  
  cat << 'EOF' > "$FAKE_PATH/curl"
#!/bin/sh
while [ $# -gt 0 ]; do
  case "$1" in
    -o) DEST="$2"; shift 2 ;;
    -*) shift 1 ;;
    *) URL="$1"; shift 1 ;;
  esac
done
echo "MOCK_CONTENT_FOR_${URL}" > "$DEST"
EOF
  chmod +x "$FAKE_PATH/curl"

  cd "$TEST_DIR"
  run env PATH="$FAKE_PATH" ./install.sh
  echo "status: $status" >&2
  echo "output: $output" >&2
  [ "$status" -eq 0 ]
  
  run cat "$HOME/.local/share/agy-statusline/statusline.sh"
  echo "cat statusline status: $status output: $output" >&2
  [[ "$output" == *"MOCK_CONTENT_FOR_https://raw.githubusercontent.com/LeanoA/agy-cli-statusline/main/statusline.sh"* ]]
  
  run cat "$HOME/.local/share/agy-statusline/uninstall.sh"
  echo "cat uninstall status: $status output: $output" >&2
  [[ "$output" == *"MOCK_CONTENT_FOR_https://raw.githubusercontent.com/LeanoA/agy-cli-statusline/main/uninstall.sh"* ]]
}
