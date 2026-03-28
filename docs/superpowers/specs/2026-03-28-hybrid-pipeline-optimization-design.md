# Hybrid Pipeline Optimization — Design Spec

## Problem

The current ADO Tracker daily scan pipeline consumes ~50K tokens per run. Approximately 60% of that is spent on deterministic operations (sprint date mapping, URL-based dedup matching, keyword scoring, state lifecycle tables) that don't require LLM judgment. The pipeline also has structural redundancy: two near-identical automations (daily/adhoc), three separate gather prompts that each read config independently, and verbose bash examples in prompts that duplicate CLAUDE.md documentation.

## Goals

1. **~50% token reduction per scan** (~50K → ~20-24K) by moving deterministic work to scripts
2. **Improved UX** — fewer interactions, configurable approval mode, pending proposal resume
3. **Reduced maintenance** — single unified automation, consolidated prompts
4. **Preserved LLM judgment** — grouping, title generation, dedup overrides, user interaction stay in the LLM

## Design Principles

- **Boundary rule:** If the operation has a deterministic correct answer (date comparison, URL matching, keyword counting), it goes in a script. If it requires judgment or natural language generation, it stays in the LLM.
- **Scripts suggest, LLM decides:** Preprocessing outputs scored recommendations (work type with confidence, dedup with similarity score, group hints). The LLM reviews these and overrides when context warrants it.
- **Full context forwarding:** Preprocessed data always carries full source details (URLs, titles, branches, existing item metadata) so the LLM can make informed overrides.
- **Safe defaults, gradual autonomy:** Approval mode starts as `interactive`, users upgrade when ready.

---

## Architecture

### New Pipeline Flow

```
SKILL LAYER (unchanged entry points)
  /ado-tracker-daily, /ado-tracker-scan, etc.
       │
UNIFIED AUTOMATION: ado-tracker-scan.automation.md
       │
  1. Load & Resolve ─────────────── script calls only
  2. Gather Activity ─────────────── 1 consolidated prompt (was 3)
  3. Preprocess ──────────────────── scripts only (zero LLM tokens)
     ├─ preprocess-activity.sh
     └─ dedup-matcher.sh
  4. Propose ─────────────────────── lean LLM prompt (pre-computed input)
  5. Apply ───────────────────────── slimmed LLM prompt
  6. Track ───────────────────────── script calls only
  7. Summary ─────────────────────── inline (no separate prompt)
```

### Token Impact

| Component | Current (approx) | New (approx) | Savings |
|-----------|------------------|--------------|---------|
| 3 gather prompts + 3 config reads | ~6K | ~3K | 50% |
| Propose prompt + raw data in context | ~25-35K | ~10-15K | 55-60% |
| Apply prompt | ~5K | ~3K | 40% |
| Automation orchestration | ~4K (2 files) | ~2.5K (1 file) | 35% |
| **Total per scan** | **~40-50K** | **~18-24K** | **~50%** |

---

## New Scripts

### `scripts/preprocess-activity.sh`

Takes raw gathered activity + sprint data, outputs enriched activity with inferences.

**Input** (via `--params-file`):
```json
{
  "activity_file": "path/to/gathered-activity.json",
  "sprints": [
    {"name": "Sprint 2026-07", "path": "MBScrum\\Sprint 2026-07", "start": "2026-03-25", "end": "2026-04-07"}
  ]
}
```

**Operations (all jq/bash):**
1. **Sprint mapping** — assigns each activity item to a sprint by comparing its date against sprint start/end ranges
2. **Work type scoring** — reads `data/task-template.json`, lowercases PR titles + commit messages, counts keyword matches against `work_type.inference_keywords`, outputs top-scored type + confidence (0.0-1.0) + matched keywords
3. **State assignment** — applies deterministic state table:
   - GitHub PR merged → Done
   - GitHub PR open → Committed
   - Notion page → Committed
   - Git commits (no PR) → Committed
