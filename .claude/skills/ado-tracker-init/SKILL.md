---
name: ado-tracker-init
description: Guided setup wizard for ADO Tracker — prerequisites, auth, template, config, and schedule
---

# ADO Tracker — Initialization Wizard

You are running the ADO Tracker setup wizard. Guide the user through each step sequentially. Each step flows into the next automatically — the user just answers prompts as they come. Do not wait for the user to trigger individual steps.

## Step 1: Prerequisites Check

Check each prerequisite and report status. For any failures, provide step-by-step fix instructions and wait for the user to resolve before continuing.

### GitHub CLI
```bash
gh auth status
```
- **Pass**: Shows authenticated user
- **Fail**: "GitHub CLI is not authenticated. Run `gh auth login` to authenticate, then tell me when you're ready."

### Azure CLI
```bash
az version
```
- **Pass**: Shows az version info
- **Fail**: "Azure CLI is not installed. Install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli — then tell me when you're ready."

### Azure DevOps Extension
```bash
az extension show --name azure-devops 2>/dev/null || echo "NOT_INSTALLED"
```
- **Pass**: Shows extension info
- **Fail**: "Azure DevOps extension is not installed. Run `az extension add --name azure-devops` — then tell me when you're ready."

### Notion MCP
- Check if Notion MCP tools are available (try `notion-search` with a test query)
- **Pass**: MCP responds
- **Fail**: "Notion MCP is not connected. Add it to your Claude Code MCP configuration. See https://github.com/anthropics/claude-code-mcp for setup instructions."

Report: "Prerequisites check complete. All tools are available."

## Step 2: Azure DevOps Authentication

Guide the user through PAT-based persistent auth:

1. Ask: "What is your Azure DevOps organization URL? (e.g., `https://dev.azure.com/your-org`)"
2. Ask: "What is your ADO project name?"
3. Ask: "What is your ADO team name? (e.g., `squad-biz-app`, `Business Experience`)"
4. Configure defaults:
   ```bash
   az devops configure --defaults organization=<org-url> project=<project-name>
   ```
5. Ask: "Do you already have an Azure DevOps Personal Access Token (PAT) set up, or do you need to create one?"
   - If they need to create one:
     - "Go to: `<org-url>/_usersettings/tokens`"
     - "Create a new token with these scopes: **Work Items** (Read & Write), **Project and Team** (Read), **Build** (Read)"
     - "Set expiration to the maximum allowed (up to 1 year recommended)"
     - "Copy the token — you won't be able to see it again"
   - If they have one: proceed to next step.
6. Ask: "Please set the `AZURE_DEVOPS_EXT_PAT` environment variable with your token. The best way depends on your shell:"
   - **bash/zsh**: `echo 'export AZURE_DEVOPS_EXT_PAT=<your-token>' >> ~/.bashrc && source ~/.bashrc`
   - **Windows (PowerShell)**: `[System.Environment]::SetEnvironmentVariable('AZURE_DEVOPS_EXT_PAT', '<your-token>', 'User')`
   - "Tell me when you've set it. You may need to restart your terminal for it to take effect."
7. After they confirm, verify: `echo $AZURE_DEVOPS_EXT_PAT | head -c 5` (just check it's set, don't display the full token)

## Step 3: Reference Task & Auth Validation

1. Ask: "Please provide a reference ADO work item ID or URL. This will be used as a template for all future task creation."
2. Extract the numeric ID from the URL if needed.
3. Attempt to fetch it:
   ```bash
   bash scripts/ado-cli.sh --action show-work-item --params '{"id":<id>}'
   ```
4. If it **fails**, parse the error and guide the user:
   - **"az: command not found"**: "Azure CLI is not in your PATH. Check your installation."
   - **"401"** or **"unauthorized"**: "Authentication failed. Check that `AZURE_DEVOPS_EXT_PAT` is set correctly and the token hasn't expired."
   - **"403"** or **"forbidden"**: "Access denied. Your PAT may be missing the required scopes (Work Items Read/Write)."
   - **"404"** or **"does not exist"**: "Work item not found. Verify the ID and that your org/project defaults are correct (`az devops configure --list`)."
   - **Other error**: Show the full error message. "Please check the error above and let me know when you've fixed it."
   - After each fix: re-attempt the fetch. Repeat until successful.
5. On **success**: "Successfully fetched work item #<id>: '<title>'. Auth is working correctly."
6. **Validate work item type**: Check `System.WorkItemType` in the response.
   - If it is not `"Product Backlog Item"`, warn: "This work item is a <type>, not a PBI. PBIs are recommended as reference items. Continue anyway?"
   - Wait for confirmation before proceeding.
7. **Extract ADO email**: Read `System.AssignedTo.uniqueName` from the work item fields and store it as `user.ado_email` for use in config.

## Step 4: Template Generation

