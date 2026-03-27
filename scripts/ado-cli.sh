#!/usr/bin/env bash
# ado-cli.sh — Wrapper around az boards commands for token-efficient ADO operations
#
# Usage:
#   bash scripts/ado-cli.sh --action <action> [--params '<json>']
#
# Actions:
#   show-work-item    — Fetch a work item by ID
#   create-work-item  — Create a new work item
#   update-work-item  — Update an existing work item
#   query-work-items  — Run a WIQL query
#   current-sprint    — Get the current active sprint/iteration
#   list-sprints      — List all sprints for the team
#   add-child         — Add a child work item link
#   close-work-item   — Set work item state to Done/Closed
#
# Examples:
#   bash scripts/ado-cli.sh --action show-work-item --params '{"id":12345}'
#   bash scripts/ado-cli.sh --action create-work-item --params '{"type":"Product Backlog Item","title":"My PBI","area_path":"Project\\Team","iteration_path":"Project\\Sprint-42"}'
#   bash scripts/ado-cli.sh --action current-sprint --params '{"team":"MyTeam"}'

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Helpers ---

json_ok() {
    jq -n --argjson data "$1" '{"success":true,"data":$data}'
}

json_error() {
    local msg="$1"
    local action="$2"
    jq -n --arg msg "$msg" --arg action "$action" '{"success":false,"error":$msg,"action":$action}'
}

require_param() {
    local value
    value=$(echo "$PARAMS" | jq -r ".$1 // empty")
    if [[ -z "$value" ]]; then
        json_error "Missing required parameter: $1" "$ACTION"
        exit 1
    fi
    echo "$value"
}

optional_param() {
    echo "$PARAMS" | jq -r ".$1 // empty"
}

# --- Parse arguments ---

ACTION=""
PARAMS="{}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --action) ACTION="$2"; shift 2 ;;
        --params) PARAMS="$2"; shift 2 ;;
        *) json_error "Unknown argument: $1" "parse"; exit 1 ;;
    esac
done

if [[ -z "$ACTION" ]]; then
    json_error "Missing --action argument" "parse"
    exit 1
fi

# --- Check az devops is available ---

if ! command -v az &>/dev/null; then
    json_error "Azure CLI (az) not found. Install from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli" "$ACTION"
    exit 1
fi

# --- Actions ---

show_work_item() {
    local id
    id=$(require_param "id") || exit 1
    local fields
    fields=$(optional_param "fields")

    local cmd="az boards work-item show --id $id --output json"
    if [[ -n "$fields" ]]; then
        cmd="$cmd --fields $fields"
    fi

    local result
    result=$(eval "$cmd" 2>&1) || {
        json_error "$result" "$ACTION"
        exit 1
    }
    json_ok "$result"
}

create_work_item() {
    local type title
    type=$(require_param "type") || exit 1
    title=$(require_param "title") || exit 1

    local area_path iteration_path description
    area_path=$(optional_param "area_path")
    iteration_path=$(optional_param "iteration_path")
    description=$(optional_param "description")

    local cmd="az boards work-item create --type \"$type\" --title \"$title\" --output json"
    if [[ -n "$area_path" ]]; then
        cmd="$cmd --area \"$area_path\""
    fi
    if [[ -n "$iteration_path" ]]; then
        cmd="$cmd --iteration \"$iteration_path\""
    fi
    if [[ -n "$description" ]]; then
        cmd="$cmd --description \"$description\""
    fi

    # Handle additional fields from params
    local fields_json
    fields_json=$(echo "$PARAMS" | jq -r '.fields // empty')
    if [[ -n "$fields_json" && "$fields_json" != "null" ]]; then
        while IFS='=' read -r key value; do
            cmd="$cmd --fields \"$key=$value\""
        done < <(echo "$fields_json" | jq -r 'to_entries[] | "\(.key)=\(.value)"')
    fi

    local result
    result=$(eval "$cmd" 2>&1) || {
        json_error "$result" "$ACTION"
        exit 1
    }
    json_ok "$result"
}

