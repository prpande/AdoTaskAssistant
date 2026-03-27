# Create PBI

## Goal
Create a new Product Backlog Item in ADO from a user-provided description, using the saved template.

## Context
- ADO CLI: `bash scripts/ado-cli.sh`
- Template: `bash scripts/template-manager.sh --action read`
- Sprint: `bash scripts/ado-cli.sh --action current-sprint`

## Input
The user provides a description of the work item. This can be a single sentence or a detailed description.

## Instructions

1. Read the template:
   ```bash
   bash scripts/template-manager.sh --action read
   ```
   If template is missing, tell the user to run `/ado-tracker-init` first.

2. Detect current sprint:
   ```bash
   bash scripts/ado-cli.sh --action current-sprint
   ```
   Present the sprint to the user for confirmation.

3. Generate PBI fields from the user's description and the template:
   - **Title**: Concise, actionable title derived from the description
   - **Description**: Formatted using `description_format` from the template, with the user's description as the summary
   - **Area Path**: From template
   - **Iteration Path**: Current sprint iteration path
   - **Tags**: Template defaults
   - **Priority**: Template default (user can override)

4. Present the full PBI preview to the user:
   ```
   ## New PBI Preview
   Title: <title>
   Type: Product Backlog Item
   Area Path: <area_path>
   Sprint: <sprint>
   Priority: <priority>
   Tags: <tags>

   Description:
   <formatted-description>
   ```

5. Ask: "Create this PBI? You can edit any field before confirming."

6. On approval, create the work item:
   ```bash
   bash scripts/ado-cli.sh --action create-work-item --params '{...}'
   ```

7. Report the result with the new work item ID and URL.

## Output
Created PBI with ID and URL.
