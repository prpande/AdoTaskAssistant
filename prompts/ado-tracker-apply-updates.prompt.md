# Apply ADO Updates

## Goal
Execute user-approved ADO changes — create PBIs with children, update states, close items.

## Context
- ADO CLI: `bash scripts/ado-cli.sh`
- Config: `data/config.json` — read `user.ado_email`

## Input
- `approved_actions`: JSON array from propose-updates
- `sprint_folder`: Path for saving results

## Instructions

1. For each approved action, execute:

   **create** — Use `create-with-children` for PBIs with tasks:
   ```bash
   bash scripts/ado-cli.sh --action create-with-children --params '{
     "pbi": {"type": "Product Backlog Item", "title": "...", "area_path": "...", "iteration_path": "...", "description": "...", "assigned_to": "...", "state": "...", "fields": {...}},
     "tasks": [{"title": "...", "description": "...", "state": "...", "assigned_to": "..."}]
   }'
   ```

   **create-task** — For adding tasks to existing PBIs:
   ```bash
   bash scripts/ado-cli.sh --action create-task --params '{"title": "...", "parent_id": <id>, "description": "...", "state": "...", "assigned_to": "..."}'
   ```

   **update-state** — For changing work item state:
   ```bash
   bash scripts/ado-cli.sh --action update-work-item --params '{"id": <id>, "state": "<new_state>"}'
   ```

2. Always embed source URLs in descriptions. Use the template's `description_format`:
   ```
   ## Summary
   <summary>

   ## Source
   <PR links, Notion links, commit refs>

   ## Date
   <activity date range>
   ```

3. Track results for each action:
   - Success: record work item ID, URL, action
   - Failure: record error, show to user, ask retry or skip

4. Save results to sprint folder:
   ```json
   {
     "run_type": "daily|adhoc",
     "date": "2026-03-27",
     "sprints": ["Sprint 2026-07"],
     "applied": [{"action": "create", "pbi_id": 12345, "task_ids": [12346], "status": "success"}],
     "errors": []
   }
   ```

5. Present summary:
   ```
   ## Applied Changes
   Created PBI #12345: "Title" (Committed) — 3 tasks
   Updated Task #12346 → Done
   ```

## Output
Summary of applied changes with links to created/updated work items.
