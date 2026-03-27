#!/usr/bin/env bash
# ado-cli.sh — Wrapper around az boards commands for token-efficient ADO operations
#
# Usage:
#   bash scripts/ado-cli.sh --action <action> [--params '<json>']
#
# Actions:
#   show-work-item         — Fetch a work item by ID
#   create-work-item       — Create a new work item (with optional assigned_to, state)
#   update-work-item       — Update an existing work item
#   query-work-items       — Run a WIQL query
#   current-sprint         — Get the current active sprint/iteration
#   list-sprints           — List all sprints for the team
#   add-child              — Add a child work item link
#   close-work-item        — Set work item state to Done/Closed
#   create-task            — Create a task and link to parent in one call
#   create-with-children   — Create a PBI + child tasks + links in one call
#   resolve-sprints-for-range — Get all sprints overlapping a date range
#   query-my-sprint-items  — Query user's work items across sprints

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$REPO_DIR/data/config.json"

# --- Load config ---

ADO_ORG=""
ADO_PROJECT=""
ADO_TEAM=""
ADO_EMAIL=""

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        ADO_ORG=$(jq -r '.ado.organization // empty' "$CONFIG_FILE")
        ADO_PROJECT=$(jq -r '.ado.project // empty' "$CONFIG_FILE")
        ADO_TEAM=$(jq -r '.ado.team // empty' "$CONFIG_FILE")
        ADO_EMAIL=$(jq -r '.user.ado_email // empty' "$CONFIG_FILE")
    fi
}

load_config

# --- Helpers ---

json_ok() {
    # Strip non-JSON lines (e.g., az CLI warnings) before parsing
    printf '%s' "$1" | grep -v '^WARNING:' | jq '{success: true, data: .}'
}

json_error() {
    local msg="$1"
    local action="$2"
    jq -n --arg msg "$msg" --arg action "$action" '{"success":false,"error":$msg,"action":$action}'
}

require_param() {
    local value
    value=$(printf '%s' "$PARAMS" | jq -r ".$1 // empty")
    if [[ -z "$value" ]]; then
        json_error "Missing required parameter: $1" "$ACTION"
        exit 1
    fi
    printf '%s' "$value"
}

optional_param() {
    printf '%s' "$PARAMS" | jq -r ".$1 // empty"
}

# --- Parse arguments ---

ACTION=""
PARAMS="{}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --action) ACTION="$2"; shift 2 ;;
        --params) PARAMS="$2"; shift 2 ;;
        --params-file) PARAMS=$(cat "$2"); shift 2 ;;
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

    local cmd_args=(az boards work-item show --id "$id" --output json)
    if [[ -n "$fields" ]]; then
        cmd_args+=(--fields "$fields")
    fi

    local result
    result=$("${cmd_args[@]}" 2>&1) || {
        json_error "$result" "$ACTION"
        exit 1
    }
    json_ok "$result"
}

