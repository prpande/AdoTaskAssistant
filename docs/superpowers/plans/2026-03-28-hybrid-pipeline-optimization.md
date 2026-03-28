# Hybrid Pipeline Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut daily scan token usage ~50% by moving deterministic operations (dedup, sprint mapping, keyword scoring, state assignment) to bash scripts while keeping LLM judgment for grouping, titles, and user interaction.

**Architecture:** Two new preprocessing scripts (`preprocess-activity.sh`, `dedup-matcher.sh`) run between the gather and propose steps, producing enriched JSON with inferences. Three gather prompts merge into one. Two automations merge into one. The propose prompt is slimmed to receive pre-computed data instead of raw activity.

**Tech Stack:** bash, jq (all scripts), existing `ado-cli.sh` and `build-params.sh` patterns

---

## File Map

### New Files
- `scripts/preprocess-activity.sh` — Sprint mapping, work type scoring, state assignment, branch group hints
- `scripts/dedup-matcher.sh` — ADO query, URL matching, title similarity, state lifecycle checks
- `prompts/ado-tracker-gather-activity.prompt.md` — Consolidated gather (replaces 3 prompts)
- `automations/ado-tracker-scan.automation.md` — Unified automation (replaces daily + adhoc)

### Modified Files
- `prompts/ado-tracker-propose-updates.prompt.md` — Slim to receive pre-computed data
- `prompts/ado-tracker-apply-updates.prompt.md` — Remove verbose bash examples
- `prompts/ado-tracker-create-pbi.prompt.md` — Minor trim of bash examples
- `prompts/ado-tracker-create-task.prompt.md` — Minor trim of bash examples
- `prompts/ado-tracker-breakdown-pbi.prompt.md` — Minor trim of bash examples
- `.claude/skills/ado-tracker-daily/SKILL.md` — Point to unified automation
- `.claude/skills/ado-tracker-scan/SKILL.md` — Point to unified automation
- `schemas/config.schema.md` — Add `scan` section
- `config/config.sample.json` — Add `scan` section
- `CLAUDE.md` — Update architecture, scripts, config docs
- `README.md` — Update features, flow, commands

### Deleted Files
- `prompts/ado-tracker-gather-github.prompt.md`
- `prompts/ado-tracker-gather-notion.prompt.md`
- `prompts/ado-tracker-gather-sessions.prompt.md`
- `automations/ado-tracker-daily.automation.md`
- `automations/ado-tracker-adhoc.automation.md`

---

## Task 1: Create `preprocess-activity.sh`

**Files:**
- Create: `scripts/preprocess-activity.sh`

This script takes raw gathered activity + sprint data and outputs enriched activity with sprint mapping, work type scoring, state assignment, and branch group hints. All operations are deterministic jq/bash — no LLM needed.

- [ ] **Step 1: Create the script skeleton with argument parsing**

```bash
#!/usr/bin/env bash
# preprocess-activity.sh — Enrich gathered activity with deterministic inferences
#
# Input (via --params-file):
#   {
#     "activity_file": "path/to/gathered-activity.json",
#     "template_file": "path/to/task-template.json",
#     "sprints": [{"name": "...", "path": "...", "start": "YYYY-MM-DD", "end": "YYYY-MM-DD"}]
#   }
#
# Output: JSON written to stdout
#   { "items": [ { "source": {...}, "sprint": "...", "sprint_path": "...",
#     "inferred_work_type": "...", "work_type_confidence": 0.8,
#     "work_type_signals": [...], "inferred_state": "...",
#     "group_hint": "...", "dedup": null } ] }

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Parse arguments ---

PARAMS=""
PARAMS_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --params)
            PARAMS="$2"
            shift 2
            ;;
        --params-file)
            PARAMS_FILE="$2"
            shift 2
            ;;
        *)
            echo '{"success":false,"error":"Unknown argument: '"$1"'"}' >&2
            exit 1
            ;;
    esac
done

if [[ -n "$PARAMS_FILE" ]]; then
    PARAMS=$(cat "$PARAMS_FILE")
elif [[ -z "$PARAMS" ]]; then
    echo '{"success":false,"error":"Missing --params or --params-file"}' >&2
    exit 1
fi

# --- Read inputs ---

ACTIVITY_FILE=$(printf '%s' "$PARAMS" | jq -r '.activity_file')
TEMPLATE_FILE=$(printf '%s' "$PARAMS" | jq -r '.template_file // "'"$REPO_DIR"'/data/task-template.json"')
SPRINTS_JSON=$(printf '%s' "$PARAMS" | jq '.sprints')

if [[ ! -f "$ACTIVITY_FILE" ]]; then
    echo '{"success":false,"error":"Activity file not found: '"$ACTIVITY_FILE"'"}' >&2
    exit 1
fi

ACTIVITY=$(cat "$ACTIVITY_FILE")
TEMPLATE=$(cat "$TEMPLATE_FILE" 2>/dev/null || echo '{}')
```

- [ ] **Step 2: Add sprint mapping function**

Add after the input reading section:

```bash
# --- Sprint mapping ---
# Assigns each activity item to a sprint based on its primary date

map_to_sprint() {
    local item="$1"
    local item_type
    item_type=$(printf '%s' "$item" | jq -r '.type')

    # Extract primary date based on source type
    local primary_date
    case "$item_type" in
        github_pr)
            primary_date=$(printf '%s' "$item" | jq -r '.created_at // .updated_at')
            ;;
        notion_page)
            primary_date=$(printf '%s' "$item" | jq -r '.last_edited // .created_at')
            ;;
        dev_activity)
            # Use first date in date_range (format: "YYYY-MM-DD to YYYY-MM-DD")
            primary_date=$(printf '%s' "$item" | jq -r '.date_range' | cut -d' ' -f1)
            ;;
        *)
            primary_date=$(printf '%s' "$item" | jq -r '.created_at // .updated_at // .last_edited // empty')
            ;;
    esac

    # Normalize date to YYYY-MM-DD (strip time component if present)
    primary_date="${primary_date:0:10}"

    if [[ -z "$primary_date" || "$primary_date" == "null" ]]; then
        # Fallback: assign to first sprint
        printf '%s' "$SPRINTS_JSON" | jq -r '.[0].name'
        return
    fi

    # Find matching sprint: item date falls within [start, end]
    local matched
    matched=$(printf '%s' "$SPRINTS_JSON" | jq -r --arg d "$primary_date" '
        [.[] | select(.start <= $d and .end >= $d)] | .[0].name // empty
    ')

    if [[ -n "$matched" ]]; then
        echo "$matched"
    else
        # Fallback: closest sprint (last one if date is after all sprints)
        printf '%s' "$SPRINTS_JSON" | jq -r '.[-1].name'
    fi
}

get_sprint_path() {
    local sprint_name="$1"
    printf '%s' "$SPRINTS_JSON" | jq -r --arg n "$sprint_name" '
        [.[] | select(.name == $n)] | .[0].path // empty
    '
}
```

