#!/usr/bin/env bats

setup() {
  export DIR="$BATS_TEST_DIRNAME/.."
  export SCRIPT="$DIR/statusline.sh"
  export AGY_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
  export AGY_SETTINGS_FILE="$BATS_TEST_TMPDIR/settings.json"
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

@test "Quota: routes Gemini 4 Argon (High) to gemini-argon-wtu-weekly and shows 5H: N/A fallback" {
  payload='{"model":{"display_name":"Gemini 4 Argon (High)"},"terminal_width":200,"quota":{"3p-5h":{"remaining_fraction":1,"reset_in_seconds":17742},"3p-weekly":{"remaining_fraction":1,"reset_in_seconds":604542},"gemini-5h":{"remaining_fraction":0.83695006,"reset_in_seconds":8921},"gemini-argon-wtu-weekly":{"remaining_fraction":0.7551988,"reset_in_seconds":567381},"gemini-weekly":{"remaining_fraction":0.85892534,"reset_in_seconds":565847}}}'
  run bash -c "printf '%s' '$payload' | bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"5H: N/A"* ]] || false
  [[ "$output" == *"7D: "*"75%"*"6d 13h"* ]] || false
  [[ "$output" != *"85%"* ]] || false
}

@test "Quota: routes Argon 5h bucket when present alongside argon weekly" {
  payload='{"model":{"display_name":"Gemini 4 Argon (High)"},"terminal_width":200,"quota":{"gemini-argon-wtu-5h":{"remaining_fraction":0.61,"reset_in_seconds":3600},"gemini-argon-wtu-weekly":{"remaining_fraction":0.7551988,"reset_in_seconds":567381}}}'
  run bash -c "printf '%s' '$payload' | bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"5H: "*"61%"*"1h"* ]] || false
  [[ "$output" == *"7D: "*"75%"*"6d 13h"* ]] || false
}

@test "Quota: routes non-Argon Gemini (Gemini 4 Hydrogen) to gemini-5h and gemini-weekly even when argon bucket is present" {
  payload='{"model":{"display_name":"Gemini 4 Hydrogen (High)"},"terminal_width":200,"quota":{"3p-5h":{"remaining_fraction":1,"reset_in_seconds":17742},"3p-weekly":{"remaining_fraction":1,"reset_in_seconds":604542},"gemini-5h":{"remaining_fraction":0.83695006,"reset_in_seconds":8921},"gemini-argon-wtu-weekly":{"remaining_fraction":0.7551988,"reset_in_seconds":567381},"gemini-weekly":{"remaining_fraction":0.85892534,"reset_in_seconds":565847}}}'
  run bash -c "printf '%s' '$payload' | bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"5H: "*"83%"* ]] || false
  [[ "$output" == *"7D: "*"85%"* ]] || false
  [[ "$output" != *"75%"* ]] || false
}

@test "Quota staleness: shows ⟳4m during active turn when quota is unchanged for >=120s" {
  payload='{"agent_state":"working","model":{"display_name":"gemini-2.5-pro"},"terminal_width":200,"quota":{"gemini-5h":{"remaining_fraction":0.5,"reset_in_seconds":3600},"gemini-weekly":{"remaining_fraction":0.8,"reset_in_seconds":86400}}}'
  run bash -c "printf '%s' '$payload' | AGY_STATUSLINE_NOW=1000 bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  [[ "$output" != *"⟳"* ]] || false

  run bash -c "printf '%s' '$payload' | AGY_STATUSLINE_NOW=1240 bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"5H: "*"50%"*"⟳4m"* ]] || false
}

@test "Quota staleness: hides staleness badge when agent is idle or when quota value changes" {
  payload_work='{"agent_state":"working","model":{"display_name":"gemini-2.5-pro"},"terminal_width":200,"quota":{"gemini-5h":{"remaining_fraction":0.5,"reset_in_seconds":3600}}}'
  payload_idle='{"agent_state":"idle","model":{"display_name":"gemini-2.5-pro"},"terminal_width":200,"quota":{"gemini-5h":{"remaining_fraction":0.5,"reset_in_seconds":3600}}}'
  payload_fresh='{"agent_state":"working","model":{"display_name":"gemini-2.5-pro"},"terminal_width":200,"quota":{"gemini-5h":{"remaining_fraction":0.45,"reset_in_seconds":3500}}}'

  run bash -c "printf '%s' '$payload_work' | AGY_STATUSLINE_NOW=1000 bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  run bash -c "printf '%s' '$payload_idle' | AGY_STATUSLINE_NOW=1300 bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  [[ "$output" != *"⟳"* ]] || false

  run bash -c "printf '%s' '$payload_fresh' | AGY_STATUSLINE_NOW=1300 bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"45%"* ]] || false
  [[ "$output" != *"⟳"* ]] || false
}

@test "Quota staleness: Classic Mode uses ASCII (~4m) and cache I/O failure is silent" {
  payload='{"agent_state":"thinking","model":{"display_name":"gemini-2.5-pro"},"terminal_width":200,"quota":{"gemini-5h":{"remaining_fraction":0.5,"reset_in_seconds":3600}}}'
  run bash -c "printf '%s' '$payload' | AGY_CLASSIC_MODE=1 AGY_STATUSLINE_NOW=1000 bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  run bash -c "printf '%s' '$payload' | AGY_CLASSIC_MODE=1 AGY_STATUSLINE_NOW=1240 bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"~4m"* ]] || false
  [[ "$output" != *"⟳"* ]] || false

  run bash -c "printf '%s' '$payload' | AGY_CACHE_DIR=/dev/null/nope AGY_STATUSLINE_NOW=1240 bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"50%"* ]] || false
}