1. Using the work item fetched in Step 3, extract the template.
   Save the raw work item JSON from the `show-work-item` response to a file, then use `build-params.sh`:
   ```bash
   # Save raw work item JSON (the .data field from show-work-item response) directly to file
   # NEVER use echo/heredoc — pipe az CLI output or use jq to write it
   bash scripts/build-params.sh --output /tmp/ado-extract-params.json \
     --slurp-file work_item /tmp/raw-work-item.json
   bash scripts/template-manager.sh --action extract --params-file /tmp/ado-extract-params.json
   ```
2. **Write the extracted template immediately** so it exists on disk before any edits:
   ```bash
   # Pipe the extracted data directly into a write operation
   bash scripts/template-manager.sh --action extract --params-file /tmp/ado-extract-params.json \
     | jq '.data' > /tmp/ado-write-params.json
   bash scripts/template-manager.sh --action write --params-file /tmp/ado-write-params.json
   ```
3. Present the saved template to the user in a readable format:
   - **Title prefix**: Show `pattern` and the extracted slot examples (slots are positional: slot_1, slot_2, etc.)
   - **Work type**: Show `default` and note that inference keywords are pre-configured for all 8 ADO work types
   - **Auto-populate**: Show which fields will be filled from activity sources (e.g., `Custom.Repo`)
   - **Area path** and **iteration pattern**
   - **Description format**: Show the Overview + Scope structure
   - **Fields**: Show remaining default field values
   - **Priority** and **tags**
4. Ask if the user wants to edit anything. If yes, apply edits using the `update` action (the template already exists on disk, so `update` will succeed):
   ```bash
   # Build a partial JSON with only the fields to change, then update
   jq -n '{...changed fields...}' > /tmp/ado-update-params.json
   bash scripts/template-manager.sh --action update --params-file /tmp/ado-update-params.json
   ```
5. "Template saved. This will be used for all future PBI/Task creation."

## Step 5: User Configuration

### Auto-detect User Identities

Before configuring data sources, detect the user's identity across tools:

1. **GitHub username** (already authenticated from Step 1):
   ```bash
   gh api user --jq .login
   ```
   Present: "Detected GitHub username: `<username>`. Correct?"
   If wrong, ask for the correct username.

2. **Notion user ID** — Search by the user's name or email:
   ```
   Use Notion MCP `notion-get-users` with query matching the user's name or ADO email.
   ```
   Present: "Found Notion account: `<name>` (`<email>`). Correct?"
   If not found, ask the user for their Notion email and retry. If still not found, skip (Notion scanning will use broader search).

3. **ADO email**: Already extracted from the reference work item in Step 3.

Save all detected identities. These will be written to the `user` section of `config.json` in the configuration step.

### Data Source Configuration

Prompt for each setting sequentially:

1. "Which GitHub organization(s) should I track? (comma-separated, e.g., `mindbodyonline`)"
2. "Any GitHub repos to exclude? (comma-separated `org/repo` format, or `none`)"
3. "For Notion, should I track all pages or only specific databases? (`all` / `databases`)"
   - If databases: "Which database IDs to exclude? (or `none`)"
4. "Which local git repos should I scan for commits?"
   - Offer auto-detect: "I can auto-detect repos under a parent directory. What's your source code root? (e.g., `C:/src`) Or provide specific paths."
5. "What time should the daily scan run? (HH:MM, 24h format, default: 09:00)"

Build `data/config.json` from the answers and save it. Use this structure:

```json
{
  "ado": { "organization": "...", "project": "...", "team": "..." },
  "user": {
    "ado_email": "<extracted from reference task>",
    "github_username": "<auto-detected>",
    "notion_user_id": "<auto-detected>"
  },
  "github": { "...": "..." },
  "notion": {
    "scope": "...",
    "excluded_databases": [],
    "filter_types": ["page"]
  },
  "git": { "...": "..." },
  "schedule": {
    "daily_scan_time": "<HH:MM>"
  },
  "proposal_grouping": {
    "consolidate_reviews_per_sprint": true,
    "exclude_title_patterns": []
  }
}
```

The `proposal_grouping` block ships with sensible defaults and does not need to be prompted during initial setup — the user can edit it later to tune how scans are grouped and filtered. Mention it briefly in the summary: "Review PRs will be grouped into a single PBI per sprint by default. Add regex patterns to `proposal_grouping.exclude_title_patterns` if you want to drop routine work (e.g., daily automated sweeps) from future proposals."

Present a summary for confirmation.

## Step 6: First Run (Optional)

"Setup is complete! Would you like to run an initial scan now?"
- If yes: "What date range? (e.g., `last week`, `2026-03-20 to 2026-03-27`, or `today`)"
  - Execute `automations/ado-tracker-scan.automation.md` with `mode: "adhoc"` and the specified range.
- If no: "No problem. You can run `/ado-tracker-daily` anytime, or wait for the scheduled run."

## Step 7: Schedule

"Would you like to set up the daily automated scan now?"
- If yes: "I'll configure a `/loop` schedule to run the daily scan at <configured-time> every day."
  - Set up the loop schedule.
  - "Daily scan scheduled. It will run at <time> and present proposed changes for your review."
- If no: "You can set this up later. Just run `/ado-tracker-daily` whenever you want."

"ADO Tracker is fully configured and ready to use!"
