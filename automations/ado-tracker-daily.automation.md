# ADO Tracker — Daily Scan

## Goal
Full daily workflow: resolve sprints, gather all activity since last run, deduplicate against existing items, check state lifecycle, propose updates, apply approved changes, persist results.

## Steps

### Step 1: Load Configuration
- Read `data/config.json`. If missing → "Run `/ado-tracker-init` to set up."
- Read `data/task-template.json`. If missing → same.
- Read `data/last-run.json`. If missing → first run, set `since_date` to yesterday.
- **On failure**: Stop and direct user to `/ado-tracker-init`.

### Step 2: Resolve Sprints
- Determine date range: `from` = last_run_date (or yesterday), `to` = today.
- Resolve all overlapping sprints:
  ```bash
  bash scripts/ado-cli.sh --action resolve-sprints-for-range --params '{"from":"<from>","to":"<to>"}'
  ```
- Present to user: "Scan covers: Sprint X (dates), Sprint Y (dates). Proceed?"
- If last_run sprint differs from current sprint, alert: "Sprint changed from <old> to <new>."
- Create sprint data folders if they don't exist.
- **On failure**: Ask user to provide sprint info manually.

### Step 3: Gather GitHub Activity
- Execute `ado-tracker-gather-github.prompt.md` with the date range.
- Uses `user.github_username` from config (no API call needed).
- **On failure**: Note "GitHub scan skipped — <error>". Continue.

### Step 4: Gather Notion Activity
- Execute `ado-tracker-gather-notion.prompt.md` with the date range.
- Uses `user.notion_user_id` from config (no API call needed).
- Filters to `notion.filter_types` (pages only by default).
- **On failure**: Note "Notion scan skipped — <error>". Continue.

### Step 5: Gather Git Activity
- Execute `ado-tracker-gather-sessions.prompt.md` with the date range.
- Uses `git.source_root` and `git.filter_by_remote_org` from config.
- Session parsing is best-effort.
- **On failure**: Note "Git scan skipped — <error>". Continue.

### Step 6: Save Activity Snapshot
- Combine all gathered activity into a single JSON file.
- Save to `data/sprints/<sprint>/activity/<date>-daily.json`.
- If ALL gathering steps failed → "No activity found. Check tool connections." Stop.

### Step 7: Dedup & State Check
- Query existing work items across all overlapping sprints:
  ```bash
  bash scripts/ado-cli.sh --action query-my-sprint-items --params '{"sprints":[<sprint-paths>]}'
  ```
- Match gathered activity against existing items by source URL in descriptions.
- Check if tracked items need state updates (PR merged → Done, all children Done → parent Done).
- Notion-sourced tasks are NEVER auto-closed.

### Step 8: Propose Updates
- Execute `ado-tracker-propose-updates.prompt.md` with:
  - Combined activity (with dedup flags)
  - Sprint mappings
  - State lifecycle proposals
- Present grouped by sprint, then by action type.
- Wait for user approval.
- If user approves nothing → skip to Step 10.

### Step 9: Apply Updates
- Execute `ado-tracker-apply-updates.prompt.md` with approved actions.
- Use `create-with-children` for new PBIs.
- Use `update-work-item` for state changes.
- Save results to `data/sprints/<sprint>/updates/<date>-daily.json`.

### Step 10: Update Last Run
- Write `data/last-run.json`:
  ```json
  {
    "last_run_date": "<today>",
    "last_run_type": "daily",
    "sprint": "<current-sprint-name>",
    "items_created": <count>,
    "items_updated": <count>,
    "scanned_date_range": {"from": "<from>", "to": "<to>"}
  }
  ```

### Step 11: Summary
```
## Daily Scan Complete
Date range: <from> to <to>
Sprints: <sprint names>
Activity found: <count> items
Proposed: <count> changes
Applied: <count> creates, <count> state updates
Next run: <scheduled time>
```
