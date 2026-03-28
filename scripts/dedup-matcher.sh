#!/usr/bin/env bash
# dedup-matcher.sh — Match preprocessed activity against existing ADO items
#
# Queries existing ADO work items for the relevant sprints, extracts URLs from
# descriptions, and matches against preprocessed activity items. Populates the
# `dedup` field on each item with match status and optional state updates.
#
# Usage:
#   bash scripts/dedup-matcher.sh --params '<json>'
#   bash scripts/dedup-matcher.sh --params-file <path>
#
# Params:
#   activity_file   — path to preprocessed activity JSON ({success, items: [...]})
#   sprints         — array of sprint iteration path strings

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
SPRINTS_JSON=$(printf '%s' "$PARAMS" | jq -c '.sprints // empty')

if [[ -z "$ACTIVITY_FILE" ]]; then
    json_error "Missing required parameter: activity_file"
fi

if [[ ! -f "$ACTIVITY_FILE" ]]; then
    json_error "Activity file not found: $ACTIVITY_FILE"
fi

if [[ -z "$SPRINTS_JSON" || "$SPRINTS_JSON" == "null" ]]; then
    json_error "Missing required parameter: sprints (array of iteration path strings)"
fi

# --- Load preprocessed activity ---

ACTIVITY=$(cat "$ACTIVITY_FILE")

# Validate structure
if ! printf '%s' "$ACTIVITY" | jq -e '.items | type == "array"' > /dev/null 2>&1; then
    json_error "Activity file must contain {success, items: [...]}"
fi

# --- Query existing ADO items ---

ADO_ITEMS="[]"
ADO_NOTE=""

# Build params file for the ADO query using build-params.sh
QUERY_PARAMS_FILE=$(mktemp)
trap 'rm -f "$QUERY_PARAMS_FILE"' EXIT

bash "$SCRIPT_DIR/build-params.sh" \
    --output "$QUERY_PARAMS_FILE" \
    --argjson sprints "$SPRINTS_JSON" > /dev/null 2>&1

if [[ $? -ne 0 ]]; then
    ADO_NOTE="Failed to build query params; treating all items as new"
else
    ADO_RESULT=$(bash "$SCRIPT_DIR/ado-cli.sh" --action query-my-sprint-items --params-file "$QUERY_PARAMS_FILE" 2>&1)
    ADO_SUCCESS=$(printf '%s' "$ADO_RESULT" | jq -r '.success // false' 2>/dev/null)

    if [[ "$ADO_SUCCESS" == "true" ]]; then
        ADO_ITEMS=$(printf '%s' "$ADO_RESULT" | jq -c '.data // []')
    else
        ADO_ERROR=$(printf '%s' "$ADO_RESULT" | jq -r '.error // "unknown error"' 2>/dev/null)
        ADO_NOTE="ADO query failed: $ADO_ERROR; treating all items as new"
    fi
fi

# --- Run matching in jq ---

printf '%s' "$ACTIVITY" | jq \
    --argjson ado_items "$ADO_ITEMS" \
    --arg ado_note "$ADO_NOTE" \
'
# -------------------------------------------------------
# Helper: extract URLs from an HTML description string
# -------------------------------------------------------
def extract_urls:
    if . == null or . == "" then []
    else
        [
            # GitHub PR URLs
            match("https://github\\.com/[^/]+/[^/]+/pull/[0-9]+"; "g") | .string,
            # Notion page URLs (with or without www)
            match("https://(www\\.)?notion\\.so/[a-zA-Z0-9_-]+"; "g") | .string
        ]
    end;

# -------------------------------------------------------
# Helper: normalize a title for comparison
# Strip brackets, punctuation, lowercase, split to words
# -------------------------------------------------------
def normalize_title:
    ascii_downcase
    | gsub("[\\[\\](){}]"; " ")
    | gsub("[^a-z0-9 ]"; " ")
    | split(" ")
    | map(select(length > 0));

