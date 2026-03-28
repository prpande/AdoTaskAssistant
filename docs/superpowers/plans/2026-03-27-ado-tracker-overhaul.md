# ADO Tracker Overhaul — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden all scripts, reconcile config, add dedup/sprint-awareness/state-lifecycle to prompts, and make the full scan pipeline work end-to-end without manual intervention.

**Architecture:** Bottom-up rewrite in 4 layers — scripts first (security + new actions), then config schema, then prompts (concrete algorithms), then automations (orchestration). Each task produces a working, committable change.

**Tech Stack:** Bash/jq (scripts), Markdown (prompts/automations/skills), JSON (config/data)

---

### Task 1: Rewrite ado-cli.sh — eliminate eval, add config loading

**Files:**
- Modify: `scripts/ado-cli.sh`

- [ ] **Step 1: Replace eval with array-based command execution**

Replace the entire `scripts/ado-cli.sh` with safe array-based commands. Every action uses `cmd_args+=()` instead of string concatenation + `eval`.

```bash
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
    printf '%s' "$1" | jq '{success: true, data: .}'
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
    sprints_json=$(printf '%s' "$PARAMS" | jq -r '.sprints // empty')
    if [[ -z "$sprints_json" || "$sprints_json" == "null" ]]; then
        json_error "Missing required parameter: sprints (array of iteration paths)" "$ACTION"
        exit 1
    fi

    local iteration_clauses=""
    while IFS= read -r sprint_path; do
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
```

- [ ] **Step 2: Test show-work-item still works**

Run: `bash scripts/ado-cli.sh --action show-work-item --params '{"id":1505951}' | jq '.success'`
Expected: `true`

- [ ] **Step 3: Test create-work-item with assigned_to and state**

Run: `bash scripts/ado-cli.sh --action resolve-sprints-for-range --params '{"from":"2026-03-20","to":"2026-03-27"}' | jq '.success'`
Expected: `true` with array of overlapping sprints

- [ ] **Step 4: Commit**

```bash
git add scripts/ado-cli.sh
git commit -m "Rewrite ado-cli.sh: eliminate eval injection, add create-with-children, create-task, resolve-sprints-for-range, query-my-sprint-items, config-aware loading"
```

---

### Task 2: Fix extract-git-activity.sh — filter by remote org, fix dates

**Files:**
- Modify: `scripts/extract-git-activity.sh`

- [ ] **Step 1: Add --filter-org argument and remote URL filtering**

Replace the auto-detect section (lines 49-58) and add org filtering:

```bash
# After the auto-detect block that populates repo_list, add:

# --- Filter by remote org if specified ---

FILTER_ORG=""
# Check for --filter-org argument (add to arg parser)
# In the while loop, add:
#   --filter-org) FILTER_ORG="$2"; shift 2 ;;

if [[ -n "$FILTER_ORG" ]]; then
    filtered_repos=()
    for repo in "${repo_list[@]}"; do
        remote_url=$(git -C "$repo" remote get-url origin 2>/dev/null || echo "")
        if [[ "$remote_url" == *"$FILTER_ORG"* ]]; then
            filtered_repos+=("$repo")
        fi
    done
    repo_list=("${filtered_repos[@]}")
fi
```

Full replacement of `scripts/extract-git-activity.sh`:

```bash
#!/usr/bin/env bash
# extract-git-activity.sh — Extract git commits across repos for a date range
#
# Usage:
#   bash scripts/extract-git-activity.sh --from <YYYY-MM-DD> --to <YYYY-MM-DD> [--repos '<json-array>'] [--auto-detect <parent-dir>] [--filter-org <org-name>]

set -o pipefail

# --- Helpers ---

json_ok() {
    printf '%s' "$1" | jq '{success: true, data: .}'
}

json_error() {
    jq -n --arg msg "$1" '{"success":false,"error":$msg}'
}

# --- Parse arguments ---

FROM_DATE=""
TO_DATE=""
REPOS="[]"
AUTO_DETECT=""
FILTER_ORG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --from) FROM_DATE="$2"; shift 2 ;;
        --to) TO_DATE="$2"; shift 2 ;;
        --repos) REPOS="$2"; shift 2 ;;
        --auto-detect) AUTO_DETECT="$2"; shift 2 ;;
        --filter-org) FILTER_ORG="$2"; shift 2 ;;
        *) json_error "Unknown argument: $1"; exit 1 ;;
    esac
done

if [[ -z "$FROM_DATE" || -z "$TO_DATE" ]]; then
    json_error "Missing required arguments: --from and --to (YYYY-MM-DD)"
    exit 1
fi

# --- Auto-detect repos if needed ---

repo_list=()

if [[ -n "$AUTO_DETECT" ]]; then
    if [[ ! -d "$AUTO_DETECT" ]]; then
        json_error "Auto-detect directory does not exist: $AUTO_DETECT"
        exit 1
    fi
    while IFS= read -r dir; do
        if [[ -d "$dir/.git" ]]; then
            repo_list+=("$dir")
        fi
    done < <(find "$AUTO_DETECT" -maxdepth 1 -type d 2>/dev/null)
fi

# Add explicitly listed repos
while IFS= read -r repo; do
    if [[ -n "$repo" ]]; then
        repo_list+=("$repo")
    fi
done < <(printf '%s' "$REPOS" | jq -r '.[]')

# --- Filter by remote org ---

if [[ -n "$FILTER_ORG" ]]; then
    filtered_repos=()
    for repo in "${repo_list[@]}"; do
        remote_url=$(git -C "$repo" remote get-url origin 2>/dev/null || echo "")
        if [[ "$remote_url" == *"$FILTER_ORG"* ]]; then
            filtered_repos+=("$repo")
        fi
    done
    repo_list=("${filtered_repos[@]}")
fi

if [[ ${#repo_list[@]} -eq 0 ]]; then
    json_error "No repos found. Provide --repos, --auto-detect, or check --filter-org."
    exit 1
fi

# --- Get current git user ---

GIT_USER_EMAIL=$(git config user.email 2>/dev/null || echo "")

# --- Extract commits ---

all_commits="[]"

for repo in "${repo_list[@]}"; do
    if [[ ! -d "$repo/.git" ]]; then
        continue
    fi

    repo_name=$(basename "$repo")

    # Use ISO dates directly — works cross-platform without date command
    commits_json=$(git -C "$repo" log \
        --after="$FROM_DATE" \
        --before="$TO_DATE" \
        --author="$GIT_USER_EMAIL" \
        --format='{"hash":"%H","short_hash":"%h","subject":"%s","date":"%ai","author":"%an"}' \
        2>/dev/null | jq -s --arg repo "$repo_name" --arg repo_path "$repo" '[.[] | . + {"repo": $repo, "repo_path": $repo_path}]')

    # Skip repos with no commits
    if [[ -z "$commits_json" || "$commits_json" == "[]" || "$commits_json" == "null" ]]; then
        continue
    fi

    all_commits=$(printf '%s\n%s' "$all_commits" "$commits_json" | jq -s '.[0] + .[1]')
done

# --- Build summary ---

summary=$(printf '%s' "$all_commits" | jq '{
    total_commits: length,
    repos: (group_by(.repo) | map({
        repo: .[0].repo,
        commit_count: length,
        commits: [.[] | {hash: .short_hash, subject: .subject, date: .date}]
    })),
    date_range: {from: "'"$FROM_DATE"'", to: "'"$TO_DATE"'"}
}')

json_ok "$summary"
```

