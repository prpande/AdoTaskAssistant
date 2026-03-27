# ADO Tracker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a prompt-driven Claude Code workspace that tracks user activity across GitHub, Notion, Claude sessions, and git — then proposes and manages ADO work items (PBIs and Tasks) via `az devops` CLI.

**Architecture:** Hybrid prompt + script approach. Prompts orchestrate the workflows (daily scan, ad-hoc scan, manual creation). Scripts handle deterministic work (session log parsing, git extraction, template management, ADO CLI wrapping). All data stored in gitignored `data/` directory, organized by sprint.

**Tech Stack:** Bash scripts, `az devops` CLI, `gh` CLI, Notion MCP, Claude Code prompts/automations/skills, JSON for data storage.

---

## File Map

| File | Responsibility | Task |
|------|---------------|------|
| `CLAUDE.md` | Core instructions for Claude Code | Task 1 |
| `.gitignore` | Exclude data/ and user config | Task 1 |
| `README.md` | Project overview and setup guide | Task 1 |
| `config/config.sample.json` | Documented sample configuration | Task 2 |
| `schemas/config.schema.md` | Config structure documentation | Task 2 |
| `schemas/task-template.schema.md` | Template structure documentation | Task 2 |
| `scripts/ado-cli.sh` | Wrapper around `az boards` commands | Task 3 |
| `scripts/template-manager.sh` | CRUD operations on task template | Task 4 |
| `scripts/extract-git-activity.sh` | Extract commits for a date range | Task 5 |
| `scripts/parse-session-logs.sh` | Parse Claude Code session logs | Task 6 |
| `prompts/ado-tracker-parse-reference-task.prompt.md` | Parse reference task, generate template | Task 7 |
| `prompts/ado-tracker-gather-github.prompt.md` | Fetch GitHub PRs by date range | Task 8 |
| `prompts/ado-tracker-gather-notion.prompt.md` | Fetch Notion page edits by date range | Task 8 |
| `prompts/ado-tracker-gather-sessions.prompt.md` | Gather Claude session + git activity | Task 8 |
| `prompts/ado-tracker-propose-updates.prompt.md` | Match activity to ADO, present proposal | Task 9 |
| `prompts/ado-tracker-apply-updates.prompt.md` | Execute approved ADO changes | Task 10 |
| `prompts/ado-tracker-create-pbi.prompt.md` | Create new PBI from description | Task 11 |
| `prompts/ado-tracker-create-task.prompt.md` | Create child task under PBI | Task 11 |
| `prompts/ado-tracker-breakdown-pbi.prompt.md` | Decompose PBI into child tasks | Task 11 |
| `automations/ado-tracker-daily.automation.md` | Full daily scan orchestration | Task 12 |
| `automations/ado-tracker-adhoc.automation.md` | Ad-hoc date range scan orchestration | Task 12 |
| `skills/ado-tracker-init.md` | Guided onboarding wizard skill | Task 13 |
| `skills/ado-tracker-daily.md` | Daily scan slash command | Task 14 |
| `skills/ado-tracker-scan.md` | Ad-hoc scan slash command | Task 14 |
| `skills/ado-tracker-create.md` | Create PBI slash command | Task 14 |
| `skills/ado-tracker-task.md` | Create task under PBI slash command | Task 14 |
| `skills/ado-tracker-breakdown.md` | Break down PBI slash command | Task 14 |

---

### Task 1: Repository Scaffolding — CLAUDE.md, .gitignore, README

**Files:**
- Create: `CLAUDE.md`
- Create: `.gitignore`
- Create: `README.md`

- [ ] **Step 1: Create .gitignore**

```gitignore
# User runtime data
data/

# OS files
.DS_Store
Thumbs.db

# Editor files
.vscode/
.idea/
*.swp
*.swo
```

- [ ] **Step 2: Create CLAUDE.md**

```markdown
# ADO Tracker

## Identity
This workspace is an ADO task tracking assistant operated via Claude Code CLI. It tracks user activity across GitHub, Notion, Claude Code sessions, and git commits — then proposes and manages ADO work items (PBIs and Tasks).

## Architecture
- **Prompts** (`prompts/`): Single-purpose reusable tasks, invokable individually
- **Automations** (`automations/`): Multi-step orchestrated workflows that call prompts in sequence
- **Scripts** (`scripts/`): Bash utilities for deterministic work — always call via `bash scripts/<name>.sh`
- **Skills** (`skills/`): Slash command definitions for Claude Code
- **Data** (`data/`): Gitignored runtime data — config, template, sprint activity/updates

## Tools
- **ADO operations (primary):** `bash scripts/ado-cli.sh --action <action> --params '<json>'`
- **Template operations:** `bash scripts/template-manager.sh --action <action> --params '<json>'`
- **Git activity:** `bash scripts/extract-git-activity.sh --from <date> --to <date> --repos '<json-array>'`
- **Session logs:** `bash scripts/parse-session-logs.sh --from <date> --to <date>`
- **GitHub:** Use `gh` CLI directly (e.g., `gh pr list`, `gh search prs`)
- **Notion:** Use Notion MCP tools directly
- **ADO fallback:** Use ADO MCP tools only when `az devops` CLI cannot handle an operation

## Configuration
- Read `data/config.json` for user settings (GitHub orgs, Notion scope, repos, schedule)
- Read `data/task-template.json` for the PBI/Task creation template
- Read `data/last-run.json` for last run timestamp and sprint info
- If any data file is missing, guide the user to run `/ado-tracker-init`

## Data Organization
All runtime data lives in `data/` (gitignored), organized by sprint:
```
data/sprints/<Sprint-Name>/activity/<date>-<type>.json
data/sprints/<Sprint-Name>/updates/<date>-<type>.json
```
- Daily runs: `2026-03-27-daily.json`
- Ad-hoc runs: `2026-03-25-to-03-27-adhoc.json`

## Sprint Management
- Detect current sprint: `bash scripts/ado-cli.sh --action current-sprint`
- Always confirm sprint with the user before applying any updates
- Alert the user when the sprint has changed since the last run

## Proposal Format
When presenting proposed ADO changes, group by source (GitHub PRs | Notion Pages | Claude Sessions / Git). Show moderate detail by default (title, source, area path, sprint, one-line summary). Allow the user to expand individual items to full preview. Allow individual item or group-level approval/rejection.

## Error Handling
- If `az devops` commands fail, show the error and suggest fixes
- If a prerequisite is missing, guide the user to `/ado-tracker-init`
- Never silently skip failures — always inform the user
```

- [ ] **Step 3: Create README.md**

```markdown
# ADO Tracker

A Claude Code workspace that automatically tracks your work across GitHub, Notion, and Claude Code sessions — then creates and manages ADO work items for you.

## Features

- **Daily scan** — Detects PRs, Notion edits, Claude sessions, and git commits since last run
- **Smart proposals** — Groups activity by source, proposes ADO PBI/Task creates/updates/closes
- **Template-based** — Uses a reference ADO work item as a template for consistent formatting
- **Sprint-aware** — Auto-detects current sprint, confirms before applying changes
- **Ad-hoc mode** — Scan any date range on demand
- **Manual creation** — Create PBIs, add tasks, break down PBIs via slash commands

## Quick Start

```bash
cd /path/to/AdoTaskAssistant
claude
# Then run:
/ado-tracker-init
```

The init wizard will walk you through:
1. Prerequisites check (gh CLI, az CLI, Notion MCP)
2. Azure DevOps PAT setup
3. Reference task → template generation
4. Configuration (GitHub orgs, Notion scope, repos)
5. Optional first scan
6. Daily schedule setup

## Prerequisites

- [Claude Code CLI](https://docs.claude.ai/en/code)
- [GitHub CLI](https://cli.github.com/) — authenticated via `gh auth login`
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) with `azure-devops` extension
- Notion MCP server — connected in Claude Code
- ADO project access with work item read/write permissions

## Slash Commands

| Command | Purpose |
|---------|---------|
| `/ado-tracker-init` | Guided setup wizard |
| `/ado-tracker-daily` | Run daily scan now |
| `/ado-tracker-scan --from YYYY-MM-DD --to YYYY-MM-DD` | Scan a date range |
| `/ado-tracker-create <description>` | Create a new PBI |
| `/ado-tracker-task <PBI-id> <description>` | Add task under a PBI |
| `/ado-tracker-breakdown <PBI-id>` | Break PBI into tasks |

## Data

All user data is stored in `data/` (gitignored) and organized by sprint. See `config/config.sample.json` for configuration options.
```