# -------------------------------------------------------
# Helper: Jaccard similarity on two word arrays
# -------------------------------------------------------
def jaccard(a; b):
    if (a | length) == 0 and (b | length) == 0 then 0
    else
        (a | unique) as $sa |
        (b | unique) as $sb |
        ([$sa[] | select(. as $w | $sb | index($w))] | length) as $inter |
        ([$sa[], $sb[]] | unique | length) as $union |
        if $union == 0 then 0
        else ($inter / $union * 100 | round / 100)
        end
    end;

# -------------------------------------------------------
# Build URL lookup from existing ADO items
# { url: {work_item_id, title, state, type} }
# -------------------------------------------------------
(
    reduce ($ado_items[] | . as $wi |
        (($wi.fields["System.Description"] // "") | extract_urls)[] |
        {
            url: .,
            info: {
                work_item_id: ($wi.fields["System.Id"] // $wi.id),
                title: ($wi.fields["System.Title"] // ""),
                state: ($wi.fields["System.State"] // ""),
                type: ($wi.fields["System.WorkItemType"] // "")
            }
        }
    ) as $entry ({}; .[$entry.url] = $entry.info)
) as $url_lookup |

# Build title lookup array for similarity matching
[
    $ado_items[] |
    {
        work_item_id: (.fields["System.Id"] // .id),
        title: (.fields["System.Title"] // ""),
        state: (.fields["System.State"] // ""),
        type: (.fields["System.WorkItemType"] // ""),
        words: ((.fields["System.Title"] // "") | normalize_title)
    }
] as $title_entries |

# -------------------------------------------------------
# Helper: extract source URL from an activity item
# -------------------------------------------------------
def source_url:
    if .source.type == "github_pr" then
        .source.url // .source.html_url // null
    elif .source.type == "notion_page" then
        .source.url // null
    else
        null
    end;

# -------------------------------------------------------
# Helper: extract title from an activity item
# -------------------------------------------------------
def source_title:
    if .source.type == "github_pr" then
        .source.title // ""
    elif .source.type == "notion_page" then
        .source.title // ""
    elif .source.type == "dev_activity" then
        ((.source.commits // []) | first | .subject // "")
    else
        ""
    end;

# -------------------------------------------------------
# Helper: determine state update for tracked items
# -------------------------------------------------------
def state_update:
    if .source.type == "github_pr" then
        # If PR is now merged and was tracked as Committed/In Progress -> Done
        if (.source.state == "merged" or .source.merged == true) then
            "Done"
        else
            null
        end
    elif .source.type == "notion_page" then
        # NEVER auto-close Notion items
        null
    else
        null
    end;

# -------------------------------------------------------
# Main: process each activity item
# -------------------------------------------------------
{
    success: true,
    items: [
        .items[] |
        . as $item |

        # If ADO query failed, mark all as new
        if ($ado_note != "") then
            . + { dedup: { status: "new", note: $ado_note } }
        else
            # Try URL match first
            ($item | source_url) as $url |
            if ($url != null and $url != "" and $url_lookup[$url] != null) then
                $url_lookup[$url] as $match |
                . + {
                    dedup: {
                        status: "tracked",
                        work_item_id: $match.work_item_id,
                        current_state: $match.state,
                        state_update: ($item | state_update)
                    }
                }
            else
                # Try title similarity
                ($item | source_title | normalize_title) as $item_words |
                if ($item_words | length) == 0 then
                    . + { dedup: { status: "new" } }
                else
                    (
                        [
                            $title_entries[] |
                            . as $entry |
                            jaccard($item_words; $entry.words) as $sim |
                            select($sim > 0.6) |
                            { work_item_id: $entry.work_item_id, existing_title: $entry.title, similarity: $sim }
                        ] | sort_by(-.similarity) | first // null
                    ) as $best_match |
                    if $best_match != null then
                        . + {
                            dedup: {
                                status: "potential_match",
                                work_item_id: $best_match.work_item_id,
                                existing_title: $best_match.existing_title,
                                similarity: $best_match.similarity
                            }
                        }
                    else
                        . + { dedup: { status: "new" } }
                    end
                end
            end
        end
    ]
}
'

rc=$?
if [[ $rc -ne 0 ]]; then
    json_error "jq processing failed (exit code $rc)"
fi
