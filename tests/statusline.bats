#!/usr/bin/env bats

setup() {
  export DIR="$BATS_TEST_DIRNAME/.."
  export SCRIPT="$DIR/statusline.sh"
  export AGY_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
  unset AGY_STATUSLINE_DEBUG AGY_STATUSLINE_DEBUG_FILE AGY_STATUSLINE_DEBUG_FLAG
}

@test "wraps to multiple lines on small width (terminal_width=40)" {
  run bash -c "echo '{\"product\":\"Test\",\"model\":{\"display_name\":\"TestModel\"},\"context_window\":{\"used_percentage\":50},\"task_count\":2,\"terminal_width\":40}' | bash \"$SCRIPT\""
  
  [ "$status" -eq 0 ]
  # Model is TestModel (should NOT be hidden)
  [[ "$output" == *"TestModel"* ]]
  # Tasks is 2 (should NOT be hidden)
  [[ "$output" == *"󰦕 2"* ]]
  # Output must contain newlines indicating a wrap
  [[ "$output" == *$'\n'* ]]
}

@test "shows all segments without wrapping on large width (terminal_width=200)" {
  run bash -c "echo '{\"product\":\"Test\",\"model\":{\"display_name\":\"TestModel\"},\"context_window\":{\"used_percentage\":50},\"task_count\":2,\"terminal_width\":200,\"quota\":{\"gemini-5h\":{\"remaining_fraction\":0.5,\"reset_in_seconds\":18000},\"gemini-weekly\":{\"remaining_fraction\":0.8,\"reset_in_seconds\":604800}}}' | bash \"$SCRIPT\""
  
  [ "$status" -eq 0 ]
  # All segments shown
  [[ "$output" == *"TestModel"* ]]
  [[ "$output" == *"󰦕 2"* ]]
  [[ "$output" == *"5H: "* ]]
  
  # Ensure it is a single line (no newlines other than the final one)
  # Wait, standard output always has a trailing newline from printf "%b\n" "$OUT"
  # Let's count newlines. There should be exactly 1 newline.
  newline_count=$(echo -n "$output" | wc -l)
  [ "$newline_count" -eq 0 ] # echo -n of a single line has 0 newlines
}

@test "wraps exactly at term_width - 1" {
  # "Agy CLI" (7), " | " (3), "󰚩 B" (3). Total = 13 characters.
  # If term_width=12, 7 + 3 + 3 = 13 > 12, so it wraps.
  run bash -c "echo '{\"model\":{\"display_name\":\"B\"},\"task_count\":0,\"terminal_width\":12}' | bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  
  # Check that it wrapped
  [[ "$output" == *"Agy CLI"*$'\n'*"󰚩 B"* ]]
}

@test "get_visible_length strips \e ANSI sequences properly" {
  run bash -c "eval \"\$(awk '/get_visible_length\(\) \\{/,/^\\}/' \"\$SCRIPT\")\"; get_visible_length \"\\e[38;5;255mhello\\e[0m\"; echo \"\$REPLY\""
  [ "$status" -eq 0 ]
  [ "$output" = "5" ]
}

@test "routes to 3p-* quota keys when model is claude-sonnet" {
  run bash -c "echo '{\"product\":\"Test\",\"model\":{\"display_name\":\"claude-sonnet\"},\"context_window\":{\"used_percentage\":10},\"task_count\":0,\"terminal_width\":200,\"quota\":{\"3p-5h\":{\"remaining_fraction\":0.6,\"reset_in_seconds\":3600},\"3p-weekly\":{\"remaining_fraction\":0.9,\"reset_in_seconds\":604800}}}' | bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"5H: "* ]]
}

@test "displays N/A when all quota pairs are absent" {
  run bash -c "echo '{\"product\":\"Test\",\"model\":{\"display_name\":\"claude-sonnet\"},\"context_window\":{\"used_percentage\":10},\"task_count\":0,\"terminal_width\":200}' | bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"N/A"* ]]
}

@test "routes to gemini-* quota keys when model has version suffix (gemini-2.5-pro)" {
  run bash -c "echo '{\"product\":\"Test\",\"model\":{\"display_name\":\"gemini-2.5-pro\"},\"context_window\":{\"used_percentage\":10},\"task_count\":0,\"terminal_width\":200,\"quota\":{\"gemini-5h\":{\"remaining_fraction\":0.7,\"reset_in_seconds\":3600},\"gemini-weekly\":{\"remaining_fraction\":0.85,\"reset_in_seconds\":604800}}}' | bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"5H: "* ]]
}