4. **Branch grouping hints** — extracts branch prefixes from git activity, flags items sharing a prefix across repos

**Output:**
```json
{
  "items": [
    {
      "source": {
        "type": "github_pr",
        "url": "https://github.com/org/repo/pull/1234",
        "title": "Fix retry logic in booking service",
        "repo": "org/repo-name",
        "state": "merged",
        "branch": "pp/fix-booking-retry",
        "created_at": "2026-03-27"
      },
      "sprint": "Sprint 2026-07",
      "sprint_path": "MBScrum\\Sprint 2026-07",
      "inferred_work_type": "Reliability & Stabilization",
      "work_type_confidence": 0.8,
      "work_type_signals": ["fix", "retry"],
      "inferred_state": "Done",
      "group_hint": "pp/fix-booking-retry",
      "dedup": null
    }
  ]
}
```

### `scripts/dedup-matcher.sh`

Queries existing ADO items and matches against preprocessed activity. Biggest single token saver.

**Input** (via `--params-file`):
```json
{
  "activity_file": "path/to/preprocessed-activity.json",
  "sprints": ["MBScrum\\Sprint 2026-07"]
}
```

**Operations:**
1. Calls `ado-cli.sh --action query-my-sprint-items` to get existing items
2. Extracts URLs from each existing item's description (regex for GitHub PR URLs, Notion page URLs)
3. Builds lookup: `{url → {work_item_id, title, state}}`
4. For each activity item:
   - **Exact URL match** → `"dedup": {"status": "tracked", "work_item_id": 12345, "current_state": "Committed"}`
   - **Title keyword overlap** (jaccard similarity > 0.6) → `"dedup": {"status": "potential_match", "work_item_id": 12345, "existing_title": "...", "similarity": 0.7}`
   - **No match** → `"dedup": {"status": "new"}`
5. For tracked items, checks state lifecycle:
   - Was Committed but source PR now merged → `"state_update": "Done"`
   - All children of a PBI are Done → `"parent_state_update": "Done"`
   - Notion-sourced → `"state_update": null` (never auto-close)

**Output:** Same structure as input with `dedup` field populated on every item.

### Existing Scripts — No Changes

`ado-cli.sh`, `build-params.sh`, `extract-git-activity.sh`, `template-manager.sh`, `parse-session-logs.sh` remain as-is.

---

## Unified Automation

### `automations/ado-tracker-scan.automation.md`

Replaces both `ado-tracker-daily.automation.md` and `ado-tracker-adhoc.automation.md`.

**Parameters:**
- `mode`: `"daily"` | `"adhoc"`
- `from_date`: YYYY-MM-DD (optional — daily computes from last-run)
- `to_date`: YYYY-MM-DD (optional — daily defaults to today)
- `approval_mode`: `"interactive"` | `"auto-confirm"` | `"auto-apply"` (from config)

**Steps:**

#### Step 1: Load & Resolve
- Read `data/config.json`, `data/task-template.json`
- If `mode == "daily"`: read `data/last-run.json`, compute date range (last_run_date → today)
- If `mode == "adhoc"`: use provided from_date/to_date
- Check for pending proposal (`data/pending-scan.json`) — if exists, offer resume
- Resolve sprints: `ado-cli.sh --action resolve-sprints-for-range`
- Create sprint data folders if needed
- On failure: direct user to `/ado-tracker-init`

#### Step 2: Gather Activity
- Execute `gather-activity.prompt.md` with date range and config
- Single prompt reads config once, runs GitHub → Notion → Git sequentially
- Save combined activity to `data/sprints/<sprint>/activity/<date>-<mode>.json`
- If ALL sources fail → inform user and stop

#### Step 3: Preprocess (Script Only — Zero LLM Tokens)
```bash
bash scripts/preprocess-activity.sh --params-file <params>
bash scripts/dedup-matcher.sh --params-file <params>
```
- Output: enriched activity JSON with sprint mapping, work type scores, state assignments, dedup results, group hints