- [ ] **Step 2: Test with filter-org**

Run: `bash scripts/extract-git-activity.sh --from 2026-03-25 --to 2026-03-28 --auto-detect "C:/src" --filter-org mindbody | jq '.data.repos[].repo'`
Expected: Only repos with `mindbody` in their origin URL

- [ ] **Step 3: Commit**

```bash
git add scripts/extract-git-activity.sh
git commit -m "Fix extract-git-activity.sh: add --filter-org for remote URL filtering, skip empty repos"
```

---

### Task 3: Fix template-manager.sh — iteration pattern, expanded validation

**Files:**
- Modify: `scripts/template-manager.sh`

- [ ] **Step 1: Fix iteration pattern extraction and expand validation**

In the `extract_template` function (line 141-195), replace the iteration pattern logic:

Replace:
```
(split("\\") | last | gsub("[0-9]+"; "{number}")) as $last_part |
(split("\\") | .[:-1] + [$last_part] | join("\\"))
```

With:
```
(split("\\") | last | gsub("[0-9]{4}"; "{year}") | gsub("{year}-[0-9]+"; "{year}-{sprint_number}")) as $last_part |
(split("\\") | .[:-1] + [$last_part] | join("\\"))
```

In the `validate_template` function (line 101-128), expand required_fields:

Replace:
```bash
local required_fields=("work_item_type" "area_path" "iteration_path_pattern")
```

With:
```bash
local required_fields=("work_item_type" "area_path" "iteration_path_pattern" "title_prefix_pbi" "description_format")
```

- [ ] **Step 2: Test validation with current template**

Run: `bash scripts/template-manager.sh --action validate | jq '.success'`
Expected: `true`

- [ ] **Step 3: Commit**

```bash
git add scripts/template-manager.sh
git commit -m "Fix template-manager.sh: use year/sprint_number placeholders, validate title_prefix and description_format"
```

---

### Task 4: Simplify parse-session-logs.sh — best-effort, graceful empty

**Files:**
- Modify: `scripts/parse-session-logs.sh`

- [ ] **Step 1: Replace with best-effort version**

Replace the entire file with a simplified version that returns gracefully when no logs are found:

```bash
#!/usr/bin/env bash
# parse-session-logs.sh — Parse Claude Code session logs for a date range (best-effort)
#
# Usage:
#   bash scripts/parse-session-logs.sh --from <YYYY-MM-DD> --to <YYYY-MM-DD> [--path <session-log-dir>]
#
# Returns session data if available, empty result if not. Never fails — git activity is the primary signal.

set -o pipefail

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
        --to) TO_DATE="$2"; shift 2 ;;
        --path) SESSION_PATH="$2"; shift 2 ;;
        *) shift ;;  # Ignore unknown args — best-effort
    esac
done

if [[ -z "$FROM_DATE" || -z "$TO_DATE" ]]; then
    json_ok '{"session_count":0,"sessions":[],"note":"Missing date arguments"}'
    exit 0
fi

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

if [[ -z "$SESSION_PATH" || ! -d "$SESSION_PATH" ]]; then
    json_ok '{"session_count":0,"sessions":[],"note":"No session log directory found. This is normal if Claude Code sessions have not been used."}'
    exit 0
fi

# --- Parse session files ---

sessions="[]"
session_count=0

while IFS= read -r session_file; do
    # Try to extract session info from JSONL files
    if [[ "$session_file" == *.jsonl ]]; then
        session_summary=$(jq -s '{
            file: input_filename,
            message_count: length,
            tools_used: [.[].tool // empty] | unique
        }' "$session_file" 2>/dev/null)
    elif [[ "$session_file" == *.json ]]; then
        session_summary=$(jq '{
            file: input_filename,
            description: (.description // .summary // "No description")
        }' "$session_file" 2>/dev/null)
    else
        continue
    fi

    if [[ -n "$session_summary" && "$session_summary" != "null" ]]; then
        sessions=$(printf '%s\n%s' "$sessions" "[$session_summary]" | jq -s '.[0] + .[1]')
        session_count=$((session_count + 1))
    fi
done < <(find "$SESSION_PATH" -type f \( -name "*.jsonl" -o -name "*.json" \) -newer "$FROM_DATE" 2>/dev/null || true)

# --- Build summary ---

summary=$(printf '%s' "$sessions" | jq \
    --arg from "$FROM_DATE" \
    --arg to "$TO_DATE" \
    --arg path "$SESSION_PATH" \
    '{
        session_count: (. | length),
        sessions: .,
        date_range: {from: $from, to: $to},
        log_path: $path
    }')

json_ok "$summary"
```

