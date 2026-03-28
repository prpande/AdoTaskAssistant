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
   - **Description**: Format using `description_format` from template:
     - `{overview}`: Brief task purpose — what this task accomplishes
     - `{scope}`: Specific deliverables — what exactly will be done

4. Present preview with parent context.

5. On approval, create and link.
   Use `build-params.sh` to safely construct JSON (handles backslash escaping in ADO paths):
   ```bash
   bash scripts/build-params.sh --output /tmp/ado-create-task-params.json \
     --arg title "..." \
     --argjson parent_id <pbi_id> \
     --arg area_path "..." \
     --arg iteration_path "..." \
     --arg description "..." \
     --arg assigned_to "..." \
     --arg state "..."
   bash scripts/ado-cli.sh --action create-task --params-file /tmp/ado-create-task-params.json
   ```

6. Report result with task ID, URL, and parent link.

## Output
Created task(s) with IDs, URLs, and parent PBI link.
