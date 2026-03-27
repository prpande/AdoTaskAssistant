# Apply ADO Updates

## Goal
Execute the user-approved ADO changes — create, update, or close work items.

## Context
- ADO CLI: `bash scripts/ado-cli.sh`
- Template: `data/task-template.json`
- Input: JSON array of approved actions from the propose step

## Input
- `approved_actions`: JSON array of approved changes (from propose-updates prompt)
- `sprint_folder`: Path to the current sprint's updates folder

## Instructions

1. For each approved action, execute the corresponding ADO CLI command:

   **CREATE:**
   ```bash
   bash scripts/ado-cli.sh --action create-work-item --params '{
     "type": "<work_item_type>",
     "title": "<title>",
     "area_path": "<area_path>",
     "iteration_path": "<iteration_path>",
     "description": "<description>",
     "fields": {<additional-fields>}
   }'
   ```

   **UPDATE:**
   ```bash
   bash scripts/ado-cli.sh --action update-work-item --params '{
     "id": <existing-id>,
     "fields": {<fields-to-update>}
   }'
   ```

   **CLOSE:**
   ```bash
   bash scripts/ado-cli.sh --action close-work-item --params '{"id": <existing-id>}'
   ```

   **ADD CHILD (for tasks under PBIs):**
   ```bash
   # First create the child task
   bash scripts/ado-cli.sh --action create-work-item --params '{
     "type": "Task",
     "title": "<title>",
     "area_path": "<area_path>",
     "iteration_path": "<iteration_path>"
   }'
   # Then link it as a child
   bash scripts/ado-cli.sh --action add-child --params '{"parent_id": <pbi-id>, "child_id": <new-task-id>}'
   ```

2. Track results for each action:
   - On success: record the work item ID, URL, and action taken
   - On failure: record the error, do NOT retry automatically. Show the error to the user and ask if they want to retry or skip.

3. Save results to the sprint updates folder:
   ```
   data/sprints/<Sprint-Name>/updates/<date>-<type>.json
   ```
   Format:
   ```json
   {
     "run_type": "daily",
     "date": "2026-03-27",
     "sprint": "Sprint-42",
     "proposed": [...],
     "accepted": [...],
     "applied": [
       {
         "action": "create",
         "work_item_id": 12345,
         "title": "Add retry logic to payment webhook",
         "url": "https://dev.azure.com/...",
         "status": "success"
       }
     ],
     "errors": []
   }
   ```

4. Present a summary to the user:
   ```
   ## Applied Changes
   ✓ Created PBI #12345: "Add retry logic to payment webhook"
   ✓ Updated PBI #5678: Added PR link
   ✗ Failed to create PBI "Q2 onboarding flow redesign" — error: <message>

   Results saved to data/sprints/Sprint-42/updates/2026-03-27-daily.json
   ```

## Output
Summary of applied changes with links to created/updated work items.
