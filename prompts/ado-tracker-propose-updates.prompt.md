# Propose ADO Updates

## Goal
Take gathered activity from all sources, cross-reference with existing ADO work items, and present a grouped proposal for the user to approve.

## Context
- ADO CLI: `bash scripts/ado-cli.sh`
- Template: `bash scripts/template-manager.sh --action read`
- Activity data: Passed in as JSON from the gathering prompts

## Input
- `activity`: Combined JSON array from all gather prompts (GitHub, Notion, sessions/git)
- `sprint`: Current sprint name and iteration path
- `last_run`: Data from `data/last-run.json`

## Instructions

1. Read the task template:
   ```bash
   bash scripts/template-manager.sh --action read
   ```

2. Query ADO for existing work items in the current sprint that may match the activity:
   ```bash
   bash scripts/ado-cli.sh --action query-work-items --params '{"wiql":"SELECT [System.Id], [System.Title], [System.State], [System.Tags] FROM WorkItems WHERE [System.IterationPath] = '\''<iteration-path>'\'' AND [System.AssignedTo] = @Me ORDER BY [System.CreatedDate] DESC"}'
   ```

3. For each activity item, classify it:
   - **CREATE** — No matching ADO work item found. Propose creating a new PBI using the template.
   - **UPDATE** — A matching ADO work item exists (by title similarity, linked PR, or tag). Propose updating it (e.g., adding a link, updating description).
   - **CLOSE** — A matching ADO work item exists and the activity indicates completion (PR merged, task done).
   - **SKIP** — Activity is too minor or already tracked. Note why.

4. Present the proposal grouped by source, using this format:

   ```
   ## GitHub PRs
     1. [+] Create PBI: "Add retry logic to payment webhook" — PR #1234 in org/repo
     2. [~] Update PBI-5678: Add PR link — PR #1235 in org/repo

   ## Notion Pages
     3. [+] Create PBI: "Q2 onboarding flow redesign" — edited page "Onboarding Spec v2"

   ## Claude Sessions / Git
     4. [+] Create Task under PBI-9012: "Refactor auth middleware" — 4 commits in Mindbody.Api.Rest

   Sprint: Sprint-42 (auto-detected, unchanged)
   Area Path: Project\Team\Area

   Skipped:
     - Minor commit "fix typo" in AdoTaskAssistant (too minor)
   ```

5. After presenting, offer controls:
   - "Enter item numbers to approve (e.g., `1,3,4`), `all` to approve everything, or `none` to skip."
   - "Enter `expand <number>` to see full ADO task preview for any item."
   - "Enter `edit <number>` to modify the proposed title or details before approving."

6. Wait for user selection. Return the approved items as a JSON array with all fields needed for the apply step:
   ```json
   [
     {
       "action": "create",
       "work_item_type": "Product Backlog Item",
       "title": "Add retry logic to payment webhook",
       "description": "...",
       "area_path": "Project\\Team\\Area",
       "iteration_path": "Project\\Sprint-42",
       "source": {"type": "github_pr", "url": "..."},
       "fields": {}
     }
   ]
   ```

## Output
JSON array of approved update actions, ready for the apply prompt.
