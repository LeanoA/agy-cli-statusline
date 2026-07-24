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
  run env PATH="$FAKE_PATH" "$INSTALL_SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error: jq is required but not installed."* ]]
  rm -rf "$FAKE_PATH"
}

@test "Creates ~/.local/share/agy-statusline and copies executable" {
  run "$INSTALL_SCRIPT"
  [ "$status" -eq 0 ]
  [ -d "$HOME/.local/share/agy-statusline" ]
  [ -f "$HOME/.local/share/agy-statusline/statusline.sh" ]
  [ -x "$HOME/.local/share/agy-statusline/statusline.sh" ]
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