@test "Quota burn-rate: projects remaining percentage and triggers WARN/CRIT colors during long active turn" {
  p1='{"agent_state":"idle","model":{"display_name":"gemini-2.5-pro"},"terminal_width":200,"quota":{"gemini-5h":{"remaining_fraction":0.55,"reset_in_seconds":3600}}}'
  p2='{"agent_state":"working","model":{"display_name":"gemini-2.5-pro"},"terminal_width":200,"quota":{"gemini-5h":{"remaining_fraction":0.45,"reset_in_seconds":3500}}}'

  run bash -c "printf '%s' '$p1' | AGY_STATUSLINE_NOW=1000 bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  run bash -c "printf '%s' '$p2' | AGY_STATUSLINE_NOW=1100 bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"45%"* ]] || false

  # 200s into active turn with frozen 45%: burn rate 10%/100s -> ~25% (WARN color 38;5;214m)
  run bash -c "printf '%s' '$p2' | AGY_STATUSLINE_NOW=1300 bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"38;5;214m~25%"*"⟳3m"* ]] || false

  # 320s into active turn with frozen 45%: projected ~13% (CRIT color 38;5;196m)
  run bash -c "printf '%s' '$p2' | AGY_STATUSLINE_NOW=1420 bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"38;5;196m~13%"* ]] || false
}

@test "Quota burn-rate: uses mid-turn live token growth to project faster quota drop" {
  p1='{"agent_state":"idle","model":{"display_name":"gemini-2.5-pro"},"context_window":{"total_input_tokens":10000,"total_output_tokens":0},"terminal_width":200,"quota":{"gemini-5h":{"remaining_fraction":0.50,"reset_in_seconds":3600}}}'
  p2='{"agent_state":"working","model":{"display_name":"gemini-2.5-pro"},"context_window":{"total_input_tokens":20000,"total_output_tokens":0},"terminal_width":200,"quota":{"gemini-5h":{"remaining_fraction":0.45,"reset_in_seconds":3300}}}'
  p3='{"agent_state":"working","model":{"display_name":"gemini-2.5-pro"},"context_window":{"total_input_tokens":80000,"total_output_tokens":0},"terminal_width":200,"quota":{"gemini-5h":{"remaining_fraction":0.45,"reset_in_seconds":3180}}}'

  run bash -c "printf '%s' '$p1' | AGY_STATUSLINE_NOW=1000 bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  run bash -c "printf '%s' '$p2' | AGY_STATUSLINE_NOW=1300 bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  run bash -c "printf '%s' '$p3' | AGY_STATUSLINE_NOW=1420 bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"38;5;196m~15%"* ]] || false
}

