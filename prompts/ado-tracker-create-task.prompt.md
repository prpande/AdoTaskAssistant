# Create Task Under PBI

## Goal
Create one or more child tasks under an existing PBI.

## Context
- ADO CLI: `bash scripts/ado-cli.sh`
- Template: `bash scripts/template-manager.sh --action read`
- Config: `data/config.json`

## Input
- `pbi_id`: The parent PBI work item ID
- `description`: Description of the task(s) to create

## Instructions

1. Fetch the parent PBI:
   ```bash
   bash scripts/ado-cli.sh --action show-work-item --params '{"id":<pbi_id>}'
   ```

2. Read template and config.

3. Generate task fields:
   - **Title**: Concise task title (no prefix convention for tasks)
   - **Area Path**: Inherit from parent PBI
   - **Iteration Path**: Inherit from parent PBI
   - **State**: Ask user (default: New)
   - **Assigned To**: `user.ado_email` from config
   - **Description**: Task-level description

4. Present preview with parent context.

5. On approval, create and link.
   Write params to a temp file to avoid shell escaping issues with backslashes in ADO paths:
   ```bash
   cat > /tmp/ado-create-task-params.json <<'EOF'
   {
     "title": "...",
     "parent_id": <pbi_id>,
     "area_path": "...",
     "iteration_path": "...",
     "description": "...",
     "assigned_to": "...",
     "state": "..."
   }
   EOF
   bash scripts/ado-cli.sh --action create-task --params-file /tmp/ado-create-task-params.json
   ```

6. Report result with task ID, URL, and parent link.

## Output
Created task(s) with IDs, URLs, and parent PBI link.