create_work_item() {
    local type title
    type=$(require_param "type") || exit 1
    title=$(require_param "title") || exit 1

    local area_path iteration_path description assigned_to state
    area_path=$(optional_param "area_path")
    iteration_path=$(optional_param "iteration_path")
    description=$(optional_param "description")
    assigned_to=$(optional_param "assigned_to")
    state=$(optional_param "state")

    local cmd_args=(az boards work-item create --type "$type" --title "$title" --output json)
    if [[ -n "$area_path" ]]; then
        cmd_args+=(--area "$area_path")
    fi
    if [[ -n "$iteration_path" ]]; then
        cmd_args+=(--iteration "$iteration_path")
    fi
    if [[ -n "$description" ]]; then
        cmd_args+=(--description "$description")
    fi

    # Collect --fields args
    local field_args=()
    if [[ -n "$assigned_to" ]]; then
        field_args+=("System.AssignedTo=$assigned_to")
    fi
    if [[ -n "$state" ]]; then
        field_args+=("System.State=$state")
    fi

    # Additional fields from params
    local fields_json
    fields_json=$(printf '%s' "$PARAMS" | jq -r '.fields // empty')
    if [[ -n "$fields_json" && "$fields_json" != "null" ]]; then
        while IFS= read -r entry; do
            field_args+=("$entry")
        done < <(printf '%s' "$fields_json" | jq -r 'to_entries[] | "\(.key)=\(.value)"')
    fi

    if [[ ${#field_args[@]} -gt 0 ]]; then
        cmd_args+=(--fields "${field_args[@]}")
    fi

    local result
    result=$("${cmd_args[@]}" 2>&1) || {
        json_error "$result" "$ACTION"
        exit 1
    }
    json_ok "$result"
}

update_work_item() {
    local id
    id=$(require_param "id") || exit 1

    local cmd_args=(az boards work-item update --id "$id" --output json)

    local title state
    title=$(optional_param "title")
    state=$(optional_param "state")

    if [[ -n "$title" ]]; then
        cmd_args+=(--title "$title")
    fi
    if [[ -n "$state" ]]; then
        cmd_args+=(--state "$state")
    fi

    local field_args=()
    local assigned_to
    assigned_to=$(optional_param "assigned_to")
    if [[ -n "$assigned_to" ]]; then
        field_args+=("System.AssignedTo=$assigned_to")
    fi

    local fields_json
    fields_json=$(printf '%s' "$PARAMS" | jq -r '.fields // empty')
    if [[ -n "$fields_json" && "$fields_json" != "null" ]]; then
        while IFS= read -r entry; do
            field_args+=("$entry")
        done < <(printf '%s' "$fields_json" | jq -r 'to_entries[] | "\(.key)=\(.value)"')
    fi

    if [[ ${#field_args[@]} -gt 0 ]]; then
        cmd_args+=(--fields "${field_args[@]}")
    fi

    local result
    result=$("${cmd_args[@]}" 2>&1) || {
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

    if [[ -z "$result" || "$result" == "" ]]; then
        result="[]"
    fi
    json_ok "$result"
}

current_sprint() {
    local team
    team=$(optional_param "team")
    if [[ -z "$team" && -n "$ADO_TEAM" ]]; then
        team="$ADO_TEAM"
    fi

    local cmd_args=(az boards iteration team list --output json)
    if [[ -n "$team" ]]; then
        cmd_args+=(--team "$team")
    fi

    local result
    result=$("${cmd_args[@]}" 2>&1) || {
        json_error "$result" "$ACTION"
        exit 1
    }

    local current
    current=$(printf '%s' "$result" | jq '[.[] | select(.attributes.timeFrame == "current")] | .[0]')

    if [[ "$current" == "null" ]]; then
        json_error "No current sprint found. Check team iteration settings in ADO." "$ACTION"
        exit 1
    fi
    json_ok "$current"
}

list_sprints() {
    local team
    team=$(optional_param "team")
    if [[ -z "$team" && -n "$ADO_TEAM" ]]; then
        team="$ADO_TEAM"
    fi

    local cmd_args=(az boards iteration team list --output json)
    if [[ -n "$team" ]]; then
        cmd_args+=(--team "$team")
    fi

    local result
    result=$("${cmd_args[@]}" 2>&1) || {
        json_error "$result" "$ACTION"
        exit 1
    }
    json_ok "$result"
}

resolve_sprints_for_range() {
    local from_date to_date team
    from_date=$(require_param "from") || exit 1
    to_date=$(require_param "to") || exit 1
    team=$(optional_param "team")
    if [[ -z "$team" && -n "$ADO_TEAM" ]]; then
        team="$ADO_TEAM"
    fi

    local cmd_args=(az boards iteration team list --output json)
    if [[ -n "$team" ]]; then
        cmd_args+=(--team "$team")
    fi

    local result
    result=$("${cmd_args[@]}" 2>&1) || {
        json_error "$result" "$ACTION"
        exit 1
    }

    # Filter to sprints overlapping [from_date, to_date]
    local matching
    matching=$(printf '%s' "$result" | jq --arg from "$from_date" --arg to "$to_date" '
        [.[] | select(
            .attributes.startDate != null and .attributes.finishDate != null
            and (.attributes.startDate[:10] <= $to)
            and (.attributes.finishDate[:10] >= $from)
        )]
    ')

    if [[ "$matching" == "[]" ]]; then
        json_error "No sprints found overlapping date range $from_date to $to_date" "$ACTION"
        exit 1
    fi
    json_ok "$matching"
}

query_my_sprint_items() {
    local assigned_to
    assigned_to=$(optional_param "assigned_to")
    if [[ -z "$assigned_to" && -n "$ADO_EMAIL" ]]; then
        assigned_to="$ADO_EMAIL"
    fi
    if [[ -z "$assigned_to" ]]; then
        json_error "Missing assigned_to param and no user.ado_email in config" "$ACTION"
        exit 1
    fi

    # Build iteration path filter from sprints array
    local sprints_json
    sprints_json=$(printf '%s' "$PARAMS" | jq '.sprints // empty')
    if [[ -z "$sprints_json" || "$sprints_json" == "null" || "$sprints_json" == "" ]]; then
        json_error "Missing required parameter: sprints (array of iteration paths)" "$ACTION"
        exit 1
    fi

    local iteration_clauses=""
    while IFS= read -r sprint_path; do
        sprint_path="${sprint_path%$'\r'}"  # Strip carriage return (Windows)
        if [[ -z "$sprint_path" ]]; then continue; fi
        if [[ -n "$iteration_clauses" ]]; then
            iteration_clauses="$iteration_clauses OR "
        fi
        iteration_clauses="${iteration_clauses}[System.IterationPath] = '${sprint_path}'"
    done < <(printf '%s' "$sprints_json" | jq -r '.[]')

    local wiql="SELECT [System.Id], [System.Title], [System.Description], [System.State], [System.WorkItemType], [System.IterationPath] FROM WorkItems WHERE [System.AssignedTo] = '${assigned_to}' AND (${iteration_clauses}) AND [System.State] <> 'Removed' ORDER BY [System.CreatedDate] DESC"

    local result
    result=$(az boards query --wiql "$wiql" --output json 2>&1) || {
        json_error "$result" "$ACTION"
        exit 1
    }

    # Handle empty results (az returns empty string, not [])
    if [[ -z "$result" || "$result" == "" ]]; then
        result="[]"
    fi
    json_ok "$result"
}

add_child() {
    local parent_id child_id
    parent_id=$(require_param "parent_id") || exit 1
    child_id=$(require_param "child_id") || exit 1

    local result
    result=$(az boards work-item relation add --id "$child_id" --relation-type parent --target-id "$parent_id" --output json 2>&1) || {
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
        state="Done"
    fi

    local result
    result=$(az boards work-item update --id "$id" --state "$state" --output json 2>&1) || {
        json_error "$result" "$ACTION"
        exit 1
    }
    json_ok "$result"
}

create_task() {
    local title parent_id
    title=$(require_param "title") || exit 1
    parent_id=$(require_param "parent_id") || exit 1

    local area_path iteration_path description assigned_to state
    area_path=$(optional_param "area_path")
    iteration_path=$(optional_param "iteration_path")
    description=$(optional_param "description")
    assigned_to=$(optional_param "assigned_to")
    if [[ -z "$assigned_to" && -n "$ADO_EMAIL" ]]; then
        assigned_to="$ADO_EMAIL"
    fi
    state=$(optional_param "state")

    # Create the task
    local cmd_args=(az boards work-item create --type Task --title "$title" --output json)
    if [[ -n "$area_path" ]]; then
        cmd_args+=(--area "$area_path")
    fi
    if [[ -n "$iteration_path" ]]; then
        cmd_args+=(--iteration "$iteration_path")
    fi
    if [[ -n "$description" ]]; then
        cmd_args+=(--description "$description")
    fi

    local field_args=()
    if [[ -n "$assigned_to" ]]; then
        field_args+=("System.AssignedTo=$assigned_to")
    fi
    if [[ -n "$state" ]]; then
        field_args+=("System.State=$state")
    fi

    if [[ ${#field_args[@]} -gt 0 ]]; then
        cmd_args+=(--fields "${field_args[@]}")
    fi

    local task_result
    task_result=$("${cmd_args[@]}" 2>&1) || {
        json_error "$task_result" "$ACTION"
        exit 1
    }

    local task_id
    task_id=$(printf '%s' "$task_result" | jq -r '.id')

    # Link to parent
    local link_result
    link_result=$(az boards work-item relation add --id "$task_id" --relation-type parent --target-id "$parent_id" --output json 2>&1) || {
        json_error "Task $task_id created but failed to link to parent $parent_id: $link_result" "$ACTION"
        exit 1
    }

    printf '%s' "$task_result" | jq --argjson parent "$parent_id" '{success: true, data: {task: ., parent_id: $parent}}'
}

create_with_children() {
    # Read PBI params
    local pbi_json
    pbi_json=$(printf '%s' "$PARAMS" | jq '.pbi')
    if [[ "$pbi_json" == "null" ]]; then
        json_error "Missing required parameter: pbi" "$ACTION"
        exit 1
    fi

    local pbi_type pbi_title pbi_area pbi_iteration pbi_description pbi_assigned pbi_state
    pbi_type=$(printf '%s' "$pbi_json" | jq -r '.type // "Product Backlog Item"')
    pbi_title=$(printf '%s' "$pbi_json" | jq -r '.title')
    pbi_area=$(printf '%s' "$pbi_json" | jq -r '.area_path // empty')
    pbi_iteration=$(printf '%s' "$pbi_json" | jq -r '.iteration_path // empty')
    pbi_description=$(printf '%s' "$pbi_json" | jq -r '.description // empty')
    pbi_assigned=$(printf '%s' "$pbi_json" | jq -r '.assigned_to // empty')
    pbi_state=$(printf '%s' "$pbi_json" | jq -r '.state // empty')
    if [[ -z "$pbi_assigned" && -n "$ADO_EMAIL" ]]; then
        pbi_assigned="$ADO_EMAIL"
    fi

    # Additional PBI fields
    local pbi_fields_json
    pbi_fields_json=$(printf '%s' "$pbi_json" | jq -r '.fields // empty')

    # Create PBI
    local pbi_cmd_args=(az boards work-item create --type "$pbi_type" --title "$pbi_title" --output json)
    if [[ -n "$pbi_area" ]]; then
        pbi_cmd_args+=(--area "$pbi_area")
    fi
    if [[ -n "$pbi_iteration" ]]; then
        pbi_cmd_args+=(--iteration "$pbi_iteration")
    fi
    if [[ -n "$pbi_description" ]]; then
        pbi_cmd_args+=(--description "$pbi_description")
    fi

    local pbi_field_args=()
    if [[ -n "$pbi_assigned" ]]; then
        pbi_field_args+=("System.AssignedTo=$pbi_assigned")
    fi
    if [[ -n "$pbi_state" ]]; then
        pbi_field_args+=("System.State=$pbi_state")
    fi
    if [[ -n "$pbi_fields_json" && "$pbi_fields_json" != "null" ]]; then
        while IFS= read -r entry; do
            pbi_field_args+=("$entry")
        done < <(printf '%s' "$pbi_fields_json" | jq -r 'to_entries[] | "\(.key)=\(.value)"')
    fi
    if [[ ${#pbi_field_args[@]} -gt 0 ]]; then
        pbi_cmd_args+=(--fields "${pbi_field_args[@]}")
    fi

    local pbi_result
    pbi_result=$("${pbi_cmd_args[@]}" 2>&1) || {
        json_error "Failed to create PBI: $pbi_result" "$ACTION"
        exit 1
    }

    local pbi_id
    pbi_id=$(printf '%s' "$pbi_result" | jq -r '.id')

    # Create child tasks
    local tasks_json
    tasks_json=$(printf '%s' "$PARAMS" | jq '.tasks // []')
    local task_count
    task_count=$(printf '%s' "$tasks_json" | jq 'length')
    local task_ids="[]"
    local errors="[]"

    for (( i=0; i<task_count; i++ )); do
        local task
        task=$(printf '%s' "$tasks_json" | jq ".[$i]")

        local t_title t_description t_assigned t_state t_area t_iteration
        t_title=$(printf '%s' "$task" | jq -r '.title')
        t_description=$(printf '%s' "$task" | jq -r '.description // empty')
        t_assigned=$(printf '%s' "$task" | jq -r '.assigned_to // empty')
        t_state=$(printf '%s' "$task" | jq -r '.state // empty')
        t_area=$(printf '%s' "$task" | jq -r '.area_path // empty')
        t_iteration=$(printf '%s' "$task" | jq -r '.iteration_path // empty')

        # Inherit from PBI if not set
        if [[ -z "$t_area" ]]; then t_area="$pbi_area"; fi
        if [[ -z "$t_iteration" ]]; then t_iteration="$pbi_iteration"; fi
        if [[ -z "$t_assigned" ]]; then t_assigned="$pbi_assigned"; fi

        local t_cmd_args=(az boards work-item create --type Task --title "$t_title" --output json)
        if [[ -n "$t_area" ]]; then t_cmd_args+=(--area "$t_area"); fi
        if [[ -n "$t_iteration" ]]; then t_cmd_args+=(--iteration "$t_iteration"); fi
        if [[ -n "$t_description" ]]; then t_cmd_args+=(--description "$t_description"); fi

        local t_field_args=()
        if [[ -n "$t_assigned" ]]; then t_field_args+=("System.AssignedTo=$t_assigned"); fi
        if [[ -n "$t_state" ]]; then t_field_args+=("System.State=$t_state"); fi
        if [[ ${#t_field_args[@]} -gt 0 ]]; then t_cmd_args+=(--fields "${t_field_args[@]}"); fi

        local t_result
        t_result=$("${t_cmd_args[@]}" 2>&1)
        if [[ $? -ne 0 ]]; then
            errors=$(printf '%s' "$errors" | jq --arg title "$t_title" --arg err "$t_result" '. + [{"title": $title, "error": $err}]')
            continue
        fi

        local t_id
        t_id=$(printf '%s' "$t_result" | jq -r '.id')

        # Link to parent
        az boards work-item relation add --id "$t_id" --relation-type parent --target-id "$pbi_id" --output json >/dev/null 2>&1 || {
            errors=$(printf '%s' "$errors" | jq --arg title "$t_title" --argjson id "$t_id" '. + [{"title": $title, "task_id": $id, "error": "created but failed to link to parent"}]')
        }

        task_ids=$(printf '%s' "$task_ids" | jq --argjson id "$t_id" '. + [$id]')
    done

    jq -n --argjson pbi_id "$pbi_id" --argjson task_ids "$task_ids" --argjson errors "$errors" \
        '{success: true, data: {pbi_id: $pbi_id, task_ids: $task_ids, errors: $errors}}'
}

# --- Dispatch ---

case "$ACTION" in
    show-work-item)            show_work_item ;;
    create-work-item)          create_work_item ;;
    update-work-item)          update_work_item ;;
    query-work-items)          query_work_items ;;
    current-sprint)            current_sprint ;;
    list-sprints)              list_sprints ;;
    add-child)                 add_child ;;
    close-work-item)           close_work_item ;;
    create-task)               create_task ;;
    create-with-children)      create_with_children ;;
    resolve-sprints-for-range) resolve_sprints_for_range ;;
    query-my-sprint-items)     query_my_sprint_items ;;
    *)
        json_error "Unknown action: $ACTION. Valid actions: show-work-item, create-work-item, update-work-item, query-work-items, current-sprint, list-sprints, add-child, close-work-item, create-task, create-with-children, resolve-sprints-for-range, query-my-sprint-items" "$ACTION"
        exit 1
        ;;
esac