@test "Orchestrator: formats planner and executor from AGY_SETTINGS_FILE and routes Gemini quotas" {
  cat > "$AGY_SETTINGS_FILE" <<'EOF'
{"model":"Orchestrator (Neon)","orchestrator":{"planner":"Gemini 4 Carbon (Medium)","executor":"Gemini 4 Hydrogen (High)"}}
EOF
  payload='{"model":{"id":"Orchestrator (Neon)","display_name":"Orchestrator (Neon)"},"terminal_width":200,"quota":{"3p-5h":{"remaining_fraction":1,"reset_in_seconds":18000},"3p-weekly":{"remaining_fraction":1,"reset_in_seconds":604800},"gemini-5h":{"remaining_fraction":0.81,"reset_in_seconds":8900},"gemini-weekly":{"remaining_fraction":0.93,"reset_in_seconds":565000}}}'
  run bash -c "printf '%s' '$payload' | bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"Orch: Carbon (Med) → Hydrogen (High)"* ]] || false
  [[ "$output" != *"Neon"* ]] || false
  [[ "$output" == *"81%"* ]] || false
  [[ "$output" == *"93%"* ]] || false
  [[ "$output" != *"100%"* ]] || false

  run bash -c "printf '%s' '$payload' | AGY_CLASSIC_MODE=1 bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"Orch: Carbon (Med) -> Hydrogen (High)"* ]] || false
}

@test "Orchestrator: falls back gracefully when AGY_SETTINGS_FILE is missing and still routes Neon to Gemini quotas" {
  rm -f "$AGY_SETTINGS_FILE"
  payload='{"model":{"id":"Orchestrator (Neon)","display_name":"Orchestrator (Neon)"},"terminal_width":200,"quota":{"3p-5h":{"remaining_fraction":1,"reset_in_seconds":18000},"3p-weekly":{"remaining_fraction":1,"reset_in_seconds":604800},"gemini-5h":{"remaining_fraction":0.81,"reset_in_seconds":8900},"gemini-weekly":{"remaining_fraction":0.93,"reset_in_seconds":565000}}}'
  run bash -c "printf '%s' '$payload' | bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"Orchestrator (Neon)"* ]] || false
  [[ "$output" == *"81%"* ]] || false
  [[ "$output" == *"93%"* ]] || false
  [[ "$output" != *"100%"* ]] || false
}

@test "Orchestrator: routes quota family from active role when planner is 3p (Claude Opus)" {
  cat > "$AGY_SETTINGS_FILE" <<'EOF'
{"orchestrator":{"planner":"Claude Opus 5.5 (Medium)","executor":"Gemini 4 Hydrogen (High)"}}
EOF
  p_plan='{"model":{"display_name":"Orchestrator (Neon)"},"permission_mode":"plan","terminal_width":200,"quota":{"3p-5h":{"remaining_fraction":0.42,"reset_in_seconds":3600},"3p-weekly":{"remaining_fraction":0.77,"reset_in_seconds":604800},"gemini-5h":{"remaining_fraction":0.81,"reset_in_seconds":8900},"gemini-weekly":{"remaining_fraction":0.93,"reset_in_seconds":565000}}}'
  run bash -c "printf '%s' '$p_plan' | bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"Orch: Opus 5.5 (Med) → Hydrogen (High)"* ]] || false
  [[ "$output" == *"42%"* ]] || false
  [[ "$output" == *"77%"* ]] || false
  [[ "$output" != *"81%"* ]] || false

  p_exec='{"model":{"display_name":"Orchestrator (Neon)"},"cycle_mode":"auto","terminal_width":200,"quota":{"3p-5h":{"remaining_fraction":0.42,"reset_in_seconds":3600},"3p-weekly":{"remaining_fraction":0.77,"reset_in_seconds":604800},"gemini-5h":{"remaining_fraction":0.81,"reset_in_seconds":8900},"gemini-weekly":{"remaining_fraction":0.93,"reset_in_seconds":565000}}}'
  run bash -c "printf '%s' '$p_exec' | bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"81%"* ]] || false
  [[ "$output" == *"93%"* ]] || false
  [[ "$output" != *"42%"* ]] || false
}

@test "Quota: Argon falls back to unified gemini-5h and gemini-weekly when no argon bucket exists" {
  payload='{"model":{"display_name":"Gemini 4 Argon (High)"},"terminal_width":200,"quota":{"3p-5h":{"remaining_fraction":1,"reset_in_seconds":18000},"3p-weekly":{"remaining_fraction":1,"reset_in_seconds":604800},"gemini-5h":{"remaining_fraction":0.81,"reset_in_seconds":8900},"gemini-weekly":{"remaining_fraction":0.93,"reset_in_seconds":565000}}}'
  run bash -c "printf '%s' '$payload' | bash \"$SCRIPT\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"5H: "*"81%"* ]] || false
  [[ "$output" == *"7D: "*"93%"* ]] || false
  [[ "$output" != *"5H: N/A"* ]] || false
}
