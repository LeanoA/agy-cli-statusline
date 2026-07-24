# Agy CLI Statusline

## Overview

This is a script to render a dynamic, visually appealing CLI status line for Antigravity (or any JSON-emitting telemetry tool). It uses standard terminal truecolors and Nerd Fonts to provide a concise, real-time overview of the system's state.

## Installation

You can install the tool as an Antigravity Plugin by running the provided installation script:

```bash
./install.sh
```

This will deploy the script to `~/.local/share/agy-statusline` and automatically configure your Antigravity IDE (`~/.gemini/antigravity-cli/settings.json`) to use it.

## Usage

The script reads a JSON payload from `stdin` and outputs a formatted status line, wrapping to the terminal width if necessary.

Example:

```bash
cat payload.json | agy-statusline
```

## Segments

The status line is composed of the following segments, which appear dynamically based on the provided JSON data:

*   **Status Indicator**: Shows the current agent state using distinct icons and colors:
    *   🟢 Idle / Ready
    *   🟡 Thinking
    *   🔵 Working / Running
    *   🔴 Blocked
*   **App Name**: Displays `Agy CLI`.
*   **Model**: Displays the current LLM model being used.
*   **Git**: Displays the current git branch, and a dirty indicator `*` or `` if there are uncommitted changes.
*   **Context**: A visual progress bar and percentage indicating the current context window usage.
*   **Workers**: Shows the number of active subagents and background tasks running.
*   **Quotas**: Shows the remaining API quota for both 5-hour (5H) and 7-day (7D) windows, along with the time until the quota resets.

## Classic Mode

By default, the script requires a terminal with a patched **Nerd Font** installed to render the icons correctly.

If you do not have a Nerd Font or prefer standard Unicode characters and emojis, you can enable Classic Mode by setting the `AGY_CLASSIC_MODE` environment variable to `1`.

```bash
export AGY_CLASSIC_MODE=1
cat payload.json | agy-statusline
```

This will fall back to standard characters (e.g., `●`, `◆`, `🤖`, `⏳`), ensuring compatibility across all terminals.
