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
- **JSON params helper:** `bash scripts/build-params.sh --output <file> [--arg key value]... [--argjson key json]... [--slurp-file key path]...`
  - **Always use this** to construct JSON params files for `ado-cli.sh` and `template-manager.sh`
  - Uses `jq --arg` internally — handles backslash escaping in ADO paths automatically
  - `--arg key value`: string values (backslashes handled safely)
  - `--argjson key json`: pre-formed JSON (objects, arrays, numbers, booleans)
  - `--slurp-file key path`: embed a JSON file under a key (e.g., wrap raw work item JSON)
  - **Never use `echo`, heredocs, or inline `--params`** for JSON containing ADO paths (area paths, iteration paths) — backslashes will be mangled by bash/jq
- **Shell escaping rule:** Both `ado-cli.sh` and `template-manager.sh` support `--params-file <path>` as an alternative to `--params '<json>'`. Use `--params` only for simple JSON without backslashes (e.g., `--params '{"id":1234}'`). For anything with ADO paths, use `build-params.sh` + `--params-file`.
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
- `data/task-template.json` — PBI/Task creation template (title_prefix with pattern/slots, work_type with inference keywords, auto_populate_from_source, description_format, fields)
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