@test "does not contain powerline characters or background color codes" {
  run bash -c "echo '{\"product\":\"A\",\"model\":{\"display_name\":\"B\"},\"task_count\":1,\"terminal_width\":200}' | bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  run bash -c "echo \"\$output\" | grep -E '||||||'"
  [ "$status" -eq 1 ]
  run bash -c "echo \"\$output\" | grep -E '\\\e\[48;5;'"
  [ "$status" -eq 1 ]
}

@test "contains minimalist separator ( | )" {
  run bash -c "echo '{\"product\":\"A\",\"model\":{\"display_name\":\"B\"},\"task_count\":1,\"terminal_width\":200}' | bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  [[ "$output" == *" | "* ]]
}

@test "does not contain system metrics" {
  run bash -c "echo '{\"product\":\"A\",\"model\":{\"display_name\":\"B\"},\"task_count\":1,\"terminal_width\":200}' | bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  [[ ! "$output" == *"CPU"* ]]
  [[ ! "$output" == *"RAM"* ]]
  [[ ! "$output" == *"Bat"* ]]
}

@test "does not contain legacy emojis" {
  bash -c "echo '{\"product\":\"A\",\"model\":{\"display_name\":\"B\"},\"task_count\":1,\"terminal_width\":200,\"context_window\":{\"used_percentage\":10},\"quota\":{\"gemini-5h\":{\"remaining_fraction\":0.7,\"reset_in_seconds\":3600}}}' | bash \"$SCRIPT\"" > /tmp/statusline_test.out
  
  run grep -q '🎩' /tmp/statusline_test.out
  [ "$status" -eq 1 ]
  
  run grep -q '🤖' /tmp/statusline_test.out
  [ "$status" -eq 1 ]
  
  run grep -q '🧠' /tmp/statusline_test.out
  [ "$status" -eq 1 ]
  
  bash -c "echo '{\"product\":\"A\",\"model\":{\"display_name\":\"gemini\"},\"task_count\":1,\"terminal_width\":200,\"context_window\":{\"used_percentage\":10},\"quota\":{\"gemini-5h\":{\"remaining_fraction\":0.7,\"reset_in_seconds\":3600}}}' | bash \"$SCRIPT\"" > /tmp/statusline_test.out
  
  run grep -q '⌛' /tmp/statusline_test.out
  [ "$status" -eq 1 ]
}

@test "Workers segment: neither icon present when subagents and tasks are empty/0" {
  run bash -c "echo '{\"product\":\"A\",\"model\":{\"display_name\":\"B\"},\"terminal_width\":200}' | bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  [[ ! "$output" == *"󱙺"* ]]
  [[ ! "$output" == *"󰦕"* ]]
}

@test "Workers segment: shows subagent count when .subagents has 3 elements" {
  run bash -c "echo '{\"product\":\"A\",\"model\":{\"display_name\":\"B\"},\"subagents\":[{\"status\":\"running\"},{\"status\":\"active\"},{\"status\":\"running\"}],\"terminal_width\":200}' | bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"󱙺 3"* ]]
  [[ ! "$output" == *"󰦕"* ]]
}

@test "Workers segment: shows task count when .task_count is 2" {
  run bash -c "echo '{\"product\":\"A\",\"model\":{\"display_name\":\"B\"},\"task_count\":2,\"terminal_width\":200}' | bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  [[ ! "$output" == *"󱙺"* ]]
  [[ "$output" == *"󰦕 2"* ]]
}

@test "Workers segment: shows both when both are > 0" {
  run bash -c "echo '{\"product\":\"A\",\"model\":{\"display_name\":\"B\"},\"subagents\":[{\"status\":\"running\"},{\"status\":\"active\"},{\"status\":\"running\"}],\"task_count\":2,\"terminal_width\":200}' | bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"󱙺 3 󰦕 2"* ]]
}

@test "Status Indicator: shows green idle icon when agent_state is idle" {
  run bash -c "echo '{\"agent_state\":\"idle\",\"product\":\"A\",\"model\":{\"display_name\":\"B\"},\"terminal_width\":200}' | bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"38;2;183;204;133m"* ]]
}

