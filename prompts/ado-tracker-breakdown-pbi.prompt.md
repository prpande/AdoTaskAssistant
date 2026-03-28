# Break Down PBI

## Goal
Decompose an existing PBI into multiple child tasks, avoiding duplicates.

## Context
- ADO CLI: `bash scripts/ado-cli.sh`
- Template: `bash scripts/template-manager.sh --action read`
- Config: `data/config.json`

## Input
- `pbi_id`: The PBI work item ID to break down

## Instructions

1. Fetch the PBI:
   ```bash
   bash scripts/ado-cli.sh --action show-work-item --params '{"id":<pbi_id>}'
   ```

2. Check for existing child tasks by inspecting the work item's `relations` array. Filter for `System.LinkTypes.Hierarchy-Forward` (child links). For each child, fetch its title and state.

3. Read template and config.

4. Analyze the PBI title and description. Propose child tasks:
   - Each task should be concrete and actionable
   - Tasks should cover the full scope of the PBI
   - **Dedup**: Skip any proposed task whose title closely matches an existing child task
   - Show existing children so the user can see what's already covered

5. Present the breakdown:
   ```
   ## PBI #<id>: <title>

   ### Existing Tasks
   - #12345: "Task A" (Done)
   - #12346: "Task B" (In Progress)

   ### Proposed New Tasks
   1. "Task C" — description
   2. "Task D" — description
   ```

6. Ask: "Approve all, select specific, or edit?"

7. Create approved tasks using `create-task` action (which handles creation + parent linking).
   Write params to a temp file to avoid shell escaping issues with backslashes in ADO paths:
   ```bash
   cat > /tmp/ado-create-task-params.json <<'EOF'
   {
     "title": "...",
     "parent_id": <pbi_id>,
     "area_path": "...",
     "iteration_path": "...",
     "assigned_to": "...",
     "state": "..."
   }
   EOF
   bash scripts/ado-cli.sh --action create-task --params-file /tmp/ado-create-task-params.json
   ```

8. Report all created tasks.

## Output
List of created child tasks with IDs, URLs, and parent link.
