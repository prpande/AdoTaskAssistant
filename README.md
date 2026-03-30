# ADO Tracker

A Claude Code automation that tracks your work across GitHub, Notion, and local git repos — then creates and manages Azure DevOps work items for you.

## How It Works

```
Activity Sources              Pipeline                          Azure DevOps
─────────────────    ─────────────────────────────    ─────────────────────────
GitHub PRs        →                                  → PBIs (Product Backlog Items)
Notion pages      →  Gather → Preprocess → Propose   → Child Tasks
Git commits       →           (zero LLM)   & Apply   → State Updates
```

The scan pipeline:
1. **Gather** — Collects PRs, Notion pages, and git commits for a date range
2. **Preprocess** — Enriches activity with sprint mapping, work type scoring, and state inference (pure bash/jq — zero LLM tokens)
3. **Dedup** — Matches against existing ADO items by URL and title similarity to avoid duplicates
4. **Propose** — Groups related activity into PBIs, presents for approval
5. **Apply** — Creates/updates ADO work items

## Features

- **Daily scan** — Detects PRs, Notion edits, and git commits since last run
- **Token-efficient** — Deterministic preprocessing (dedup, sprint mapping, keyword scoring) runs in bash scripts, not the LLM
- **Smart deduplication** — URL matching, title similarity, and cross-correlation prevent duplicate PBIs. Related work across repos is grouped under existing PBIs as child tasks
- **Template-based** — Uses a reference ADO work item to generate consistent formatting (title prefixes, area/iteration paths, fields)
- **Multi-sprint aware** — Resolves all sprints overlapping the scan date range, maps items by date
- **State lifecycle** — Merged PRs → Done, open PRs/Notion → Committed. Tasks inherit mapped states automatically
- **Configurable approval** — `interactive` (show & wait), `auto-confirm` (show & proceed), or `auto-apply` (silent)
- **Pending proposals** — Unreviewed proposals are saved and resumed on next interaction
- **Ad-hoc scanning** — Scan any date range on demand
- **Manual creation** — Create PBIs, add tasks, or break down existing PBIs via slash commands

## Prerequisites

