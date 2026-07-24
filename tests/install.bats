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

@test "Creates ~/.local/bin if missing" {
  run "$INSTALL_SCRIPT"
  [ "$status" -eq 0 ]
  [ -d "$HOME/.local/bin" ]
}

@test "Copies executable, renames it, and makes it executable" {
  run "$INSTALL_SCRIPT"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.local/bin/agy-statusline" ]
  [ -x "$HOME/.local/bin/agy-statusline" ]
}

@test "Overwrites existing installation automatically" {
  mkdir -p "$HOME/.local/bin"
  echo "old version" > "$HOME/.local/bin/agy-statusline"
  
  run "$INSTALL_SCRIPT"
  [ "$status" -eq 0 ]
  
  run cat "$HOME/.local/bin/agy-statusline"
  [[ "$output" != "old version" ]]
  [[ "$output" == *"#!/usr/bin/env bash"* ]]
}

@test "Prints post-installation instructions" {
  run "$INSTALL_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Installation successful!"* ]]
  [[ "$output" == *'export PATH="$HOME/.local/bin:$PATH"'* ]]
}
