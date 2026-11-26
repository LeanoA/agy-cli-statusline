#!/usr/bin/env bash

set -Eeuo pipefail

# --- 1. Dependencies Check ---
if ! command -v jq >/dev/null 2>&1; then
    printf "jq not found\n"
    exit 0
fi

# --- 2. Read JSON payload ---
if ! json_payload=$(cat); then
    exit 0
fi

# Ensure it's not empty
if [[ -z "$json_payload" ]]; then
    exit 0
fi

# --- 2b. Optional payload capture (opt-in via AGY_STATUSLINE_DEBUG=1 or debug.on sentinel) ---
# Appends {ts, payload} as one JSONL line. Failures never affect rendering.
AGY_CACHE_DIR="${AGY_CACHE_DIR:-$HOME/.cache/agy-statusline}"
AGY_DEBUG_FILE="${AGY_STATUSLINE_DEBUG_FILE:-$AGY_CACHE_DIR/payloads.jsonl}"
AGY_DEBUG_FLAG="${AGY_STATUSLINE_DEBUG_FLAG:-$(dirname "$AGY_DEBUG_FILE")/debug.on}"
AGY_SETTINGS_FILE="${AGY_SETTINGS_FILE:-$HOME/.gemini/antigravity-cli/settings.json}"

capture_payload() {
    local file="$AGY_DEBUG_FILE"
    local line
    mkdir -p "$(dirname "$file")" 2>/dev/null || return 0
    line=$(printf "%s" "$json_payload" | jq -c --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{ts: $ts, payload: .}' 2>/dev/null) || return 0
    printf "%s\n" "$line" >> "$file" 2>/dev/null || return 0
}

if [[ "${AGY_STATUSLINE_DEBUG:-0}" == "1" || -f "$AGY_DEBUG_FLAG" ]]; then
    capture_payload || true
fi

# --- 3. Extract JSON Fields ---
agent_state=$(printf "%s" "$json_payload" | jq -r '.agent_state // "idle"')
model=$(printf "%s" "$json_payload" | jq -r '.model.display_name // "unknown"')
permission_mode=$(printf "%s" "$json_payload" | jq -r '.permission_mode // .cycle_mode // empty')
ctx_pct=$(printf "%s" "$json_payload" | jq -r '.context_window.used_percentage // 0 | floor')
git_branch=$(printf "%s" "$json_payload" | jq -r '.vcs?.branch? // empty')
git_dirty=$(printf "%s" "$json_payload" | jq -r '.vcs?.dirty? // false')
cwd=$(printf "%s" "$json_payload" | jq -r '.cwd // empty')

if [[ -z "$git_branch" && -n "$cwd" ]]; then
    if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git_branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
        if [[ -z "$git_branch" ]]; then
            git_branch=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
        fi
        
        if [[ -n "$(git -C "$cwd" status --porcelain -uno 2>/dev/null)" ]]; then
            git_dirty="true"
        else
            git_dirty="false"
        fi
    fi
fi
term_width=$(printf "%s" "$json_payload" | jq -r '.terminal_width // 80')
task_count=$(printf "%s" "$json_payload" | jq -r '.task_count // 0')
subagent_count=$(printf "%s" "$json_payload" | jq -r '[ .subagents[]? | select(.status == "running" or .status == "active") ] | length')

shorten_orch_model() {
    local m="$1"
    local nocase_set=0
    shopt -q nocasematch && nocase_set=1 || shopt -s nocasematch
    if [[ "$m" =~ ^(Gemini\ 4|Gemini|Claude)[[:space:]]+(.+)$ ]]; then
        m="${BASH_REMATCH[2]}"
    fi
    if [[ "$m" =~ ^(.*)\(Medium\)(.*)$ ]]; then
        m="${BASH_REMATCH[1]}(Med)${BASH_REMATCH[2]}"
    fi
    (( nocase_set == 0 )) && shopt -u nocasematch
    printf "%s" "$m"
}

quota_model="$model"
if [[ "$model" =~ ^[Oo]rchestrator ]]; then
    orch_planner=""
    orch_executor=""
    IFS=$'\t' read -r orch_planner orch_executor <<< "$(printf "%s" "$json_payload" | jq -r '
        if (.orchestrator? | type) == "object" then
            "\(.orchestrator.planner // "")\t\(.orchestrator.executor // "")"
        else "" end
    ' 2>/dev/null || true)"
    if [[ ( -z "$orch_planner" || -z "$orch_executor" ) && -f "$AGY_SETTINGS_FILE" ]]; then
        IFS=$'\t' read -r orch_planner orch_executor <<< "$(jq -r '
            "\(.orchestrator.planner // "")\t\(.orchestrator.executor // "")"
        ' "$AGY_SETTINGS_FILE" 2>/dev/null || true)"
    fi
    if [[ -n "$orch_planner" && -n "$orch_executor" ]]; then
        orch_arrow="→"
        if [[ "${AGY_CLASSIC_MODE:-0}" == "1" ]]; then
            orch_arrow="->"
        fi
        model="Orch: $(shorten_orch_model "$orch_planner") ${orch_arrow} $(shorten_orch_model "$orch_executor")"
        if [[ -n "$permission_mode" && "$permission_mode" != "plan" ]]; then
            quota_model="$orch_executor"
        else
            quota_model="$orch_planner"
        fi
    fi
fi

# Dynamically resolve 5h and weekly quota buckets for the active model
resolve_quota_bucket() {
    local window_regex="$1"
    local family_regex="$2"
    local exclude_regex="${3:-}"
    printf "%s" "$json_payload" | jq -r \
        --arg win "$window_regex" \
        --arg fam "$family_regex" \
        --arg exc "$exclude_regex" '
        (.quota // {}) | to_entries
        | map(select(
            (.key | test($win; "i")) and
            (.key | test($fam; "i")) and
            (($exc == "") or ((.key | test($exc; "i")) | not)) and
            (.value.remaining_fraction != null)
          ))
        | first // empty
        | "\(.key)\t\(.value.remaining_fraction)\t\((.value.remaining_fraction * 100 | floor))\t\(.value.reset_in_seconds // "")"
    '
}

bucket_5h=""
bucket_wk=""
if [[ "$quota_model" =~ [Aa][Rr][Gg][Oo][Nn] ]]; then
    bucket_5h=$(resolve_quota_bucket "5h$" "argon")
    bucket_wk=$(resolve_quota_bucket "(weekly|7d|wk)$" "argon")
    if [[ -z "$bucket_5h" && -z "$bucket_wk" ]]; then
        bucket_5h=$(resolve_quota_bucket "5h$" "^gemini" "argon")
        bucket_wk=$(resolve_quota_bucket "(weekly|7d|wk)$" "^gemini" "argon")
    elif [[ -z "$bucket_wk" ]]; then
        bucket_wk=$(resolve_quota_bucket "(weekly|7d|wk)$" "^gemini" "argon")
    fi
elif [[ "$quota_model" =~ ([Gg][Ee][Mm][Ii][Nn][Ii]|[Cc][Aa][Rr][Bb][Oo][Nn]|[Hh][Yy][Dd][Rr][Oo][Gg][Ee][Nn]|[Nn][Ee][Oo][Nn]) ]]; then
    bucket_5h=$(resolve_quota_bucket "5h$" "^gemini" "argon")
    bucket_wk=$(resolve_quota_bucket "(weekly|7d|wk)$" "^gemini" "argon")
else
    bucket_5h=$(resolve_quota_bucket "5h$" "^3p" "argon|gemini")
    bucket_wk=$(resolve_quota_bucket "(weekly|7d|wk)$" "^3p" "argon|gemini")
fi

IFS=$'\t' read -r quota_5h_key quota_5h_raw quota_5h_rem quota_5h_rst <<< "$bucket_5h"
IFS=$'\t' read -r quota_wk_key quota_wk_raw quota_wk_rem quota_wk_rst <<< "$bucket_wk"

session_id=$(printf "%s" "$json_payload" | jq -r '.session_id // "default"')
curr_tokens=$(printf "%s" "$json_payload" | jq -r '((.context_window.total_input_tokens // 0) + (.context_window.total_output_tokens // 0)) | floor')
now_ts="${AGY_STATUSLINE_NOW:-$(date +%s)}"
stale_threshold="${AGY_QUOTA_STALE_SECONDS:-120}"
quota_state_file="${AGY_QUOTA_STATE_FILE:-$AGY_CACHE_DIR/quota-state.json}"

is_active_turn=0
case "$agent_state" in
    thinking|working|running) is_active_turn=1 ;;
esac

# Track quota snapshot age and project burn rate per session+bucket.
# Outputs: "<age_seconds>\t<effective_rem>\t<is_projected_0_or_1>"
update_and_project_quota() {
    local bkey="$1"
    local braw="$2"
    local brem="$3"
    if [[ -z "$bkey" || -z "$braw" || -z "$brem" || ! "$now_ts" =~ ^[0-9]+$ ]]; then
        printf "0\t%s\t0" "$brem"
        return 0
    fi
    local skey="${session_id}:${bkey}"
    local cur_state="{}"
    if [[ -f "$quota_state_file" ]]; then
        cur_state=$(cat "$quota_state_file" 2>/dev/null || printf "{}")
    fi
    local snap_raw snap_rem snap_ts snap_tok prev_rem prev_ts prev_tok
    IFS=$'\t' read -r snap_raw snap_rem snap_ts snap_tok prev_rem prev_ts prev_tok <<< "$(printf "%s" "$cur_state" | jq -r --arg k "$skey" '
        .[$k] | if . != null then
            "\(.raw // "")\t\(.rem // "")\t\(.ts // "")\t\(.tokens // 0)\t\(.prev_rem // "")\t\(.prev_ts // "")\t\(.prev_tokens // 0)"
        else "" end
    ' 2>/dev/null || true)"

    if [[ -z "$snap_raw" || "$snap_raw" != "$braw" || ! "$snap_ts" =~ ^[0-9]+$ ]]; then
        prev_rem="$snap_rem"
        prev_ts="$snap_ts"
        prev_tok="${snap_tok:-0}"
        snap_raw="$braw"
        snap_rem="$brem"
        snap_ts="$now_ts"
        snap_tok="$curr_tokens"
        mkdir -p "$(dirname "$quota_state_file")" 2>/dev/null || true
        local new_state
        new_state=$(printf "%s" "$cur_state" | jq -c \
            --arg k "$skey" \
            --arg raw "$braw" \
            --argjson rem "${brem:-0}" \
            --argjson ts "$now_ts" \
            --argjson tok "${curr_tokens:-0}" '
            . + {($k): {
                raw: $raw,
                rem: $rem,
                ts: $ts,
                tokens: $tok,
                prev_raw: (.[$k].raw // null),
                prev_rem: (.[$k].rem // null),
                prev_ts: (.[$k].ts // null),
                prev_tokens: (.[$k].tokens // 0)
            }}
        ' 2>/dev/null || true)
        if [[ -n "$new_state" ]]; then
            printf "%s\n" "$new_state" > "$quota_state_file" 2>/dev/null || true
        fi
    fi

    local age=$(( now_ts - snap_ts ))
    if (( age < 0 )); then age=0; fi

    local eff_rem="$brem"
    local is_proj=0
    if (( is_active_turn == 1 && age >= stale_threshold )); then
        if [[ "$prev_rem" =~ ^[0-9]+$ && "$prev_ts" =~ ^[0-9]+$ ]] && (( prev_rem > brem && snap_ts > prev_ts )); then
            local delta_rem=$(( prev_rem - brem ))
            local delta_ts=$(( snap_ts - prev_ts ))
            local drop_time=$(( delta_rem * age / delta_ts ))
            local drop_tok=0
            if [[ "$prev_tok" =~ ^[0-9]+$ && "$snap_tok" =~ ^[0-9]+$ ]] && (( snap_tok > prev_tok && curr_tokens > snap_tok )); then
                drop_tok=$(( delta_rem * (curr_tokens - snap_tok) / (snap_tok - prev_tok) ))
            fi
            local drop="$drop_time"
            if (( drop_tok > drop )); then drop="$drop_tok"; fi
            if (( drop > 0 )); then
                eff_rem=$(( brem - drop ))
                if (( eff_rem < 0 )); then eff_rem=0; fi
                is_proj=1
            fi
        fi
    fi
    printf "%d\t%s\t%d" "$age" "$eff_rem" "$is_proj"
}

IFS=$'\t' read -r quota_5h_age quota_5h_eff quota_5h_proj <<< "$(update_and_project_quota "$quota_5h_key" "$quota_5h_raw" "$quota_5h_rem")"
IFS=$'\t' read -r quota_wk_age quota_wk_eff quota_wk_proj <<< "$(update_and_project_quota "$quota_wk_key" "$quota_wk_raw" "$quota_wk_rem")"

# --- 4. Theming & Colors ---
C_RESET="\e[0m"
C_FG_WHITE="\e[38;5;255m"

# Pastel TrueColors
C_FG_READY="\e[38;2;183;204;133m"
C_FG_THINKING="\e[38;2;229;192;123m"
C_FG_WORKING="\e[38;2;97;175;239m"
C_FG_AGY="\e[38;2;198;120;221m"

# Status & Base
C_FG_GRAY="\e[38;5;245m"
C_FG_WARN="\e[38;5;214m"
C_FG_CRIT="\e[38;5;196m"

# Separator for simple whitespace design
DIV=" | "

# --- Helper to draw a small progress bar ---
draw_bar() {
    local pct="$1"
    local size="$2"
    local filled=$(( pct * size / 100 ))
    local bar=""
    for (( i=0; i<size; i++ )); do
        if (( i < filled )); then
            bar+="█"
        else
            bar+="░"
        fi
    done
    printf "%s" "$bar"
}

# --- Helper to format reset time ---
format_reset() {
    local sec="$1"
    if [[ -z "$sec" || ! "$sec" =~ ^[0-9]+$ || "$sec" -le 0 ]]; then
        return
    fi
    local d=$(( sec / 86400 ))
    local rem=$(( sec % 86400 ))
    local h=$(( rem / 3600 ))
    rem=$(( rem % 3600 ))
    local m=$(( rem / 60 ))
    if (( d > 0 )); then
        if (( h > 0 )); then
            printf "%dd %dh" "$d" "$h"
        else
            printf "%dd" "$d"
        fi
    elif (( h > 0 )); then
        if (( m > 0 )); then
            printf "%dh %dm" "$h" "$m"
        else
            printf "%dh" "$h"
        fi
    elif (( m > 0 )); then
        printf "%dm" "$m"
    else
        printf "<1m"
    fi
}

# --- 5. Icon Definitions (Classic Mode Support) ---
if [[ "${AGY_CLASSIC_MODE:-0}" == "1" ]]; then
    ICON_STATUS_IDLE="[IDLE]"
    ICON_STATUS_THINKING="[THINK]"
    ICON_STATUS_WORKING="[RUN]"
    ICON_STATUS_BLOCKED="[BLOCK]"
    ICON_MODEL="[MDL]"
    ICON_GIT_BRANCH="[GIT]"
    ICON_GIT_DIRTY="*"
    ICON_CTX="[CTX]"
    ICON_SUBAGENTS="[SUB]"
    ICON_TASKS="[TSK]"
    ICON_QUOTA_RESET=" "
    ICON_QUOTA_STALE="~"
else
    ICON_STATUS_IDLE=""
    ICON_STATUS_THINKING="󰟷"
    ICON_STATUS_WORKING=""
    ICON_STATUS_BLOCKED=""
    ICON_MODEL="󰚩"
    ICON_GIT_BRANCH=""
    ICON_GIT_DIRTY=""
    ICON_CTX="󰘦"
    ICON_SUBAGENTS="󱙺"
    ICON_TASKS="󰦕"
    ICON_QUOTA_RESET="󱎫"
    ICON_QUOTA_STALE="⟳"
fi

# --- 6. Segment Assembly & Line Packing ---

declare -a SEG_CONTENT

# 1. Status Indicator
status_icon=""
case "$agent_state" in
  idle|ready)
    status_icon="${C_FG_READY}${ICON_STATUS_IDLE}${C_RESET}"
    ;;
  thinking)
    status_icon="${C_FG_THINKING}${ICON_STATUS_THINKING}${C_RESET}"
    ;;
  working|running)
    status_icon="${C_FG_WORKING}${ICON_STATUS_WORKING}${C_RESET}"
    ;;
  blocked)
    status_icon="${C_FG_CRIT}${ICON_STATUS_BLOCKED}${C_RESET}"
    ;;
  *)
    status_icon="${C_FG_GRAY}${ICON_STATUS_IDLE}${C_RESET}"
    ;;
esac
SEG_CONTENT+=("$status_icon")

# 2. App Name
SEG_CONTENT+=("${C_FG_AGY}Agy CLI${C_RESET}")

# 3. Model
SEG_CONTENT+=("${C_FG_WORKING}${ICON_MODEL} ${model}${C_RESET}")

# 4. Git
if [[ -n "$git_branch" && "$git_branch" != "null" ]]; then
    if [[ "$git_dirty" == "true" ]]; then
        SEG_CONTENT+=("${C_FG_GRAY}${ICON_GIT_BRANCH} ${git_branch} ${C_FG_WARN}${ICON_GIT_DIRTY}${C_RESET}")
    else
        SEG_CONTENT+=("${C_FG_GRAY}${ICON_GIT_BRANCH} ${git_branch}${C_RESET}")
    fi
fi

# 5. Context
ctx_color="${C_FG_GRAY}"
if (( ctx_pct >= 90 )); then
    ctx_color="${C_FG_CRIT}"
elif (( ctx_pct >= 75 )); then
    ctx_color="${C_FG_WARN}"
fi
ctx_bar="$(draw_bar "$ctx_pct" 5)"
SEG_CONTENT+=("${C_FG_GRAY}${ICON_CTX}: ${ctx_color}${ctx_bar} ${ctx_pct}%${C_RESET}")

# 6. Workers (Subagents & Tasks)
if (( subagent_count > 0 || task_count > 0 )); then
    workers_content=""
    if (( subagent_count > 0 )); then
        workers_content+="${ICON_SUBAGENTS} ${subagent_count}"
    fi
    if (( task_count > 0 )); then
        if [[ -n "$workers_content" ]]; then workers_content+=" "; fi
        workers_content+="${ICON_TASKS} ${task_count}"
    fi
    SEG_CONTENT+=("${C_FG_THINKING}${workers_content}${C_RESET}")
fi

# 7. Quota 5H
if [[ -n "$quota_5h_rem" ]]; then
    q5h_val="${quota_5h_eff:-$quota_5h_rem}"
    q5h_prefix=""
    if (( quota_5h_proj == 1 )); then q5h_prefix="~"; fi
    q5h_color="${C_FG_READY}"
    if (( q5h_val <= 15 )); then q5h_color="${C_FG_CRIT}"
    elif (( q5h_val <= 40 )); then q5h_color="${C_FG_WARN}"
    fi
    q5_content="${C_FG_GRAY}5H: ${q5h_color}${q5h_prefix}${q5h_val}%${C_RESET}"
    if (( is_active_turn == 1 && quota_5h_age >= stale_threshold )); then
        stale_fmt=$(format_reset "$quota_5h_age")
        if [[ -n "$stale_fmt" ]]; then q5_content+="${C_FG_WARN} ${ICON_QUOTA_STALE}${stale_fmt}${C_RESET}"; fi
    fi
    rst_fmt=$(format_reset "$quota_5h_rst")
    if [[ -n "$rst_fmt" ]]; then q5_content+="${C_FG_GRAY} ${ICON_QUOTA_RESET} ${rst_fmt}${C_RESET}"; fi
    SEG_CONTENT+=("$q5_content")
elif [[ -n "$quota_wk_rem" ]]; then
    SEG_CONTENT+=("${C_FG_GRAY}5H: N/A${C_RESET}")
fi

# 8. Quota 7D
if [[ -n "$quota_wk_rem" ]]; then
    qwk_val="${quota_wk_eff:-$quota_wk_rem}"
    qwk_prefix=""
    if (( quota_wk_proj == 1 )); then qwk_prefix="~"; fi
    qwk_color="${C_FG_READY}"
    if (( qwk_val <= 15 )); then qwk_color="${C_FG_CRIT}"
    elif (( qwk_val <= 40 )); then qwk_color="${C_FG_WARN}"
    fi
    qwk_content="${C_FG_GRAY}7D: ${qwk_color}${qwk_prefix}${qwk_val}%${C_RESET}"
    if (( is_active_turn == 1 && quota_wk_age >= stale_threshold )); then
        stale_fmt=$(format_reset "$quota_wk_age")
        if [[ -n "$stale_fmt" ]]; then qwk_content+="${C_FG_WARN} ${ICON_QUOTA_STALE}${stale_fmt}${C_RESET}"; fi
    fi
    rst_fmt=$(format_reset "$quota_wk_rst")
    if [[ -n "$rst_fmt" ]]; then qwk_content+="${C_FG_GRAY} ${ICON_QUOTA_RESET} ${rst_fmt}${C_RESET}"; fi
    SEG_CONTENT+=("$qwk_content")
fi

# 8. Quota N/A fallback
if [[ -z "$quota_5h_rem" && -z "$quota_wk_rem" ]]; then
    SEG_CONTENT+=("${C_FG_GRAY}N/A${C_RESET}")
fi

# Dynamic Line Wrapping Logic

get_visible_length() {
    local extglob_set=0
    shopt -q extglob && extglob_set=1 || shopt -s extglob
    # Strip ANSI escape sequences to compute length
    local s="${1//\\e\[*([0-9;])m/}"
    (( extglob_set == 0 )) && shopt -u extglob
    REPLY="${#s}"
}

OUT=""
CURRENT_LEN=0

# Plain text divider length
get_visible_length "${C_FG_GRAY}${DIV}${C_RESET}"
DIV_LEN=$REPLY

for i in "${!SEG_CONTENT[@]}"; do
    content="${SEG_CONTENT[$i]}"
    
    get_visible_length "$content"
    seg_vis_len=$REPLY
    
    if (( CURRENT_LEN == 0 )); then
        # Start of line
        OUT+="${content}"
        CURRENT_LEN=$(( seg_vis_len ))
    else
        # If adding divider + content exceeds width, wrap to new line
        if (( CURRENT_LEN + DIV_LEN + seg_vis_len > term_width )); then
            OUT+="\n${content}"
            CURRENT_LEN=$(( seg_vis_len ))
        else
            OUT+="${C_FG_GRAY}${DIV}${C_RESET}${content}"
            CURRENT_LEN=$(( CURRENT_LEN + DIV_LEN + seg_vis_len ))
        fi
    fi
done

printf "%b\n" "$OUT"
