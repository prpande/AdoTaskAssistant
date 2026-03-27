#!/usr/bin/env bash
# parse-session-logs.sh — Parse Claude Code session logs for a date range (best-effort)
#
# Usage:
#   bash scripts/parse-session-logs.sh --from <YYYY-MM-DD> --to <YYYY-MM-DD> [--path <session-log-dir>]
#
# Always exits 0. Returns a JSON envelope with success:true even when no logs are found.

# --- Helpers ---

json_ok() {
    printf '%s' "$1" | jq '{success: true, data: .}'
}

# --- Parse arguments ---

FROM_DATE=""
TO_DATE=""
SESSION_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --from) FROM_DATE="$2"; shift 2 ;;
        --to)   TO_DATE="$2";   shift 2 ;;
        --path) SESSION_PATH="$2"; shift 2 ;;
        *)      shift ;;  # ignore unknown args
    esac
done

# --- Auto-detect session log location ---

if [[ -z "$SESSION_PATH" ]]; then
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

# If still no path, return graceful empty result
if [[ -z "$SESSION_PATH" || ! -d "$SESSION_PATH" ]]; then
    json_ok "$(jq -n \
        --arg from "${FROM_DATE:-unknown}" \
        --arg to   "${TO_DATE:-unknown}" \
        '{
            session_count: 0,
            sessions: [],
            date_range: {from: $from, to: $to},
            log_path: null,
            note: "No Claude Code session log directory found. Searched ~/.claude/projects, ~/.claude/sessions, $APPDATA/Claude/sessions."
        }')"
    exit 0
fi

# --- Find and parse session files (best-effort, no date epoch conversion) ---

sessions="[]"

while IFS= read -r session_file; do
    session_summary=""

    if [[ "$session_file" == *.jsonl ]]; then
        session_summary=$(jq -s '{
            file: "'"$session_file"'",
            message_count: length,
            first_message: (if length > 0 then first | (.timestamp // .created_at // "unknown") else "unknown" end),
            last_message:  (if length > 0 then last  | (.timestamp // .created_at // "unknown") else "unknown" end),
            tools_used: [.[].tool // empty] | unique
        }' "$session_file" 2>/dev/null)
    elif [[ "$session_file" == *.json ]]; then
        session_summary=$(jq '{
            file: "'"$session_file"'",
            description: (.description // .summary // "No description"),
            created: (.created_at // .timestamp // "unknown")
        }' "$session_file" 2>/dev/null)
    fi

    if [[ -n "$session_summary" ]]; then
        sessions=$(printf '%s\n%s' "$sessions" "[$session_summary]" | jq -s '.[0] + .[1]')
    fi
done < <(find "$SESSION_PATH" -type f \( -name "*.jsonl" -o -name "*.json" \) 2>/dev/null)

# --- Build and return summary ---

summary=$(printf '%s' "$sessions" | jq \
    --arg from "${FROM_DATE:-unknown}" \
    --arg to   "${TO_DATE:-unknown}" \
    --arg path "$SESSION_PATH" \
    '{
        session_count: length,
        sessions: .,
        date_range: {from: $from, to: $to},
        log_path: $path
    }')

json_ok "$summary"
exit 0