#### Step 4: Propose
- Execute lean `propose-updates.prompt.md` with pre-computed data
- LLM reviews inferences, does final grouping, writes titles/descriptions
- Presents proposal grouped by sprint → action type
- Behavior depends on `approval_mode`:
  - `interactive`: wait for user approval
  - `auto-confirm`: show proposal, then proceed to apply immediately (user can review in scrollback)
  - `auto-apply`: skip presentation, proceed to apply
- If no user response (scheduled scan): save to `data/pending-scan.json`, skip apply

#### Step 5: Apply
- Execute `apply-updates.prompt.md` with approved actions
- Save results to `data/sprints/<sprint>/updates/<date>-<mode>.json`

#### Step 6: Track
- If `mode == "daily"`: update `data/last-run.json`
- Both modes: write results file

#### Step 7: Summary
- Present counts and links inline (no separate prompt needed)

---

## Consolidated Prompts

### New: `gather-activity.prompt.md`

Replaces `gather-github.prompt.md`, `gather-notion.prompt.md`, `gather-sessions.prompt.md`.

Single prompt that:
- Reads config once
- Runs GitHub collection (gh search prs)
- Runs Notion collection (notion-search MCP)
- Runs Git/session collection (extract-git-activity.sh + parse-session-logs.sh)
- If a source fails, notes it and continues
- Outputs one combined JSON array

### Slimmed: `propose-updates.prompt.md`

**Removed** (now handled by scripts):
- Sprint date math instructions
- WIQL query instructions and ADO JSON parsing
- URL scanning/matching logic
- Keyword scoring rules and inference_keywords map
- State lifecycle decision table

**Retained** (LLM judgment):
- Review preprocessed inferences, override when context warrants
- Group items into PBIs using group_hints + cross-reference analysis
- Write titles using template prefix/slots
- Write descriptions using template description_format
- Present proposal grouped by sprint → action type
- Handle user approval interaction (expand, edit, approve)

**Key instruction:** "Use preprocessed signals as starting points. Override when your judgment says otherwise. Flag low-confidence inferences to the user. Full source context (URLs, titles, branches, existing items) is available in each item for your review."

### Slimmed: `apply-updates.prompt.md`

- Drops verbose bash examples (already in CLAUDE.md)
- Focuses on: execution order, error handling, description formatting, result tracking, retry/skip behavior

### Minor Trims

`create-pbi.prompt.md`, `create-task.prompt.md`, `breakdown-pbi.prompt.md` — remove redundant `build-params.sh` usage examples that duplicate CLAUDE.md.

### Unchanged

`parse-reference-task.prompt.md` — only runs during init, token cost irrelevant.

### Deleted

- `gather-github.prompt.md`
- `gather-notion.prompt.md`
- `gather-sessions.prompt.md`
- `ado-tracker-daily.automation.md`
- `ado-tracker-adhoc.automation.md`

---

## Configurable Approval Mode

### Config Schema Addition

In `data/config.json`:
```json
{
  "scan": {
    "approval_mode": "interactive",
    "auto_apply_sources": []
  }
}
```

### Modes

| Mode | Behavior | Best For |
|------|----------|----------|
| `interactive` | Show full proposal, wait for user approval (approve all / select / expand / edit) | New users, default |
| `auto-confirm` | Show proposal, then immediately proceed to apply without waiting for input. User can review the displayed proposal in scrollback. | Experienced users who want visibility |
| `auto-apply` | Apply all changes, show summary after | Fully autonomous scheduled scans |

### Upgrade Path

```
Week 1:  approval_mode: "interactive"    — see everything, approve manually
Week 3:  approval_mode: "auto-confirm"   — see everything, auto-approves
Month 2: approval_mode: "auto-apply"     — fully autonomous
```

Users change via `data/config.json` directly or a future `/ado-tracker-config` command.

---

## Pending Proposal & Resume

### When a scan gets no user response

