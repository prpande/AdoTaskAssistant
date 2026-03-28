# ADO Tracker — Full Overhaul Design Spec

**Date:** 2026-03-27
**Status:** Draft
**Scope:** Scripts, config, prompts, automations, init wizard

---

## Problem Statement

During the first end-to-end run of ADO Tracker, several issues surfaced:

1. **Script bugs** — `echo` mangling JSON with backslashes (fixed), but `ado-cli.sh` still uses `eval` with string concatenation (shell injection risk)
2. **Missing assignment/state** — Created work items defaulted to "New" and unassigned; required manual follow-up
3. **Config inconsistencies** — Field names differ between config, prompts, and scripts; user identities not centralized
4. **No deduplication** — Overlapping scans would propose duplicate PBIs
5. **Sprint boundary issues** — Tool assumes "current sprint only", but activity at sprint boundaries belongs to multiple sprints
6. **Notion gathering too broad** — Got org-wide results + Slack/SharePoint noise; required manual filtering
7. **No state lifecycle** — Tool creates items but never updates their state when PRs merge or work completes
8. **Proposal algorithm undefined** — Grouping and matching logic was ad-hoc, not codified
9. **Session log parsing broken** — Script guesses at storage format; returned no data
10. **Multiple API calls per item** — Create, then update state, then update assignment, then link children — all separate

---

## Design

### Layer 1: Scripts

#### `ado-cli.sh` — Security & Feature Overhaul

**Security fix — eliminate `eval`:**

Replace all `eval "$cmd"` patterns with bash arrays:

```bash
# Before (unsafe):
local cmd="az boards work-item create --type \"$type\" --title \"$title\""
eval "$cmd"

# After (safe):
local cmd_args=(az boards work-item create --type "$type" --title "$title" --output json)
"${cmd_args[@]}"
```

Apply this to all actions: `create-work-item`, `update-work-item`, `show-work-item`, `query-work-items`, `current-sprint`, `list-sprints`, `add-child`, `close-work-item`.

**Config-aware startup:**

On script load, read `data/config.json` once to get `ado.organization`, `ado.project`, `ado.team`. Pass `--org` and `--project` to `az` commands automatically so callers don't need to.

**Enhanced `create-work-item`:**

Add optional params:
- `assigned_to` — set `System.AssignedTo` via `--fields` during creation
- `state` — set `System.State` via `--fields` during creation

This eliminates the separate `update` call after creation.

**New action: `create-with-children`:**

Params:
```json
{
  "pbi": {
    "type": "Product Backlog Item",
    "title": "...",
    "description": "...",
    "area_path": "...",
    "iteration_path": "...",
    "assigned_to": "...",
    "state": "Committed",
    "fields": {}
  },
  "tasks": [
    {
      "title": "...",
      "description": "...",
      "assigned_to": "...",
      "state": "Done"
    }
  ]
}
```

Flow:
1. Create PBI with assignment + state
2. For each task: create with assignment + state, then link as child to PBI
3. Return all IDs: `{pbi_id: N, task_ids: [...]}`