@test "Status Indicator: shows yellow thinking icon when agent_state is thinking" {
  run bash -c "echo '{\"agent_state\":\"thinking\",\"product\":\"A\",\"model\":{\"display_name\":\"B\"},\"terminal_width\":200}' | bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"38;2;229;192;123m󰟷"* ]]
}

@test "Status Indicator: defaults to idle icon when agent_state is missing" {
  run bash -c "echo '{\"product\":\"A\",\"model\":{\"display_name\":\"B\"},\"terminal_width\":200}' | bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"38;2;183;204;133m"* ]]
}

@test "Workers segment: subagent count ONLY includes running and active statuses" {
  run bash -c "echo '{\"product\":\"A\",\"model\":{\"display_name\":\"B\"},\"subagents\":[{\"status\":\"running\"},{\"status\":\"dead\"},{\"status\":\"active\"},{\"status\":\"completed\"}],\"terminal_width\":200}' | bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"󱙺 2"* ]]
}

@test "App Name: always outputs Agy CLI and ignores JSON persona fields" {
  run bash -c "echo '{\"product\":\"FallbackProduct\",\"agent\":{\"display_name\":\"DispName\",\"name\":\"RawName\"},\"model\":{\"display_name\":\"B\"},\"terminal_width\":200}' | bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"Agy CLI"* ]]
  [[ ! "$output" == *"DispName"* ]]
  [[ ! "$output" == *"RawName"* ]]
  [[ ! "$output" == *"FallbackProduct"* ]]
}

@test "Classic Mode: uses standard unicode/emoji characters instead of Nerd Fonts" {
  run bash -c "echo '{\"agent_state\":\"thinking\",\"product\":\"Test\",\"model\":{\"display_name\":\"gemini\"},\"context_window\":{\"used_percentage\":50},\"task_count\":2,\"subagents\":[{\"status\":\"running\"}],\"terminal_width\":200,\"quota\":{\"gemini-5h\":{\"remaining_fraction\":0.5,\"reset_in_seconds\":18000}}}' | AGY_CLASSIC_MODE=1 bash \"$SCRIPT\""
  
  [ "$status" -eq 0 ]
  # Assert that Nerd Font icons are NOT present
  [[ ! "$output" == *""* ]]
  [[ ! "$output" == *"󰟷"* ]]
  [[ ! "$output" == *""* ]]
  [[ ! "$output" == *""* ]]
  [[ ! "$output" == *"󰚩"* ]]
  [[ ! "$output" == *""* ]]
  [[ ! "$output" == *""* ]]
  [[ ! "$output" == *"󰘦"* ]]
  [[ ! "$output" == *"󱙺"* ]]
  [[ ! "$output" == *"󰦕"* ]]
  [[ ! "$output" == *"󱎫"* ]]
  [[ ! "$output" == *"󰆧"* ]]
  
  # Assert that fallback characters are present
  [[ "$output" == *"[THINK]"* ]]  # thinking state
  [[ "$output" == *"[MDL]"* ]]    # model
  [[ "$output" == *"[CTX]"* ]]    # context
  [[ "$output" == *"[SUB]"* ]]    # subagents
  [[ "$output" == *"[TSK]"* ]]    # tasks
  [[ ! "$output" == *"⌛"* ]]     # quota reset
}

@test "Git: uses vcs payload when present" {
  run bash -c "echo '{\"product\":\"A\",\"model\":{\"display_name\":\"B\"},\"terminal_width\":200,\"vcs\":{\"branch\":\"main-test\",\"dirty\":true}}' | bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"main-test"* ]] || false
  [[ "$output" == *""* ]] || false
}

@test "Git: falls back to native git when vcs is omitted but cwd is present" {
  repo_dir=$(mktemp -d)
  git init "$repo_dir"
  git -C "$repo_dir" config user.name "Test User"
  git -C "$repo_dir" config user.email "test@example.com"
  git -C "$repo_dir" commit --allow-empty -m "init"
  git -C "$repo_dir" branch -M "fallback-branch"
  
  run bash -c "echo '{\"product\":\"A\",\"model\":{\"display_name\":\"B\"},\"terminal_width\":200,\"cwd\":\"$repo_dir\"}' | bash \"$SCRIPT\""
  rm -rf "$repo_dir"
  
  [ "$status" -eq 0 ]
  [[ "$output" == *"fallback-branch"* ]] || false
  [[ ! "$output" == *""* ]] || false
}