(Scheduled scan in `interactive` mode, or user closes session mid-proposal)

1. Save full proposal to `data/sprints/<sprint>/pending-proposal-<date>.json`
2. Save metadata to `data/pending-scan.json`:
   ```json
   {
     "date": "2026-03-28",
     "mode": "daily",
     "sprint": "Sprint 2026-07",
     "proposal_file": "data/sprints/Sprint-2026-07/pending-proposal-2026-03-28.json",
     "item_count": 5,
     "state_updates": 2
   }
   ```

### Resume trigger

At the start of any `/ado-tracker-*` command, check for `data/pending-scan.json`. If it exists:

> "You have a pending proposal from Mar 28 (5 new items, 2 state updates). Review now, or discard and continue?"

- **Review** → load proposal, present, proceed to approval/apply
- **Discard** → delete pending files, continue with invoked command

---

## Skill Layer Changes

### Updated Skills

| Skill | Change |
|-------|--------|
| `/ado-tracker-daily` | Points to `ado-tracker-scan.automation.md` with `mode: "daily"` |
| `/ado-tracker-scan` | Points to `ado-tracker-scan.automation.md` with `mode: "adhoc"` |

### Unchanged Skills

| Skill | Reason |
|-------|--------|
| `/ado-tracker-init` | One-time setup, token cost irrelevant |
| `/ado-tracker-create` | Already lean and interactive |
| `/ado-tracker-task` | Already lean |
| `/ado-tracker-breakdown` | Already lean |

---

## Documentation Updates

| File | Changes |
|------|---------|
| `README.md` | Update architecture diagram, command reference, example user flows (before/after), document approval modes |
| `CLAUDE.md` | Update architecture section (new scripts, unified automation), document `approval_mode` config, update data organization (pending-scan.json), remove references to deleted files |
| `schemas/config.schema.md` | Add `scan.approval_mode` and `scan.auto_apply_sources` fields |
| `schemas/task-template.schema.md` | No changes |

---

## User Flow — Before vs After

### Daily Scan — Before (~50K tokens, 6-8 interactions, 3-5 min)

```
/ado-tracker-daily
  → read config (1st time)
  → resolve sprints → user confirms
  → read config (2nd time) → gather GitHub
  → read config (3rd time) → gather Notion
  → read config (4th time) → gather Git
  → save activity
  → LLM: query ADO, parse JSON, scan URLs, map sprints, score keywords, assign states
  → LLM: group items, write titles, present proposal
  → user approves
  → apply changes
  → update last-run
  → summary
```

### Daily Scan — After (~20K tokens, 3-4 interactions, 2-3 min)

```
/ado-tracker-daily
  → check pending proposal (resume if exists)
  → read config once, resolve sprints
  → gather all activity (1 prompt, 1 config read)
  → save activity
  → preprocess-activity.sh (sprint mapping, work type scoring, state assignment, group hints)
  → dedup-matcher.sh (ADO query, URL matching, similarity scoring, lifecycle checks)
  → LLM: review inferences, group, write titles, present proposal
  → user approves (or auto per approval_mode)
  → apply changes
  → track + summary
```

---

## What's NOT Changing

- All existing scripts (`ado-cli.sh`, `build-params.sh`, `extract-git-activity.sh`, `template-manager.sh`, `parse-session-logs.sh`)
- The `/ado-tracker-init` wizard
- Manual creation commands (`/ado-tracker-create`, `/ado-tracker-task`, `/ado-tracker-breakdown`)
- Template schema and extraction logic
- Data directory structure (`data/sprints/<sprint>/activity/` and `updates/`)
- The fundamental user experience: activity is gathered, proposals are presented, user approves, changes are applied

## What IS Changing

- Where deterministic work happens (LLM → scripts)
- How many prompts run per scan (5 → 3)
- How many automations exist (2 → 1)
- How approval works (always interactive → configurable)
- What happens when a scan has no audience (nothing → pending proposal)