On any failure mid-way: report what was created and what failed (don't silently skip).

**New action: `create-task`:**

Standalone task creation with built-in parent linking:
```json
{
  "title": "...",
  "description": "...",
  "parent_id": 12345,
  "assigned_to": "...",
  "state": "In Progress"
}
```

Creates the task, links to parent, returns the task ID.

**New action: `resolve-sprints-for-range`:**

Params: `{"from": "2026-03-20", "to": "2026-03-27"}`

Flow:
1. Fetch all team iterations via `az boards iteration team list --team <team>`
2. Filter to sprints whose `[startDate, finishDate]` overlap with `[from, to]`
3. Return array of matching sprints with their date ranges

Replaces `current-sprint` as the primary sprint lookup for scans.

**New action: `query-my-sprint-items`:**

Params: `{"sprints": ["MBScrum\\Sprint 2026-06", "MBScrum\\Sprint 2026-07"], "assigned_to": "user@email.com"}`

Runs WIQL:
```sql
SELECT [System.Id], [System.Title], [System.Description], [System.State], [System.WorkItemType]
FROM WorkItems
WHERE [System.AssignedTo] = '<assigned_to>'
AND ([System.IterationPath] = '<sprint1>' OR [System.IterationPath] = '<sprint2>')
AND [System.State] <> 'Removed'
ORDER BY [System.CreatedDate] DESC
```

Returns work items with their child tasks for deduplication.

#### `extract-git-activity.sh`

**Wire `filter_by_remote_org`:**

After auto-detecting repos under `source_root`, for each repo:
```bash
remote_url=$(git -C "$repo" remote get-url origin 2>/dev/null)
if [[ "$remote_url" != *"$filter_org"* ]]; then
    skip
fi
```

**Fix date handling:**

Use ISO format strings directly with git (no platform-specific `date` command):
```bash
git log --after="$FROM_DATE" --before="$TO_DATE" --format=...
```

**Handle empty repos:**

If a repo has zero commits in the range, skip it silently instead of adding an empty entry.

#### `template-manager.sh`

**Iteration pattern:**

Replace generic `{number}` regex with explicit `{year}` and `{sprint_number}` placeholders:
```bash
# Extract: "Sprint 2026-07" → "Sprint {year}-{sprint_number}"
gsub("[0-9]{4}"; "{year}") | gsub("-[0-9]+"; "-{sprint_number}")
```

**Validation update:**

Add to required fields check: `title_prefix_pbi`, `description_format`, `description_required`.

#### `parse-session-logs.sh`

**Best-effort only:**

If session log directory not found or empty, return gracefully:
```json
{"sessions": [], "note": "No session logs found at checked paths"}
```

No errors, no blocking. Git activity is the primary signal from this gathering step.

---

### Layer 2: Config & Schema

#### `config.json` — New structure

```json
{
  "ado": {
    "organization": "https://dev.azure.com/mindbody",
    "project": "MBScrum",
    "team": "squad-biz-app"
  },
  "user": {
    "ado_email": "pratyush.pande@playlist.com",
    "github_username": "prpande",
    "notion_user_id": "2f8d872b-594c-81a7-a5c5-0002f6a8eb70"
  },
  "github": {
    "organizations": ["mindbody"],
    "excluded_repos": []
  },
  "notion": {
    "scope": "all",
    "excluded_databases": [],
    "filter_types": ["page"]
  },
  "git": {
    "source_root": "C:/src",
    "auto_detect": true,
    "filter_by_remote_org": "mindbody",
    "explicit_repos": []
  },
  "schedule": {
    "daily_scan_time": "10:00"
  }
}
```

Changes:
- **New `user` section** — centralized identity for ADO, GitHub, Notion. Detected during init, reused on every scan.
- **`notion.filter_types`** — default `["page"]` to exclude Slack/SharePoint noise from Notion AI search.
- Removed unused `timezone` field.

#### `last-run.json` — New file with defined schema

```json
{
  "last_run_date": "2026-03-27",
  "last_run_type": "daily",
  "sprint": "Sprint 2026-07",
  "items_created": 3,
  "items_updated": 0,
  "scanned_date_range": {
    "from": "2026-03-26",
    "to": "2026-03-27"
  }
}
```

Written after each successful daily scan. Adhoc scans do NOT update it.

#### `task-template.json` — No structural changes

Existing fields (`title_prefix_pbi`, `title_prefix_task`, `description_format`, `description_required`) are already present. The change is that prompts will now actually use them (see Layer 3).

---

### Layer 3: Prompts

#### `ado-tracker-gather-github.prompt.md`

Changes:
- Read `user.github_username` from config instead of calling `gh api user` each time
- Handle pagination: if results hit 100 limit, fetch next page
- Concrete dedup: merge by PR URL, combine roles into `"author+reviewer"` if both match

#### `ado-tracker-gather-notion.prompt.md`

Changes:
- Read `user.notion_user_id` from config
- Search with `created_by_user_ids` filter using the stored ID
- Filter results to types in `notion.filter_types` (default: `["page"]`) — drop Slack, SharePoint, etc.
- Group pages by parent database/workspace for better context in proposals

#### `ado-tracker-gather-sessions.prompt.md`

Changes:
- Session parsing is best-effort — if no logs found, return empty array gracefully
- Git activity remains the primary output
- Remove references to undefined config fields (`session_logs`)

#### `ado-tracker-propose-updates.prompt.md` — Major rewrite

**Phase 1: Resolve sprints**

Call `resolve-sprints-for-range` to get all sprints overlapping with the scan date range. Map each activity item to its sprint based on the activity's date.

**Phase 2: Deduplication**

Call `query-my-sprint-items` across all overlapping sprints. For each existing work item:
- Extract source URLs from description (PR links, Notion links)
- Build a lookup: `{source_url → work_item_id}`

For each gathered activity item:
- Check if its source URL is already in the lookup → **skip** or **update**
- Check title keyword overlap with existing items → **potential match** (flag for user)

**Phase 3: Smart grouping**

Group unmatched activity using signals:
- **Branch name prefix** — `pp/gstBooking-2503` across repos = same feature
- **PR cross-references** — PR body mentioning other repos/PRs
- **Notion page hierarchy** — pages sharing a parent database or title pattern
- **Time proximity** — commits in same repo within same day cluster together

**Phase 4: State determination**

For each proposed item, determine state by source type:

| Source | Created State | Auto-update to Done? |
|--------|--------------|---------------------|
| GitHub PR (open) | In Progress | Yes — when PR merges |
| GitHub PR (merged at scan time) | Done | N/A, already Done |
| Notion page | In Progress | Never — user decides when doc is complete |
| Git commits (no associated PR) | In Progress | Never — no clear completion signal |

**Phase 5: State lifecycle updates**

For existing tracked items, check if state needs updating:
- PR was open, now merged → propose task **→ Done**
- All child tasks of a PBI are Done → propose PBI **→ Done**
- Notion-sourced tasks: **never auto-close** — only user can mark Done

**Phase 6: Present proposal**

Group by sprint, then by action type:

```
Sprint 2026-06 (Mar 11 – Mar 24):
  State Updates:
    - PBI #12345 → Done (all child tasks completed)

Sprint 2026-07 (Mar 25 – Apr 7):
  New Items:
    1. [BizApp][Backend][Feature] Title — source, state
  State Updates:
    - Task #12346 → Done (PR #1034 merged)
  Already Tracked:
    - PR #808 covered by PBI #12345 (skipped)
```

User can approve/reject individual items or groups.

#### `ado-tracker-apply-updates.prompt.md`

Input format — array of approved actions:
```json
[
  {
    "action": "create",
    "sprint": "MBScrum\\Sprint 2026-07",
    "pbi": { "title": "...", "description": "...", "state": "Committed" },
    "tasks": [ { "title": "...", "state": "Done" } ]
  },
  {
    "action": "update-state",
    "work_item_id": 12345,
    "new_state": "Done"
  }
]
```

For `create` actions: use `create-with-children` from `ado-cli.sh`.
For `update-state` actions: use `update-work-item`.
For `add-tasks` actions: use `create-task` with parent linking.

Always embed source URLs in descriptions for future dedup.
Always set `assigned_to` from `user.ado_email`.

#### `ado-tracker-create-pbi.prompt.md` / `create-task.prompt.md`

- Apply `title_prefix_pbi` from template (prompt user for `{featureArea}`)
- Use `description_format` from template with placeholder substitution
- Always assign to `user.ado_email`
- Always prompt for state
- Tasks linked to Notion pages default to **In Progress**
- Tasks linked to merged PRs default to **Done**

---

### Layer 4: Automations & Init

#### `ado-tracker-daily.automation.md`

Updated flow:

1. Load config + template (fail → direct to init)
2. **Resolve sprints for date range** (last_run_date → today) — replaces single "current sprint" detection
3. Confirm with user: "Scan covers Sprint X (dates) and Sprint Y (dates). Proceed?"
4. Gather GitHub activity
5. Gather Notion activity (using stored user.notion_user_id, filtering to pages only)
6. Gather git activity (best-effort session logs)
7. Save activity snapshot
8. **Dedup against existing sprint items** — query across all overlapping sprints
9. **Check state lifecycle** — identify items whose state should change (PRs merged, etc.)
10. Propose updates (grouped by sprint, then by action type)
11. Apply approved updates
12. Write `last-run.json`
13. Summary

#### `ado-tracker-adhoc.automation.md`

Same as daily but:
- Date range provided by user (not from last-run.json)
- Does NOT update last-run.json
- Sprint boundary handling: if range spans sprints, show both and map items correctly

#### `ado-tracker-init` SKILL

Updated wizard:

**Step 2 (ADO Auth)** — no change

**Step 3 (Reference Task)** — validate that the fetched work item is a PBI (`System.WorkItemType == "Product Backlog Item"`)

**Step 5 (User Configuration)** — auto-detect and save user identities:
- `user.github_username` via `gh api user --jq .login`
- `user.notion_user_id` via Notion MCP `notion-get-users` search by email
- `user.ado_email` extracted from the reference work item's `System.AssignedTo` field
- Save all to `user` section in config.json

These are detected once during init and reused on every scan — no re-fetching.

---

## Files Changed

| File | Change Type | Summary |
|------|-------------|---------|
| `scripts/ado-cli.sh` | Major rewrite | Array-based commands, new actions (create-with-children, create-task, resolve-sprints-for-range, query-my-sprint-items), config-aware, assignment/state on create |
| `scripts/extract-git-activity.sh` | Enhancement | Wire filter_by_remote_org, fix dates, skip empty repos |
| `scripts/template-manager.sh` | Enhancement | Fix iteration pattern extraction, validate new fields |
| `scripts/parse-session-logs.sh` | Simplification | Best-effort only, graceful empty return |
| `data/config.json` | Schema change | Add user section, notion.filter_types, remove unused fields |
| `data/last-run.json` | New file | Created after first daily scan |
| `prompts/ado-tracker-gather-github.prompt.md` | Update | Use config username, pagination, dedup |
| `prompts/ado-tracker-gather-notion.prompt.md` | Rewrite | Use stored notion_user_id, filter to pages only |
| `prompts/ado-tracker-gather-sessions.prompt.md` | Update | Best-effort, git is primary |
| `prompts/ado-tracker-propose-updates.prompt.md` | Major rewrite | Concrete grouping algorithm, dedup, sprint-aware, state lifecycle |
| `prompts/ado-tracker-apply-updates.prompt.md` | Rewrite | Defined input format, use create-with-children, embed source URLs |
| `prompts/ado-tracker-create-pbi.prompt.md` | Update | Use template prefixes, always assign/state |
| `prompts/ado-tracker-create-task.prompt.md` | Update | Use template prefixes, always assign/state |
| `prompts/ado-tracker-breakdown-pbi.prompt.md` | Update | Dedup child tasks before proposing |
| `automations/ado-tracker-daily.automation.md` | Rewrite | Multi-sprint, dedup step, state lifecycle, better error handling |
| `automations/ado-tracker-adhoc.automation.md` | Update | Multi-sprint, dedup step, sprint boundary handling |
| `.claude/skills/ado-tracker-init/SKILL.md` | Update | Auto-detect user identities, validate PBI type |
| `CLAUDE.md` | Update | Document new actions, config schema, state rules |
