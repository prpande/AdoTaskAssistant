# Create Task Under PBI

## Goal
Create one or more child tasks under an existing PBI.

## Context
- ADO CLI: `bash scripts/ado-cli.sh`
- Template: `bash scripts/template-manager.sh --action read`
- Sprint: `bash scripts/ado-cli.sh --action current-sprint`

## Input
- `pbi_id`: The parent PBI work item ID
- `description`: Description of the task(s) to create

## Instructions

1. Fetch the parent PBI to confirm it exists and get its context:
   ```bash
   bash scripts/ado-cli.sh --action show-work-item --params '{"id":<pbi_id>}'
   ```
   If it fails, show the error and ask the user to verify the ID.

2. Read the template and detect current sprint (same as create-pbi prompt).

3. Generate task fields:
   - **Title**: Concise task title from the description
   - **Type**: `"Task"`
   - **Area Path**: Inherit from parent PBI
   - **Iteration Path**: Current sprint (confirm with user)
   - **Description**: Task-level description

4. Present the task preview, showing the parent PBI for context:
   ```
   ## New Task Preview
   Parent PBI #<id>: <pbi-title>

   Task Title: <title>
   Area Path: <area_path> (inherited from parent)
   Sprint: <sprint>

   Description:
   <description>
   ```

5. On approval, create the task and link it:
   ```bash
   # Create the task
   bash scripts/ado-cli.sh --action create-work-item --params '{
     "type": "Task",
     "title": "<title>",
     "area_path": "<area_path>",
     "iteration_path": "<iteration_path>",
     "description": "<description>"
   }'
   # Link as child of PBI
   bash scripts/ado-cli.sh --action add-child --params '{"parent_id": <pbi_id>, "child_id": <new_task_id>}'
   ```

6. Report result with task ID, URL, and parent link.

## Output
Created task(s) with IDs, URLs, and parent PBI link.
