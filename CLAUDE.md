# ADO Tracker

## Identity
This workspace is an ADO task tracking assistant operated via Claude Code CLI. It tracks user activity across GitHub, Notion, and git commits — then proposes and manages ADO work items (PBIs and Tasks).

## Architecture
- **Prompts** (`prompts/`): Single-purpose reusable tasks, invokable individually
- **Automations** (`automations/`): Multi-step orchestrated workflows that call prompts in sequence (unified `ado-tracker-scan.automation.md` handles both daily and adhoc modes)
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

## Backslash Escaping — Root Cause & Rules
Claude Code's Bash tool transmits command strings as JSON parameters. JSON string encoding converts every `\\` to `\` during deserialization. This means **any `\\` you write in a Bash command arrives in bash as a single `\`**. This is not a bug — it's standard JSON encoding.

**Consequences:**
- `echo '{"path": "MBScrum\\Sprint"}' > file.json` → file contains `MBScrum\Sprint` → **invalid JSON** (`\S` is not a valid JSON escape)
- Heredocs with `\\` in JSON values → same corruption
- `jq --arg p 'MBScrum\Sprint'` → jq receives single `\` → correctly outputs `MBScrum\\Sprint` in JSON → **safe**

**Rules (non-negotiable):**
1. **Never write JSON containing ADO paths via `echo`, `cat <<`, or inline strings** — the `\\` will be halved, producing invalid JSON
2. **Always use `jq --arg`** (via `build-params.sh`) to inject backslash-containing values into JSON — jq receives the correct single-backslash value and handles JSON encoding itself
3. **To save az CLI JSON output to a file**, pipe it: `az boards ... | jq '.data' > file.json` — never capture in a variable and echo it back
4. **In jq filters inside script files** (on disk, not in Bash tool commands), `split("\\")` splits by one backslash. Use exactly `\\` (2 backslashes) per literal backslash in jq string literals within .sh files.
- **Activity preprocessing:** `bash scripts/preprocess-activity.sh --params-file <file>`
  - Enriches gathered activity with sprint mapping, work type scoring, state assignment, branch group hints
  - All operations are deterministic jq/bash — no LLM tokens consumed
- **Dedup matching:** `bash scripts/dedup-matcher.sh --params-file <file>`
  - Queries existing ADO items, matches by URL and title similarity, checks state lifecycle
  - Gracefully falls back to "all new" if ADO query fails
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
  - `scan`: approval_mode (interactive/auto-confirm/auto-apply), auto_apply_sources
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
| GitHub PR (open) | Committed | Yes — when PR merges |
| GitHub PR (merged) | Done | N/A |
| Notion page | Committed | **Never** — user decides |
| Git commits (no PR) | Committed | Never |

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
data/pending-scan.json                          — metadata for unreviewed proposals
data/sprints/<Sprint-Name>/activity/<date>-<type>.json
data/sprints/<Sprint-Name>/updates/<date>-<type>.json
data/sprints/<Sprint-Name>/pending-proposal-<date>.json — saved proposal awaiting review
```

## Error Handling
- If `az devops` commands fail, show the error and suggest fixes
- If a prerequisite is missing, guide the user to `/ado-tracker-init`
- Never silently skip failures — always inform the user
- Gathering step failures don't block the pipeline — continue with what succeeded
- Session log parsing is best-effort and never blocks
