# ADO Tracker — Design Spec

**Date:** 2026-03-27
**Status:** Draft
**Repository:** Personal GitHub account (not org), at `C:\src\AdoTaskAssitant`

## Purpose

A prompt-driven Claude Code workspace backed by utility scripts that tracks user activity across GitHub, Notion, Claude Code sessions, and git commits — then proposes, creates, updates, or closes ADO work items (PBIs and Tasks) accordingly.

The assistant runs daily via Claude Code's `/loop` feature, presenting a formatted list of proposed ADO changes for user approval. It also supports ad-hoc invocation for custom date ranges and manual task creation.

## Architecture

**Approach:** Hybrid — prompts as the core orchestration layer, backed by utility scripts for deterministic work (session log parsing, git history extraction, template management). All prompts and scripts are independently invocable as ad-hoc skills or slash commands.

**Runtime:** Claude Code CLI with ADO MCP, Notion MCP, and `gh` CLI as the integration layer. No standalone application code.

## Repository Structure

```
AdoTaskAssistant/
├── CLAUDE.md                          # Core instructions for Claude Code
├── .gitignore                         # Excludes data/ directory
├── README.md
│
├── prompts/                           # Single-purpose reusable prompts
│   ├── ado-tracker-gather-github.prompt.md
│   ├── ado-tracker-gather-notion.prompt.md
│   ├── ado-tracker-gather-sessions.prompt.md
│   ├── ado-tracker-parse-reference-task.prompt.md
│   ├── ado-tracker-propose-updates.prompt.md
│   ├── ado-tracker-apply-updates.prompt.md
│   ├── ado-tracker-create-pbi.prompt.md
│   ├── ado-tracker-create-task.prompt.md
│   └── ado-tracker-breakdown-pbi.prompt.md
│
├── automations/                       # Multi-step orchestrated workflows
│   ├── ado-tracker-daily.automation.md
│   └── ado-tracker-adhoc.automation.md
│
├── scripts/                           # Utility scripts for deterministic work
│   ├── parse-session-logs.sh
│   ├── extract-git-activity.sh
│   └── template-manager.sh
│
├── schemas/                           # Data format definitions
│   ├── task-template.schema.md
│   └── config.schema.md
│
├── config/                            # Sample config files (tracked in git)
│   └── config.sample.json
│
└── data/                              # Runtime user data (gitignored)
    ├── config.json
    ├── task-template.json
    ├── last-run.json
    │
    └── sprints/                       # Organized by sprint
        └── Sprint-42/
            ├── activity/
            │   ├── 2026-03-27-daily.json
            │   ├── 2026-03-28-daily.json
            │   └── 2026-03-25-to-03-27-adhoc.json
            └── updates/
                ├── 2026-03-27-daily.json
                ├── 2026-03-28-daily.json
                └── 2026-03-25-to-03-27-adhoc.json
```

- `data/` is fully gitignored — local-only user data
- `config/` holds sample files tracked in git for reference
- Sprint folders are auto-created, named to match the ADO iteration
- Each run (daily or ad-hoc) produces one activity file and one updates file
- Activity files capture all sources for that run
- Update files track the full lifecycle: proposed → accepted → applied

## Core Workflows

### Daily Automated Flow (via `/loop`)

1. **Detect Sprint** — Query ADO for current active iteration, compare with last run. If changed, alert and confirm with user.
2. **Gather Activity** (since last run):
   - GitHub: PRs authored/reviewed via `gh` CLI, filtered by configured org
   - Notion: Pages owned or substantially edited via Notion MCP
   - Claude Sessions: Parsed from local session logs
   - Git Commits: Extracted across configured repos
3. **Match & Deduplicate** — Cross-reference activity against existing ADO tasks. Classify each: CREATE / UPDATE / CLOSE / SKIP.
4. **Propose Changes** — Present grouped by source (GitHub | Notion | Claude/Git). Moderate detail by default, expandable per item. Individual item-level approval control.
5. **Apply** — Execute approved changes via ADO MCP using the task template. Write results to sprint updates folder.
6. **Persist** — Save activity snapshot, update last-run.json.

### Ad-hoc Date Range Scan

Same as daily flow but with a user-specified date range. Triggered via `/ado-tracker-scan --from X --to Y` or natural language. Results saved with the range in the filename.

### Manual PBI/Task Creation

User provides a description, Claude creates the work item using the template. Supports:
- **Create PBI** — New standalone PBI from description
- **Create Task under PBI** — Add child task(s) beneath an existing PBI
- **Break down PBI** — Decompose an existing PBI into smaller child tasks
- **Update existing PBI/Task** — Modify fields on existing items
- **Close PBI/Task** — Mark items as done/closed

