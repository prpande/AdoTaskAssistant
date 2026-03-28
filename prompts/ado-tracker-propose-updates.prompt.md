# Propose ADO Updates

## Goal
Take gathered activity, cross-reference with existing ADO work items, resolve sprints, deduplicate, determine state, and present a grouped proposal for user approval.

## Context
- ADO CLI: `bash scripts/ado-cli.sh`
- Template: `bash scripts/template-manager.sh --action read`
- Config: `data/config.json` — read `user.ado_email`

## Input
- `activity`: Combined JSON from all gather prompts (GitHub, Notion, sessions/git)
- `sprints`: Array of overlapping sprints from `resolve-sprints-for-range`

## Instructions

### Phase 1: Map activity to sprints

For each activity item, determine which sprint it belongs to based on the item's date and the sprint date ranges. An activity's primary date is:
- GitHub PR: `created_at`
- Notion page: `last_edited`
- Git commits: date of first commit in the group

### Phase 2: Dedup against existing items

1. Query existing work items across all overlapping sprints:
   ```bash
   bash scripts/ado-cli.sh --action query-my-sprint-items --params '{"sprints": [<sprint-paths>]}'
   ```

2. For each existing work item, scan its description for source URLs (GitHub PR links, Notion page links).

3. Build a lookup: `{source_url → work_item_id}`

4. For each gathered activity item:
   - If its source URL is in the lookup → mark as **already tracked**
   - If title keywords overlap significantly with an existing item → mark as **potential match** (flag for user)
   - Otherwise → mark as **new**

### Phase 3: Smart grouping of new items

Group unmatched activity using these signals (in priority order):
1. **Git branch name prefix** — same branch prefix across repos = same feature (e.g., `pp/gstBooking-2503` in Scheduling + Clients)
2. **PR cross-references** — PR body or commits mentioning other repos/PRs
3. **Notion page hierarchy** — pages sharing a parent or title pattern
4. **Time proximity** — commits in the same repo on the same day

Each group becomes one proposed PBI with child tasks.

### Phase 4: Determine title, work type, and state

**Title prefix**: Read `title_prefix.pattern` and `title_prefix.slots` from template. For each proposed PBI:
- The `static` portion (e.g., `[BizApp]`) is always included
- For each slot, infer a value from context (repo name, PR title, activity type) or leave as `{slot_N}` for user to fill during review

**Work type inference**: For each proposed PBI, infer `ScrumMB.WorkType` from activity text:
1. Collect text signals: PR titles, commit messages, Notion page titles
2. Lowercase all text, scan against `work_type.inference_keywords` from template
3. Count keyword matches per work type category. Highest score wins.
4. Tie or no matches → use `work_type.default` from template
5. Include the inferred work type in the proposal for user to confirm or change

**Auto-populate fields**: Read `auto_populate_from_source` from template. For each mapping (e.g., `Custom.Repo` → `repo_name`), populate the field from the activity source.

Set state based on source type:

| Source | PBI State | Task State | Auto-update to Done? |
|--------|-----------|------------|---------------------|
| GitHub PR (open) | Committed | In Progress | Yes — when PR merges |
| GitHub PR (merged) | Done | Done | N/A |
| Notion page | Committed | In Progress | **Never** — user decides |
| Git commits (no PR) | Committed | In Progress | Never |

If a group contains mixed sources (e.g., merged PR + open PR), use the most active state (Committed over Done).

### Phase 5: State lifecycle updates for existing items

For items marked as **already tracked**, check if state needs updating:
- If a tracked PR was open but is now merged → propose **update-state → Done**
- If all child tasks of a PBI are now Done → propose **update-parent-state → Done**
- Notion-sourced tasks → **never propose auto-close**

### Phase 6: Present proposal

Group by sprint, then by action type:

```
## Sprint 2026-06 (Mar 11 – Mar 24)

### State Updates
- Task #12346 → Done (PR #1034 now merged)
- PBI #12345 → Done (all children completed)

## Sprint 2026-07 (Mar 25 – Apr 7)

### New Items
1. [BizApp][Backend][Feature] Title — Work Type: New Feature Development
   Tasks: task1 (Done), task2 (In Progress)

### Already Tracked (skipped)
- PR #808 covered by PBI #12345
```

Always assign all items to `user.ado_email` from config.
Always embed source URLs in descriptions for future dedup.
Always use `description_format` from template for PBI descriptions:
- `{overview}`: Summarize from activity source
- `{scope}`: Bullet list of specific changes, with source URLs for future dedup

### Controls

After presenting, offer:
- "Enter item numbers to approve (e.g., `1,3`), `all`, or `none`."
- "Enter `expand <number>` for full preview."
- "Enter `edit <number>` to modify before approving."

Return approved items as structured JSON for the apply step.

## Output
JSON array of approved actions:
```json
[
  {
    "action": "create",
    "sprint_path": "MBScrum\\Sprint 2026-07",
    "pbi": {"title": "...", "description": "...", "state": "Committed", "assigned_to": "...", "work_type": "New Feature Development", "fields": {"Custom.Repo": "org/repo-name"}},
    "tasks": [{"title": "...", "state": "Done", "description": "..."}]
  },
  {
    "action": "update-state",
    "work_item_id": 12345,
    "new_state": "Done"
  }
]
```