- [ ] **Step 3: Add work type scoring function**

Add after the sprint mapping section:

```bash
# --- Work type scoring ---
# Scores activity text against inference_keywords from template

score_work_type() {
    local text="$1"
    # Lowercase the text for matching
    local lower_text
    lower_text=$(echo "$text" | tr '[:upper:]' '[:lower:]')

    local default_type
    default_type=$(printf '%s' "$TEMPLATE" | jq -r '.work_type.default // "New Feature Development"')

    local keywords_json
    keywords_json=$(printf '%s' "$TEMPLATE" | jq '.work_type.inference_keywords // {}')

    if [[ "$keywords_json" == "{}" || "$keywords_json" == "null" ]]; then
        jq -n --arg type "$default_type" '{"type": $type, "confidence": 0.0, "signals": []}'
        return
    fi

    # Score each work type by counting keyword matches
    local best_type="$default_type"
    local best_score=0
    local best_signals="[]"
    local total_keywords=0

    while IFS= read -r work_type; do
        local score=0
        local signals="[]"
        local keywords
        keywords=$(printf '%s' "$keywords_json" | jq -r --arg wt "$work_type" '.[$wt][]')

        while IFS= read -r keyword; do
            [[ -z "$keyword" ]] && continue
            total_keywords=$((total_keywords + 1))
            if echo "$lower_text" | grep -qF "$keyword"; then
                score=$((score + 1))
                signals=$(printf '%s' "$signals" | jq --arg k "$keyword" '. + [$k]')
            fi
        done <<< "$keywords"

        if [[ $score -gt $best_score ]]; then
            best_score=$score
            best_type="$work_type"
            best_signals="$signals"
        fi
    done < <(printf '%s' "$keywords_json" | jq -r 'keys[]')

    # Confidence: matches / max possible (capped at 1.0)
    local confidence
    if [[ $total_keywords -gt 0 && $best_score -gt 0 ]]; then
        # Simple confidence: score / 3 capped at 1.0 (3+ matches = full confidence)
        confidence=$(echo "scale=2; s=$best_score; if (s>3) s=3; s/3" | bc 2>/dev/null || echo "0.5")
    else
        confidence="0.0"
    fi

    jq -n --arg type "$best_type" --arg conf "$confidence" --argjson signals "$best_signals" \
        '{"type": $type, "confidence": ($conf | tonumber), "signals": $signals}'
}
```

- [ ] **Step 4: Add state assignment function**

Add after the work type scoring section:

```bash
# --- State assignment ---
# Deterministic state based on source type and current status

assign_state() {
    local item="$1"
    local item_type
    item_type=$(printf '%s' "$item" | jq -r '.type')

    case "$item_type" in
        github_pr)
            local pr_state
            pr_state=$(printf '%s' "$item" | jq -r '.state')
            case "$pr_state" in
                merged|closed)
                    echo "Done"
                    ;;
                *)
                    echo "Committed"
                    ;;
            esac
            ;;
        notion_page)
            echo "Committed"
            ;;
        dev_activity)
            echo "Committed"
            ;;
        *)
            echo "Committed"
            ;;
    esac
}
```

- [ ] **Step 5: Add branch group hint extraction**

Add after the state assignment section:

```bash
# --- Branch group hints ---
# Extracts branch name prefixes to suggest grouping across repos

extract_group_hint() {
    local item="$1"
    local item_type
    item_type=$(printf '%s' "$item" | jq -r '.type')

    case "$item_type" in
        github_pr)
            # PR branch name if available (from head ref)
            local branch
            branch=$(printf '%s' "$item" | jq -r '.branch // .head_ref // empty')
            if [[ -n "$branch" ]]; then
                echo "$branch"
            else
                echo ""
            fi
            ;;
        dev_activity)
            # Git activity may have branch info in commits
            local branch
            branch=$(printf '%s' "$item" | jq -r '.branch // empty')
            if [[ -n "$branch" ]]; then
                echo "$branch"
            else
                echo ""
            fi
            ;;
        *)
            echo ""
            ;;
    esac
}
```

- [ ] **Step 6: Add main processing loop and output**

Add after all helper functions:

```bash
# --- Main processing ---

ITEM_COUNT=$(printf '%s' "$ACTIVITY" | jq 'length')
OUTPUT_ITEMS="[]"

for (( i=0; i<ITEM_COUNT; i++ )); do
    item=$(printf '%s' "$ACTIVITY" | jq ".[$i]")

    # Sprint mapping
    sprint_name=$(map_to_sprint "$item")
    sprint_path=$(get_sprint_path "$sprint_name")

    # Work type scoring — collect text signals from the item
    text_signals=""
    item_type=$(printf '%s' "$item" | jq -r '.type')
    case "$item_type" in
        github_pr)
            text_signals=$(printf '%s' "$item" | jq -r '[.title // "", .repo // ""] | join(" ")')
            ;;
        notion_page)
            text_signals=$(printf '%s' "$item" | jq -r '.title // ""')
            ;;
        dev_activity)
            text_signals=$(printf '%s' "$item" | jq -r '[.repo // "", (.commits // [] | .[].subject // "")] | join(" ")')
            ;;
    esac
    work_type_result=$(score_work_type "$text_signals")

    # State assignment
    inferred_state=$(assign_state "$item")

    # Group hint
    group_hint=$(extract_group_hint "$item")

    # Build enriched item
    enriched=$(jq -n \
        --argjson source "$item" \
        --arg sprint "$sprint_name" \
        --arg sprint_path "$sprint_path" \
        --arg inferred_work_type "$(printf '%s' "$work_type_result" | jq -r '.type')" \
        --argjson work_type_confidence "$(printf '%s' "$work_type_result" | jq '.confidence')" \
        --argjson work_type_signals "$(printf '%s' "$work_type_result" | jq '.signals')" \
        --arg inferred_state "$inferred_state" \
        --arg group_hint "$group_hint" \
        '{
            source: $source,
            sprint: $sprint,
            sprint_path: $sprint_path,
            inferred_work_type: $inferred_work_type,
            work_type_confidence: $work_type_confidence,
            work_type_signals: $work_type_signals,
            inferred_state: $inferred_state,
            group_hint: $group_hint,
            dedup: null
        }')

    OUTPUT_ITEMS=$(printf '%s' "$OUTPUT_ITEMS" | jq --argjson item "$enriched" '. + [$item]')
done

# Output
jq -n --argjson items "$OUTPUT_ITEMS" '{"success": true, "items": $items}'
```

