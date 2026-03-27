# ADO Tracker — Ad-hoc Scan

## Goal
Run an activity scan for a user-specified date range. Same pipeline as daily but with custom dates, multi-sprint support, and no last-run.json update.

## Input
- `from_date`: Start date (YYYY-MM-DD)
- `to_date`: End date (YYYY-MM-DD)

If not provided, ask: "What date range? (YYYY-MM-DD to YYYY-MM-DD)"

## Steps

### Step 1: Load Configuration
- Read `data/config.json` and `data/task-template.json`.
- **On failure**: Direct user to `/ado-tracker-init`.

### Step 2: Resolve Sprints for Date Range
- Resolve all overlapping sprints:
  ```bash
  bash scripts/ado-cli.sh --action resolve-sprints-for-range --params '{"from":"<from>","to":"<to>"}'
  ```
- If range spans multiple sprints, inform user: "Date range covers Sprint X (dates) and Sprint Y (dates). Items will be filed under the sprint matching their activity date."
- **On failure**: Ask user to provide sprint info manually.

### Steps 3-5: Gather Activity
Same as daily scan steps 3-5 but using the user-specified date range.

### Step 6: Save Activity Snapshot
- Save to `data/sprints/<primary-sprint>/activity/<from>-to-<to>-adhoc.json`.
- If ALL gathering failed → inform and stop.

### Step 7: Dedup & State Check
Same as daily scan step 7 — query across ALL overlapping sprints.

### Step 8: Propose Updates
Same as daily scan step 8. Items are grouped by their sprint.

### Step 9: Apply Updates
Same as daily scan step 9.

### Step 10: Summary
- Present results with counts and links.
- Note: Ad-hoc scans do NOT update `last-run.json`.
