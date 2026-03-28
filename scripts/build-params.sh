#!/usr/bin/env bash
# build-params.sh — Safely construct JSON params files using jq --arg
#
# Solves the backslash escaping problem: ADO paths like "MBScrum\Business Experience"
# contain backslashes that are escape characters in JSON and bash. This script uses
# jq's --arg (for strings) and --argjson (for JSON values) to construct valid JSON
# without any manual escaping.
#
# Usage:
#   bash scripts/build-params.sh --output <file> [--arg key value]... [--argjson key json]... [--slurp-file key path]...
#
# Options:
#   --output <file>        Path to write the JSON file (required)
#   --arg <key> <value>    Add a string value (jq handles all escaping)
#   --argjson <key> <json> Add a pre-formed JSON value (object, array, number, bool)
#   --slurp-file <key> <path>  Read a JSON file and embed it under <key>
#
# Examples:
#   # Simple string params (backslashes handled automatically):
#   bash scripts/build-params.sh --output /tmp/params.json \
#     --arg area_path 'MBScrum\Business Experience\squad-biz-app' \
#     --arg title '[BizApp] My PBI' \
#     --arg type 'Product Backlog Item'
#
#   # Wrap a raw work item JSON for template extraction:
#   bash scripts/build-params.sh --output /tmp/params.json \
#     --slurp-file work_item /tmp/raw-work-item.json
#
#   # Mix strings and JSON objects:
#   bash scripts/build-params.sh --output /tmp/params.json \
#     --arg title 'My Task' \
#     --arg area_path 'MBScrum\Business Experience\squad-biz-app' \
#     --argjson parent_id 12345 \
#     --argjson fields '{"Custom.Repo":"MyRepo","Microsoft.VSTS.Common.Priority":2}'

set -o pipefail

# --- Parse arguments ---

OUTPUT_FILE=""
JQ_ARGS=()       # jq CLI args: --arg key val, --argjson key json, --slurpfile key path
JQ_KEYS=()       # keys to include in the output object

json_error() {
    local msg="$1"
    echo "{\"success\":false,\"error\":\"$msg\"}" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)
            [[ -z "$2" ]] && json_error "Missing value for --output"
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --arg)
            [[ -z "$2" || -z "$3" ]] && json_error "Missing key or value for --arg"
            JQ_ARGS+=(--arg "$2" "$3")
            JQ_KEYS+=("$2")
            shift 3
            ;;
        --argjson)
            [[ -z "$2" || -z "$3" ]] && json_error "Missing key or value for --argjson"
            JQ_ARGS+=(--argjson "$2" "$3")
            JQ_KEYS+=("$2")
            shift 3
            ;;
        --slurp-file)
            [[ -z "$2" || -z "$3" ]] && json_error "Missing key or path for --slurp-file"
            if [[ ! -f "$3" ]]; then
                json_error "File not found: $3"
            fi
            JQ_ARGS+=(--slurpfile "$2" "$3")
            JQ_KEYS+=("$2:slurp")
            shift 3
            ;;
        *)
            json_error "Unknown argument: $1"
            ;;
    esac
done

if [[ -z "$OUTPUT_FILE" ]]; then
    json_error "Missing --output <file> argument"
fi

if [[ ${#JQ_KEYS[@]} -eq 0 ]]; then
    json_error "No parameters specified. Use --arg, --argjson, or --slurp-file."
fi

# --- Build jq filter expression ---
# Construct: {key1: $key1, key2: $key2, key3: $key3[0]}
# (slurpfile values are arrays, so we take [0])

filter_parts=()
for key_spec in "${JQ_KEYS[@]}"; do
    if [[ "$key_spec" == *":slurp" ]]; then
        key="${key_spec%:slurp}"
        filter_parts+=("\"$key\": \$${key}[0]")
    else
        filter_parts+=("\"$key_spec\": \$$key_spec")
    fi
done

JQ_FILTER="{ $(IFS=','; echo "${filter_parts[*]}") }"

# --- Execute ---

jq -n "${JQ_ARGS[@]}" "$JQ_FILTER" > "$OUTPUT_FILE" 2>&1
rc=$?

if [[ $rc -ne 0 ]]; then
    json_error "jq failed to construct JSON (exit code $rc)"
fi

echo "{\"success\":true,\"path\":\"$OUTPUT_FILE\"}"
