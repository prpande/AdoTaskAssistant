# ADO Tracker — Ad-hoc Scan

## Goal
Run an activity scan for a user-specified date range and propose ADO updates. Same as daily scan but with custom dates and no schedule dependency.

## Input
- `from_date`: Start date (YYYY-MM-DD)
- `to_date`: End date (YYYY-MM-DD)

If not provided, ask the user: "What date range would you like to scan? (format: YYYY-MM-DD to YYYY-MM-DD)"

## Steps

### Step 1: Load Configuration
- Read `data/config.json`. If missing, direct user to `/ado-tracker-init`.
- Read `data/task-template.json`. If missing, direct user to `/ado-tracker-init`.
- **On failure**: Stop and direct user to `/ado-tracker-init`.

### Step 2: Detect and Confirm Sprint
- Run `bash scripts/ado-cli.sh --action current-sprint`
- Present for confirmation: "Current sprint: <sprint-name>. The scan results will be filed under this sprint. Proceed?"
- **On failure**: Ask user to provide sprint name manually.

### Step 3: Gather GitHub Activity
- Execute `ado-tracker-gather-github.prompt.md` with the user-specified date range.
- **On failure**: Note "GitHub scan skipped — <error>". Continue.

### Step 4: Gather Notion Activity
- Execute `ado-tracker-gather-notion.prompt.md` with the user-specified date range.
- **On failure**: Note "Notion scan skipped — <error>". Continue.

### Step 5: Gather Claude Session & Git Activity
- Execute `ado-tracker-gather-sessions.prompt.md` with the user-specified date range.
- **On failure**: Note "Session/git scan skipped — <error>". Continue.

### Step 6: Save Activity Snapshot
- Save to `data/sprints/<sprint>/activity/<from>-to-<to>-adhoc.json`.
- If all steps failed, inform user and stop.

### Step 7: Propose Updates
- Execute `ado-tracker-propose-updates.prompt.md` with combined activity.
- Wait for user approval.

### Step 8: Apply Updates
- Execute `ado-tracker-apply-updates.prompt.md` with approved actions.
- Save to `data/sprints/<sprint>/updates/<from>-to-<to>-adhoc.json`.

### Step 9: Summary
- Present results with counts and links to created/updated items.
- Note: Ad-hoc scans do NOT update `last-run.json` (they don't affect the daily schedule).