- [ ] **Step 7: Make the script executable and test with a sample**

Run:
```bash
chmod +x scripts/preprocess-activity.sh
```

Create a test fixture and run:
```bash
cat > /tmp/test-activity.json << 'FIXTURE'
[
  {"type": "github_pr", "title": "Fix retry logic", "repo": "org/scheduling", "url": "https://github.com/org/scheduling/pull/1", "state": "merged", "branch": "pp/fix-retry", "created_at": "2026-03-27"},
  {"type": "notion_page", "title": "Architecture Overview", "url": "https://notion.so/abc", "last_edited": "2026-03-27"},
  {"type": "dev_activity", "repo": "org/clients", "branch": "pp/fix-retry", "commits": [{"hash": "abc", "subject": "fix retry"}], "date_range": "2026-03-27 to 2026-03-27"}
]
FIXTURE

cat > /tmp/test-sprints.json << 'FIXTURE'
{
  "activity_file": "/tmp/test-activity.json",
  "sprints": [{"name": "Sprint 2026-07", "path": "MBScrum\\Sprint 2026-07", "start": "2026-03-25", "end": "2026-04-07"}]
}
FIXTURE

bash scripts/preprocess-activity.sh --params-file /tmp/test-sprints.json
```

Expected: JSON output with 3 items, each having `sprint`, `inferred_work_type`, `inferred_state`, and `group_hint` populated. The PR item should have `inferred_state: "Done"` (merged). Both the PR and dev_activity should share `group_hint: "pp/fix-retry"`.

- [ ] **Step 8: Commit**

```bash
git add scripts/preprocess-activity.sh
git commit -m "feat: add preprocess-activity.sh for deterministic activity enrichment

Sprint mapping, work type keyword scoring, state assignment,
and branch group hint extraction — all in jq/bash."
```

---

## Task 2: Create `dedup-matcher.sh`

**Files:**
- Create: `scripts/dedup-matcher.sh`

This script queries existing ADO items, extracts URLs from descriptions, matches against preprocessed activity, and checks state lifecycle. This is the biggest single token saver — it replaces the LLM scanning raw ADO JSON.

- [ ] **Step 1: Create script with argument parsing and ADO query**

```bash
#!/usr/bin/env bash
# dedup-matcher.sh — Match preprocessed activity against existing ADO work items
#
# Input (via --params-file):
#   {
#     "activity_file": "path/to/preprocessed-activity.json",
#     "sprints": ["MBScrum\\Sprint 2026-07"]
#   }
#
# Output: Same structure as input with "dedup" field populated on every item.
# Writes enriched JSON to stdout.

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Parse arguments ---

PARAMS=""
PARAMS_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --params)
            PARAMS="$2"
            shift 2
            ;;
        --params-file)
            PARAMS_FILE="$2"
            shift 2
            ;;
        *)
            echo '{"success":false,"error":"Unknown argument: '"$1"'"}' >&2
            exit 1
            ;;
    esac
done

if [[ -n "$PARAMS_FILE" ]]; then
    PARAMS=$(cat "$PARAMS_FILE")
elif [[ -z "$PARAMS" ]]; then
    echo '{"success":false,"error":"Missing --params or --params-file"}' >&2
    exit 1
fi

ACTIVITY_FILE=$(printf '%s' "$PARAMS" | jq -r '.activity_file')
SPRINTS_JSON=$(printf '%s' "$PARAMS" | jq '.sprints')

if [[ ! -f "$ACTIVITY_FILE" ]]; then
    echo '{"success":false,"error":"Activity file not found: '"$ACTIVITY_FILE"'"}' >&2
    exit 1
fi

PREPROCESSED=$(cat "$ACTIVITY_FILE")
```

- [ ] **Step 2: Add ADO query and URL extraction**

Add after input parsing:

```bash
# --- Query existing ADO items ---

# Build sprints params file for ado-cli
SPRINT_PARAMS_FILE=$(mktemp)
printf '%s' "$SPRINTS_JSON" | jq '{sprints: .}' > "$SPRINT_PARAMS_FILE"

EXISTING_RESULT=$(bash "$SCRIPT_DIR/ado-cli.sh" --action query-my-sprint-items --params-file "$SPRINT_PARAMS_FILE" 2>&1)
rm -f "$SPRINT_PARAMS_FILE"

EXISTING_SUCCESS=$(printf '%s' "$EXISTING_RESULT" | jq -r '.success // false')

if [[ "$EXISTING_SUCCESS" != "true" ]]; then
    # If ADO query fails, pass through with all items marked as "new" (dedup skipped)
    printf '%s' "$PREPROCESSED" | jq '.items |= [.[] | .dedup = {"status": "new", "note": "ADO query failed — dedup skipped"}]'
    exit 0
fi

EXISTING_ITEMS=$(printf '%s' "$EXISTING_RESULT" | jq '.data // []')

# --- Extract URLs from existing item descriptions ---
# Build a lookup: { "url" -> { "work_item_id": N, "title": "...", "state": "..." } }

URL_LOOKUP="{}"
TITLE_LOOKUP="[]"

EXISTING_COUNT=$(printf '%s' "$EXISTING_ITEMS" | jq 'length')
for (( i=0; i<EXISTING_COUNT; i++ )); do
    wi=$(printf '%s' "$EXISTING_ITEMS" | jq ".[$i]")
    wi_id=$(printf '%s' "$wi" | jq -r '.fields["System.Id"] // .id')
    wi_title=$(printf '%s' "$wi" | jq -r '.fields["System.Title"] // ""')
    wi_state=$(printf '%s' "$wi" | jq -r '.fields["System.State"] // ""')
    wi_desc=$(printf '%s' "$wi" | jq -r '.fields["System.Description"] // ""')
    wi_type=$(printf '%s' "$wi" | jq -r '.fields["System.WorkItemType"] // ""')

    # Extract GitHub PR URLs and Notion page URLs from description
    urls=$(echo "$wi_desc" | grep -oE 'https://github\.com/[^/]+/[^/]+/pull/[0-9]+' || true)
    urls="$urls"$'\n'$(echo "$wi_desc" | grep -oE 'https://(www\.)?notion\.so/[a-zA-Z0-9-]+' || true)

    while IFS= read -r url; do
        [[ -z "$url" ]] && continue
        URL_LOOKUP=$(printf '%s' "$URL_LOOKUP" | jq \
            --arg url "$url" \
            --argjson id "${wi_id:-0}" \
            --arg title "$wi_title" \
            --arg state "$wi_state" \
            --arg type "$wi_type" \
            '. + {($url): {"work_item_id": $id, "title": $title, "state": $state, "type": $type}}')
    done <<< "$urls"

    # Also store title + id for fuzzy matching
    TITLE_LOOKUP=$(printf '%s' "$TITLE_LOOKUP" | jq \
        --argjson id "${wi_id:-0}" \
        --arg title "$wi_title" \
        --arg state "$wi_state" \
        --arg type "$wi_type" \
        '. + [{"work_item_id": $id, "title": $title, "state": $state, "type": $type}]')
done
```

