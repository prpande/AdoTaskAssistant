# Parse Reference Task

## Goal
Fetch a reference ADO work item and generate a reusable task template from it.

## Context
- ADO CLI: `bash scripts/ado-cli.sh --action show-work-item --params '{"id":<ID>}'`
- Template manager: `bash scripts/template-manager.sh`
- Template schema: `schemas/task-template.schema.md`

## Input
The user provides a work item ID or URL. If a URL is provided, extract the numeric ID from it.

## Instructions

1. Fetch the work item using the ADO CLI:
   ```bash
   bash scripts/ado-cli.sh --action show-work-item --params '{"id":<ID>}'
   ```
2. If the fetch fails, show the error message and guide the user to fix it:
   - **401/403**: PAT may be expired or missing scopes. Direct user to check `AZURE_DEVOPS_EXT_PAT`.
   - **404**: Work item ID may be wrong, or it's in a different project. Confirm org/project config.
   - **Connection error**: Check network and `az devops configure --defaults`.
3. On success, extract the template using the template manager.
   Write the work item JSON to a temp file and use `--params-file` to avoid shell escaping issues with backslashes in ADO paths:
   ```bash
   echo '<raw-work-item-json>' > /tmp/ado-extract-params.json
   bash scripts/template-manager.sh --action extract --params-file /tmp/ado-extract-params.json
   ```
4. Present the extracted template to the user in a readable format:
   - Show each field with its value
   - Highlight the area path and iteration pattern
   - Show the description format template
   - Show default tags and priority
5. Ask the user to review:
   - "Does this template look correct?"
   - "Would you like to change any fields or defaults?"
6. If the user requests changes, apply them.
   Write params to a temp file when they contain ADO paths with backslashes:
   ```bash
   echo '{"updates": {<changed-fields>}}' > /tmp/ado-update-params.json
   bash scripts/template-manager.sh --action update --params-file /tmp/ado-update-params.json
   ```
7. Save the final approved template:
   ```bash
   echo '<final-template-json>' > /tmp/ado-write-params.json
   bash scripts/template-manager.sh --action write --params-file /tmp/ado-write-params.json
   ```
8. Confirm: "Template saved to `data/task-template.json`. This will be used for all future PBI/Task creation."

## Output
The saved template file at `data/task-template.json`, reviewed and approved by the user.
