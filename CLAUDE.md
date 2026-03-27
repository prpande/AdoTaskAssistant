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