- [ ] **Step 2: Test that it returns gracefully**

Run: `bash scripts/parse-session-logs.sh --from 2026-03-20 --to 2026-03-27 | jq '.success'`
Expected: `true` (with sessions or empty array, never an error)

- [ ] **Step 3: Commit**

```bash
git add scripts/parse-session-logs.sh
git commit -m "Simplify parse-session-logs.sh: best-effort only, graceful empty return, never blocks pipeline"
```

---

### Task 5: Update config.json schema — add user section

**Files:**
- Modify: `data/config.json`

- [ ] **Step 1: Update config.json with user section and notion.filter_types**

```json
{
  "ado": {
    "organization": "https://dev.azure.com/mindbody",
    "project": "MBScrum",
    "team": "squad-biz-app"
  },
  "user": {
    "ado_email": "pratyush.pande@playlist.com",
    "github_username": "prpande",
    "notion_user_id": "2f8d872b-594c-81a7-a5c5-0002f6a8eb70"
  },
  "github": {
    "organizations": ["mindbody"],
    "excluded_repos": []
  },
  "notion": {
    "scope": "all",
    "excluded_databases": [],
    "filter_types": ["page"]
  },
  "git": {
    "source_root": "C:/src",
    "auto_detect": true,
    "filter_by_remote_org": "mindbody",
    "explicit_repos": []
  },
  "schedule": {
    "daily_scan_time": "10:00"
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add data/config.json
git commit -m "Add user section to config.json: ado_email, github_username, notion_user_id; add notion.filter_types"
```

---

### Task 6: Rewrite all prompts

**Files:**
- Modify: `prompts/ado-tracker-gather-github.prompt.md`
- Modify: `prompts/ado-tracker-gather-notion.prompt.md`
- Modify: `prompts/ado-tracker-gather-sessions.prompt.md`
- Modify: `prompts/ado-tracker-propose-updates.prompt.md`
- Modify: `prompts/ado-tracker-apply-updates.prompt.md`
- Modify: `prompts/ado-tracker-create-pbi.prompt.md`
- Modify: `prompts/ado-tracker-create-task.prompt.md`
- Modify: `prompts/ado-tracker-breakdown-pbi.prompt.md`

- [ ] **Step 1: Rewrite gather-github prompt**

Replace `prompts/ado-tracker-gather-github.prompt.md` with:

```markdown
# Gather GitHub Activity

## Goal
Fetch GitHub PRs authored or reviewed by the user within a date range, filtered by configured organizations.

## Context
- Config: `data/config.json` — read `user.github_username`, `github.organizations`, `github.excluded_repos`
- Tool: `gh` CLI (must be authenticated)

## Input
- `from_date`: Start date (YYYY-MM-DD)
- `to_date`: End date (YYYY-MM-DD)

## Instructions

1. Read `data/config.json`. Use `user.github_username` — do NOT call `gh api user`.

2. For each org in `github.organizations`, search for PRs authored by the user:
   ```bash
   gh search prs --author=<username> --created=<from_date>..<to_date> --owner=<org> --json number,title,repository,state,createdAt,updatedAt,url --limit 100
   ```
   If results return exactly 100, fetch the next page with `--page 2` and continue until fewer than 100 results are returned.

3. Also search for PRs reviewed by the user:
   ```bash
   gh search prs --reviewed-by=<username> --created=<from_date>..<to_date> --owner=<org> --json number,title,repository,state,createdAt,updatedAt,url --limit 100
   ```

4. Filter out any repos in `github.excluded_repos`.

5. Deduplicate by PR URL. If a PR appears in both authored and reviewed results, keep one entry with `role: "author+reviewer"`.

6. Return structured JSON array:
   ```json
   [
     {
       "type": "github_pr",
       "pr_number": 1234,
       "title": "Add retry logic",
       "repo": "org/repo-name",
       "url": "https://github.com/org/repo/pull/1234",
       "state": "merged",
       "role": "author",
       "created_at": "2026-03-27",
       "updated_at": "2026-03-27"
     }
   ]
   ```

## Output
JSON array of PR activity objects.
```

- [ ] **Step 2: Rewrite gather-notion prompt**

Replace `prompts/ado-tracker-gather-notion.prompt.md` with:

```markdown
# Gather Notion Activity

## Goal
Fetch Notion pages created by the user within a date range.

## Context
- Config: `data/config.json` — read `user.notion_user_id`, `notion.scope`, `notion.excluded_databases`, `notion.filter_types`
- Tool: Notion MCP (`notion-search`)

## Input
- `from_date`: Start date (YYYY-MM-DD)
- `to_date`: End date (YYYY-MM-DD)

## Instructions

1. Read `data/config.json`. Use `user.notion_user_id` — do NOT call `notion-get-users`.

2. Search Notion with the stored user ID:
   ```
   notion-search:
     query: "*"
     filters:
       created_date_range: {start_date: <from_date>, end_date: <to_date + 1 day>}
       created_by_user_ids: [<user.notion_user_id>]
     page_size: 25
     max_highlight_length: 50
   ```

3. Filter results:
   - Only include results where `type` is in `notion.filter_types` (default: `["page"]`). Drop Slack, SharePoint, and other connector results.
   - If `notion.scope` is `"databases"`, only include pages from non-excluded databases.
   - Filter out any databases in `notion.excluded_databases`.

4. For each qualifying page, extract:
   - Page title
   - Page ID and URL
   - Parent context (from the search result metadata)
   - Timestamp

5. Return structured JSON array:
   ```json
   [
     {
       "type": "notion_page",
       "page_id": "abc-123",
       "title": "Architecture Overview — AI Chatbot",
       "url": "https://www.notion.so/abc123",
       "role": "owner",
       "last_edited": "2026-03-27"
     }
   ]
   ```

## Output
JSON array of Notion activity objects (pages only, filtered to user).
```