- [ ] **Step 3: Add title similarity function**

Add after URL extraction:

```bash
# --- Title similarity (Jaccard on words) ---

jaccard_similarity() {
    local title_a="$1"
    local title_b="$2"

    # Normalize: lowercase, strip brackets/punctuation, split to words
    local words_a words_b
    words_a=$(echo "$title_a" | tr '[:upper:]' '[:lower:]' | sed 's/\[//g;s/\]//g;s/[^a-z0-9 ]/ /g' | tr -s ' ' '\n' | sort -u)
    words_b=$(echo "$title_b" | tr '[:upper:]' '[:lower:]' | sed 's/\[//g;s/\]//g;s/[^a-z0-9 ]/ /g' | tr -s ' ' '\n' | sort -u)

    # Count intersection and union
    local intersection union
    intersection=$(comm -12 <(echo "$words_a") <(echo "$words_b") | wc -l)
    union=$(sort -u <(echo "$words_a") <(echo "$words_b") | wc -l)

    if [[ $union -eq 0 ]]; then
        echo "0.0"
        return
    fi

    echo "scale=2; $intersection / $union" | bc 2>/dev/null || echo "0.0"
}
```

- [ ] **Step 4: Add main matching loop**

Add after the similarity function:

```bash
# --- Match activity items ---

ITEMS=$(printf '%s' "$PREPROCESSED" | jq '.items')
ITEM_COUNT=$(printf '%s' "$ITEMS" | jq 'length')
MATCHED_ITEMS="[]"

for (( i=0; i<ITEM_COUNT; i++ )); do
    item=$(printf '%s' "$ITEMS" | jq ".[$i]")
    source_url=$(printf '%s' "$item" | jq -r '.source.url // empty')
    source_title=$(printf '%s' "$item" | jq -r '.source.title // ""')
    source_type=$(printf '%s' "$item" | jq -r '.source.type // ""')

    # 1. Exact URL match
    if [[ -n "$source_url" ]]; then
        url_match=$(printf '%s' "$URL_LOOKUP" | jq --arg url "$source_url" '.[$url] // null')
        if [[ "$url_match" != "null" ]]; then
            # Check state lifecycle for tracked items
            state_update="null"
            current_state=$(printf '%s' "$url_match" | jq -r '.state')

            if [[ "$source_type" == "github_pr" ]]; then
                pr_state=$(printf '%s' "$item" | jq -r '.source.state')
                if [[ "$pr_state" == "merged" && "$current_state" != "Done" ]]; then
                    state_update='"Done"'
                fi
            fi
            # Notion items: never auto-close (state_update stays null)

            dedup=$(printf '%s' "$url_match" | jq --argjson su "$state_update" '. + {"status": "tracked", "state_update": $su}')
            item=$(printf '%s' "$item" | jq --argjson d "$dedup" '.dedup = $d')
            MATCHED_ITEMS=$(printf '%s' "$MATCHED_ITEMS" | jq --argjson item "$item" '. + [$item]')
            continue
        fi
    fi

    # 2. Title keyword overlap (Jaccard > 0.6)
    best_similarity="0.0"
    best_match="null"
    TITLE_COUNT=$(printf '%s' "$TITLE_LOOKUP" | jq 'length')

    if [[ -n "$source_title" && $TITLE_COUNT -gt 0 ]]; then
        for (( j=0; j<TITLE_COUNT; j++ )); do
            existing=$(printf '%s' "$TITLE_LOOKUP" | jq ".[$j]")
            existing_title=$(printf '%s' "$existing" | jq -r '.title')
            sim=$(jaccard_similarity "$source_title" "$existing_title")

            if (( $(echo "$sim > $best_similarity" | bc -l 2>/dev/null || echo 0) )); then
                best_similarity="$sim"
                best_match="$existing"
            fi
        done

        if (( $(echo "$best_similarity > 0.6" | bc -l 2>/dev/null || echo 0) )); then
            dedup=$(printf '%s' "$best_match" | jq --arg sim "$best_similarity" \
                '. + {"status": "potential_match", "similarity": ($sim | tonumber)}')
            item=$(printf '%s' "$item" | jq --argjson d "$dedup" '.dedup = $d')
            MATCHED_ITEMS=$(printf '%s' "$MATCHED_ITEMS" | jq --argjson item "$item" '. + [$item]')
            continue
        fi
    fi

    # 3. No match — new item
    item=$(printf '%s' "$item" | jq '.dedup = {"status": "new"}')
    MATCHED_ITEMS=$(printf '%s' "$MATCHED_ITEMS" | jq --argjson item "$item" '. + [$item]')
done
```

- [ ] **Step 5: Add output assembly**

Add after the matching loop:

```bash
# --- Output ---

jq -n --argjson items "$MATCHED_ITEMS" '{"success": true, "items": $items}'
```

- [ ] **Step 6: Make executable and test with sample data**

Run:
```bash
chmod +x scripts/dedup-matcher.sh
```

Test (requires ADO access — if unavailable, verify the graceful fallback):
```bash
# Save preprocessed output from Task 1's test to a file first
bash scripts/preprocess-activity.sh --params-file /tmp/test-sprints.json | jq '.' > /tmp/test-preprocessed.json

cat > /tmp/test-dedup-params.json << 'FIXTURE'
{
  "activity_file": "/tmp/test-preprocessed.json",
  "sprints": ["MBScrum\\Sprint 2026-07"]
}
FIXTURE

bash scripts/dedup-matcher.sh --params-file /tmp/test-dedup-params.json
```