| Tool | Purpose | Install |
|------|---------|---------|
| [Claude Code CLI](https://docs.claude.ai/en/code) | Runtime environment | `npm install -g @anthropic-ai/claude-code` |
| [GitHub CLI](https://cli.github.com/) | PR discovery | `gh auth login` after install |
| [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) | ADO operations | Install, then `az extension add --name azure-devops` |
| Notion MCP | Notion page tracking | Add to Claude Code MCP config ([setup guide](https://github.com/anthropics/claude-code-mcp)) |
| ADO PAT | Work item read/write | Created during init wizard |

## Getting Started

### 1. Clone and Open

```bash
git clone <repo-url> && cd AdoTaskAssistant
claude
```

### 2. Run the Init Wizard

```
/ado-tracker-init
```

The wizard walks you through 7 steps:

#### Step 1: Prerequisites Check

Verifies that all required tools are installed and authenticated:
- **GitHub CLI** — checks `gh auth status`
- **Azure CLI** — checks `az version`
- **Azure DevOps extension** — checks `az extension show --name azure-devops`
- **Notion MCP** — tests connectivity with a search query

If anything fails, the wizard provides step-by-step fix instructions and waits for you to resolve it before continuing.

#### Step 2: Azure DevOps Authentication

Configures your ADO connection:
1. Provide your **ADO organization URL** (e.g., `https://dev.azure.com/your-org`)
2. Provide your **project name** and **team name**
3. Sets `az devops configure --defaults` for your org and project
4. Guides you through creating a **Personal Access Token (PAT)** if you don't have one
   - Required scopes: Work Items (Read & Write), Project and Team (Read), Build (Read)
5. Sets `AZURE_DEVOPS_EXT_PAT` environment variable for persistent auth

#### Step 3: Reference Task & Auth Validation

Validates your auth setup end-to-end:
1. You provide a reference ADO work item ID or URL (should be a PBI)
2. The wizard fetches it — this confirms your org/project/PAT are all working
3. Extracts your ADO email from the work item's `AssignedTo` field for automatic assignment

#### Step 4: Template Generation

Creates a reusable template from your reference work item:
- **Title prefix** — extracts patterns like `[Team][Area]` with configurable slots
- **Work type** — default type + keyword-based inference for 8 categories (New Feature, Bug Fix, Maintenance, etc.)
- **Area/iteration paths** — extracted with sprint number pattern
- **Auto-populate fields** — maps source data to ADO fields (e.g., repo name → `Custom.Repo`)
- **Description format** — Overview + Scope structure with source URLs for dedup matching

You can edit any part of the template before saving.

#### Step 5: User Configuration

Auto-detects your identity across tools and configures data sources:

**Identity detection:**
- **GitHub username** — from `gh api user`
- **Notion user ID** — from Notion user search
- **ADO email** — from reference task (Step 3)

**Data source setup:**
1. GitHub organization(s) to track
2. Repos to exclude (if any)
3. Notion scope — all pages or specific databases
4. Git source root for auto-detecting local repos
5. Daily scan time (HH:MM)

Saves everything to `data/config.json`.

#### Step 6: First Run (Optional)

Offers to run an initial scan immediately:
- Provide a date range (e.g., "last week", "2024-03-20 to 2024-03-27")
- Runs the full scan pipeline: gather → preprocess → dedup → propose → apply

#### Step 7: Schedule (Optional)

Sets up automated daily scans at your configured time using Claude Code's `/loop` command.

### 3. Daily Usage

After setup, you have two main workflows:

**Automated daily scan:**
```
/ado-tracker-daily
```
Scans from last run date to today.

**Ad-hoc scan for a specific range:**
```
/ado-tracker-scan --from 2024-03-20 --to 2024-03-27
```

Both follow the same pipeline and present proposals for your approval before making any changes in ADO.

## Slash Commands

| Command | Purpose |
|---------|---------|
| `/ado-tracker-init` | Guided setup wizard (7 steps) |
| `/ado-tracker-daily` | Run daily scan from last run to today |
| `/ado-tracker-scan --from YYYY-MM-DD --to YYYY-MM-DD` | Scan a custom date range |
| `/ado-tracker-create <description>` | Create a new PBI from a description |
| `/ado-tracker-task <PBI-id> <description>` | Add a child task under an existing PBI |
| `/ado-tracker-breakdown <PBI-id>` | Break down a PBI into child tasks |

## Architecture

```
.claude/skills/          Slash command definitions (user-facing entry points)
       │
       ▼
automations/             Multi-step orchestrated workflows
       │
       ▼
prompts/                 Single-purpose reusable tasks (LLM-powered)
       │
       ▼
scripts/                 Deterministic bash utilities (zero LLM tokens)
       │
       ▼
data/                    Runtime data — config, templates, activity, updates (gitignored)
```

### Scripts

| Script | Purpose |
|--------|---------|
| `ado-cli.sh` | ADO operations wrapper (create, update, query, sprint resolution) |
| `build-params.sh` | Safe JSON construction — handles backslash escaping in ADO paths |
| `template-manager.sh` | Template extraction, reading, and updating |
| `preprocess-activity.sh` | Enriches activity with sprint mapping, work type scoring, state inference |
| `dedup-matcher.sh` | Matches activity against existing ADO items by URL and title similarity |
| `extract-git-activity.sh` | Gathers git commits by date range across local repos |
| `parse-session-logs.sh` | Parses Claude Code session logs (best-effort) |

### Prompts

| Prompt | Used By | Purpose |
|--------|---------|---------|
| `ado-tracker-gather-activity` | Scan pipeline | Collect activity from GitHub, Notion, and git |
| `ado-tracker-propose-updates` | Scan pipeline | Group activity, write titles, handle approval |
| `ado-tracker-apply-updates` | Scan pipeline | Execute approved ADO creates/updates |
| `ado-tracker-create-pbi` | `/ado-tracker-create` | Create a PBI with template slots |
| `ado-tracker-create-task` | `/ado-tracker-task` | Create a child task under a PBI |
| `ado-tracker-breakdown-pbi` | `/ado-tracker-breakdown` | Decompose a PBI into tasks |

## Scan Pipeline Detail

### Activity Sources

| Source | What's Collected | Dedup Key |
|--------|-----------------|-----------|
| GitHub PRs | Authored and reviewed PRs via `gh search prs` | PR URL in description |
| Notion pages | Pages created/edited by user via Notion MCP workspace search | Notion page URL in description |
| Git commits | Local commits via `git log`, filtered by org remote | Covered-by-PR detection (same repo/branch) |

### Preprocessing (Zero LLM)

The preprocessing scripts run pure bash/jq — no LLM tokens consumed:

- **Sprint mapping** — Each activity item is assigned to the correct sprint by its date
- **Work type scoring** — Title keywords are matched against 8 work type categories with confidence scores
- **State inference** — Merged PRs → Done, open PRs → Committed, Notion pages → Committed
- **Group hints** — Branch names enable cross-repo grouping (e.g., same feature branch in multiple repos)

### Deduplication

Three levels of matching prevent duplicate work items:

| Match Type | How | Result |
|-----------|-----|--------|
| **URL match** | Source URL found in existing ADO item description | `tracked` — skip (optionally update state) |
| **Title similarity** | Jaccard similarity > 0.6 against existing items | `potential_match` — flagged for review |
| **Cross-correlation** | New item's title similar (> 0.35) to a PBI matched by tracked items | `related` — proposed as child task under existing PBI |

### Proposal Format

Proposals are grouped by sprint, then by action type:

```
## Sprint 2024-07 (Mar 25 – Apr 7)

### New Items
1. [Team][Backend][Feature] Add endpoint for ... — New Feature Development
   Tasks: PR #1034 (Committed), Design doc (Committed)

### New Tasks for Existing PBIs
- PBI #12345: Add PR #808 task — Add ReassignClient endpoint (Done)

### State Updates
- Task #12345 → Done (PR #1034 now merged)

### Already Tracked (skipped)
- PR #808 → PBI #12340
```

## Data

All runtime data lives in `data/` (gitignored), organized by sprint:

```
data/
├── config.json                    User settings
├── task-template.json             PBI/Task creation template
├── last-run.json                  Last daily scan metadata
├── pending-scan.json              Unreviewed proposal (auto-resumed)
└── sprints/
    └── Sprint 2024-07/
        ├── activity/              Gathered activity snapshots
        │   └── 2024-03-25-to-2024-03-29-adhoc.json
        └── updates/               Applied changes log
            └── 2024-03-30-adhoc.json
```

### Configuration Reference

`data/config.json` structure (generated by `/ado-tracker-init`):

| Section | Key Fields | Purpose |
|---------|-----------|---------|
| `ado` | organization, project, team | ADO connection |
| `user` | ado_email, github_username, notion_user_id | Identity across tools |
| `github` | organizations, excluded_repos | PR tracking scope |
| `notion` | scope, excluded_databases, filter_types | Notion page tracking |
| `git` | source_root, auto_detect, filter_by_remote_org | Local commit scanning |
| `scan` | approval_mode, auto_apply_sources | Approval behavior |
| `schedule` | daily_scan_time | Daily scan timing |

### Approval Modes

Set `scan.approval_mode` in `data/config.json`:

| Mode | Behavior |
|------|----------|
| `interactive` | Show proposal, wait for approval (default) |
| `auto-confirm` | Show proposal, proceed immediately |
| `auto-apply` | Apply without showing, summarize after |

## State Lifecycle

| Source | Created State | Auto-close? |
|--------|--------------|-------------|
| GitHub PR (open) | Committed | Yes — when PR merges |
| GitHub PR (merged) | Done | N/A |
| Notion page | Committed | Never — user decides |
| Git commits (no PR) | Committed | Never |

Task work items use mapped states: Committed → In Progress, New/Approved → To Do.