- [ ] **Step 3: Rewrite gather-sessions prompt**

Replace `prompts/ado-tracker-gather-sessions.prompt.md` with:

```markdown
# Gather Claude Session & Git Activity

## Goal
Gather git commits and (optionally) Claude Code session data for a date range. Git activity is the primary signal; session data is best-effort bonus context.

## Context
- Config: `data/config.json` — read `git.source_root`, `git.auto_detect`, `git.filter_by_remote_org`, `git.explicit_repos`
- Git extractor: `bash scripts/extract-git-activity.sh`
- Session parser: `bash scripts/parse-session-logs.sh` (best-effort)

## Input
- `from_date`: Start date (YYYY-MM-DD)
- `to_date`: End date (YYYY-MM-DD)

## Instructions

1. Read `data/config.json` for git settings.

2. Extract git activity using the config:
   ```bash
   bash scripts/extract-git-activity.sh --from <from_date> --to <to_date> --auto-detect "<git.source_root>" --filter-org "<git.filter_by_remote_org>"
   ```
   If `git.explicit_repos` is non-empty, also pass `--repos '<json-array>'`.

3. Parse Claude Code session logs (best-effort — if this fails or returns empty, continue without it):
   ```bash
   bash scripts/parse-session-logs.sh --from <from_date> --to <to_date>
   ```

4. Build the output. For each repo with commits, create a dev_activity entry:
   ```json
   [
     {
       "type": "dev_activity",
       "source": "git",
       "repo": "Mindbody.Scheduling",
       "summary": "<brief summary of commits>",
       "commit_count": 20,
       "commits": [{"hash": "abc1234", "subject": "..."}],
       "date_range": "2026-03-25 to 2026-03-27"
     }
   ]
   ```

5. If session data was found, add it as context to matching repo entries where possible. Sessions without matching repos are included as standalone entries.

## Output
JSON array of development activity objects.
```

- [ ] **Step 4: Rewrite propose-updates prompt**

Replace `prompts/ado-tracker-propose-updates.prompt.md` with:

```markdown
# Propose ADO Updates

## Goal
Take gathered activity, cross-reference with existing ADO work items, resolve sprints, deduplicate, determine state, and present a grouped proposal for user approval.

## Context
- ADO CLI: `bash scripts/ado-cli.sh`
- Template: `bash scripts/template-manager.sh --action read`
- Config: `data/config.json` — read `user.ado_email`

## Input
- `activity`: Combined JSON from all gather prompts (GitHub, Notion, sessions/git)
- `sprints`: Array of overlapping sprints from `resolve-sprints-for-range`

## Instructions

### Phase 1: Map activity to sprints

For each activity item, determine which sprint it belongs to based on the item's date and the sprint date ranges. An activity's primary date is:
- GitHub PR: `created_at`
- Notion page: `last_edited`
- Git commits: date of first commit in the group

### Phase 2: Dedup against existing items

1. Query existing work items across all overlapping sprints:
   ```bash
   bash scripts/ado-cli.sh --action query-my-sprint-items --params '{"sprints": [<sprint-paths>]}'
   ```

2. For each existing work item, scan its description for source URLs (GitHub PR links, Notion page links).

3. Build a lookup: `{source_url → work_item_id}`

4. For each gathered activity item:
   - If its source URL is in the lookup → mark as **already tracked**
   - If title keywords overlap significantly with an existing item → mark as **potential match** (flag for user)
   - Otherwise → mark as **new**

### Phase 3: Smart grouping of new items

Group unmatched activity using these signals (in priority order):
1. **Git branch name prefix** — same branch prefix across repos = same feature (e.g., `pp/gstBooking-2503` in Scheduling + Clients)
2. **PR cross-references** — PR body or commits mentioning other repos/PRs
3. **Notion page hierarchy** — pages sharing a parent or title pattern
4. **Time proximity** — commits in the same repo on the same day

Each group becomes one proposed PBI with child tasks.

### Phase 4: Determine state

Apply the template's `title_prefix_pbi` to PBI titles (prompt user for `{featureArea}` if needed).

Set state based on source type:

| Source | PBI State | Task State | Auto-update to Done? |
|--------|-----------|------------|---------------------|
| GitHub PR (open) | Committed | In Progress | Yes — when PR merges |
| GitHub PR (merged) | Done | Done | N/A |
| Notion page | Committed | In Progress | **Never** — user decides |
| Git commits (no PR) | Committed | In Progress | Never |

If a group contains mixed sources (e.g., merged PR + open PR), use the most active state (Committed over Done).

### Phase 5: State lifecycle updates for existing items

For items marked as **already tracked**, check if state needs updating:
- If a tracked PR was open but is now merged → propose **update-state → Done**
- If all child tasks of a PBI are now Done → propose **update-parent-state → Done**
- Notion-sourced tasks → **never propose auto-close**

### Phase 6: Present proposal

Group by sprint, then by action type:

```
## Sprint 2026-06 (Mar 11 – Mar 24)

