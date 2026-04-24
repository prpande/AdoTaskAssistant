#!/usr/bin/env bash
# preprocess-activity.sh — Deterministic preprocessing of gathered activity
#
# Takes raw gathered activity + sprint data and outputs enriched activity with:
#   - Sprint mapping (by date)
#   - Work type scoring (from template keywords)
#   - State assignment (deterministic table)
#   - Branch group hints
#
# Usage:
#   bash scripts/preprocess-activity.sh --params '<json>'
#   bash scripts/preprocess-activity.sh --params-file <path>
#
# Params:
#   activity_file   — path to gathered activity JSON (array of items)
#   template_file   — path to task-template.json (default: data/task-template.json)
#   sprints         — array of {name, path, start, end} objects

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Helpers ---

json_error() {
    local msg="$1"
    jq -n --arg msg "$msg" '{"success":false,"error":$msg}'
    exit 1
}

# --- Parse arguments ---

PARAMS="{}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --params) PARAMS="$2"; shift 2 ;;
        --params-file) PARAMS=$(cat "$2"); shift 2 ;;
        *) json_error "Unknown argument: $1" ;;
    esac
done

# --- Extract params ---

ACTIVITY_FILE=$(printf '%s' "$PARAMS" | jq -r '.activity_file // empty')
TEMPLATE_FILE=$(printf '%s' "$PARAMS" | jq -r '.template_file // empty')
SPRINTS_JSON=$(printf '%s' "$PARAMS" | jq -c '.sprints // empty')
# Optional: regex patterns (case-insensitive) to drop items from before processing.
# See config_grouping.exclude_title_patterns in data/config.json.
EXCLUDE_PATTERNS_JSON=$(printf '%s' "$PARAMS" | jq -c '.exclude_title_patterns // []')

if [[ -z "$ACTIVITY_FILE" ]]; then
    json_error "Missing required parameter: activity_file"
fi

if [[ ! -f "$ACTIVITY_FILE" ]]; then
    json_error "Activity file not found: $ACTIVITY_FILE"
fi

if [[ -z "$TEMPLATE_FILE" ]]; then
    TEMPLATE_FILE="$REPO_DIR/data/task-template.json"
fi

if [[ ! -f "$TEMPLATE_FILE" ]]; then
    json_error "Template file not found: $TEMPLATE_FILE"
fi

if [[ -z "$SPRINTS_JSON" || "$SPRINTS_JSON" == "null" ]]; then
    json_error "Missing required parameter: sprints (array of {name, path, start, end})"
fi

# --- Load data ---

ACTIVITY=$(cat "$ACTIVITY_FILE")
TEMPLATE=$(cat "$TEMPLATE_FILE")

# Validate activity is a JSON array
if ! printf '%s' "$ACTIVITY" | jq -e 'type == "array"' > /dev/null 2>&1; then
    json_error "Activity file must contain a JSON array"
fi

# --- Run jq preprocessing ---
# All logic is in a single jq invocation for efficiency

printf '%s' "$ACTIVITY" | jq \
    --argjson sprints "$SPRINTS_JSON" \
    --argjson template "$TEMPLATE" \
    --argjson exclude_patterns "$EXCLUDE_PATTERNS_JSON" \
'
# -------------------------------------------------------
# Helper functions
# -------------------------------------------------------