Expected: JSON output with `dedup` field populated on every item. If ADO is unreachable, all items should have `"status": "new"` with a note that dedup was skipped.

- [ ] **Step 7: Commit**

```bash
git add scripts/dedup-matcher.sh
git commit -m "feat: add dedup-matcher.sh for URL matching and title similarity

Queries existing ADO items, extracts URLs from descriptions, matches
against preprocessed activity by exact URL or Jaccard title similarity.
Checks state lifecycle for tracked items (PR merged → Done)."
```

---

## Task 3: Create consolidated `gather-activity.prompt.md`

**Files:**
- Create: `prompts/ado-tracker-gather-activity.prompt.md`

Merges the three separate gather prompts into one. Single config read, sequential collection, combined output.

- [ ] **Step 1: Write the consolidated gather prompt**

```markdown
# Gather All Activity

## Goal
Collect activity from GitHub, Notion, and Git for a date range in a single pass.

## Context
- Config: `data/config.json` — read once for all sources
- Tools: `gh` CLI, Notion MCP (`notion-search`), `bash scripts/extract-git-activity.sh`, `bash scripts/parse-session-logs.sh`

## Input
- `from_date`: Start date (YYYY-MM-DD)
- `to_date`: End date (YYYY-MM-DD)

## Instructions

1. Read `data/config.json` once. Extract all needed settings:
   - `user.github_username`, `github.organizations`, `github.excluded_repos`
   - `user.notion_user_id`, `notion.scope`, `notion.excluded_databases`, `notion.filter_types`
   - `git.source_root`, `git.auto_detect`, `git.filter_by_remote_org`, `git.explicit_repos`

### GitHub Activity

2. For each org in `github.organizations`, search for PRs authored by the user:
   ```bash
   gh search prs --author=<username> --created=<from_date>..<to_date> --owner=<org> --json number,title,repository,state,createdAt,updatedAt,url --limit 100
   ```
   If results return exactly 100, paginate with `--page 2` etc.

3. Also search for PRs reviewed by the user:
   ```bash
   gh search prs --reviewed-by=<username> --created=<from_date>..<to_date> --owner=<org> --json number,title,repository,state,createdAt,updatedAt,url --limit 100
   ```

4. Filter out repos in `github.excluded_repos`. Deduplicate by URL. If a PR appears in both authored and reviewed, keep one entry with `role: "author+reviewer"`.

5. If GitHub collection fails, note "GitHub scan skipped — <error>" and continue.

### Notion Activity

6. Search Notion with the stored user ID:
   ```
   notion-search:
     query: "*"
     filters:
       created_date_range: {start_date: <from_date>, end_date: <to_date + 1 day>}
       created_by_user_ids: [<user.notion_user_id>]
     page_size: 25
     max_highlight_length: 50
   ```

7. Filter results: only include `type` in `notion.filter_types` (default: `["page"]`). Drop Slack, SharePoint, connector results. Exclude databases in `notion.excluded_databases`.

8. If Notion collection fails, note "Notion scan skipped — <error>" and continue.

### Git & Session Activity

9. Extract git activity:
   ```bash
   bash scripts/extract-git-activity.sh --from <from_date> --to <to_date> --auto-detect "<git.source_root>" --filter-org "<git.filter_by_remote_org>"
   ```
   If `git.explicit_repos` is non-empty, also pass `--repos '<json-array>'`.

10. Parse session logs (best-effort):
    ```bash
    bash scripts/parse-session-logs.sh --from <from_date> --to <to_date>
    ```

11. If Git collection fails, note "Git scan skipped — <error>" and continue.

### Combine and Output

12. Combine all activity into a single JSON array. Each item has a `type` field (`github_pr`, `notion_page`, or `dev_activity`).

13. Report collection summary: "Found X PRs, Y Notion pages, Z repos with commits." Note any skipped sources.

## Output
Combined JSON array of all activity objects.
```

- [ ] **Step 2: Commit**

```bash
git add prompts/ado-tracker-gather-activity.prompt.md
git commit -m "feat: add consolidated gather-activity prompt

Merges gather-github, gather-notion, and gather-sessions into a single
prompt with one config read and sequential collection."
```

---

## Task 4: Rewrite `propose-updates.prompt.md` (lean version)

**Files:**
- Modify: `prompts/ado-tracker-propose-updates.prompt.md`

Strip out all deterministic logic (now handled by scripts). The prompt receives pre-computed data and focuses on judgment calls.

- [ ] **Step 1: Replace the propose-updates prompt content**

Replace the entire content of `prompts/ado-tracker-propose-updates.prompt.md` with:

```markdown
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
- **Dedup**: Items with `"status": "tracked"` (exact URL match) are definitive — skip them. Items with `"status": "potential_match"` need your review — check titles, URLs, and context to decide if they're truly duplicates.
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

Check `scan.approval_mode` from config:
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
```

- [ ] **Step 2: Commit**

```bash
git add prompts/ado-tracker-propose-updates.prompt.md
git commit -m "feat: slim propose-updates prompt to receive pre-computed data

Removes sprint mapping, WIQL queries, URL scanning, keyword scoring,
and state lifecycle table. Focuses on grouping, titles, and approval."
```

---

## Task 5: Slim `apply-updates.prompt.md`

**Files:**
- Modify: `prompts/ado-tracker-apply-updates.prompt.md`

Remove verbose bash examples that duplicate CLAUDE.md documentation.

- [ ] **Step 1: Replace the apply-updates prompt content**

Replace the entire content of `prompts/ado-tracker-apply-updates.prompt.md` with:

```markdown
# Apply ADO Updates

## Goal
Execute user-approved ADO changes — create PBIs with children, update states.

## Context
- ADO CLI: `bash scripts/ado-cli.sh` (see CLAUDE.md for usage patterns)
- JSON construction: `bash scripts/build-params.sh` (see CLAUDE.md — always use for params with ADO paths)
- Config: `data/config.json` — read `user.ado_email`

## Input
- `approved_actions`: JSON array from propose-updates
- `sprint_folder`: Path for saving results (e.g., `data/sprints/Sprint-2026-07`)

## Instructions

1. For each approved action:

   **create** — Use `ado-cli.sh --action create-with-children`. Build params with `build-params.sh` using `--argjson pbi` and `--argjson tasks`. Construct PBI and task objects with `jq -n --arg` to handle backslash escaping in area/iteration paths.

   **create-task** — Use `ado-cli.sh --action create-task` with `build-params.sh`.

   **update-state** — Use `ado-cli.sh --action update-work-item --params '{"id": <id>, "state": "<state>"}'` (no backslash risk, inline is safe).

2. Format descriptions using the template's `description_format`:
   - `{overview}`: Summarize from activity source
   - `{scope}`: Bullet list of specific changes with source URLs for future dedup

3. Auto-populate fields from `auto_populate_from_source` in template (e.g., `Custom.Repo` → repo name). Set `ScrumMB.WorkType` from the proposal's work type.

4. Track results: success → record work item ID, URL. Failure → show error, ask retry or skip.

5. Save results to `<sprint_folder>/updates/<date>-<mode>.json`:
   ```json
   {
     "run_type": "daily|adhoc",
     "date": "2026-03-28",
     "sprints": ["Sprint 2026-07"],
     "applied": [{"action": "create", "pbi_id": 12345, "task_ids": [12346], "status": "success"}],
     "errors": []
   }
   ```

6. Present summary with work item IDs and links.

## Output
Summary of applied changes with links to created/updated work items.
```

- [ ] **Step 2: Commit**

```bash
git add prompts/ado-tracker-apply-updates.prompt.md
git commit -m "feat: slim apply-updates prompt, reference CLAUDE.md for tool patterns"
```

---

## Task 6: Create unified `ado-tracker-scan.automation.md`

**Files:**
- Create: `automations/ado-tracker-scan.automation.md`

Single automation replacing both daily and adhoc, with preprocessing step and approval mode support.

- [ ] **Step 1: Write the unified automation**

```markdown
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
  - **Review** → load proposal file, skip to Step 5 (Propose) with loaded data.
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
- Create sprint data folders if needed.
- On failure: ask user for sprint info manually.

### Step 2: Gather Activity

Execute `prompts/ado-tracker-gather-activity.prompt.md` with the date range.

Save combined activity to `data/sprints/<primary-sprint>/activity/<date>-<mode>.json` (daily) or `<from>-to-<to>-adhoc.json` (adhoc).

If ALL sources fail → "No activity found. Check tool connections." Stop.

### Step 3: Preprocess (Script Only)

Run the preprocessing pipeline — zero LLM tokens:

```bash
# Step 3a: Enrich activity with sprint mapping, work type scoring, state assignment, group hints
bash scripts/build-params.sh --output /tmp/ado-preprocess-params.json \
  --arg activity_file "<path-to-activity-snapshot>" \
  --argjson sprints '<sprints-json-from-step-1>'
bash scripts/preprocess-activity.sh --params-file /tmp/ado-preprocess-params.json > /tmp/ado-preprocessed.json

# Step 3b: Match against existing ADO items for dedup
bash scripts/build-params.sh --output /tmp/ado-dedup-params.json \
  --arg activity_file "/tmp/ado-preprocessed.json" \
  --argjson sprints '<sprint-paths-array>'
bash scripts/dedup-matcher.sh --params-file /tmp/ado-dedup-params.json > /tmp/ado-matched.json
```

Save the matched output for the propose step. If either script fails, show the error and ask whether to continue without preprocessing (fall back to LLM-based processing) or abort.

### Step 4: Propose Updates

Execute `prompts/ado-tracker-propose-updates.prompt.md` with:
- `preprocessed_file`: path to matched JSON from Step 3
- `sprints`: sprint objects from Step 1

The prompt handles grouping, title writing, and user approval based on `approval_mode`.

If `approval_mode` is `"interactive"` and user does not respond (scheduled scan):
- Save proposal to `data/sprints/<sprint>/pending-proposal-<date>.json`
- Save metadata to `data/pending-scan.json`
- Skip to Step 7 (Summary) with note: "Proposal saved for later review."

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
```

- [ ] **Step 2: Commit**

```bash
git add automations/ado-tracker-scan.automation.md
git commit -m "feat: add unified scan automation replacing daily + adhoc

Single automation with mode parameter. Adds preprocessing step,
approval mode support, and pending proposal resume."
```

---

## Task 7: Update skills to point to unified automation

**Files:**
- Modify: `.claude/skills/ado-tracker-daily/SKILL.md`
- Modify: `.claude/skills/ado-tracker-scan/SKILL.md`

- [ ] **Step 1: Update the daily skill**

Replace the entire content of `.claude/skills/ado-tracker-daily/SKILL.md` with:

```markdown
---
name: ado-tracker-daily
description: Run the ADO Tracker daily scan — gather activity, propose ADO updates, apply approved changes
---

# ADO Tracker — Daily Scan

Execute the daily scan automation.

## Instructions

1. Execute `automations/ado-tracker-scan.automation.md` with `mode: "daily"` — follow each step in sequence.
2. This skill can be triggered manually or by the `/loop` schedule.
```

- [ ] **Step 2: Update the scan skill**

Replace the entire content of `.claude/skills/ado-tracker-scan/SKILL.md` with:

```markdown
---
name: ado-tracker-scan
description: Run an ad-hoc ADO Tracker scan for a custom date range
---

# ADO Tracker — Ad-hoc Scan

Execute an ad-hoc scan for a custom date range.

## Arguments
- `--from YYYY-MM-DD` — Start date
- `--to YYYY-MM-DD` — End date

If dates are not provided as arguments, ask the user.

## Instructions

1. Parse `--from` and `--to` from the arguments.
2. Execute `automations/ado-tracker-scan.automation.md` with `mode: "adhoc"` and the parsed date range.
```

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/ado-tracker-daily/SKILL.md .claude/skills/ado-tracker-scan/SKILL.md
git commit -m "feat: update daily and scan skills to use unified automation"
```

---

## Task 8: Delete old files

**Files:**
- Delete: `prompts/ado-tracker-gather-github.prompt.md`
- Delete: `prompts/ado-tracker-gather-notion.prompt.md`
- Delete: `prompts/ado-tracker-gather-sessions.prompt.md`
- Delete: `automations/ado-tracker-daily.automation.md`
- Delete: `automations/ado-tracker-adhoc.automation.md`

- [ ] **Step 1: Delete the old gather prompts and automations**

```bash
git rm prompts/ado-tracker-gather-github.prompt.md
git rm prompts/ado-tracker-gather-notion.prompt.md
git rm prompts/ado-tracker-gather-sessions.prompt.md
git rm automations/ado-tracker-daily.automation.md
git rm automations/ado-tracker-adhoc.automation.md
```

- [ ] **Step 2: Commit**

```bash
git commit -m "chore: remove old gather prompts and split automations