### State Updates
- Task #12346 → Done (PR #1034 now merged)
- PBI #12345 → Done (all children completed)

## Sprint 2026-07 (Mar 25 – Apr 7)

### New Items
1. [BizApp][Backend][Feature] Title — source summary
   Tasks: task1 (Done), task2 (In Progress)

### Already Tracked (skipped)
- PR #808 covered by PBI #12345
```

Always assign all items to `user.ado_email` from config.
Always embed source URLs in descriptions for future dedup.
Always use `description_format` from template for PBI descriptions.

### Controls

After presenting, offer:
- "Enter item numbers to approve (e.g., `1,3`), `all`, or `none`."
- "Enter `expand <number>` for full preview."
- "Enter `edit <number>` to modify before approving."

Return approved items as structured JSON for the apply step.

## Output
JSON array of approved actions:
```json
[
  {
    "action": "create",
    "sprint_path": "MBScrum\\Sprint 2026-07",
    "pbi": {"title": "...", "description": "...", "state": "Committed", "assigned_to": "..."},
    "tasks": [{"title": "...", "state": "Done", "description": "..."}]
  },
  {
    "action": "update-state",
    "work_item_id": 12345,
    "new_state": "Done"
  }
]
```
```

- [ ] **Step 5: Rewrite apply-updates prompt**

Replace `prompts/ado-tracker-apply-updates.prompt.md` with:

```markdown
# Apply ADO Updates

## Goal
Execute user-approved ADO changes — create PBIs with children, update states, close items.

## Context
- ADO CLI: `bash scripts/ado-cli.sh`
- Config: `data/config.json` — read `user.ado_email`

## Input
- `approved_actions`: JSON array from propose-updates
- `sprint_folder`: Path for saving results

## Instructions

1. For each approved action, execute:

   **create** — Use `create-with-children` for PBIs with tasks:
   ```bash
   bash scripts/ado-cli.sh --action create-with-children --params '{
     "pbi": {"type": "Product Backlog Item", "title": "...", "area_path": "...", "iteration_path": "...", "description": "...", "assigned_to": "...", "state": "...", "fields": {...}},
     "tasks": [{"title": "...", "description": "...", "state": "...", "assigned_to": "..."}]
   }'
   ```

   **create-task** — For adding tasks to existing PBIs:
   ```bash
   bash scripts/ado-cli.sh --action create-task --params '{"title": "...", "parent_id": <id>, "description": "...", "state": "...", "assigned_to": "..."}'
   ```

   **update-state** — For changing work item state:
   ```bash
   bash scripts/ado-cli.sh --action update-work-item --params '{"id": <id>, "state": "<new_state>"}'
   ```

2. Always embed source URLs in descriptions. Use the template's `description_format`:
   ```
   ## Summary
   <summary>

   ## Source
   <PR links, Notion links, commit refs>

   ## Date
   <activity date range>
   ```

3. Track results for each action:
   - Success: record work item ID, URL, action
   - Failure: record error, show to user, ask retry or skip

4. Save results to sprint folder:
   ```json
   {
     "run_type": "daily|adhoc",
     "date": "2026-03-27",
     "sprints": ["Sprint 2026-07"],
     "applied": [{"action": "create", "pbi_id": 12345, "task_ids": [12346], "status": "success"}],
     "errors": []
   }
   ```

5. Present summary:
   ```
   ## Applied Changes
   Created PBI #12345: "Title" (Committed) — 3 tasks
   Updated Task #12346 → Done
   ```

## Output
Summary of applied changes with links to created/updated work items.
```

- [ ] **Step 6: Rewrite create-pbi prompt**

Replace `prompts/ado-tracker-create-pbi.prompt.md` with:

```markdown
# Create PBI

## Goal
Create a new Product Backlog Item in ADO using the saved template.

## Context
- ADO CLI: `bash scripts/ado-cli.sh`
- Template: `bash scripts/template-manager.sh --action read`
- Config: `data/config.json`

## Input
The user provides a description of the work item.

## Instructions

1. Read template and config. If either is missing → direct user to `/ado-tracker-init`.

2. Detect current sprint:
   ```bash
   bash scripts/ado-cli.sh --action current-sprint
   ```

3. Generate PBI fields:
   - **Title**: Apply `title_prefix_pbi` from template. Prompt user for `{featureArea}` placeholder value. Example: `[BizApp][Backend][Scheduling] Add retry logic`
   - **Description**: Format using `description_format` from template
   - **Area Path**: From template
   - **Iteration Path**: Current sprint
   - **State**: Ask user (default: New)
   - **Assigned To**: `user.ado_email` from config
   - **Priority**: Template default
   - **Additional fields**: From template `fields` section

4. Present preview. Ask user to confirm or edit.

5. On approval, create:
   ```bash
   bash scripts/ado-cli.sh --action create-work-item --params '{
     "type": "Product Backlog Item",
     "title": "...",
     "area_path": "...",
     "iteration_path": "...",
     "description": "...",
     "assigned_to": "...",
     "state": "...",
     "fields": {...}
   }'
   ```

6. Report result with work item ID and URL.

## Output
Created PBI with ID and URL.
```

- [ ] **Step 7: Rewrite create-task prompt**

Replace `prompts/ado-tracker-create-task.prompt.md` with:

