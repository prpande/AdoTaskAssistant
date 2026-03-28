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

3. **Title**: Build the title using the template's `title_prefix`:
   - Read `title_prefix.pattern` and `title_prefix.slots` from template
   - For each slot in `slots`, ask the user to provide a value. Show the slot's `description` and `examples`.
     Example prompt: "slot_1 — Title tag 1 (from reference: Backend). Examples: Backend. Your value:"
   - Assemble: replace each `{slot_N}` in `pattern` with the user's value, append the descriptive title
   - Example result: `[BizApp][Backend] Add retry logic`

4. **Work Type**: Ask the user to pick from the 8 available work types:
   - Customer Committed Features
   - Dedicated Tech Excellence
   - New Feature Development
   - Production Support & Incident remediation
   - Production Systems & Operations
   - Reliability & Stabilization
   - Security & Compliance
   - Software Maintenance
   - Default to `work_type.default` from template

5. **Description**: Format using `description_format` from template:
   - `{overview}`: Summarize the user's description — what is being done and why
   - `{scope}`: Detailed bullet list of what's included and what's out of scope

6. **Other fields**:
   - **Area Path**: From template
   - **Iteration Path**: Current sprint (replace placeholders in `iteration_path_pattern`)
   - **State**: Ask user (default: New)
   - **Assigned To**: `user.ado_email` from config
   - **Priority**: Template default
   - **Additional fields**: From template `fields` section
   - **Work Type field**: Set `ScrumMB.WorkType` to the user's selection from step 4

7. Present preview. Ask user to confirm or edit.

8. On approval, create.
   Use `build-params.sh` to safely construct JSON (handles backslash escaping in ADO paths):
   ```bash
   bash scripts/build-params.sh --output /tmp/ado-create-pbi-params.json \
     --arg type "Product Backlog Item" \
     --arg title "..." \
     --arg area_path "..." \
     --arg iteration_path "..." \
     --arg description "..." \
     --arg assigned_to "..." \
     --arg state "..." \
     --argjson fields '{"Microsoft.VSTS.Common.Priority":4,"Microsoft.VSTS.Common.ValueArea":"Business","ScrumMB.WorkType":"..."}'
   bash scripts/ado-cli.sh --action create-work-item --params-file /tmp/ado-create-pbi-params.json
   ```

9. Report result with work item ID and URL.

## Output
Created PBI with ID and URL.
