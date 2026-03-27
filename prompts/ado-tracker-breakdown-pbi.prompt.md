# Break Down PBI

## Goal
Decompose an existing PBI into multiple smaller child tasks.

## Context
- ADO CLI: `bash scripts/ado-cli.sh`
- Template: `bash scripts/template-manager.sh --action read`
- Sprint: `bash scripts/ado-cli.sh --action current-sprint`

## Input
- `pbi_id`: The PBI work item ID to break down

## Instructions

1. Fetch the PBI to understand what needs to be decomposed:
   ```bash
   bash scripts/ado-cli.sh --action show-work-item --params '{"id":<pbi_id>}'
   ```

2. Also check for any existing child tasks:
   ```bash
   bash scripts/ado-cli.sh --action query-work-items --params '{"wiql":"SELECT [System.Id], [System.Title], [System.State] FROM WorkItemLinks WHERE ([Source].[System.Id] = <pbi_id>) AND ([System.Links.LinkType] = '\''System.LinkTypes.Hierarchy-Forward'\'') MODE (MustContain)"}'
   ```

3. Read the template and detect current sprint.

4. Analyze the PBI title and description. Propose a breakdown into child tasks:
   - Each task should be a concrete, actionable unit of work
   - Tasks should cover the full scope of the PBI
   - If existing child tasks are found, account for them (don't duplicate)

5. Present the breakdown proposal:
   ```
   ## PBI #<id>: <pbi-title>
   Existing tasks: <count> (listed below if any)

   ## Proposed Breakdown
   1. Task: "<task-1-title>" — <one-line description>
   2. Task: "<task-2-title>" — <one-line description>
   3. Task: "<task-3-title>" — <one-line description>

   Sprint: <sprint>
   Area Path: <area_path>
   ```

6. Ask user to review: "Approve all, select specific tasks, or edit any task before creating?"

7. Create approved tasks and link each as a child:
   ```bash
   # For each approved task:
   bash scripts/ado-cli.sh --action create-work-item --params '{...}'
   bash scripts/ado-cli.sh --action add-child --params '{"parent_id": <pbi_id>, "child_id": <task_id>}'
   ```

8. Report all created tasks with IDs and URLs.

## Output
List of created child tasks with IDs, URLs, and parent link.