```markdown
# Create Task Under PBI

## Goal
Create one or more child tasks under an existing PBI.

## Context
- ADO CLI: `bash scripts/ado-cli.sh`
- Template: `bash scripts/template-manager.sh --action read`
- Config: `data/config.json`

## Input
- `pbi_id`: The parent PBI work item ID
- `description`: Description of the task(s) to create

## Instructions

1. Fetch the parent PBI:
   ```bash
   bash scripts/ado-cli.sh --action show-work-item --params '{"id":<pbi_id>}'
   ```

2. Read template and config.

3. Generate task fields:
   - **Title**: Concise task title (no prefix convention for tasks)
   - **Area Path**: Inherit from parent PBI
   - **Iteration Path**: Inherit from parent PBI
   - **State**: Ask user (default: New)
   - **Assigned To**: `user.ado_email` from config
   - **Description**: Task-level description

4. Present preview with parent context.

5. On approval, create and link:
   ```bash
   bash scripts/ado-cli.sh --action create-task --params '{
     "title": "...",
     "parent_id": <pbi_id>,
     "area_path": "...",
     "iteration_path": "...",
     "description": "...",
     "assigned_to": "...",
     "state": "..."
   }'
   ```

6. Report result with task ID, URL, and parent link.

## Output
Created task(s) with IDs, URLs, and parent PBI link.
```

- [ ] **Step 8: Rewrite breakdown-pbi prompt**

Replace `prompts/ado-tracker-breakdown-pbi.prompt.md` with:

```markdown
# Break Down PBI

## Goal
Decompose an existing PBI into multiple child tasks, avoiding duplicates.

## Context
- ADO CLI: `bash scripts/ado-cli.sh`
- Template: `bash scripts/template-manager.sh --action read`
- Config: `data/config.json`

## Input
- `pbi_id`: The PBI work item ID to break down

## Instructions

1. Fetch the PBI:
   ```bash
   bash scripts/ado-cli.sh --action show-work-item --params '{"id":<pbi_id>}'
   ```

2. Check for existing child tasks by inspecting the work item's `relations` array. Filter for `System.LinkTypes.Hierarchy-Forward` (child links). For each child, fetch its title and state.

3. Read template and config.

4. Analyze the PBI title and description. Propose child tasks:
   - Each task should be concrete and actionable
   - Tasks should cover the full scope of the PBI
   - **Dedup**: Skip any proposed task whose title closely matches an existing child task
   - Show existing children so the user can see what's already covered

5. Present the breakdown:
   ```
   ## PBI #<id>: <title>

   ### Existing Tasks
   - #12345: "Task A" (Done)
   - #12346: "Task B" (In Progress)

   ### Proposed New Tasks
   1. "Task C" — description
   2. "Task D" — description
   ```

6. Ask: "Approve all, select specific, or edit?"

7. Create approved tasks using `create-task` action (which handles creation + parent linking):
   ```bash
   bash scripts/ado-cli.sh --action create-task --params '{
     "title": "...",
     "parent_id": <pbi_id>,
     "area_path": "...",
     "iteration_path": "...",
     "assigned_to": "...",
     "state": "..."
   }'
   ```

8. Report all created tasks.

## Output
List of created child tasks with IDs, URLs, and parent link.
```

- [ ] **Step 9: Commit all prompts**

```bash
git add prompts/
git commit -m "Rewrite all prompts: use config identities, template prefixes, dedup, sprint-aware state lifecycle, create-with-children"
```

---

### Task 7: Rewrite automations — multi-sprint, dedup, state lifecycle

**Files:**
- Modify: `automations/ado-tracker-daily.automation.md`
- Modify: `automations/ado-tracker-adhoc.automation.md`

- [ ] **Step 1: Rewrite daily automation**

Replace `automations/ado-tracker-daily.automation.md` with:

```markdown
# ADO Tracker — Daily Scan

## Goal
Full daily workflow: resolve sprints, gather all activity since last run, deduplicate against existing items, check state lifecycle, propose updates, apply approved changes, persist results.

## Steps

### Step 1: Load Configuration
- Read `data/config.json`. If missing → "Run `/ado-tracker-init` to set up."
- Read `data/task-template.json`. If missing → same.
- Read `data/last-run.json`. If missing → first run, set `since_date` to yesterday.
- **On failure**: Stop and direct user to `/ado-tracker-init`.

### Step 2: Resolve Sprints
- Determine date range: `from` = last_run_date (or yesterday), `to` = today.
- Resolve all overlapping sprints:
  ```bash
  bash scripts/ado-cli.sh --action resolve-sprints-for-range --params '{"from":"<from>","to":"<to>"}'
  ```
- Present to user: "Scan covers: Sprint X (dates), Sprint Y (dates). Proceed?"
- If last_run sprint differs from current sprint, alert: "Sprint changed from <old> to <new>."
- Create sprint data folders if they don't exist.
- **On failure**: Ask user to provide sprint info manually.

### Step 3: Gather GitHub Activity
- Execute `ado-tracker-gather-github.prompt.md` with the date range.
- Uses `user.github_username` from config (no API call needed).
- **On failure**: Note "GitHub scan skipped — <error>". Continue.

### Step 4: Gather Notion Activity
- Execute `ado-tracker-gather-notion.prompt.md` with the date range.
- Uses `user.notion_user_id` from config (no API call needed).
- Filters to `notion.filter_types` (pages only by default).
- **On failure**: Note "Notion scan skipped — <error>". Continue.

### Step 5: Gather Git Activity
- Execute `ado-tracker-gather-sessions.prompt.md` with the date range.
- Uses `git.source_root` and `git.filter_by_remote_org` from config.
- Session parsing is best-effort.
- **On failure**: Note "Git scan skipped — <error>". Continue.

### Step 6: Save Activity Snapshot
- Combine all gathered activity into a single JSON file.
- Save to `data/sprints/<sprint>/activity/<date>-daily.json`.
- If ALL gathering steps failed → "No activity found. Check tool connections." Stop.

### Step 7: Dedup & State Check
- Query existing work items across all overlapping sprints:
  ```bash
  bash scripts/ado-cli.sh --action query-my-sprint-items --params '{"sprints":[<sprint-paths>]}'
  ```
- Match gathered activity against existing items by source URL in descriptions.
- Check if tracked items need state updates (PR merged → Done, all children Done → parent Done).
- Notion-sourced tasks are NEVER auto-closed.

### Step 8: Propose Updates
- Execute `ado-tracker-propose-updates.prompt.md` with:
  - Combined activity (with dedup flags)
  - Sprint mappings
  - State lifecycle proposals
- Present grouped by sprint, then by action type.
- Wait for user approval.
- If user approves nothing → skip to Step 10.

### Step 9: Apply Updates
- Execute `ado-tracker-apply-updates.prompt.md` with approved actions.
- Use `create-with-children` for new PBIs.
- Use `update-work-item` for state changes.
- Save results to `data/sprints/<sprint>/updates/<date>-daily.json`.

### Step 10: Update Last Run
- Write `data/last-run.json`:
  ```json
  {
    "last_run_date": "<today>",
    "last_run_type": "daily",
    "sprint": "<current-sprint-name>",
    "items_created": <count>,
    "items_updated": <count>,
    "scanned_date_range": {"from": "<from>", "to": "<to>"}
  }
  ```

### Step 11: Summary
```
## Daily Scan Complete
Date range: <from> to <to>
Sprints: <sprint names>
Activity found: <count> items
Proposed: <count> changes
Applied: <count> creates, <count> state updates
Next run: <scheduled time>
```
```

