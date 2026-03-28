#!/usr/bin/env bash
# template-manager.sh — CRUD operations on the task template
#
# Usage:
#   bash scripts/template-manager.sh --action <action> [--params '<json>' | --params-file <path>]
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
    printf '%s' "$1" | jq '{success: true, data: .}'
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
        --params-file) PARAMS=$(cat "$2"); shift 2 ;;
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
    template=$(printf '%s' "$PARAMS" | jq '.template // .')
    printf '%s' "$template" | jq '.' > "$TEMPLATE_FILE" || {
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
    updates=$(printf '%s' "$PARAMS" | jq '.updates // .')
    local current
    current=$(cat "$TEMPLATE_FILE")
    local merged
    merged=$(printf '%s\n%s' "$current" "$updates" | jq -s '.[0] * .[1]')
    printf '%s' "$merged" | jq '.' > "$TEMPLATE_FILE" || {
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

    local required_fields=("work_item_type" "area_path" "iteration_path_pattern" "description_format")
    local missing=()
    for field in "${required_fields[@]}"; do
        local value
        value=$(printf '%s' "$template" | jq -r ".$field // empty")
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
    work_item=$(printf '%s' "$PARAMS" | jq '.work_item')

    if [[ "$work_item" == "null" ]]; then
        json_error "Missing required parameter: work_item (the raw work item JSON)" "$ACTION"
        exit 1
    fi

    # Extract reusable fields, filter out instance-specific data
    local template
    template=$(printf '%s' "$work_item" | jq '
      # --- Title prefix parsing ---
      (.fields["System.Title"] // "") as $title |
      ($title | [scan("\\[([^\\]]+)\\]")] | map(.[0])) as $brackets |
      (if ($brackets | length) == 0 then
        { static: "", pattern: "{title}", slots: {} }
      else
        ($brackets[0]) as $static_val |
        ($brackets[1:]) as $slot_brackets |
        (("[" + $static_val + "]") + ($slot_brackets | to_entries | map("[{slot_" + (.key + 1 | tostring) + "}]") | join(""))) as $pattern |
        ($slot_brackets | to_entries | map({
          key: ("slot_" + (.key + 1 | tostring)),
          value: { description: ("Title tag " + (.key + 1 | tostring) + " (from reference: " + .value + ")"), examples: [.value] }
        }) | from_entries) as $slots |
        { static: ("[" + $static_val + "]"), pattern: $pattern, slots: $slots }
      end) as $title_prefix |

      # --- Work type ---
      { default: (.fields["ScrumMB.WorkType"] // "New Feature Development"),
        inference_keywords: {
          "Customer Committed Features": ["customer", "committed", "client-requested"],
          "Dedicated Tech Excellence": ["tech-excellence", "innovation", "spike", "poc", "prototype"],
          "New Feature Development": ["add", "implement", "create", "expose", "enable", "feature"],
          "Production Support & Incident remediation": ["incident", "outage", "p1", "p2", "sev1", "sev2", "hotfix", "emergency"],
          "Production Systems & Operations": ["infra", "deploy", "pipeline", "ci/cd", "monitoring", "alerting"],
          "Reliability & Stabilization": ["fix", "bug", "flaky", "stabilize", "reliability", "retry", "resilience"],
          "Security & Compliance": ["security", "vulnerability", "cve", "compliance", "audit", "gdpr", "pci"],
          "Software Maintenance": ["update", "upgrade", "migrate", "bump", "deprecate", "refactor", "cleanup", "debt"]
        }
      } as $work_type |

      # --- Auto-populate from source ---
      (if .fields["Custom.Repo"] then {"Custom.Repo": "repo_name"} else {} end) as $auto_populate |

      # --- Build template ---
      {
        source_work_item_id: .id,
        work_item_type: .fields["System.WorkItemType"],
        area_path: .fields["System.AreaPath"],
        iteration_path_pattern: (
          .fields["System.IterationPath"]
          | if . then
              (split("\\\\") | last | gsub("[0-9]{4}"; "{year}") | gsub("\\{year\\}-[0-9]+"; "{year}-{sprint_number}")) as $last_part |
              (split("\\\\") | .[:-1] + [$last_part] | join("\\"))
            else null end
        ),
        title_prefix: $title_prefix,
        work_type: $work_type,
        auto_populate_from_source: $auto_populate,
        fields: (
          .fields
          | del(
              .["System.Id"], .["System.Rev"], .["System.Title"],
              .["System.Description"], .["System.AssignedTo"],
              .["System.CreatedBy"], .["System.CreatedDate"],
              .["System.ChangedBy"], .["System.ChangedDate"],
              .["System.AuthorizedDate"], .["System.RevisedDate"],
              .["System.Watermark"], .["System.CommentCount"],
              .["System.BoardColumn"], .["System.BoardColumnDone"],
              .["System.BoardLane"], .["System.WorkItemType"],
              .["System.AreaPath"], .["System.IterationPath"],
              .["System.State"], .["System.Reason"],
              .["System.History"], .["System.RelatedLinkCount"],
              .["System.ExternalLinkCount"], .["System.HyperLinkCount"],
              .["System.AttachedFileCount"], .["System.NodeName"],
              .["System.AreaId"], .["System.IterationId"],
              .["System.TeamProject"], .["System.PersonId"],
              .["System.AreaLevel1"], .["System.AreaLevel2"],
              .["System.AreaLevel3"], .["System.IterationLevel1"],
              .["System.IterationLevel2"], .["System.AuthorizedAs"],
              .["ScrumMB.WorkType"], .["Custom.Repo"]
          )
          | with_entries(select(
              (.key | startswith("Custom.") | not) or (.value | type != "boolean")
          ))
          | with_entries(select(.key | startswith("WEF_") | not))
          | with_entries(select(.key | startswith("MB.") | not))
          | with_entries(select(.value != null and .value != "" and .value != 0))
        ),
        description_format: "## Overview\n{overview}\n\n## Scope\n{scope}",
        tags: (
          .fields["System.Tags"]
          | if . and . != "" then split("; ") else [] end
        ),
        priority: (.fields["Microsoft.VSTS.Common.Priority"] // 2)
      }
    ')

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