- [ ] **Step 4: Commit scaffolding**

```bash
git add CLAUDE.md .gitignore README.md
git commit -m "Add repository scaffolding — CLAUDE.md, .gitignore, README"
```

---

### Task 2: Configuration Schema and Sample Config

**Files:**
- Create: `config/config.sample.json`
- Create: `schemas/config.schema.md`
- Create: `schemas/task-template.schema.md`

- [ ] **Step 1: Create config/config.sample.json**

```json
{
  "github": {
    "orgs": ["your-org-name"],
    "exclude_repos": [],
    "username": null
  },
  "notion": {
    "scope": "all",
    "exclude_databases": [],
    "track_ownership": true,
    "track_edits": true
  },
  "git": {
    "repos": [],
    "auto_detect_from": "C:/src"
  },
  "ado": {
    "organization": null,
    "project": null,
    "default_work_item_type": "Product Backlog Item",
    "use_cli": true,
    "fallback_to_mcp": true
  },
  "schedule": {
    "daily_time": "09:00",
    "loop_interval": "24h"
  },
  "session_logs": {
    "enabled": true,
    "path": null
  }
}
```

- [ ] **Step 2: Create schemas/config.schema.md**

```markdown
# Configuration Schema

## File Location
`data/config.json` (gitignored, user-specific)

## Reference
See `config/config.sample.json` for a working example with all fields.

## Fields

### `github`
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `orgs` | string[] | `[]` | GitHub organizations to track. Only PRs in these orgs are scanned. |
| `exclude_repos` | string[] | `[]` | Repos to exclude from tracking (format: `org/repo`). |
| `username` | string\|null | `null` | GitHub username. Auto-detected from `gh api user --jq .login` if null. |

### `notion`
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `scope` | `"all"` \| `"databases"` | `"all"` | Track all pages or only pages in specific databases. |
| `exclude_databases` | string[] | `[]` | Notion database IDs to exclude. |
| `track_ownership` | boolean | `true` | Track pages where user is the creator/owner. |
| `track_edits` | boolean | `true` | Track pages where user made substantial edits (not just comments). |

### `git`
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `repos` | string[] | `[]` | Absolute paths to local git repos to scan. If empty, uses `auto_detect_from`. |
| `auto_detect_from` | string\|null | `null` | Parent directory to auto-discover git repos from. |

### `ado`
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `organization` | string | required | ADO organization URL (e.g., `https://dev.azure.com/your-org`). |
| `project` | string | required | ADO project name. |
| `default_work_item_type` | string | `"Product Backlog Item"` | Default work item type for new items. |
| `use_cli` | boolean | `true` | Use `az devops` CLI as primary ADO interface. |
| `fallback_to_mcp` | boolean | `true` | Fall back to ADO MCP when CLI can't handle an operation. |

### `schedule`
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `daily_time` | string | `"09:00"` | Preferred daily run time (HH:MM, 24h format). |
| `loop_interval` | string | `"24h"` | Interval for `/loop` scheduling. |

### `session_logs`
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | `true` | Whether to parse Claude Code session logs. |
| `path` | string\|null | `null` | Path to Claude Code session logs. Auto-detected if null. |
```

- [ ] **Step 3: Create schemas/task-template.schema.md**

```markdown
# Task Template Schema

## File Location
`data/task-template.json` (gitignored, generated from reference task)

## Purpose
Defines the reusable structure for creating new ADO work items. Generated once from a reference work item via `/ado-tracker-init`, then used for all future PBI/Task creation.

## Fields

| Field | Type | Description |
|-------|------|-------------|
| `source_work_item_id` | number | ID of the reference work item this template was derived from. |
| `work_item_type` | string | e.g., `"Product Backlog Item"`, `"Task"` |
| `area_path` | string | e.g., `"Project\\Team\\Area"` |
| `iteration_path_pattern` | string | e.g., `"Project\\Sprint-{number}"` — `{number}` is replaced with current sprint. |
| `fields` | object | Key-value pairs of ADO field reference names to default values. |
| `description_format` | string | Markdown template for the description body. Supports placeholders: `{title}`, `{source}`, `{summary}`, `{date}`. |
| `tags` | string[] | Default tags to apply. |
| `priority` | number | Default priority (1-4). |

## Example

```json
{
  "source_work_item_id": 12345,
  "work_item_type": "Product Backlog Item",
  "area_path": "MyProject\\MyTeam\\Backend",
  "iteration_path_pattern": "MyProject\\Sprint-{number}",
  "fields": {
    "System.State": "New",
    "Microsoft.VSTS.Common.ValueArea": "Business"
  },
  "description_format": "## Summary\n{summary}\n\n## Source\n{source}\n\n## Date\n{date}",
  "tags": ["auto-tracked"],
  "priority": 2
}
```

## What Is Extracted From Reference Task
- Area path
- Iteration path (converted to a pattern with `{number}` placeholder)
- Work item type
- Non-instance-specific field values (state defaults, value area, etc.)
- Description structure/format (converted to a template with placeholders)
- Tags
- Priority

## What Is Filtered Out
- The specific description body text
- Assigned-to and created-by
- Attachments
- Comments
- Relations/links
- History
- Iteration-specific dates
- Any field value unique to that one work item
```

- [ ] **Step 4: Commit schemas and config**

```bash
git add config/config.sample.json schemas/config.schema.md schemas/task-template.schema.md
git commit -m "Add configuration schema, template schema, and sample config"
```

---

### Task 3: ADO CLI Wrapper Script

**Files:**
- Create: `scripts/ado-cli.sh`

- [ ] **Step 1: Create scripts/ado-cli.sh**

```bash
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
```

- [ ] **Step 2: Make script executable and test basic parsing**

```bash
chmod +x scripts/ado-cli.sh
bash scripts/ado-cli.sh
# Expected: {"success":false,"error":"Missing --action argument","action":"parse"}

