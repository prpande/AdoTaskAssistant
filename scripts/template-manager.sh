#!/usr/bin/env bash
# template-manager.sh — CRUD operations on the task template
#
# Usage:
#   bash scripts/template-manager.sh --action <action> [--params '<json>']
#
# Actions:
#   read       — Read current template (returns JSON)
#   write      — Write a new template (params: full template JSON)
#   update     — Update specific fields in template (params: partial JSON to merge)
#   validate   — Check if template exists and has required fields
#   extract    — Extract template fields from a raw work item JSON (params: {"work_item": <json>})
#
# Examples:
#   bash scripts/template-manager.sh --action read
#   bash scripts/template-manager.sh --action validate
#   bash scripts/template-manager.sh --action extract --params '{"work_item": {...}}'

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DIR="$REPO_DIR/data"
TEMPLATE_FILE="$DATA_DIR/task-template.json"

# --- Helpers ---

json_ok() {
    jq -n --argjson data "$1" '{"success":true,"data":$data}'
}

json_error() {
    local msg="$1"
    local action="$2"
    jq -n --arg msg "$msg" --arg action "$action" '{"success":false,"error":$msg,"action":$action}'
}

ensure_data_dir() {
    mkdir -p "$DATA_DIR"
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

# --- Actions ---

read_template() {
    if [[ ! -f "$TEMPLATE_FILE" ]]; then
        json_error "Template not found at $TEMPLATE_FILE. Run /ado-tracker-init to generate one." "$ACTION"
        exit 1
    fi
    local content
    content=$(cat "$TEMPLATE_FILE")
    json_ok "$content"
}

write_template() {
    ensure_data_dir
    local template
    template=$(echo "$PARAMS" | jq '.template // .')
    echo "$template" | jq '.' > "$TEMPLATE_FILE" || {
        json_error "Failed to write template" "$ACTION"
        exit 1
    }
    json_ok '{"message":"Template written successfully","path":"'"$TEMPLATE_FILE"'"}'
}

update_template() {
    if [[ ! -f "$TEMPLATE_FILE" ]]; then
        json_error "Template not found. Cannot update. Run /ado-tracker-init first." "$ACTION"
        exit 1
    fi
    local updates
    updates=$(echo "$PARAMS" | jq '.updates // .')
    local current
    current=$(cat "$TEMPLATE_FILE")
    local merged
    merged=$(echo "$current" "$updates" | jq -s '.[0] * .[1]')
    echo "$merged" | jq '.' > "$TEMPLATE_FILE" || {
        json_error "Failed to update template" "$ACTION"
        exit 1
    }
    json_ok "$merged"
}

validate_template() {
    if [[ ! -f "$TEMPLATE_FILE" ]]; then
        json_error "Template file does not exist at $TEMPLATE_FILE" "$ACTION"
        exit 1
    fi

    local template
    template=$(cat "$TEMPLATE_FILE")

    local required_fields=("work_item_type" "area_path" "iteration_path_pattern")
    local missing=()
    for field in "${required_fields[@]}"; do
        local value
        value=$(echo "$template" | jq -r ".$field // empty")
        if [[ -z "$value" ]]; then
            missing+=("$field")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        local missing_json
        missing_json=$(printf '%s\n' "${missing[@]}" | jq -R . | jq -s .)
        json_error "Template is missing required fields: $(echo "$missing_json" | jq -r 'join(", ")')" "$ACTION"
        exit 1
    fi

    json_ok '{"valid":true,"path":"'"$TEMPLATE_FILE"'"}'
}

extract_template() {
    local work_item
    work_item=$(echo "$PARAMS" | jq '.work_item')

    if [[ "$work_item" == "null" ]]; then
        json_error "Missing required parameter: work_item (the raw work item JSON)" "$ACTION"
        exit 1
    fi

    # Extract reusable fields, filter out instance-specific data
    local template
    template=$(echo "$work_item" | jq '{
        source_work_item_id: .id,
        work_item_type: .fields["System.WorkItemType"],
        area_path: .fields["System.AreaPath"],
        iteration_path_pattern: (
            .fields["System.IterationPath"]
            | if . then
                # Replace the last numeric segment with {number} placeholder
                (split("\\") | last | gsub("[0-9]+"; "{number}")) as $last_part |
                (split("\\") | .[:-1] + [$last_part] | join("\\"))
              else null end
        ),
        fields: (
            .fields
            | del(
                .["System.Id"],
                .["System.Rev"],
                .["System.Title"],
                .["System.Description"],
                .["System.AssignedTo"],
                .["System.CreatedBy"],
                .["System.CreatedDate"],
                .["System.ChangedBy"],
                .["System.ChangedDate"],
                .["System.AuthorizedDate"],
                .["System.RevisedDate"],
                .["System.Watermark"],
                .["System.CommentCount"],
                .["System.BoardColumn"],
                .["System.BoardColumnDone"],
                .["System.BoardLane"],
                .["System.WorkItemType"],
                .["System.AreaPath"],
                .["System.IterationPath"],
                .["System.State"],
                .["System.Reason"],
                .["System.History"],
                .["System.RelatedLinkCount"],
                .["System.ExternalLinkCount"],
                .["System.HyperLinkCount"],
                .["System.AttachedFileCount"],
                .["System.NodeName"],
                .["System.AreaId"],
                .["System.IterationId"],
                .["System.TeamProject"]
            )
            | with_entries(select(.value != null and .value != "" and .value != 0))
        ),
        description_format: "## Summary\\n{summary}\\n\\n## Source\\n{source}\\n\\n## Date\\n{date}",
        tags: (
            .fields["System.Tags"]
            | if . and . != "" then split("; ") else [] end
        ),
        priority: (.fields["Microsoft.VSTS.Common.Priority"] // 2)
    }')

    json_ok "$template"
}

# --- Dispatch ---

case "$ACTION" in
    read)      read_template ;;
    write)     write_template ;;
    update)    update_template ;;
    validate)  validate_template ;;
    extract)   extract_template ;;
    *)
        json_error "Unknown action: $ACTION. Valid actions: read, write, update, validate, extract" "$ACTION"
        exit 1
        ;;
esac
