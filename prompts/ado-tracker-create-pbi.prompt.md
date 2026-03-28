# Create PBI

## Goal
Create a new Product Backlog Item in ADO using the saved template.

## Context
- ADO CLI: `bash scripts/ado-cli.sh`
- Template: `bash scripts/template-manager.sh --action read`
- Config: `data/config.json`

## Input
The user provides a description of the work item.

## Instructions

1. Read template and config. If either is missing → direct user to `/ado-tracker-init`.

2. Detect current sprint:
   ```bash
   bash scripts/ado-cli.sh --action current-sprint
   ```

3. Generate PBI fields:
   - **Title**: Apply `title_prefix_pbi` from template. Prompt user for `{featureArea}` placeholder value. Example: `[BizApp][Backend][Scheduling] Add retry logic`
   - **Description**: Format using `description_format` from template
   - **Area Path**: From template
   - **Iteration Path**: Current sprint
   - **State**: Ask user (default: New)
   - **Assigned To**: `user.ado_email` from config
   - **Priority**: Template default
   - **Additional fields**: From template `fields` section

4. Present preview. Ask user to confirm or edit.

5. On approval, create.
   Use `build-params.sh` to safely construct JSON (handles backslash escaping in ADO paths):
   ```bash
   bash scripts/build-params.sh --output /tmp/ado-create-pbi-params.json \
     --arg type "Product Backlog Item" \
     --arg title "..." \
     --arg area_path "MBScrum\Business Experience\squad-biz-app" \
     --arg iteration_path "MBScrum\Sprint 2026-07" \
     --arg description "..." \
     --arg assigned_to "..." \
     --arg state "..." \
     --argjson fields '{"Custom.Repo":"...","Microsoft.VSTS.Common.Priority":2}'
   bash scripts/ado-cli.sh --action create-work-item --params-file /tmp/ado-create-pbi-params.json
   ```

6. Report result with work item ID and URL.

## Output
Created PBI with ID and URL.
