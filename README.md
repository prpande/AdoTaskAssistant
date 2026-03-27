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