update_work_item() {
    local id
    id=$(require_param "id") || exit 1

    local cmd="az boards work-item update --id $id --output json"

    local title state
    title=$(optional_param "title")
    state=$(optional_param "state")

    if [[ -n "$title" ]]; then
        cmd="$cmd --title \"$title\""
    fi
    if [[ -n "$state" ]]; then
        cmd="$cmd --state \"$state\""
    fi

    local fields_json
    fields_json=$(echo "$PARAMS" | jq -r '.fields // empty')
    if [[ -n "$fields_json" && "$fields_json" != "null" ]]; then
        while IFS='=' read -r key value; do
            cmd="$cmd --fields \"$key=$value\""
        done < <(echo "$fields_json" | jq -r 'to_entries[] | "\(.key)=\(.value)"')
    fi

    local result
    result=$(eval "$cmd" 2>&1) || {
        json_error "$result" "$ACTION"
        exit 1
    }
    json_ok "$result"
}

query_work_items() {
    local wiql
    wiql=$(require_param "wiql") || exit 1

    local result
    result=$(az boards query --wiql "$wiql" --output json 2>&1) || {
        json_error "$result" "$ACTION"
        exit 1
    }
    json_ok "$result"
}

current_sprint() {
    local team
    team=$(optional_param "team")

    local cmd="az boards iteration team list --output json"
    if [[ -n "$team" ]]; then
        cmd="$cmd --team \"$team\""
    fi

    local result
    result=$(eval "$cmd" 2>&1) || {
        json_error "$result" "$ACTION"
        exit 1
    }

    # Filter to the current active sprint (timeframe = current)
    local current
    current=$(echo "$result" | jq '[.[] | select(.attributes.timeFrame == "current")] | .[0]')

    if [[ "$current" == "null" ]]; then
        json_error "No current sprint found. Check team iteration settings in ADO." "$ACTION"
        exit 1
    fi
    json_ok "$current"
}

list_sprints() {
    local team
    team=$(optional_param "team")

    local cmd="az boards iteration team list --output json"
    if [[ -n "$team" ]]; then
        cmd="$cmd --team \"$team\""
    fi

    local result
    result=$(eval "$cmd" 2>&1) || {
        json_error "$result" "$ACTION"
        exit 1
    }
    json_ok "$result"
}

add_child() {
    local parent_id child_id
    parent_id=$(require_param "parent_id") || exit 1
    child_id=$(require_param "child_id") || exit 1

    local result
    result=$(az boards work-item relation add --id "$parent_id" --relation-type "System.LinkTypes.Hierarchy-Forward" --target-id "$child_id" --output json 2>&1) || {
        json_error "$result" "$ACTION"
        exit 1
    }
    json_ok "$result"
}

close_work_item() {
    local id
    id=$(require_param "id") || exit 1
    local state
    state=$(optional_param "state")
    if [[ -z "$state" ]]; then
        state="Closed"
    fi

    local result
    result=$(az boards work-item update --id "$id" --state "$state" --output json 2>&1) || {
        json_error "$result" "$ACTION"
        exit 1
    }
    json_ok "$result"
}

# --- Dispatch ---

case "$ACTION" in
    show-work-item)    show_work_item ;;
    create-work-item)  create_work_item ;;
    update-work-item)  update_work_item ;;
    query-work-items)  query_work_items ;;
    current-sprint)    current_sprint ;;
    list-sprints)      list_sprints ;;
    add-child)         add_child ;;
    close-work-item)   close_work_item ;;
    *)
        json_error "Unknown action: $ACTION. Valid actions: show-work-item, create-work-item, update-work-item, query-work-items, current-sprint, list-sprints, add-child, close-work-item" "$ACTION"
        exit 1
        ;;
esac