# Extract primary date from an activity item (truncated to YYYY-MM-DD)
def primary_date:
    (if .type == "github_pr" then
        .createdAt // .created_at // .updatedAt // .updated_at // ""
    elif .type == "notion_page" then
        .last_edited // ""
    elif .type == "dev_activity" then
        # date_range format: "YYYY-MM-DD to YYYY-MM-DD"
        (.date_range // "" | split(" to ") | first // "")
    else
        ""
    end) | .[:10];

# Find the sprint that contains a given date string (YYYY-MM-DD)
# Falls back to last sprint if no match
def find_sprint(date_str):
    if date_str == "" or date_str == null then
        ($sprints | last)
    else
        ([ $sprints[] | select(.start <= date_str and .end >= date_str) ] | first)
        // ($sprints | last)
    end;

# Extract text signals for work type scoring
def text_signals:
    if .type == "github_pr" then
        [(.title // ""), (.repository.name // .repo // "")] | map(ascii_downcase) | join(" ")
    elif .type == "notion_page" then
        (.title // "") | ascii_downcase
    elif .type == "dev_activity" then
        [(.commits // [])[] | .subject // ""] | map(ascii_downcase) | join(" ")
    else
        ""
    end;

# Count keyword matches and score work type
def score_work_type:
    . as $text |
    ($template.work_type.inference_keywords // {}) as $keywords |
    ($template.work_type.default // "New Feature Development") as $default |
    [
        $keywords | to_entries[] |
        {
            type: .key,
            keywords: .value,
            matches: [ .value[] | . as $kw | ("\\b" + $kw + "\\b") as $pat | select($text | test($pat; "i")) ],
            count: ([ .value[] | . as $kw | ("\\b" + $kw + "\\b") as $pat | select($text | test($pat; "i")) ] | length)
        }
    ] |
    sort_by(-.count) |
    if (first.count // 0) > 0 then
        {
            inferred_work_type: first.type,
            work_type_confidence: (if first.count >= 3 then 1.0 elif first.count == 2 then 0.67 elif first.count == 1 then 0.33 else 0.0 end),
            work_type_signals: first.matches
        }
    else
        {
            inferred_work_type: $default,
            work_type_confidence: 0.0,
            work_type_signals: []
        }
    end;

# Determine state from source type
def infer_state:
    if .type == "github_pr" then
        if (.state // "") == "merged" then "Done"
        else "Committed"
        end
    elif .type == "notion_page" then
        "Committed"
    elif .type == "dev_activity" then
        "Committed"
    else
        "Committed"
    end;

# Extract branch name for group hints
def extract_branch:
    if .type == "github_pr" then
        .branch // .head_ref // null
    elif .type == "dev_activity" then
        .branch // null
    else
        null
    end;

# Return the effective title used for exclusion matching. For github_pr and
# notion_page this is the source title; for dev_activity (which has no title)
# we fall back to the repo name so patterns like "^Api\\.Codex$" still work.
def match_text:
    if .type == "github_pr" then (.title // "")
    elif .type == "notion_page" then (.title // "")
    elif .type == "dev_activity" then (.repo // "")
    else (.title // "")
    end;

# True if the item matches any user-configured exclude pattern.
# Patterns are case-insensitive. Invalid regex is treated as non-matching.
def is_excluded:
    . as $item |
    ($exclude_patterns // []) as $pats |
    ($pats | length) > 0 and
    (any($pats[]; . as $pat | ($item | match_text | test($pat; "i"))));

# -------------------------------------------------------
# Main processing
# -------------------------------------------------------

. as $all |
[ $all[] | select(is_excluded | not) ] as $kept |

{
    success: true,
    excluded_count: (($all | length) - ($kept | length)),
    items: [
        $kept[] |
        . as $item |
        ($item | primary_date) as $date |
        (find_sprint($date)) as $sprint |
        ($item | text_signals) as $signals |
        ($signals | score_work_type) as $wt |
        {
            source: $item,
            sprint: ($sprint.name // null),
            sprint_path: ($sprint.path // null),
            inferred_work_type: $wt.inferred_work_type,
            work_type_confidence: $wt.work_type_confidence,
            work_type_signals: $wt.work_type_signals,
            inferred_state: ($item | infer_state),
            group_hint: ($item | extract_branch),
            dedup: null
        }
    ]
}
'

rc=$?
if [[ $rc -ne 0 ]]; then
    json_error "jq processing failed (exit code $rc)"
fi