- [ ] **Step 2: Rewrite adhoc automation**

Replace `automations/ado-tracker-adhoc.automation.md` with:

```markdown
# ADO Tracker — Ad-hoc Scan

## Goal
Run an activity scan for a user-specified date range. Same pipeline as daily but with custom dates, multi-sprint support, and no last-run.json update.

## Input
- `from_date`: Start date (YYYY-MM-DD)
- `to_date`: End date (YYYY-MM-DD)

If not provided, ask: "What date range? (YYYY-MM-DD to YYYY-MM-DD)"

## Steps

### Step 1: Load Configuration
- Read `data/config.json` and `data/task-template.json`.
- **On failure**: Direct user to `/ado-tracker-init`.

### Step 2: Resolve Sprints for Date Range
- Resolve all overlapping sprints:
  ```bash
  bash scripts/ado-cli.sh --action resolve-sprints-for-range --params '{"from":"<from>","to":"<to>"}'
  ```
- If range spans multiple sprints, inform user: "Date range covers Sprint X (dates) and Sprint Y (dates). Items will be filed under the sprint matching their activity date."
- **On failure**: Ask user to provide sprint info manually.

### Steps 3-5: Gather Activity
Same as daily scan steps 3-5 but using the user-specified date range.

### Step 6: Save Activity Snapshot
- Save to `data/sprints/<primary-sprint>/activity/<from>-to-<to>-adhoc.json`.
- If ALL gathering failed → inform and stop.

### Step 7: Dedup & State Check
Same as daily scan step 7 — query across ALL overlapping sprints.

### Step 8: Propose Updates
Same as daily scan step 8. Items are grouped by their sprint.

### Step 9: Apply Updates
Same as daily scan step 9.

### Step 10: Summary
- Present results with counts and links.
- Note: Ad-hoc scans do NOT update `last-run.json`.
```

- [ ] **Step 3: Commit**

```bash
git add automations/
git commit -m "Rewrite automations: multi-sprint resolution, dedup step, state lifecycle, better error handling"
```

---

### Task 8: Update init skill — auto-detect user identities

**Files:**
- Modify: `.claude/skills/ado-tracker-init/SKILL.md`

- [ ] **Step 1: Update the init SKILL.md**

In the existing SKILL.md, make these changes:

**Step 3 (Reference Task)**: After successfully fetching the work item, extract the user's ADO email:
```
Extract `user.ado_email` from the work item's `System.AssignedTo.uniqueName` field.
```

Also validate that the work item type is "Product Backlog Item":
```
Verify `System.WorkItemType == "Product Backlog Item"`. If not, warn: "This work item is a <type>, not a PBI. PBIs are recommended as reference items. Continue anyway?"
```

**Step 5 (User Configuration)**: Before prompting for GitHub orgs, auto-detect user identities:

```
### Auto-detect user identities

1. GitHub username:
   ```bash
   gh api user --jq .login
   ```
   "Detected GitHub username: <username>. Correct?"

2. Notion user ID (search by the user's email):
   ```
   notion-get-users: query: "<ado_email or name>"
   ```
   "Found Notion account: <name> (<email>). Correct?"

3. ADO email: Already extracted from reference task in Step 3.

Save all to the `user` section in config.json.
```

Remove the separate question "Which GitHub organization(s)..." prompt — the GitHub username is now auto-detected. Still ask for orgs since that's separate from username.

- [ ] **Step 2: Commit**

```bash
git add .claude/skills/ado-tracker-init/SKILL.md
git commit -m "Update init skill: auto-detect user identities, validate PBI type, save user section to config"
```

---

### Task 9: Update CLAUDE.md — document new actions, config, state rules

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update CLAUDE.md**

Replace the full file with updated documentation reflecting all changes:

