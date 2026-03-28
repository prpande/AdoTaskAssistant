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

   **create** — Use `create-with-children` for PBIs with tasks.
   Use `build-params.sh` to safely construct JSON (handles backslash escaping in ADO paths):
   ```bash
   # First build the PBI params
   bash scripts/build-params.sh --output /tmp/ado-create-params.json \
     --argjson pbi '{}' \
     --argjson tasks '[]'
   ```
   For the PBI and tasks objects, construct them with `jq` to handle backslashes in area/iteration paths:
   ```bash
   PBI=$(jq -n \
     --arg type "Product Backlog Item" \
     --arg title "..." \
     --arg area_path "MBScrum\Business Experience\squad-biz-app" \
     --arg iteration_path "MBScrum\Sprint 2026-07" \
     --arg description "..." \
     --arg assigned_to "..." \
     --arg state "..." \
     '{type: $type, title: $title, area_path: $area_path, iteration_path: $iteration_path, description: $description, assigned_to: $assigned_to, state: $state}')
   TASKS=$(jq -n \
     --arg title "..." --arg description "..." --arg state "..." --arg assigned_to "..." \
     '[{title: $title, description: $description, state: $state, assigned_to: $assigned_to}]')
   bash scripts/build-params.sh --output /tmp/ado-create-params.json \
     --argjson pbi "$PBI" \
     --argjson tasks "$TASKS"
   bash scripts/ado-cli.sh --action create-with-children --params-file /tmp/ado-create-params.json
   ```

   **create-task** — For adding tasks to existing PBIs:
   ```bash
   bash scripts/build-params.sh --output /tmp/ado-task-params.json \
     --arg title "..." \
     --argjson parent_id <id> \
     --arg area_path "..." \
     --arg iteration_path "..." \
     --arg description "..." \
     --arg assigned_to "..." \
     --arg state "..."
   bash scripts/ado-cli.sh --action create-task --params-file /tmp/ado-task-params.json
   ```

   **update-state** — For changing work item state (no backslash risk, inline is safe):
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