bash scripts/ado-cli.sh --action unknown-action
# Expected: {"success":false,"error":"Unknown action: unknown-action...","action":"unknown-action"}
```

- [ ] **Step 3: Commit ADO CLI wrapper**

```bash
git add scripts/ado-cli.sh
git commit -m "Add ADO CLI wrapper script for token-efficient work item operations"
```

---

### Task 4: Template Manager Script

**Files:**
- Create: `scripts/template-manager.sh`

- [ ] **Step 1: Create scripts/template-manager.sh**

```bash
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
```

- [ ] **Step 2: Make script executable and test basic parsing**

```bash
chmod +x scripts/template-manager.sh
bash scripts/template-manager.sh --action validate
# Expected: {"success":false,"error":"Template file does not exist...","action":"validate"}
```

- [ ] **Step 3: Commit template manager**

```bash
git add scripts/template-manager.sh
git commit -m "Add template manager script for task template CRUD operations"
```

---

### Task 5: Git Activity Extraction Script

**Files:**
- Create: `scripts/extract-git-activity.sh`

- [ ] **Step 1: Create scripts/extract-git-activity.sh**

```bash
#!/usr/bin/env bash
# extract-git-activity.sh — Extract git commits across repos for a date range
#
# Usage:
#   bash scripts/extract-git-activity.sh --from <YYYY-MM-DD> --to <YYYY-MM-DD> [--repos '<json-array>'] [--auto-detect <parent-dir>]
#
# Examples:
#   bash scripts/extract-git-activity.sh --from 2026-03-26 --to 2026-03-27 --repos '["C:/src/Repo1","C:/src/Repo2"]'
#   bash scripts/extract-git-activity.sh --from 2026-03-26 --to 2026-03-27 --auto-detect "C:/src"

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
REPOS="[]"
AUTO_DETECT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --from) FROM_DATE="$2"; shift 2 ;;
        --to) TO_DATE="$2"; shift 2 ;;
        --repos) REPOS="$2"; shift 2 ;;
        --auto-detect) AUTO_DETECT="$2"; shift 2 ;;
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
    repo_list+=("$repo")
done < <(echo "$REPOS" | jq -r '.[]')

