# ADO Tracker — Scan

## Goal
Unified scan workflow: resolve sprints, gather activity, preprocess with scripts, propose updates, apply approved changes.

## Parameters
- `mode`: `"daily"` | `"adhoc"`
- `from_date`: YYYY-MM-DD (adhoc only — daily computes from last-run)
- `to_date`: YYYY-MM-DD (adhoc only — daily defaults to today)

## Steps

### Step 1: Load & Resolve

- Read `data/config.json`. If missing → "Run `/ado-tracker-init` to set up."
- Read `data/task-template.json`. If missing → same.
- Read `scan.approval_mode` from config (default: `"interactive"`).

**Check for pending proposal:**
- If `data/pending-scan.json` exists, offer resume:
  > "You have a pending proposal from <date> (<N> new items, <N> state updates). Review now, or discard?"
  - **Review** → load proposal file, skip to Step 4 (Propose) with loaded data.
  - **Discard** → delete `data/pending-scan.json` and the referenced proposal file. Continue.

**Compute date range:**
- If `mode == "daily"`:
  - Read `data/last-run.json`. If missing → first run, set `from_date` to yesterday.
  - `from_date` = `last_run_date`, `to_date` = today.
  - If last_run sprint differs from current sprint, note: "Sprint changed from <old> to <new>."
- If `mode == "adhoc"`:
  - Use provided `from_date` and `to_date`.

**Resolve sprints:**
```bash
bash scripts/ado-cli.sh --action resolve-sprints-for-range --params '{"from":"<from>","to":"<to>"}'
```
- Present: "Scanning <from> to <to> across <sprint names>."
- Create sprint data folders if needed (`data/sprints/<Sprint-Name>/activity/` and `data/sprints/<Sprint-Name>/updates/`).
- **On failure**: Ask user for sprint info manually.

### Step 2: Gather Activity

Execute `prompts/ado-tracker-gather-activity.prompt.md` with the date range.

The gather prompt outputs a **flat JSON array** (not a nested object). All item types are mixed in one array, each with a `type` field. Save this array directly — do not wrap it in an object.

Save combined activity to:
- Daily: `data/sprints/<primary-sprint>/activity/<date>-daily.json`
- Adhoc: `data/sprints/<primary-sprint>/activity/<from>-to-<to>-adhoc.json`

If ALL sources fail → "No activity found. Check tool connections." Stop.

### Step 3: Preprocess (Script Only)

Run the preprocessing pipeline — zero LLM tokens:

```bash
# Step 3a: Build sprint data safely (backslash-safe via jq --arg)
# For each sprint, use --arg for path strings, then combine with jq
jq -n \
  --arg s1_name "<sprint-1-name>" \
  --arg s1_path '<sprint-1-iteration-path>' \
  --arg s1_start "<YYYY-MM-DD>" \
  --arg s1_end "<YYYY-MM-DD>" \
  --arg s2_name "<sprint-2-name>" \
  --arg s2_path '<sprint-2-iteration-path>' \
  --arg s2_start "<YYYY-MM-DD>" \
  --arg s2_end "<YYYY-MM-DD>" \
  '[{name:$s1_name, path:$s1_path, start:$s1_start, end:$s1_end},
    {name:$s2_name, path:$s2_path, start:$s2_start, end:$s2_end}]' \
  > /tmp/ado-sprints.json

# Read proposal_grouping.exclude_title_patterns from config (default: []).
# Patterns applied here save tokens and keep routine work out of the proposal.
jq '.proposal_grouping.exclude_title_patterns // []' data/config.json > /tmp/ado-exclude-patterns.json

# Enrich activity with sprint mapping, work type scoring, state, group hints.
# exclude_title_patterns is applied first — matching items are dropped before
# anything else runs. The output includes .excluded_count so the propose step
# can report what was filtered.
bash scripts/build-params.sh --output /tmp/ado-preprocess-params.json \
  --arg activity_file "<path-to-activity-snapshot>" \
  --slurp-file sprints /tmp/ado-sprints.json \
  --slurp-file exclude_title_patterns /tmp/ado-exclude-patterns.json
bash scripts/preprocess-activity.sh --params-file /tmp/ado-preprocess-params.json > /tmp/ado-preprocessed.json

# Step 3b: Build sprint paths array for dedup (also backslash-safe)
jq '[.[].path]' /tmp/ado-sprints.json > /tmp/ado-sprint-paths.json

bash scripts/build-params.sh --output /tmp/ado-dedup-params.json \
  --arg activity_file "/tmp/ado-preprocessed.json" \
  --slurp-file sprints /tmp/ado-sprint-paths.json
bash scripts/dedup-matcher.sh --params-file /tmp/ado-dedup-params.json > /tmp/ado-matched.json
```

**Important:** Never use `--argjson` with inline JSON containing ADO paths (backslashes). Always build path-containing JSON to a file first using `jq --arg`, then use `--slurp-file` to embed it.

Verify both scripts succeeded (check `"success": true` in output). If either fails, show the error and ask whether to continue without preprocessing (fall back to LLM-based analysis) or abort.

### Step 4: Propose Updates

Execute `prompts/ado-tracker-propose-updates.prompt.md` with:
- `preprocessed_file`: path to matched JSON from Step 3
- `sprints`: sprint objects from Step 1
- `excluded_count`: number of items dropped by `exclude_title_patterns` (from preprocess output) — mention this in the proposal summary if non-zero

The prompt handles grouping, title writing, and user approval based on `approval_mode`.

If `approval_mode` is `"interactive"` and user does not respond (scheduled scan):
- Save proposal to `data/sprints/<sprint>/pending-proposal-<date>.json`
- Save metadata to `data/pending-scan.json`:
  ```json
  {
    "date": "<today>",
    "mode": "<mode>",
    "sprint": "<primary-sprint-name>",
    "proposal_file": "<path-to-proposal>",
    "item_count": <new-items>,
    "state_updates": <update-count>
  }
  ```
- Skip to Step 7 with note: "Proposal saved for later review."

If user approves nothing → skip to Step 6.

### Step 5: Apply Updates

Execute `prompts/ado-tracker-apply-updates.prompt.md` with approved actions.

Save results to `data/sprints/<sprint>/updates/<date>-<mode>.json`.

### Step 6: Track

If `mode == "daily"`:
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

### Step 7: Summary

```
## Scan Complete
Date range: <from> to <to>
Sprints: <sprint names>
Activity found: <count> items
Proposed: <count> changes
Applied: <count> creates, <count> state updates
```