Replaced by consolidated gather-activity.prompt.md and unified
ado-tracker-scan.automation.md."
```

---

## Task 9: Trim remaining prompts

**Files:**
- Modify: `prompts/ado-tracker-create-pbi.prompt.md`
- Modify: `prompts/ado-tracker-create-task.prompt.md`
- Modify: `prompts/ado-tracker-breakdown-pbi.prompt.md`

Remove redundant `build-params.sh` usage examples that duplicate CLAUDE.md documentation.

- [ ] **Step 1: Trim create-pbi prompt**

In `prompts/ado-tracker-create-pbi.prompt.md`, replace the verbose bash example in step 8:

Replace:
```
8. On approval, create.
   Use `build-params.sh` to safely construct JSON (handles backslash escaping in ADO paths):
   ```bash
   bash scripts/build-params.sh --output /tmp/ado-create-pbi-params.json \
     --arg type "Product Backlog Item" \
     --arg title "..." \
     --arg area_path "..." \
     --arg iteration_path "..." \
     --arg description "..." \
     --arg assigned_to "..." \
     --arg state "..." \
     --argjson fields '{"Microsoft.VSTS.Common.Priority":4,"Microsoft.VSTS.Common.ValueArea":"Business","ScrumMB.WorkType":"..."}'
   bash scripts/ado-cli.sh --action create-work-item --params-file /tmp/ado-create-pbi-params.json
   ```
```

With:
```
8. On approval, create using `build-params.sh` + `ado-cli.sh --action create-work-item` (see CLAUDE.md for patterns). Include all fields: type, title, area_path, iteration_path, description, assigned_to, state, and the fields object with Priority, ValueArea, and ScrumMB.WorkType.
```

- [ ] **Step 2: Trim create-task prompt**

In `prompts/ado-tracker-create-task.prompt.md`, read the file first, then replace verbose bash examples with a reference to CLAUDE.md patterns. The key instruction is: "Use `build-params.sh` + `ado-cli.sh --action create-task` (see CLAUDE.md for patterns)."

- [ ] **Step 3: Trim breakdown-pbi prompt**

In `prompts/ado-tracker-breakdown-pbi.prompt.md`, replace the verbose bash example in step 7:

Replace:
```
   Use `build-params.sh` to safely construct JSON (handles backslash escaping in ADO paths):
   ```bash
   bash scripts/build-params.sh --output /tmp/ado-create-task-params.json \
     --arg title "..." \
     --argjson parent_id <pbi_id> \
     --arg area_path "..." \
     --arg iteration_path "..." \
     --arg assigned_to "..." \
     --arg state "..."
   bash scripts/ado-cli.sh --action create-task --params-file /tmp/ado-create-task-params.json
   ```
```

With:
```
   Use `build-params.sh` + `ado-cli.sh --action create-task` (see CLAUDE.md for patterns). Include: title, parent_id, area_path, iteration_path, assigned_to, state.
```

- [ ] **Step 4: Commit**

```bash
git add prompts/ado-tracker-create-pbi.prompt.md prompts/ado-tracker-create-task.prompt.md prompts/ado-tracker-breakdown-pbi.prompt.md
git commit -m "chore: trim redundant bash examples from create/task/breakdown prompts"
```

---

## Task 10: Update config schema and sample

**Files:**
- Modify: `schemas/config.schema.md`
- Modify: `config/config.sample.json`

- [ ] **Step 1: Add `scan` section to config schema**

In `schemas/config.schema.md`, add after the `### session_logs` section:

```markdown

### `scan`
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `approval_mode` | `"interactive"` \| `"auto-confirm"` \| `"auto-apply"` | `"interactive"` | How scan proposals are approved. `interactive`: show and wait. `auto-confirm`: show then proceed immediately. `auto-apply`: apply without showing. |
| `auto_apply_sources` | string[] | `[]` | Reserved for future per-source auto-apply rules. |
```

- [ ] **Step 2: Add `scan` section to config.sample.json**

In `config/config.sample.json`, add after the `session_logs` block:

```json
  "scan": {
    "approval_mode": "interactive",
    "auto_apply_sources": []
  }
```

- [ ] **Step 3: Commit**

```bash
git add schemas/config.schema.md config/config.sample.json
git commit -m "feat: add scan.approval_mode to config schema and sample"
```

---

## Task 11: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update the Architecture section**

In `CLAUDE.md`, update the `## Architecture` section. Add the new scripts and update the description:

Replace:
```
- **Prompts** (`prompts/`): Single-purpose reusable tasks, invokable individually
- **Automations** (`automations/`): Multi-step orchestrated workflows that call prompts in sequence
```

With:
```
- **Prompts** (`prompts/`): Single-purpose reusable tasks, invokable individually
- **Automations** (`automations/`): Multi-step orchestrated workflows that call prompts in sequence (unified `ado-tracker-scan.automation.md` handles both daily and adhoc modes)
```

- [ ] **Step 2: Update the Tools section**

Add the new scripts to the Tools section. After the existing `template-manager.sh` entry, add:

```markdown
- **Activity preprocessing:** `bash scripts/preprocess-activity.sh --params-file <file>`
  - Enriches gathered activity with sprint mapping, work type scoring, state assignment, branch group hints
  - All operations are deterministic jq/bash — no LLM tokens consumed
- **Dedup matching:** `bash scripts/dedup-matcher.sh --params-file <file>`
  - Queries existing ADO items, matches by URL and title similarity, checks state lifecycle
  - Gracefully falls back to "all new" if ADO query fails
```

- [ ] **Step 3: Update Configuration section**

Add the new `scan` config field. After the `schedule` description, add:

```markdown
  - `scan`: approval_mode (interactive/auto-confirm/auto-apply), auto_apply_sources
```

- [ ] **Step 4: Update Data Organization section**

Add pending scan file to the data organization. After the existing structure, add:

```markdown
data/pending-scan.json                          — metadata for unreviewed proposals
data/sprints/<Sprint-Name>/pending-proposal-<date>.json — saved proposal awaiting review
```

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for new scripts, unified automation, approval config"
```

---

## Task 12: Update README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update features list**

In `README.md`, replace the features section:

Replace:
```markdown
## Features

- **Daily scan** — Detects PRs, Notion edits, Claude sessions, and git commits since last run
- **Smart proposals** — Groups activity by source, proposes ADO PBI/Task creates/updates/closes
- **Template-based** — Uses a reference ADO work item as a template for consistent formatting
- **Sprint-aware** — Auto-detects current sprint, confirms before applying changes
- **Ad-hoc mode** — Scan any date range on demand
- **Manual creation** — Create PBIs, add tasks, break down PBIs via slash commands
```

With:
```markdown
## Features

