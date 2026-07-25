#!/usr/bin/env bats

setup() {
  export UNINSTALL_SCRIPT="$(pwd)/uninstall.sh"
  export MOCK_HOME="$(mktemp -d)"
  export HOME="$MOCK_HOME"
  
  # Setup mock environment simulating an installed state
  export TARGET_DIR="$HOME/.local/share/agy-statusline"
  export SETTINGS_DIR="$HOME/.gemini/antigravity-cli"
  
  mkdir -p "$TARGET_DIR"
  touch "$TARGET_DIR/statusline.sh"
  touch "$TARGET_DIR/uninstall.sh"
  chmod +x "$TARGET_DIR/statusline.sh" "$TARGET_DIR/uninstall.sh"
}

teardown() {
  rm -rf "$MOCK_HOME"
}

@test "Deletes scripts and removes empty ~/.local/share/agy-statusline directory" {
  run "$UNINSTALL_SCRIPT"
  
  [ "$status" -eq 0 ]
  [ ! -f "$TARGET_DIR/statusline.sh" ]
  [ ! -f "$TARGET_DIR/uninstall.sh" ]
  [ ! -d "$TARGET_DIR" ]
}

@test "Restores settings.json from settings.json.bak if present and deletes the backup" {
  mkdir -p "$SETTINGS_DIR"
  echo '{"test": "original"}' > "$SETTINGS_DIR/settings.json.bak"
  echo '{"test": "modified"}' > "$SETTINGS_DIR/settings.json"
  
  run "$UNINSTALL_SCRIPT"
  
  [ "$status" -eq 0 ]
  [ -f "$SETTINGS_DIR/settings.json" ]
  [ ! -f "$SETTINGS_DIR/settings.json.bak" ]
  
  run cat "$SETTINGS_DIR/settings.json"
  [[ "$output" == '{"test": "original"}' ]]
}

@test "Disables status line using jq if settings.json.bak is missing" {
  mkdir -p "$SETTINGS_DIR"
  echo '{"test": "keep", "statusLine": {"enabled": true, "command": "dummy"}}' > "$SETTINGS_DIR/settings.json"
  
  run "$UNINSTALL_SCRIPT"
  
  [ "$status" -eq 0 ]
  [ -f "$SETTINGS_DIR/settings.json" ]
  
  run jq -c '.statusLine.enabled' "$SETTINGS_DIR/settings.json"
  [ "$output" = "false" ]
  
  run jq -c '.test' "$SETTINGS_DIR/settings.json"
  [ "$output" = '"keep"' ]
}

@test "Fails gracefully if jq is missing and no .bak exists" {
  mkdir -p "$SETTINGS_DIR"
  echo '{"statusLine": {"enabled": true}}' > "$SETTINGS_DIR/settings.json"
  
  export FAKE_PATH="$(mktemp -d)"
  ln -s $(which rm) "$FAKE_PATH/rm"
  ln -s $(which rmdir) "$FAKE_PATH/rmdir"
  ln -s $(which cp) "$FAKE_PATH/cp"
  ln -s $(which mv) "$FAKE_PATH/mv"
  
  run env PATH="$FAKE_PATH" "$UNINSTALL_SCRIPT"
  
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error: jq is required to update settings.json"* ]]
  
  rm -rf "$FAKE_PATH"
}

@test "Prints informative messages and is idempotent on repeat executions" {
  run "$UNINSTALL_SCRIPT"
  [ "$status" -eq 0 ]
  
  [[ "$output" == *"Removing scripts..."* ]]
  [[ "$output" == *"Reverting settings changes..."* ]]
  [[ "$output" == *"Uninstall successful!"* ]]
  
  # Idempotent execution
  run "$UNINSTALL_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Uninstall successful!"* ]]
}
