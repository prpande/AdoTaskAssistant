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
  - Alert: "Sprint changed from <old> to <new> since last run on <date>."
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