if [[ ${#repo_list[@]} -eq 0 ]]; then
    json_error "No repos found. Provide --repos or --auto-detect."
    exit 1
fi

# --- Get current git user ---

GIT_USER_NAME=$(git config user.name 2>/dev/null || echo "")
GIT_USER_EMAIL=$(git config user.email 2>/dev/null || echo "")

# --- Extract commits ---

all_commits="[]"

for repo in "${repo_list[@]}"; do
    if [[ ! -d "$repo/.git" ]]; then
        continue
    fi

    repo_name=$(basename "$repo")

    # Get commits by the current user in the date range
    commits_json=$(git -C "$repo" log \
        --after="$FROM_DATE" \
        --before="$TO_DATE" \
        --author="$GIT_USER_EMAIL" \
        --format='{"hash":"%H","short_hash":"%h","subject":"%s","date":"%ai","author":"%an"}' \
        2>/dev/null | jq -s --arg repo "$repo_name" --arg repo_path "$repo" '[.[] | . + {"repo": $repo, "repo_path": $repo_path}]')

    if [[ -n "$commits_json" && "$commits_json" != "[]" ]]; then
        all_commits=$(echo "$all_commits" "$commits_json" | jq -s '.[0] + .[1]')
    fi
done

# --- Build summary ---

summary=$(echo "$all_commits" | jq '{
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

- [ ] **Step 2: Make script executable and test**

```bash
chmod +x scripts/extract-git-activity.sh
bash scripts/extract-git-activity.sh --from 2026-03-26 --to 2026-03-28 --repos '["C:/src/AdoTaskAssitant"]'
# Expected: JSON with commits from this repo
```

- [ ] **Step 3: Commit git activity script**

```bash
git add scripts/extract-git-activity.sh
git commit -m "Add git activity extraction script for commit scanning across repos"
```

---

### Task 6: Session Log Parser Script

**Files:**
- Create: `scripts/parse-session-logs.sh`

- [ ] **Step 1: Investigate Claude Code session log location and format**

Run these commands to find where Claude Code stores session data:

```bash
# Check common locations
ls -la ~/.claude/ 2>/dev/null
ls -la ~/.claude/projects/ 2>/dev/null
ls -la "$APPDATA/Claude/" 2>/dev/null
ls -la "$LOCALAPPDATA/Claude/" 2>/dev/null

# Look for session-related files
find ~/.claude -name "*session*" -o -name "*history*" -o -name "*log*" 2>/dev/null | head -20
```

Document what you find — the script will need to adapt to the actual file format.

- [ ] **Step 2: Create scripts/parse-session-logs.sh**

```bash
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
# discovered in Step 1
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
```

- [ ] **Step 3: Make script executable**

```bash
chmod +x scripts/parse-session-logs.sh
bash scripts/parse-session-logs.sh --from 2026-03-26 --to 2026-03-28
# Expected: Either session data or a clear error about log location
```

- [ ] **Step 4: Commit session log parser**

```bash
git add scripts/parse-session-logs.sh
git commit -m "Add session log parser script for Claude Code activity extraction"
```

---

### Task 7: Reference Task Parser Prompt

**Files:**
- Create: `prompts/ado-tracker-parse-reference-task.prompt.md`

- [ ] **Step 1: Create prompts/ado-tracker-parse-reference-task.prompt.md**

```markdown
# Parse Reference Task

## Goal
Fetch a reference ADO work item and generate a reusable task template from it.

## Context
- ADO CLI: `bash scripts/ado-cli.sh --action show-work-item --params '{"id":<ID>}'`
- Template manager: `bash scripts/template-manager.sh`
- Template schema: `schemas/task-template.schema.md`

## Input
The user provides a work item ID or URL. If a URL is provided, extract the numeric ID from it.

## Instructions

1. Fetch the work item using the ADO CLI:
   ```bash
   bash scripts/ado-cli.sh --action show-work-item --params '{"id":<ID>}'
   ```
2. If the fetch fails, show the error message and guide the user to fix it:
   - **401/403**: PAT may be expired or missing scopes. Direct user to check `AZURE_DEVOPS_EXT_PAT`.
   - **404**: Work item ID may be wrong, or it's in a different project. Confirm org/project config.
   - **Connection error**: Check network and `az devops configure --defaults`.
3. On success, extract the template using the template manager:
   ```bash
   bash scripts/template-manager.sh --action extract --params '{"work_item": <raw-work-item-json>}'
   ```
4. Present the extracted template to the user in a readable format:
   - Show each field with its value
   - Highlight the area path and iteration pattern
   - Show the description format template
   - Show default tags and priority
5. Ask the user to review:
   - "Does this template look correct?"
   - "Would you like to change any fields or defaults?"
6. If the user requests changes, apply them:
   ```bash
   bash scripts/template-manager.sh --action update --params '{"updates": {<changed-fields>}}'
   ```
7. Save the final approved template:
   ```bash
   bash scripts/template-manager.sh --action write --params '<final-template-json>'
   ```
8. Confirm: "Template saved to `data/task-template.json`. This will be used for all future PBI/Task creation."

## Output
The saved template file at `data/task-template.json`, reviewed and approved by the user.
```

- [ ] **Step 2: Commit reference task parser prompt**

```bash
git add prompts/ado-tracker-parse-reference-task.prompt.md
git commit -m "Add reference task parser prompt for template generation"
```

---

### Task 8: Activity Gathering Prompts

**Files:**
- Create: `prompts/ado-tracker-gather-github.prompt.md`
- Create: `prompts/ado-tracker-gather-notion.prompt.md`
- Create: `prompts/ado-tracker-gather-sessions.prompt.md`

- [ ] **Step 1: Create prompts/ado-tracker-gather-github.prompt.md**

```markdown
# Gather GitHub Activity

## Goal
Fetch GitHub PRs authored or reviewed by the user within a date range, filtered by configured organizations.

## Context
- Config: `data/config.json` — read `github.orgs`, `github.exclude_repos`, `github.username`
- Tool: `gh` CLI (must be authenticated)

## Input
- `from_date`: Start date (YYYY-MM-DD)
- `to_date`: End date (YYYY-MM-DD)

## Instructions

1. Read `data/config.json` for GitHub settings.
2. Detect username if not configured:
   ```bash
   gh api user --jq .login
   ```
3. For each configured org, search for PRs authored by the user in the date range:
   ```bash
   gh search prs --author=<username> --created=<from_date>..<to_date> --owner=<org> --json number,title,repository,state,createdAt,updatedAt,url --limit 100
   ```
4. Also search for PRs reviewed by the user:
   ```bash
   gh search prs --reviewed-by=<username> --created=<from_date>..<to_date> --owner=<org> --json number,title,repository,state,createdAt,updatedAt,url --limit 100
   ```
5. Filter out any repos in `github.exclude_repos`.
6. Deduplicate (a PR you authored and reviewed should appear once, tagged as both).
7. Return structured JSON array:
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

- [ ] **Step 2: Create prompts/ado-tracker-gather-notion.prompt.md**

```markdown
# Gather Notion Activity

## Goal
Fetch Notion pages owned or substantially edited by the user within a date range.

## Context
- Config: `data/config.json` — read `notion.scope`, `notion.exclude_databases`, `notion.track_ownership`, `notion.track_edits`
- Tool: Notion MCP (`notion-search`, `notion-fetch`)

## Input
- `from_date`: Start date (YYYY-MM-DD)
- `to_date`: End date (YYYY-MM-DD)

## Instructions

1. Read `data/config.json` for Notion settings.
2. Use the Notion MCP `notion-search` tool to find recently edited pages:
   - Search with a broad query or use `notion-query-data-sources` for database-scoped searches
   - Filter results to the date range
3. For each page found, determine the user's relationship:
   - **Owner**: User created the page
   - **Editor**: User made substantial edits (not just comments)
   - Skip pages where the user only added comments
4. If `notion.scope` is `"databases"`, only include pages from non-excluded databases.
5. Filter out any databases in `notion.exclude_databases`.
6. For each qualifying page, fetch enough detail to generate a meaningful task title:
   - Page title
   - Parent database or workspace location
   - Last edited time
7. Return structured JSON array:
   ```json
   [
     {
       "type": "notion_page",
       "page_id": "abc-123",
       "title": "Q2 Onboarding Flow Redesign",
       "url": "https://notion.so/abc-123",
       "parent": "Design Specs database",
       "role": "owner",
       "last_edited": "2026-03-27"
     }
   ]
   ```

## Output
JSON array of Notion activity objects.
```

- [ ] **Step 3: Create prompts/ado-tracker-gather-sessions.prompt.md**

```markdown
# Gather Claude Session & Git Activity

## Goal
Gather Claude Code session activity and git commits for a date range. These are combined because they represent closely related local development work.

## Context
- Session parser: `bash scripts/parse-session-logs.sh --from <date> --to <date>`
- Git extractor: `bash scripts/extract-git-activity.sh --from <date> --to <date>`
- Config: `data/config.json` — read `git.repos`, `git.auto_detect_from`, `session_logs`

## Input
- `from_date`: Start date (YYYY-MM-DD)
- `to_date`: End date (YYYY-MM-DD)

## Instructions

1. Read `data/config.json` for git and session log settings.
2. Extract git activity:
   ```bash
   bash scripts/extract-git-activity.sh --from <from_date> --to <to_date> --repos '<repos-json>'
   ```
   Or if using auto-detect:
   ```bash
   bash scripts/extract-git-activity.sh --from <from_date> --to <to_date> --auto-detect "<auto_detect_from>"
   ```
3. Parse Claude Code session logs (if enabled):
   ```bash
   bash scripts/parse-session-logs.sh --from <from_date> --to <to_date>
   ```
4. Correlate sessions with git commits where possible:
   - If a session description mentions a repo that also has commits, group them
   - Sessions without matching commits are still included as standalone activity
5. Return structured JSON array:
   ```json
   [
     {
       "type": "dev_activity",
       "source": "git+session",
       "repo": "Mindbody.Api.Rest",
       "summary": "Refactored auth middleware — 4 commits",
       "commit_count": 4,
       "commits": [
         {"hash": "abc1234", "subject": "Extract auth logic to middleware"}
       ],
       "session_description": "Refactored authentication middleware for the REST API",
       "date": "2026-03-27"
     }
   ]
   ```

## Output
JSON array of development activity objects combining git and session data.
```

- [ ] **Step 4: Commit activity gathering prompts**

```bash
git add prompts/ado-tracker-gather-github.prompt.md prompts/ado-tracker-gather-notion.prompt.md prompts/ado-tracker-gather-sessions.prompt.md
git commit -m "Add activity gathering prompts for GitHub, Notion, and Claude sessions"
```

---

### Task 9: Proposal Prompt — Match Activity to ADO

**Files:**
- Create: `prompts/ado-tracker-propose-updates.prompt.md`

- [ ] **Step 1: Create prompts/ado-tracker-propose-updates.prompt.md**

```markdown
# Propose ADO Updates

## Goal
Take gathered activity from all sources, cross-reference with existing ADO work items, and present a grouped proposal for the user to approve.

## Context
- ADO CLI: `bash scripts/ado-cli.sh`
- Template: `bash scripts/template-manager.sh --action read`
- Activity data: Passed in as JSON from the gathering prompts

## Input
- `activity`: Combined JSON array from all gather prompts (GitHub, Notion, sessions/git)
- `sprint`: Current sprint name and iteration path
- `last_run`: Data from `data/last-run.json`

## Instructions

1. Read the task template:
   ```bash
   bash scripts/template-manager.sh --action read
   ```

2. Query ADO for existing work items in the current sprint that may match the activity:
   ```bash
   bash scripts/ado-cli.sh --action query-work-items --params '{"wiql":"SELECT [System.Id], [System.Title], [System.State], [System.Tags] FROM WorkItems WHERE [System.IterationPath] = '\''<iteration-path>'\'' AND [System.AssignedTo] = @Me ORDER BY [System.CreatedDate] DESC"}'
   ```

3. For each activity item, classify it:
   - **CREATE** — No matching ADO work item found. Propose creating a new PBI using the template.
   - **UPDATE** — A matching ADO work item exists (by title similarity, linked PR, or tag). Propose updating it (e.g., adding a link, updating description).
   - **CLOSE** — A matching ADO work item exists and the activity indicates completion (PR merged, task done).
   - **SKIP** — Activity is too minor or already tracked. Note why.

4. Present the proposal grouped by source, using this format:

   ```
   ## GitHub PRs
     1. [+] Create PBI: "Add retry logic to payment webhook" — PR #1234 in org/repo
     2. [~] Update PBI-5678: Add PR link — PR #1235 in org/repo

   ## Notion Pages
     3. [+] Create PBI: "Q2 onboarding flow redesign" — edited page "Onboarding Spec v2"

   ## Claude Sessions / Git
     4. [+] Create Task under PBI-9012: "Refactor auth middleware" — 4 commits in Mindbody.Api.Rest

   Sprint: Sprint-42 (auto-detected, unchanged)
   Area Path: Project\Team\Area

   Skipped:
     - Minor commit "fix typo" in AdoTaskAssistant (too minor)
   ```

5. After presenting, offer controls:
   - "Enter item numbers to approve (e.g., `1,3,4`), `all` to approve everything, or `none` to skip."
   - "Enter `expand <number>` to see full ADO task preview for any item."
   - "Enter `edit <number>` to modify the proposed title or details before approving."

6. Wait for user selection. Return the approved items as a JSON array with all fields needed for the apply step:
   ```json
   [
     {
       "action": "create",
       "work_item_type": "Product Backlog Item",
       "title": "Add retry logic to payment webhook",
       "description": "...",
       "area_path": "Project\\Team\\Area",
       "iteration_path": "Project\\Sprint-42",
       "source": {"type": "github_pr", "url": "..."},
       "fields": {}
     }
   ]
   ```

## Output
JSON array of approved update actions, ready for the apply prompt.
```

- [ ] **Step 2: Commit proposal prompt**

```bash
git add prompts/ado-tracker-propose-updates.prompt.md
git commit -m "Add proposal prompt for matching activity to ADO and user approval"
```

---

### Task 10: Apply Updates Prompt

**Files:**
- Create: `prompts/ado-tracker-apply-updates.prompt.md`

- [ ] **Step 1: Create prompts/ado-tracker-apply-updates.prompt.md**

```markdown
# Apply ADO Updates

## Goal
Execute the user-approved ADO changes — create, update, or close work items.

## Context
- ADO CLI: `bash scripts/ado-cli.sh`
- Template: `data/task-template.json`
- Input: JSON array of approved actions from the propose step

## Input
- `approved_actions`: JSON array of approved changes (from propose-updates prompt)
- `sprint_folder`: Path to the current sprint's updates folder

## Instructions

1. For each approved action, execute the corresponding ADO CLI command:

   **CREATE:**
   ```bash
   bash scripts/ado-cli.sh --action create-work-item --params '{
     "type": "<work_item_type>",
     "title": "<title>",
     "area_path": "<area_path>",
     "iteration_path": "<iteration_path>",
     "description": "<description>",
     "fields": {<additional-fields>}
   }'
   ```

   **UPDATE:**
   ```bash
   bash scripts/ado-cli.sh --action update-work-item --params '{
     "id": <existing-id>,
     "fields": {<fields-to-update>}
   }'
   ```

   **CLOSE:**
   ```bash
   bash scripts/ado-cli.sh --action close-work-item --params '{"id": <existing-id>}'
   ```

   **ADD CHILD (for tasks under PBIs):**
   ```bash
   # First create the child task
   bash scripts/ado-cli.sh --action create-work-item --params '{
     "type": "Task",
     "title": "<title>",
     "area_path": "<area_path>",
     "iteration_path": "<iteration_path>"
   }'
   # Then link it as a child
   bash scripts/ado-cli.sh --action add-child --params '{"parent_id": <pbi-id>, "child_id": <new-task-id>}'
   ```

2. Track results for each action:
   - On success: record the work item ID, URL, and action taken
   - On failure: record the error, do NOT retry automatically. Show the error to the user and ask if they want to retry or skip.

3. Save results to the sprint updates folder:
   ```
   data/sprints/<Sprint-Name>/updates/<date>-<type>.json
   ```
   Format:
   ```json
   {
     "run_type": "daily",
     "date": "2026-03-27",
     "sprint": "Sprint-42",
     "proposed": [...],
     "accepted": [...],
     "applied": [
       {
         "action": "create",
         "work_item_id": 12345,
         "title": "Add retry logic to payment webhook",
         "url": "https://dev.azure.com/...",
         "status": "success"
       }
     ],
     "errors": []
   }
   ```

4. Present a summary to the user:
   ```
   ## Applied Changes
   ✓ Created PBI #12345: "Add retry logic to payment webhook"
   ✓ Updated PBI #5678: Added PR link
   ✗ Failed to create PBI "Q2 onboarding flow redesign" — error: <message>

   Results saved to data/sprints/Sprint-42/updates/2026-03-27-daily.json
   ```

## Output
Summary of applied changes with links to created/updated work items.
```

- [ ] **Step 2: Commit apply updates prompt**

```bash
git add prompts/ado-tracker-apply-updates.prompt.md
git commit -m "Add apply updates prompt for executing approved ADO changes"
```

---

### Task 11: Manual PBI/Task Creation Prompts

**Files:**
- Create: `prompts/ado-tracker-create-pbi.prompt.md`
- Create: `prompts/ado-tracker-create-task.prompt.md`
- Create: `prompts/ado-tracker-breakdown-pbi.prompt.md`

- [ ] **Step 1: Create prompts/ado-tracker-create-pbi.prompt.md**

```markdown
# Create PBI

## Goal
Create a new Product Backlog Item in ADO from a user-provided description, using the saved template.

## Context
- ADO CLI: `bash scripts/ado-cli.sh`
- Template: `bash scripts/template-manager.sh --action read`
- Sprint: `bash scripts/ado-cli.sh --action current-sprint`

## Input
The user provides a description of the work item. This can be a single sentence or a detailed description.

## Instructions

1. Read the template:
   ```bash
   bash scripts/template-manager.sh --action read
   ```
   If template is missing, tell the user to run `/ado-tracker-init` first.

2. Detect current sprint:
   ```bash
   bash scripts/ado-cli.sh --action current-sprint
   ```
   Present the sprint to the user for confirmation.

3. Generate PBI fields from the user's description and the template:
   - **Title**: Concise, actionable title derived from the description
   - **Description**: Formatted using `description_format` from the template, with the user's description as the summary
   - **Area Path**: From template
   - **Iteration Path**: Current sprint iteration path
   - **Tags**: Template defaults
   - **Priority**: Template default (user can override)

4. Present the full PBI preview to the user:
   ```
   ## New PBI Preview
   Title: <title>
   Type: Product Backlog Item
   Area Path: <area_path>
   Sprint: <sprint>
   Priority: <priority>
   Tags: <tags>

   Description:
   <formatted-description>
   ```

5. Ask: "Create this PBI? You can edit any field before confirming."

6. On approval, create the work item:
   ```bash
   bash scripts/ado-cli.sh --action create-work-item --params '{...}'
   ```

7. Report the result with the new work item ID and URL.

## Output
Created PBI with ID and URL.
```

- [ ] **Step 2: Create prompts/ado-tracker-create-task.prompt.md**

```markdown
# Create Task Under PBI

## Goal
Create one or more child tasks under an existing PBI.

## Context
- ADO CLI: `bash scripts/ado-cli.sh`
- Template: `bash scripts/template-manager.sh --action read`
- Sprint: `bash scripts/ado-cli.sh --action current-sprint`

## Input
- `pbi_id`: The parent PBI work item ID
- `description`: Description of the task(s) to create

## Instructions

1. Fetch the parent PBI to confirm it exists and get its context:
   ```bash
   bash scripts/ado-cli.sh --action show-work-item --params '{"id":<pbi_id>}'
   ```
   If it fails, show the error and ask the user to verify the ID.

2. Read the template and detect current sprint (same as create-pbi prompt).

3. Generate task fields:
   - **Title**: Concise task title from the description
   - **Type**: `"Task"`
   - **Area Path**: Inherit from parent PBI
   - **Iteration Path**: Current sprint (confirm with user)
   - **Description**: Task-level description

4. Present the task preview, showing the parent PBI for context:
   ```
   ## New Task Preview
   Parent PBI #<id>: <pbi-title>

   Task Title: <title>
   Area Path: <area_path> (inherited from parent)
   Sprint: <sprint>

   Description:
   <description>
   ```

5. On approval, create the task and link it:
   ```bash
   # Create the task
   bash scripts/ado-cli.sh --action create-work-item --params '{
     "type": "Task",
     "title": "<title>",
     "area_path": "<area_path>",
     "iteration_path": "<iteration_path>",
     "description": "<description>"
   }'
   # Link as child of PBI
   bash scripts/ado-cli.sh --action add-child --params '{"parent_id": <pbi_id>, "child_id": <new_task_id>}'
   ```

6. Report result with task ID, URL, and parent link.

## Output
Created task(s) with IDs, URLs, and parent PBI link.
```

- [ ] **Step 3: Create prompts/ado-tracker-breakdown-pbi.prompt.md**

```markdown
# Break Down PBI

## Goal
Decompose an existing PBI into multiple smaller child tasks.

## Context
- ADO CLI: `bash scripts/ado-cli.sh`
- Template: `bash scripts/template-manager.sh --action read`
- Sprint: `bash scripts/ado-cli.sh --action current-sprint`

## Input
- `pbi_id`: The PBI work item ID to break down

## Instructions

1. Fetch the PBI to understand what needs to be decomposed:
   ```bash
   bash scripts/ado-cli.sh --action show-work-item --params '{"id":<pbi_id>}'
   ```

2. Also check for any existing child tasks:
   ```bash
   bash scripts/ado-cli.sh --action query-work-items --params '{"wiql":"SELECT [System.Id], [System.Title], [System.State] FROM WorkItemLinks WHERE ([Source].[System.Id] = <pbi_id>) AND ([System.Links.LinkType] = '\''System.LinkTypes.Hierarchy-Forward'\'') MODE (MustContain)"}'
   ```

3. Read the template and detect current sprint.

4. Analyze the PBI title and description. Propose a breakdown into child tasks:
   - Each task should be a concrete, actionable unit of work
   - Tasks should cover the full scope of the PBI
   - If existing child tasks are found, account for them (don't duplicate)

5. Present the breakdown proposal:
   ```
   ## PBI #<id>: <pbi-title>
   Existing tasks: <count> (listed below if any)

   ## Proposed Breakdown
   1. Task: "<task-1-title>" — <one-line description>
   2. Task: "<task-2-title>" — <one-line description>
   3. Task: "<task-3-title>" — <one-line description>

   Sprint: <sprint>
   Area Path: <area_path>
   ```

6. Ask user to review: "Approve all, select specific tasks, or edit any task before creating?"

7. Create approved tasks and link each as a child:
   ```bash
   # For each approved task:
   bash scripts/ado-cli.sh --action create-work-item --params '{...}'
   bash scripts/ado-cli.sh --action add-child --params '{"parent_id": <pbi_id>, "child_id": <task_id>}'
   ```

8. Report all created tasks with IDs and URLs.

## Output
List of created child tasks with IDs, URLs, and parent link.
```

- [ ] **Step 4: Commit manual creation prompts**

```bash
git add prompts/ado-tracker-create-pbi.prompt.md prompts/ado-tracker-create-task.prompt.md prompts/ado-tracker-breakdown-pbi.prompt.md
git commit -m "Add manual PBI/Task creation and breakdown prompts"
```

---

### Task 12: Automation Files — Daily and Ad-hoc Scans

**Files:**
- Create: `automations/ado-tracker-daily.automation.md`
- Create: `automations/ado-tracker-adhoc.automation.md`

- [ ] **Step 1: Create automations/ado-tracker-daily.automation.md**

```markdown
# ADO Tracker — Daily Scan

## Goal
Full daily workflow: detect sprint, gather all activity since last run, propose ADO updates, apply approved changes, and persist results.

## Steps

### Step 1: Load Configuration
- Read `data/config.json`. If missing, tell the user: "Configuration not found. Run `/ado-tracker-init` to set up."
- Read `data/last-run.json`. If missing, this is the first run — set `since_date` to yesterday.
- Read `data/task-template.json`. If missing, tell the user: "Task template not found. Run `/ado-tracker-init` to set up."
- **On failure**: Stop and direct user to `/ado-tracker-init`.

### Step 2: Detect Sprint
- Run `bash scripts/ado-cli.sh --action current-sprint`
- Compare with `last-run.json` sprint value.
- If sprint has changed since last run:
  - Alert: "⚠️ Sprint changed from <old> to <new> since last run on <date>."
  - Create new sprint folder: `data/sprints/<new-sprint>/activity/` and `data/sprints/<new-sprint>/updates/`
- Present sprint for confirmation: "Current sprint: <sprint-name>. Proceed?"
- **On failure**: Show error, suggest checking `az devops configure --defaults` and team iteration settings. Continue only after user confirms sprint manually.

### Step 3: Gather GitHub Activity
- Execute `ado-tracker-gather-github.prompt.md` with `from_date` = last run date, `to_date` = today.
- **On failure**: Note "GitHub activity scan skipped — <error>". Continue to next step.

### Step 4: Gather Notion Activity
- Execute `ado-tracker-gather-notion.prompt.md` with `from_date` = last run date, `to_date` = today.
- **On failure**: Note "Notion activity scan skipped — <error>". Continue to next step.

### Step 5: Gather Claude Session & Git Activity
- Execute `ado-tracker-gather-sessions.prompt.md` with `from_date` = last run date, `to_date` = today.
- **On failure**: Note "Session/git activity scan skipped — <error>". Continue to next step.

### Step 6: Save Activity Snapshot
- Combine all gathered activity into a single JSON file.
- Save to `data/sprints/<sprint>/activity/<date>-daily.json`.
- If all gathering steps failed, inform the user and stop: "No activity could be gathered. Check tool connections."

### Step 7: Propose Updates
- Execute `ado-tracker-propose-updates.prompt.md` with the combined activity, current sprint, and last run data.
- Wait for user approval/selection.
- If user approves nothing, skip to Step 9.
- **On failure**: Show error. Save activity snapshot (Step 6 already done) and update last-run.json so the next run doesn't re-scan the same period.

### Step 8: Apply Updates
- Execute `ado-tracker-apply-updates.prompt.md` with the approved actions.
- Results are saved to `data/sprints/<sprint>/updates/<date>-daily.json` by the apply prompt.
- **On failure**: Partial results are saved. Show what succeeded and what failed.

### Step 9: Update Last Run
- Write `data/last-run.json`:
  ```json
  {
    "last_run_date": "<today>",
    "last_run_type": "daily",
    "sprint": "<current-sprint-name>",
    "items_proposed": <count>,
    "items_applied": <count>
  }
  ```

### Step 10: Summary
- Present a final summary:
  ```
  ## Daily Scan Complete
  Sprint: <sprint>
  Activity found: <count> items across <sources>
  Proposed: <count> ADO updates
  Applied: <count> changes
  Next run: <scheduled time>
  ```
```

- [ ] **Step 2: Create automations/ado-tracker-adhoc.automation.md**

```markdown
# ADO Tracker — Ad-hoc Scan

## Goal
Run an activity scan for a user-specified date range and propose ADO updates. Same as daily scan but with custom dates and no schedule dependency.

## Input
- `from_date`: Start date (YYYY-MM-DD)
- `to_date`: End date (YYYY-MM-DD)

If not provided, ask the user: "What date range would you like to scan? (format: YYYY-MM-DD to YYYY-MM-DD)"

## Steps

### Step 1: Load Configuration
- Read `data/config.json`. If missing, direct user to `/ado-tracker-init`.
- Read `data/task-template.json`. If missing, direct user to `/ado-tracker-init`.
- **On failure**: Stop and direct user to `/ado-tracker-init`.

### Step 2: Detect and Confirm Sprint
- Run `bash scripts/ado-cli.sh --action current-sprint`
- Present for confirmation: "Current sprint: <sprint-name>. The scan results will be filed under this sprint. Proceed?"
- **On failure**: Ask user to provide sprint name manually.

### Step 3: Gather GitHub Activity
- Execute `ado-tracker-gather-github.prompt.md` with the user-specified date range.
- **On failure**: Note "GitHub scan skipped — <error>". Continue.

### Step 4: Gather Notion Activity
- Execute `ado-tracker-gather-notion.prompt.md` with the user-specified date range.
- **On failure**: Note "Notion scan skipped — <error>". Continue.

### Step 5: Gather Claude Session & Git Activity
- Execute `ado-tracker-gather-sessions.prompt.md` with the user-specified date range.
- **On failure**: Note "Session/git scan skipped — <error>". Continue.

### Step 6: Save Activity Snapshot
- Save to `data/sprints/<sprint>/activity/<from>-to-<to>-adhoc.json`.
- If all steps failed, inform user and stop.

### Step 7: Propose Updates
- Execute `ado-tracker-propose-updates.prompt.md` with combined activity.
- Wait for user approval.

### Step 8: Apply Updates
- Execute `ado-tracker-apply-updates.prompt.md` with approved actions.
- Save to `data/sprints/<sprint>/updates/<from>-to-<to>-adhoc.json`.

### Step 9: Summary
- Present results with counts and links to created/updated items.
- Note: Ad-hoc scans do NOT update `last-run.json` (they don't affect the daily schedule).
```

- [ ] **Step 3: Commit automation files**

```bash
git add automations/ado-tracker-daily.automation.md automations/ado-tracker-adhoc.automation.md
git commit -m "Add daily and ad-hoc scan automation workflows"
```

---

### Task 13: Init Wizard Skill

**Files:**
- Create: `skills/ado-tracker-init.md`

- [ ] **Step 1: Create skills/ado-tracker-init.md**

```markdown
---
name: ado-tracker-init
description: Guided setup wizard for ADO Tracker — prerequisites, auth, template, config, and schedule
---

# ADO Tracker — Initialization Wizard

You are running the ADO Tracker setup wizard. Guide the user through each step sequentially. Each step flows into the next automatically — the user just answers prompts as they come. Do not wait for the user to trigger individual steps.

## Step 1: Prerequisites Check

Check each prerequisite and report status. For any failures, provide step-by-step fix instructions and wait for the user to resolve before continuing.

### GitHub CLI
```bash
gh auth status
```
- **Pass**: Shows authenticated user
- **Fail**: "GitHub CLI is not authenticated. Run `gh auth login` to authenticate, then tell me when you're ready."

### Azure CLI
```bash
az version
```
- **Pass**: Shows az version info
- **Fail**: "Azure CLI is not installed. Install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli — then tell me when you're ready."

### Azure DevOps Extension
```bash
az extension show --name azure-devops 2>/dev/null || echo "NOT_INSTALLED"
```
- **Pass**: Shows extension info
- **Fail**: "Azure DevOps extension is not installed. Run `az extension add --name azure-devops` — then tell me when you're ready."

### Notion MCP
- Check if Notion MCP tools are available (try `notion-search` with a test query)
- **Pass**: MCP responds
- **Fail**: "Notion MCP is not connected. Add it to your Claude Code MCP configuration. See https://github.com/anthropics/claude-code-mcp for setup instructions."

Report: "✓ Prerequisites check complete. All tools are available."

## Step 2: Azure DevOps Authentication

Guide the user through PAT-based persistent auth:

1. Ask: "What is your Azure DevOps organization URL? (e.g., `https://dev.azure.com/your-org`)"
2. Ask: "What is your ADO project name?"
3. Configure defaults:
   ```bash
   az devops configure --defaults organization=<org-url> project=<project-name>
   ```
4. Ask: "Do you already have an Azure DevOps Personal Access Token (PAT) set up, or do you need to create one?"
   - If they need to create one:
     - "Go to: `<org-url>/_usersettings/tokens`"
     - "Create a new token with these scopes: **Work Items** (Read & Write), **Project and Team** (Read), **Build** (Read)"
     - "Set expiration to the maximum allowed (up to 1 year recommended)"
     - "Copy the token — you won't be able to see it again"
   - If they have one: proceed to next step.
5. Ask: "Please set the `AZURE_DEVOPS_EXT_PAT` environment variable with your token. The best way depends on your shell:"
   - **bash/zsh**: `echo 'export AZURE_DEVOPS_EXT_PAT=<your-token>' >> ~/.bashrc && source ~/.bashrc`
   - **Windows (PowerShell)**: `[System.Environment]::SetEnvironmentVariable('AZURE_DEVOPS_EXT_PAT', '<your-token>', 'User')`
   - "Tell me when you've set it. You may need to restart your terminal for it to take effect."
6. After they confirm, verify: `echo $AZURE_DEVOPS_EXT_PAT | head -c 5` (just check it's set, don't display the full token)

## Step 3: Reference Task & Auth Validation

1. Ask: "Please provide a reference ADO work item ID or URL. This will be used as a template for all future task creation."
2. Extract the numeric ID from the URL if needed.
3. Attempt to fetch it:
   ```bash
   bash scripts/ado-cli.sh --action show-work-item --params '{"id":<id>}'
   ```
4. If it **fails**, parse the error and guide the user:
   - **"az: command not found"**: "Azure CLI is not in your PATH. Check your installation."
   - **"401"** or **"unauthorized"**: "Authentication failed. Check that `AZURE_DEVOPS_EXT_PAT` is set correctly and the token hasn't expired."
   - **"403"** or **"forbidden"**: "Access denied. Your PAT may be missing the required scopes (Work Items Read/Write)."
   - **"404"** or **"does not exist"**: "Work item not found. Verify the ID and that your org/project defaults are correct (`az devops configure --list`)."
   - **Other error**: Show the full error message. "Please check the error above and let me know when you've fixed it."
   - After each fix: re-attempt the fetch. Repeat until successful.
5. On **success**: "✓ Successfully fetched work item #<id>: '<title>'. Auth is working correctly."

## Step 4: Template Generation

1. Using the work item fetched in Step 3, extract the template:
   ```bash
   bash scripts/template-manager.sh --action extract --params '{"work_item": <raw-json>}'
   ```
2. Present the template to the user (follow the parse-reference-task prompt instructions).
3. Allow edits. Save the final approved template:
   ```bash
   bash scripts/template-manager.sh --action write --params '<template-json>'
   ```
4. "✓ Template saved. This will be used for all future PBI/Task creation."

## Step 5: User Configuration

Prompt for each setting sequentially:

1. "Which GitHub organization(s) should I track? (comma-separated, e.g., `mindbodyonline`)"
2. "Any GitHub repos to exclude? (comma-separated `org/repo` format, or `none`)"
3. "For Notion, should I track all pages or only specific databases? (`all` / `databases`)"
   - If databases: "Which database IDs to exclude? (or `none`)"
4. "Which local git repos should I scan for commits?"
   - Offer auto-detect: "I can auto-detect repos under a parent directory. What's your source code root? (e.g., `C:/src`) Or provide specific paths."
5. "What time should the daily scan run? (HH:MM, 24h format, default: 09:00)"

Build `data/config.json` from the answers and save it. Present a summary for confirmation.

## Step 6: First Run (Optional)

"Setup is complete! Would you like to run an initial scan now?"
- If yes: "What date range? (e.g., `last week`, `2026-03-20 to 2026-03-27`, or `today`)"
  - Execute `ado-tracker-adhoc.automation.md` with the specified range.
- If no: "No problem. You can run `/ado-tracker-daily` anytime, or wait for the scheduled run."

## Step 7: Schedule

"Would you like to set up the daily automated scan now?"
- If yes: "I'll configure a `/loop` schedule to run the daily scan at <configured-time> every day."
  - Set up the loop schedule.
  - "✓ Daily scan scheduled. It will run at <time> and present proposed changes for your review."
- If no: "You can set this up later. Just run `/ado-tracker-daily` whenever you want."

"✅ ADO Tracker is fully configured and ready to use!"
```

- [ ] **Step 2: Commit init wizard skill**

```bash
git add skills/ado-tracker-init.md
git commit -m "Add init wizard skill for guided ADO Tracker onboarding"
```

---

### Task 14: Remaining Skills — Daily, Scan, Create, Task, Breakdown

**Files:**
- Create: `skills/ado-tracker-daily.md`
- Create: `skills/ado-tracker-scan.md`
- Create: `skills/ado-tracker-create.md`
- Create: `skills/ado-tracker-task.md`
- Create: `skills/ado-tracker-breakdown.md`

- [ ] **Step 1: Create skills/ado-tracker-daily.md**

```markdown
---
name: ado-tracker-daily
description: Run the ADO Tracker daily scan — gather activity, propose ADO updates, apply approved changes
---

# ADO Tracker — Daily Scan

Execute the daily scan automation.

## Instructions

1. Execute `automations/ado-tracker-daily.automation.md` — follow each step in sequence.
2. This skill can be triggered manually or by the `/loop` schedule.
```

- [ ] **Step 2: Create skills/ado-tracker-scan.md**

```markdown
---
name: ado-tracker-scan
description: Run an ad-hoc ADO Tracker scan for a custom date range
---

# ADO Tracker — Ad-hoc Scan

Execute an ad-hoc scan for a custom date range.

## Arguments
- `--from YYYY-MM-DD` — Start date
- `--to YYYY-MM-DD` — End date

If dates are not provided as arguments, ask the user.

## Instructions

1. Parse `--from` and `--to` from the arguments.
2. Execute `automations/ado-tracker-adhoc.automation.md` with the parsed date range.
```

- [ ] **Step 3: Create skills/ado-tracker-create.md**

```markdown
---
name: ado-tracker-create
description: Create a new PBI in ADO from a description
---

# ADO Tracker — Create PBI

Create a new Product Backlog Item from a user description.

## Arguments
The remaining text after the command is the PBI description.

## Instructions

1. Take the user's description from the arguments.
2. Execute `prompts/ado-tracker-create-pbi.prompt.md` with the description.
```

- [ ] **Step 4: Create skills/ado-tracker-task.md**

```markdown
---
name: ado-tracker-task
description: Create a child task under an existing PBI
---

# ADO Tracker — Create Task

Create a child task under an existing PBI.

## Arguments
- First argument: PBI work item ID
- Remaining text: task description

## Instructions

1. Parse the PBI ID and description from the arguments.
2. Execute `prompts/ado-tracker-create-task.prompt.md` with the PBI ID and description.
```

- [ ] **Step 5: Create skills/ado-tracker-breakdown.md**

```markdown
---
name: ado-tracker-breakdown
description: Break down an existing PBI into child tasks
---

# ADO Tracker — Break Down PBI

Decompose a PBI into smaller child tasks.

## Arguments
- First argument: PBI work item ID

## Instructions

1. Parse the PBI ID from the arguments.
2. Execute `prompts/ado-tracker-breakdown-pbi.prompt.md` with the PBI ID.
```

- [ ] **Step 6: Commit all remaining skills**

```bash
git add skills/ado-tracker-daily.md skills/ado-tracker-scan.md skills/ado-tracker-create.md skills/ado-tracker-task.md skills/ado-tracker-breakdown.md
git commit -m "Add slash command skills for daily scan, ad-hoc scan, create, task, and breakdown"
```

---

### Task 15: Final Integration — Verify All Files and End-to-End Dry Run

**Files:**
- Modify: `CLAUDE.md` (if any adjustments needed after creating all files)

- [ ] **Step 1: Verify repository structure**

```bash
find . -not -path './.git/*' -not -path './data/*' | sort
```

Expected output should match the spec's repository structure:
```
.
./CLAUDE.md
./.gitignore
./README.md
./automations/ado-tracker-adhoc.automation.md
./automations/ado-tracker-daily.automation.md
./config/config.sample.json
./docs/superpowers/plans/2026-03-27-ado-tracker.md
./docs/superpowers/specs/2026-03-27-ado-tracker-design.md
./prompts/ado-tracker-apply-updates.prompt.md
./prompts/ado-tracker-breakdown-pbi.prompt.md
./prompts/ado-tracker-create-pbi.prompt.md
./prompts/ado-tracker-create-task.prompt.md
./prompts/ado-tracker-gather-github.prompt.md
./prompts/ado-tracker-gather-notion.prompt.md
./prompts/ado-tracker-gather-sessions.prompt.md
./prompts/ado-tracker-parse-reference-task.prompt.md
./prompts/ado-tracker-propose-updates.prompt.md
./schemas/config.schema.md
./schemas/task-template.schema.md
./scripts/ado-cli.sh
./scripts/extract-git-activity.sh
./scripts/parse-session-logs.sh
./scripts/template-manager.sh
./skills/ado-tracker-breakdown.md
./skills/ado-tracker-create.md
./skills/ado-tracker-daily.md
./skills/ado-tracker-init.md
./skills/ado-tracker-scan.md
./skills/ado-tracker-task.md
```

- [ ] **Step 2: Verify all scripts are executable**

```bash
ls -la scripts/*.sh
# All should show -rwxr-xr-x
```

- [ ] **Step 3: Test script error handling**

```bash
# Test ado-cli.sh with no args
bash scripts/ado-cli.sh
# Expected: {"success":false,"error":"Missing --action argument","action":"parse"}

# Test template-manager.sh read before template exists
bash scripts/template-manager.sh --action read
# Expected: {"success":false,"error":"Template not found...","action":"read"}

# Test extract-git-activity.sh with missing dates
bash scripts/extract-git-activity.sh
# Expected: {"success":false,"error":"Missing required arguments: --from and --to..."}

# Test parse-session-logs.sh with missing dates
bash scripts/parse-session-logs.sh
# Expected: {"success":false,"error":"Missing required arguments: --from and --to..."}
```

- [ ] **Step 4: Review CLAUDE.md matches actual file structure**

Read `CLAUDE.md` and verify all script names, paths, and action names match the actual scripts created. Fix any discrepancies.

- [ ] **Step 5: Final commit if any fixes were needed**

```bash
git add -A
git status
# Only commit if there are changes
git commit -m "Final integration fixes after end-to-end verification"
```

---

## Self-Review Checklist

**Spec coverage:**
- ✓ Repository structure (Task 1)
- ✓ Configuration and schemas (Task 2)
- ✓ ADO CLI wrapper (Task 3)
- ✓ Template manager (Task 4)
- ✓ Git activity extraction (Task 5)
- ✓ Session log parsing (Task 6)
- ✓ Reference task parsing / template generation (Task 7)
- ✓ Activity gathering — GitHub, Notion, sessions (Task 8)
- ✓ Proposal / matching (Task 9)
- ✓ Apply updates (Task 10)
- ✓ Manual PBI creation, task creation, PBI breakdown (Task 11)
- ✓ Daily and ad-hoc automation workflows (Task 12)
- ✓ Init wizard (Task 13)
- ✓ All slash command skills (Task 14)
- ✓ Sprint management — covered in ado-cli.sh (current-sprint, list-sprints) and daily automation
- ✓ Sprint-based data organization — covered in automation files
- ✓ Proposal format with grouped display and item-level control (Task 9)
- ✓ Auth validation via reference task fetch (Task 13, Step 3)

**Placeholder scan:** No TBDs, TODOs, or "implement later" found.

**Type consistency:** All script action names, file paths, and JSON formats are consistent across prompts, automations, and skills.
