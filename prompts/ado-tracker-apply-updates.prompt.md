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

   **add-task** — Use `ado-cli.sh --action create-task` with `build-params.sh`. The `parent_id` from the approved action is the existing PBI to link under. Build task params with area/iteration inherited from the parent PBI.

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
