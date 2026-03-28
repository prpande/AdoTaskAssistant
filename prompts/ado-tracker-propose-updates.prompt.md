# Propose ADO Updates

## Goal
Review pre-computed activity data, apply judgment for grouping and titles, and present a proposal for user approval.

## Context
- Template: `data/task-template.json` (read for title prefix, description format)
- Config: `data/config.json` (read for `user.ado_email`, `scan.approval_mode`)

## Input
- `preprocessed_file`: Path to JSON from preprocess + dedup pipeline. Each item has:
  - `source`: Original activity (type, url, title, repo, state, branch, dates)
  - `sprint` / `sprint_path`: Assigned sprint
  - `inferred_work_type` / `work_type_confidence` / `work_type_signals`: Script's keyword scoring
  - `inferred_state`: Deterministic state (Done/Committed)
  - `group_hint`: Branch prefix for cross-repo grouping
  - `dedup.status`: `"new"` | `"tracked"` | `"potential_match"`
  - `dedup.work_item_id` / `dedup.existing_title` / `dedup.similarity`: Match details
  - `dedup.state_update`: Proposed state change for tracked items (or null)
- `sprints`: Array of sprint objects with name, path, start, end

## Instructions

### Review preprocessed inferences

Use the script's inferences as starting points. Override when your judgment says otherwise:
- **Dedup**: Items with `"status": "tracked"` (exact URL match) are definitive — skip them. Items with `"status": "potential_match"` need your review — check the source URLs, titles, and broader context to decide if they're truly duplicates or separate work.
- **Work type**: If `work_type_confidence` < 0.5, flag to the user for confirmation. If the broader context contradicts the keyword score (e.g., "fix" keyword but actually a new feature), override.
- **State**: The script's state assignment is deterministic and correct. Only override if you have specific context (e.g., a mixed-source group should use the most active state).

### Group new items into PBIs

For items with `"dedup.status": "new"`, group into proposed PBIs:

1. **Branch prefix** — items sharing a `group_hint` across repos likely belong together
2. **PR cross-references** — PR body or commits mentioning other repos/PRs
3. **Notion page hierarchy** — pages sharing a parent or title pattern
4. **Time proximity** — commits in the same repo on the same day
5. **Single-item groups** — standalone items become their own PBI

Each group becomes one proposed PBI with child tasks.

### Write titles and descriptions

**Title**: Read `title_prefix.pattern` and `title_prefix.slots` from template.
- The `static` portion is always included
- For each slot, infer a value from context (repo name, PR title, activity type) or leave as `{slot_N}` for user to fill
- Append a concise descriptive title summarizing the work

**Description**: Use `description_format` from template:
- `{overview}`: Summarize from activity source — what was done and why
- `{scope}`: Bullet list of specific changes, with source URLs for future dedup matching

**Auto-populate fields**: Read `auto_populate_from_source` from template. Map activity source to ADO field values (e.g., `Custom.Repo` → repo name).

### Determine state for groups

If a group has mixed sources, use the most active state:
- All merged PRs → Done
- Any open PR or Notion page → Committed
- Committed is the default

### Present proposal

Group by sprint, then by action type:

```
## Sprint 2026-07 (Mar 25 – Apr 7)

### New Items
1. [BizApp][Backend] Fix booking retry — Reliability & Stabilization
   Tasks: PR #1234 (Done), commits in Scheduling (Committed)

### State Updates
- Task #12345 → Done (PR #1034 now merged)

### Already Tracked (skipped)
- PR #808 → PBI #12340
```

Always assign all items to `user.ado_email` from config.

### Handle approval

Check `scan.approval_mode` from config (default: `"interactive"`):
- `interactive`: "Enter item numbers to approve (e.g., `1,3`), `all`, or `none`. Use `expand <N>` for details, `edit <N>` to modify."
- `auto-confirm`: Display the proposal, then immediately proceed to apply.
- `auto-apply`: Skip presentation, proceed directly to apply.

Return approved items as structured JSON for the apply step.

## Output
JSON array of approved actions:
```json
[
  {
    "action": "create",
    "sprint_path": "MBScrum\\Sprint 2026-07",
    "pbi": {"title": "...", "description": "...", "state": "Committed", "assigned_to": "...", "work_type": "...", "fields": {}},
    "tasks": [{"title": "...", "state": "Done", "description": "..."}]
  },
  {
    "action": "update-state",
    "work_item_id": 12345,
    "new_state": "Done"
  }
]
```
