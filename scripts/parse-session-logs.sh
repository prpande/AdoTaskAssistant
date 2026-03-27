#!/usr/bin/env bash
# parse-session-logs.sh — Parse Claude Code session logs for a date range
#
# Usage:
#   bash scripts/parse-session-logs.sh --from <YYYY-MM-DD> --to <YYYY-MM-DD> [--path <session-log-dir>]
#
# Attempts to auto-detect Claude Code session log location if --path is not provided.
# Returns a summary of sessions including descriptions and tool usage.

set -o pipefail

# --- Helpers ---

json_ok() {
    jq -n --argjson data "$1" '{"success":true,"data":$data}'
}

json_error() {
    jq -n --arg msg "$1" '{"success":false,"error":$msg}'
}

# --- Parse arguments ---

FROM_DATE=""
TO_DATE=""
SESSION_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --from) FROM_DATE="$2"; shift 2 ;;
        --to) TO_DATE="$2"; shift 2 ;;
        --path) SESSION_PATH="$2"; shift 2 ;;
        *) json_error "Unknown argument: $1"; exit 1 ;;
    esac
done

if [[ -z "$FROM_DATE" || -z "$TO_DATE" ]]; then
    json_error "Missing required arguments: --from and --to (YYYY-MM-DD)"
    exit 1
fi

# --- Auto-detect session log location ---

if [[ -z "$SESSION_PATH" ]]; then
    # Try common Claude Code session locations
    candidates=(
        "$HOME/.claude/projects"
        "$HOME/.claude/sessions"
        "$APPDATA/Claude/sessions"
        "$LOCALAPPDATA/Claude/sessions"
    )
    for candidate in "${candidates[@]}"; do
        if [[ -d "$candidate" ]]; then
            SESSION_PATH="$candidate"
            break
        fi
    done
fi

if [[ -z "$SESSION_PATH" || ! -d "$SESSION_PATH" ]]; then
    json_error "Could not find Claude Code session logs. Provide --path or check that Claude Code has been used on this machine. Searched: ~/.claude/projects, ~/.claude/sessions, \$APPDATA/Claude/sessions"
    exit 1
fi

# --- Parse session files ---

# Convert dates to epoch for comparison
from_epoch=$(date -d "$FROM_DATE" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$FROM_DATE" +%s 2>/dev/null)
to_epoch=$(date -d "$TO_DATE" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$TO_DATE" +%s 2>/dev/null)

if [[ -z "$from_epoch" || -z "$to_epoch" ]]; then
    json_error "Could not parse dates. Use YYYY-MM-DD format."
    exit 1
fi

sessions="[]"

# Walk through session directories and find sessions in the date range
# Adapt this section based on the actual Claude Code session log format
while IFS= read -r session_file; do
    # Get file modification time
    file_epoch=$(stat -c %Y "$session_file" 2>/dev/null || stat -f %m "$session_file" 2>/dev/null)
    if [[ -z "$file_epoch" ]]; then
        continue
    fi

    if [[ "$file_epoch" -ge "$from_epoch" && "$file_epoch" -le "$to_epoch" ]]; then
        # Try to extract session info — format depends on Claude Code's storage
        # This reads JSONL format (one JSON object per line) which is common
        if [[ "$session_file" == *.jsonl ]]; then
            session_summary=$(jq -s '{
                file: "'"$session_file"'",
                message_count: length,
                first_message: (first | .timestamp // .created_at // "unknown"),
                last_message: (last | .timestamp // .created_at // "unknown"),
                tools_used: [.[].tool // empty] | unique
            }' "$session_file" 2>/dev/null)
        elif [[ "$session_file" == *.json ]]; then
            session_summary=$(jq '{
                file: "'"$session_file"'",
                description: (.description // .summary // "No description"),
                created: (.created_at // .timestamp // "unknown")
            }' "$session_file" 2>/dev/null)
        else
            continue
        fi

        if [[ -n "$session_summary" ]]; then
            sessions=$(echo "$sessions" "[$session_summary]" | jq -s '.[0] + .[1]')
        fi
    fi
done < <(find "$SESSION_PATH" -type f \( -name "*.jsonl" -o -name "*.json" \) 2>/dev/null)

# --- Build summary ---

summary=$(jq -n \
    --argjson sessions "$sessions" \
    --arg from "$FROM_DATE" \
    --arg to "$TO_DATE" \
    --arg path "$SESSION_PATH" \
    '{
        session_count: ($sessions | length),
        sessions: $sessions,
        date_range: {from: $from, to: $to},
        log_path: $path
    }')

json_ok "$summary"
