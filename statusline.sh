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

# --- 3. Extract JSON Fields ---
agent_state=$(printf "%s" "$json_payload" | jq -r '.agent_state // "idle"')
model=$(printf "%s" "$json_payload" | jq -r '.model.display_name // "unknown"')
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

# Extract all quota bucket candidates
_g5h_rem=$(printf "%s" "$json_payload" | jq -r '.quota["gemini-5h"]?.remaining_fraction | if . != null then (. * 100 | floor) else empty end')
_g5h_rst=$(printf "%s" "$json_payload" | jq -r '.quota["gemini-5h"]?.reset_in_seconds // empty')
_gwk_rem=$(printf "%s" "$json_payload" | jq -r '.quota["gemini-weekly"]?.remaining_fraction | if . != null then (. * 100 | floor) else empty end')
_gwk_rst=$(printf "%s" "$json_payload" | jq -r '.quota["gemini-weekly"]?.reset_in_seconds // empty')

_3p5h_rem=$(printf "%s" "$json_payload" | jq -r '.quota["3p-5h"]?.remaining_fraction | if . != null then (. * 100 | floor) else empty end')
_3p5h_rst=$(printf "%s" "$json_payload" | jq -r '.quota["3p-5h"]?.reset_in_seconds // empty')
_3pwk_rem=$(printf "%s" "$json_payload" | jq -r '.quota["3p-weekly"]?.remaining_fraction | if . != null then (. * 100 | floor) else empty end')
_3pwk_rst=$(printf "%s" "$json_payload" | jq -r '.quota["3p-weekly"]?.reset_in_seconds // empty')

# Route to the correct bucket pair based on model name
if [[ "$model" =~ [Gg][Ee][Mm][Ii][Nn][Ii] ]]; then
    quota_5h_rem="$_g5h_rem"
    quota_5h_rst="$_g5h_rst"
    quota_wk_rem="$_gwk_rem"
    quota_wk_rst="$_gwk_rst"
else
    quota_5h_rem="$_3p5h_rem"
    quota_5h_rst="$_3p5h_rst"
    quota_wk_rem="$_3pwk_rem"
    quota_wk_rst="$_3pwk_rst"
fi

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
    q5h_color="${C_FG_READY}"
    if (( quota_5h_rem <= 15 )); then q5h_color="${C_FG_CRIT}"
    elif (( quota_5h_rem <= 40 )); then q5h_color="${C_FG_WARN}"
    fi
    q5_content="${C_FG_GRAY}5H: ${q5h_color}${quota_5h_rem}%${C_RESET}"
    rst_fmt=$(format_reset "$quota_5h_rst")
    if [[ -n "$rst_fmt" ]]; then q5_content+="${C_FG_GRAY} ${ICON_QUOTA_RESET} ${rst_fmt}${C_RESET}"; fi
    SEG_CONTENT+=("$q5_content")
fi

# 8. Quota 7D
if [[ -n "$quota_wk_rem" ]]; then
    qwk_color="${C_FG_READY}"
    if (( quota_wk_rem <= 15 )); then qwk_color="${C_FG_CRIT}"
    elif (( quota_wk_rem <= 40 )); then qwk_color="${C_FG_WARN}"
    fi
    qwk_content="${C_FG_GRAY}7D: ${qwk_color}${quota_wk_rem}%${C_RESET}"
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