- **Daily scan** — Detects PRs, Notion edits, Claude sessions, and git commits since last run
- **Token-efficient** — Deterministic preprocessing (dedup, sprint mapping, keyword scoring) runs in bash scripts, not the LLM
- **Smart proposals** — Groups activity by feature, proposes ADO PBI/Task creates/updates/closes
- **Template-based** — Uses a reference ADO work item as a template for consistent formatting
- **Sprint-aware** — Auto-detects sprints overlapping scan date range
- **Configurable approval** — Start interactive, graduate to auto-confirm or auto-apply as you build trust
- **Pending proposals** — Missed a scan? Proposals are saved and resumed on next interaction
- **Ad-hoc mode** — Scan any date range on demand
- **Manual creation** — Create PBIs, add tasks, break down PBIs via slash commands
```

- [ ] **Step 2: Update data section**

Replace:
```markdown
## Data

All user data is stored in `data/` (gitignored) and organized by sprint. See `config/config.sample.json` for configuration options.
```

With:
```markdown
## Data

All user data is stored in `data/` (gitignored) and organized by sprint:
- `data/config.json` — user settings (see `config/config.sample.json`)
- `data/task-template.json` — generated from reference work item
- `data/last-run.json` — last daily scan metadata
- `data/pending-scan.json` — unreviewed proposal (auto-resumed)
- `data/sprints/<Sprint>/activity/` — gathered activity snapshots
- `data/sprints/<Sprint>/updates/` — applied changes log

### Approval Modes

Set `scan.approval_mode` in `data/config.json`:
| Mode | Behavior |
|------|----------|
| `interactive` | Show proposal, wait for approval (default) |
| `auto-confirm` | Show proposal, proceed immediately |
| `auto-apply` | Apply without showing, summarize after |
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: update README for token-efficient pipeline and approval modes"
```

---

## Task 13: End-to-end validation

- [ ] **Step 1: Verify file structure**

Run:
```bash
find /c/src/AdoTaskAssistant -type f -not -path '*/.git/*' -not -path '*/data/*' -not -path '*/docs/superpowers/plans/*' -not -path '*/docs/superpowers/specs/*' | sort
```

Expected: No old gather prompts, no old automation files. New scripts and consolidated prompt present.

Verify these files exist:
- `scripts/preprocess-activity.sh`
- `scripts/dedup-matcher.sh`
- `prompts/ado-tracker-gather-activity.prompt.md`
- `automations/ado-tracker-scan.automation.md`

Verify these files are gone:
- `prompts/ado-tracker-gather-github.prompt.md`
- `prompts/ado-tracker-gather-notion.prompt.md`
- `prompts/ado-tracker-gather-sessions.prompt.md`
- `automations/ado-tracker-daily.automation.md`
- `automations/ado-tracker-adhoc.automation.md`

- [ ] **Step 2: Test preprocess-activity.sh end-to-end**

Run:
```bash
cat > /tmp/e2e-activity.json << 'FIXTURE'
[
  {"type": "github_pr", "title": "Add retry logic for booking", "repo": "org/scheduling", "url": "https://github.com/org/scheduling/pull/42", "state": "merged", "branch": "pp/booking-retry", "created_at": "2026-03-27"},
  {"type": "github_pr", "title": "Update booking client", "repo": "org/clients", "url": "https://github.com/org/clients/pull/99", "state": "open", "branch": "pp/booking-retry", "created_at": "2026-03-27"},
  {"type": "notion_page", "title": "Booking Retry Design", "url": "https://notion.so/booking-retry-123", "last_edited": "2026-03-26"},
  {"type": "dev_activity", "repo": "org/scheduling", "branch": "pp/booking-retry", "commits": [{"hash": "abc", "subject": "add retry logic"}], "date_range": "2026-03-27 to 2026-03-27"}
]
FIXTURE

cat > /tmp/e2e-params.json << 'FIXTURE'
{
  "activity_file": "/tmp/e2e-activity.json",
  "sprints": [
    {"name": "Sprint 2026-06", "path": "MBScrum\\Sprint 2026-06", "start": "2026-03-11", "end": "2026-03-24"},
    {"name": "Sprint 2026-07", "path": "MBScrum\\Sprint 2026-07", "start": "2026-03-25", "end": "2026-04-07"}
  ]
}
FIXTURE

bash scripts/preprocess-activity.sh --params-file /tmp/e2e-params.json | jq '.'
```

Expected output validates:
- Merged PR → `inferred_state: "Done"`, sprint 2026-07
- Open PR → `inferred_state: "Committed"`, sprint 2026-07
- Notion page → `inferred_state: "Committed"`, sprint 2026-06 (edited Mar 26, within sprint 06 range)
- Dev activity → `inferred_state: "Committed"`, sprint 2026-07
- PRs and dev_activity share `group_hint: "pp/booking-retry"`
- Work type signals should include "retry" or "add"

- [ ] **Step 3: Test dedup-matcher.sh graceful fallback**

Run (without ADO access, or with invalid sprints to trigger failure):
```bash
bash scripts/preprocess-activity.sh --params-file /tmp/e2e-params.json > /tmp/e2e-preprocessed.json

cat > /tmp/e2e-dedup-params.json << 'FIXTURE'
{
  "activity_file": "/tmp/e2e-preprocessed.json",
  "sprints": ["NonExistent\\Sprint"]
}
FIXTURE

bash scripts/dedup-matcher.sh --params-file /tmp/e2e-dedup-params.json | jq '.items[0].dedup'
```

Expected: All items have `"status": "new"` with a note about dedup being skipped (ADO query failure is gracefully handled).

- [ ] **Step 4: Verify all prompts and automations are well-formed**

Read each modified/new file and verify:
```bash
# Check no file references deleted prompts
grep -r "gather-github\|gather-notion\|gather-sessions\|ado-tracker-daily\.automation\|ado-tracker-adhoc\.automation" \
  prompts/ automations/ .claude/skills/ CLAUDE.md README.md 2>/dev/null || echo "No stale references found"
```

Expected: "No stale references found" — no remaining references to deleted files.

- [ ] **Step 5: Commit any fixes from validation**

If any issues were found and fixed:
```bash
git add -A
git commit -m "fix: address issues found during end-to-end validation"
```