### One-time Setup (via `/ado-tracker-init`)

A sequential guided wizard — each step flows into the next automatically. User answers prompts as they come, no manual step triggering.

1. **Prerequisites Check** — Verify `gh` CLI, Notion MCP, ADO MCP are connected. Report missing pieces with fix instructions.
2. **User Configuration** — Prompt for: GitHub org(s), Notion scope, git repos to scan (auto-detect option), daily run time. Save to `data/config.json`.
3. **Template Generation** — Prompt for reference ADO task/PBI URL. Parse via ADO MCP, extract relevant properties (area path, sprint pattern, fields, format). Filter out instance-specific data (attachments, comments). Present template for review. Save to `data/task-template.json`.
4. **First Run (optional)** — Offer an immediate scan with a user-chosen date range. Creates the first sprint folder.
5. **Schedule** — Set up the `/loop` schedule for daily runs. Confirm readiness.

## Skills (Slash Commands)

| Skill | Trigger | Purpose |
|-------|---------|---------|
| `/ado-tracker-init` | Setup | Guided onboarding wizard |
| `/ado-tracker-daily` | On demand | Run the daily scan manually |
| `/ado-tracker-scan` | `/ado-tracker-scan --from X --to Y` | Ad-hoc date range scan |
| `/ado-tracker-create` | `/ado-tracker-create <description>` | Create a new PBI |
| `/ado-tracker-task` | `/ado-tracker-task <PBI-id> <description>` | Add task under existing PBI |
| `/ado-tracker-breakdown` | `/ado-tracker-breakdown <PBI-id>` | Break PBI into child tasks |

## Prompts

| Prompt | Purpose | Ad-hoc? |
|--------|---------|---------|
| `ado-tracker-gather-github.prompt.md` | Fetch PRs by date range for configured org | Yes |
| `ado-tracker-gather-notion.prompt.md` | Fetch edited/owned pages by date range | Yes |
| `ado-tracker-gather-sessions.prompt.md` | Parse Claude session logs for date range | Yes |
| `ado-tracker-parse-reference-task.prompt.md` | Read reference ADO work item, generate template | Yes |
| `ado-tracker-propose-updates.prompt.md` | Match activity to ADO, present grouped proposal | Yes |
| `ado-tracker-apply-updates.prompt.md` | Execute approved ADO creates/updates/closes | Yes |
| `ado-tracker-create-pbi.prompt.md` | Create new PBI from user description | Yes |
| `ado-tracker-create-task.prompt.md` | Create child task(s) under existing PBI | Yes |
| `ado-tracker-breakdown-pbi.prompt.md` | Decompose PBI into child tasks | Yes |

## Scripts

| Script | Purpose |
|--------|---------|
| `parse-session-logs.sh` | Extract Claude Code session activity for a date range |
| `extract-git-activity.sh` | Extract commits across configured repos for a date range |
| `template-manager.sh` | Read/update/validate the task template |

## Configuration

```json
{
  "github": {
    "orgs": ["mindbodyonline"],
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
    "project": null,
    "default_work_item_type": "Product Backlog Item"
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

- `username` auto-detected from `gh` CLI if null
- `session_logs.path` auto-detected if null
- `git.repos` can be manually listed or auto-discovered from `auto_detect_from` path
- Org filtering ensures only work-related activity is tracked, excluding personal projects

## Sprint Management

- Auto-detect current active sprint/iteration from ADO
- Always present sprint for user confirmation before applying any updates
- Explicitly alert user when sprint has changed since the last run
- Sprint name used as the folder name under `data/sprints/`

## Proposal Presentation Format

Changes are presented grouped by source:

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

[Select items to approve, or approve/reject all]
```

- Moderate detail by default (title, source link, area path, sprint, one-line summary)
- Individual items expandable to full ADO task preview
- Selectable per item or per group

## Template System

- Generated once from a user-provided reference ADO work item via `/ado-tracker-init`
- Extracts: area path pattern, field structure, description format, work item type, tags, priority defaults
- Filters out: attachments, comments, the specific description body, assigned-to, created-by, history, relations/links, iteration-specific dates, and any fields whose values are unique to that one work item rather than reusable as a pattern
- Stored as `data/task-template.json`
- Presented to user for review and approval before first use
- Updatable via `/ado-tracker-init` (re-run template step) or manual edit

## Prerequisites

- Claude Code CLI
- `gh` CLI — authenticated
- ADO MCP server — connected and configured
- Notion MCP server — connected and configured
- Access to ADO project with permissions to create/update work items