```markdown
# ADO Tracker

## Identity
This workspace is an ADO task tracking assistant operated via Claude Code CLI. It tracks user activity across GitHub, Notion, and git commits — then proposes and manages ADO work items (PBIs and Tasks).

## Architecture
- **Prompts** (`prompts/`): Single-purpose reusable tasks, invokable individually
- **Automations** (`automations/`): Multi-step orchestrated workflows that call prompts in sequence
- **Scripts** (`scripts/`): Bash utilities for deterministic work — always call via `bash scripts/<name>.sh`
- **Skills** (`.claude/skills/`): Slash command definitions for Claude Code (each in its own directory as `SKILL.md`)
- **Data** (`data/`): Gitignored runtime data — config, template, sprint activity/updates

## Tools
- **ADO operations (primary):** `bash scripts/ado-cli.sh --action <action> --params '<json>'`
  - Actions: `show-work-item`, `create-work-item`, `update-work-item`, `query-work-items`, `current-sprint`, `list-sprints`, `add-child`, `close-work-item`, `create-task`, `create-with-children`, `resolve-sprints-for-range`, `query-my-sprint-items`
  - Config-aware: reads `data/config.json` for org/project/team/email defaults
  - `create-work-item` supports `assigned_to` and `state` params
  - `create-with-children` creates a PBI + all child tasks + links in one call
  - `create-task` creates a task and links to parent in one call
  - `resolve-sprints-for-range` returns all sprints overlapping a date range
  - `query-my-sprint-items` queries user's items across multiple sprints (for dedup)
- **Template operations:** `bash scripts/template-manager.sh --action <action> --params '<json>'`
- **Git activity:** `bash scripts/extract-git-activity.sh --from <date> --to <date> --auto-detect <dir> --filter-org <org>`
- **Session logs:** `bash scripts/parse-session-logs.sh --from <date> --to <date>` (best-effort)
- **GitHub:** Use `gh` CLI directly
- **Notion:** Use Notion MCP tools directly
- **ADO fallback:** Use ADO MCP tools only when `az devops` CLI cannot handle an operation

## Configuration
- `data/config.json` — user settings:
  - `ado`: organization, project, team
  - `user`: ado_email, github_username, notion_user_id (auto-detected during init)
  - `github`: organizations, excluded_repos
  - `notion`: scope, excluded_databases, filter_types (default: ["page"])
  - `git`: source_root, auto_detect, filter_by_remote_org, explicit_repos
  - `schedule`: daily_scan_time
- `data/task-template.json` — PBI/Task creation template (title_prefix_pbi, description_format, fields)
- `data/last-run.json` — last daily scan timestamp, sprint, counts, date range
- If any data file is missing, guide the user to run `/ado-tracker-init`

## Sprint Management
- **Multi-sprint aware**: Scans resolve all sprints overlapping the date range, not just "current"
- `resolve-sprints-for-range` replaces `current-sprint` for scans
- Activity items are mapped to sprints by their date
- Sprint boundaries are handled: items at start/end of sprint go to the correct sprint

## Deduplication
- Before proposing, query existing items across all overlapping sprints
- Match by source URL in description (PR links, Notion links)
- Match by title keyword overlap
- Prevents duplicate PBIs from overlapping scan date ranges

## State Lifecycle
State is set during creation and updated automatically based on source type:

| Source | Created State | Auto-close? |
|--------|--------------|-------------|
| GitHub PR (open) | In Progress | Yes — when PR merges |
| GitHub PR (merged) | Done | N/A |
| Notion page | In Progress | **Never** — user decides |
| Git commits (no PR) | In Progress | Never |

All items are always assigned to `user.ado_email`.

## Proposal Format
When presenting proposed ADO changes:
- Group by sprint, then by action type (new items, state updates, already tracked)
- Show moderate detail by default
- Allow expand/edit/approve per item or group
- Always show what was skipped and why

## Data Organization
All runtime data lives in `data/` (gitignored), organized by sprint:
```
data/sprints/<Sprint-Name>/activity/<date>-<type>.json
data/sprints/<Sprint-Name>/updates/<date>-<type>.json
```

## Error Handling
- If `az devops` commands fail, show the error and suggest fixes
- If a prerequisite is missing, guide the user to `/ado-tracker-init`
- Never silently skip failures — always inform the user
- Gathering step failures don't block the pipeline — continue with what succeeded
- Session log parsing is best-effort and never blocks
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "Update CLAUDE.md: document new CLI actions, config schema, sprint management, dedup, state lifecycle"
```

---

### Task 10: Verify end-to-end — test key script actions

- [ ] **Step 1: Test ado-cli.sh show-work-item**

Run: `bash scripts/ado-cli.sh --action show-work-item --params '{"id":1505951}' | jq '.success'`
Expected: `true`

- [ ] **Step 2: Test resolve-sprints-for-range**

Run: `bash scripts/ado-cli.sh --action resolve-sprints-for-range --params '{"from":"2026-03-20","to":"2026-03-27"}' | jq '.data | length'`
Expected: Number > 0 (sprints overlapping the range)

- [ ] **Step 3: Test query-my-sprint-items**

Run: `bash scripts/ado-cli.sh --action query-my-sprint-items --params '{"sprints":["MBScrum\\Sprint 2026-07"]}' | jq '.success'`
Expected: `true`

- [ ] **Step 4: Test extract-git-activity.sh with filter-org**

Run: `bash scripts/extract-git-activity.sh --from 2026-03-25 --to 2026-03-28 --auto-detect "C:/src" --filter-org mindbody | jq '.data.repos | length'`
Expected: Number > 0 (only mindbody org repos)

- [ ] **Step 5: Test template-manager.sh validate**

Run: `bash scripts/template-manager.sh --action validate | jq '.success'`
Expected: `true`

- [ ] **Step 6: Test parse-session-logs.sh graceful return**

Run: `bash scripts/parse-session-logs.sh --from 2026-03-20 --to 2026-03-27 | jq '.success'`
Expected: `true` (never errors)

- [ ] **Step 7: Final commit**

```bash
git add -A
git commit -m "ADO Tracker overhaul complete: hardened scripts, config consistency, dedup, multi-sprint, state lifecycle"
```