@test "Git: native fallback detects dirty state" {
  repo_dir=$(mktemp -d)
  git init "$repo_dir"
  git -C "$repo_dir" config user.name "Test User"
  git -C "$repo_dir" config user.email "test@example.com"
  git -C "$repo_dir" commit --allow-empty -m "init"
  git -C "$repo_dir" branch -M "fallback-branch"
  touch "$repo_dir/dirty_file"
  git -C "$repo_dir" add "$repo_dir/dirty_file"
  
  run bash -c "echo '{\"product\":\"A\",\"model\":{\"display_name\":\"B\"},\"terminal_width\":200,\"cwd\":\"$repo_dir\"}' | bash \"$SCRIPT\""
  rm -rf "$repo_dir"
  
  [ "$status" -eq 0 ]
  [[ "$output" == *"fallback-branch"* ]] || false
  [[ "$output" == *""* ]] || false
}

@test "Git: native fallback in detached HEAD state" {
  repo_dir=$(mktemp -d)
  git init "$repo_dir"
  git -C "$repo_dir" config user.name "Test User"
  git -C "$repo_dir" config user.email "test@example.com"
  git -C "$repo_dir" commit --allow-empty -m "init"
  git -C "$repo_dir" commit --allow-empty -m "second"
  git -C "$repo_dir" checkout HEAD~1
  
  short_sha=$(git -C "$repo_dir" rev-parse --short HEAD)
  
  run bash -c "echo '{\"product\":\"A\",\"model\":{\"display_name\":\"B\"},\"terminal_width\":200,\"cwd\":\"$repo_dir\"}' | bash \"$SCRIPT\""
  rm -rf "$repo_dir"
  
  [ "$status" -eq 0 ]
  [[ "$output" == *" $short_sha"* ]] || false
}

@test "Git: incomplete payload missing cwd shows no git info" {
  run bash -c "echo '{\"product\":\"A\",\"model\":{\"display_name\":\"B\"},\"terminal_width\":200}' | bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  [[ ! "$output" == *""* ]] || false
}

@test "debug capture is off by default and writes nothing" {
  export AGY_STATUSLINE_DEBUG_FILE="$BATS_TEST_TMPDIR/payloads.jsonl"
  unset AGY_STATUSLINE_DEBUG
  run bash -c "echo '{\"model\":{\"display_name\":\"M\"},\"terminal_width\":200}' | bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  [ ! -e "$AGY_STATUSLINE_DEBUG_FILE" ]
}

@test "debug capture appends one JSONL line per invocation with ts and payload" {
  export AGY_STATUSLINE_DEBUG=1
  export AGY_STATUSLINE_DEBUG_FILE="$BATS_TEST_TMPDIR/sub/payloads.jsonl"
  run bash -c "echo '{\"model\":{\"display_name\":\"M\"},\"quota\":{\"x-5h\":{\"remaining_fraction\":0.5}}}' | bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  run bash -c "echo '{\"model\":{\"display_name\":\"N\"}}' | bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$AGY_STATUSLINE_DEBUG_FILE" | tr -d ' ')" -eq 2 ]
  run jq -r 'select(.payload.model.display_name == "M") | .payload.quota["x-5h"].remaining_fraction' "$AGY_STATUSLINE_DEBUG_FILE"
  [ "$output" = "0.5" ]
  run jq -r '.ts | type' "$AGY_STATUSLINE_DEBUG_FILE"
  [ "${lines[0]}" = "string" ]
}

@test "debug capture failure does not break rendering" {
  export AGY_STATUSLINE_DEBUG=1
  export AGY_STATUSLINE_DEBUG_FILE="/dev/null/nope/payloads.jsonl"
  run bash -c "echo '{\"model\":{\"display_name\":\"Still\"},\"terminal_width\":200}' | bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"Still"* ]]
}

@test "debug capture activates when debug.on sentinel file exists without env var" {
  unset AGY_STATUSLINE_DEBUG
  mkdir -p "$AGY_CACHE_DIR"
  : > "$AGY_CACHE_DIR/debug.on"
  run bash -c "echo '{\"model\":{\"display_name\":\"Gemini 4 Argon (High)\"},\"quota\":{\"argon-wk\":{\"remaining_fraction\":0.75}}}' | bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  [ -f "$AGY_CACHE_DIR/payloads.jsonl" ]
  run jq -r '.payload.model.display_name' "$AGY_CACHE_DIR/payloads.jsonl"
  [ "$output" = "Gemini 4 Argon (High)" ]
}
