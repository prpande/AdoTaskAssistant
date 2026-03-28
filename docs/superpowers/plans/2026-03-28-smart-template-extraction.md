# Smart Template Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enrich template extraction to auto-derive title prefix patterns, work type inference, auto-populate fields, and a description format with Overview + Scope.

**Architecture:** All intelligence lives in the `extract_template()` jq filter in `template-manager.sh`. The enriched template schema drives all PBI/task creation prompts. No new scripts needed — just a richer jq filter and updated prompt instructions.

**Tech Stack:** bash, jq, markdown prompts

---

### Task 1: Update `extract_template()` jq filter

**Files:**
- Modify: `scripts/template-manager.sh:131-199`

- [ ] **Step 1: Replace the `extract_template()` jq filter**

Replace the entire jq expression inside `extract_template()` (lines 142-196) with the new filter that produces the enriched schema. The new filter:
- Parses bracket-delimited title prefix (`[A] [B] [C] Description...`)
- Extracts `ScrumMB.WorkType` as `work_type.default`
- Seeds `work_type.inference_keywords` as a constant
- Detects `Custom.Repo` → adds to `auto_populate_from_source`
- Excludes all `Custom.*` booleans, `Custom.Repo`, `ScrumMB.WorkType` from `fields`
- Uses new `description_format`

Replace lines 142-196 in `scripts/template-manager.sh` with:

```bash
    template=$(printf '%s' "$work_item" | jq '
      # --- Title prefix parsing ---
      (.fields["System.Title"] // "") as $title |
      # Extract all leading [bracket] groups with optional whitespace between them
      ($title | [scan("\\[([^\\]]+)\\]")] | map(.[0])) as $brackets |
      (if ($brackets | length) == 0 then
        { static: "", pattern: "{title}", slots: {} }
      elif ($brackets | length) == 1 then
        { static: ("["+ $brackets[0] + "]"), pattern: ("[" + $brackets[0] + "][{layer}][{feature}]"),
          slots: {
            layer: { description: "Code layer", examples: ["Backend", "Frontend", "Infra"] },
            feature: { description: "Feature area or acronym", examples: [] }
          }
        }
      elif ($brackets | length) == 2 then
        { static: ("[" + $brackets[0] + "]"),
          pattern: ("[" + $brackets[0] + "][{layer}][{feature}]"),
          slots: {
            layer: { description: "Code layer", examples: [$brackets[1]] },
            feature: { description: "Feature area or acronym", examples: [] }
          }
        }
      else
        { static: ("[" + $brackets[0] + "]"),
          pattern: ("[" + $brackets[0] + "][{layer}][{feature}]"),
          slots: {
            layer: { description: "Code layer", examples: [$brackets[1]] },
            feature: { description: "Feature area or acronym", examples: [$brackets[2]] }
          }
        }
      end) as $title_prefix |

      # --- Work type ---
      { default: (.fields["ScrumMB.WorkType"] // "New Feature Development"),
        inference_keywords: {
          "Customer Committed Features": ["customer", "committed", "client-requested"],
          "Dedicated Tech Excellence": ["tech-excellence", "innovation", "spike", "poc", "prototype"],
          "New Feature Development": ["add", "implement", "create", "expose", "enable", "feature"],
          "Production Support & Incident remediation": ["incident", "outage", "p1", "p2", "sev1", "sev2", "hotfix", "emergency"],
          "Production Systems & Operations": ["infra", "deploy", "pipeline", "ci/cd", "monitoring", "alerting"],
          "Reliability & Stabilization": ["fix", "bug", "flaky", "stabilize", "reliability", "retry", "resilience"],
          "Security & Compliance": ["security", "vulnerability", "cve", "compliance", "audit", "gdpr", "pci"],
          "Software Maintenance": ["update", "upgrade", "migrate", "bump", "deprecate", "refactor", "cleanup", "debt"]
        }
      } as $work_type |

      # --- Auto-populate from source ---
      (if .fields["Custom.Repo"] then {"Custom.Repo": "repo_name"} else {} end) as $auto_populate |

      # --- Build template ---
      {
        source_work_item_id: .id,
        work_item_type: .fields["System.WorkItemType"],
        area_path: .fields["System.AreaPath"],
        iteration_path_pattern: (
          .fields["System.IterationPath"]
          | if . then
              (split("\\\\") | last | gsub("[0-9]{4}"; "{year}") | gsub("\\{year\\}-[0-9]+"; "{year}-{sprint_number}")) as $last_part |
              (split("\\\\") | .[:-1] + [$last_part] | join("\\"))
            else null end
        ),
        title_prefix: $title_prefix,
        work_type: $work_type,
        auto_populate_from_source: $auto_populate,
        fields: (
          .fields
          | del(
              .["System.Id"], .["System.Rev"], .["System.Title"],
              .["System.Description"], .["System.AssignedTo"],
              .["System.CreatedBy"], .["System.CreatedDate"],
              .["System.ChangedBy"], .["System.ChangedDate"],
              .["System.AuthorizedDate"], .["System.RevisedDate"],
              .["System.Watermark"], .["System.CommentCount"],
              .["System.BoardColumn"], .["System.BoardColumnDone"],
              .["System.BoardLane"], .["System.WorkItemType"],
              .["System.AreaPath"], .["System.IterationPath"],
              .["System.State"], .["System.Reason"],
              .["System.History"], .["System.RelatedLinkCount"],
              .["System.ExternalLinkCount"], .["System.HyperLinkCount"],
              .["System.AttachedFileCount"], .["System.NodeName"],
              .["System.AreaId"], .["System.IterationId"],
              .["System.TeamProject"], .["System.PersonId"],
              .["System.AreaLevel1"], .["System.AreaLevel2"],
              .["System.AreaLevel3"], .["System.IterationLevel1"],
              .["System.IterationLevel2"], .["System.AuthorizedAs"],
              .["ScrumMB.WorkType"], .["Custom.Repo"]
          )
          # Exclude all Custom.* boolean fields
          | with_entries(select(
              (.key | startswith("Custom.") | not) or (.value | type != "boolean")
          ))
          # Exclude WEF_ fields (board metadata)
          | with_entries(select(.key | startswith("WEF_") | not))
          # Exclude MB.* fields (release metadata)
          | with_entries(select(.key | startswith("MB.") | not))
          | with_entries(select(.value != null and .value != "" and .value != 0))
        ),
        description_format: "## Overview\n{overview}\n\n## Scope\n{scope}",
        tags: (
          .fields["System.Tags"]
          | if . and . != "" then split("; ") else [] end
        ),
        priority: (.fields["Microsoft.VSTS.Common.Priority"] // 2)
      }
    ')
```

- [ ] **Step 2: Test extraction with the reference work item**

```bash
# Create a test work item JSON matching the reference item
jq -n \
  --arg ap 'MBScrum\Business Experience\squad-biz-app' \
  --arg ip 'MBScrum\Sprint 2024-21' \
  '{id: 1364772, fields: {
    "System.AreaPath": $ap,
    "System.IterationPath": $ip,
    "System.Title": "[BizApp] [Backend] Expose sorting parameter to FE via BFF",
    "System.WorkItemType": "Product Backlog Item",
    "Microsoft.VSTS.Common.Priority": 4,
    "Microsoft.VSTS.Common.ValueArea": "Business",
    "ScrumMB.WorkType": "New Feature Development",
    "Custom.Repo": "Mindbody.Mobile.BusinessGateway",
    "Custom.CustomerFacing": false,
    "Custom.Deployable": false,
    "Custom.Deployed": false,
    "Custom.HasImplementationSwitch": false,
    "Custom.LDFlagPresent": false,
    "Custom.ReadyforQATesting": false,
    "Custom.Releasable": false,
    "Custom.Released": false,
    "Custom.SAWork": false,
    "Custom.SwitchesAreReleased": false,
    "Custom.SwitchesAreRemoved": false
  }}' > /tmp/raw-work-item.json

bash scripts/build-params.sh --output /tmp/ado-extract-params.json \
  --slurp-file work_item /tmp/raw-work-item.json

bash scripts/template-manager.sh --action extract --params-file /tmp/ado-extract-params.json
```

Expected output:
- `title_prefix.static` = `"[BizApp]"`
- `title_prefix.pattern` = `"[BizApp][{layer}][{feature}]"`
- `title_prefix.slots.layer.examples` = `["Backend"]`
- `work_type.default` = `"New Feature Development"`
- `auto_populate_from_source` = `{"Custom.Repo": "repo_name"}`
- `fields` does NOT contain `Custom.*` booleans, `Custom.Repo`, or `ScrumMB.WorkType`
- `description_format` = `"## Overview\n{overview}\n\n## Scope\n{scope}"`

- [ ] **Step 3: Test with a title that has 3 brackets**

```bash
jq -n --arg ap 'MBScrum\Test' --arg ip 'MBScrum\Sprint 2024-21' \
  '{id: 99999, fields: {
    "System.AreaPath": $ap, "System.IterationPath": $ip,
    "System.Title": "[BizApp] [Frontend] [Scheduling] Add calendar view",
    "System.WorkItemType": "Product Backlog Item"
  }}' > /tmp/raw-wi-3brackets.json

bash scripts/build-params.sh --output /tmp/ado-extract-3.json \
  --slurp-file work_item /tmp/raw-wi-3brackets.json

bash scripts/template-manager.sh --action extract --params-file /tmp/ado-extract-3.json
```

Expected: `slots.layer.examples` = `["Frontend"]`, `slots.feature.examples` = `["Scheduling"]`

- [ ] **Step 4: Test with a title that has no brackets**

```bash
jq -n --arg ap 'MBScrum\Test' --arg ip 'MBScrum\Sprint 2024-21' \
  '{id: 99998, fields: {
    "System.AreaPath": $ap, "System.IterationPath": $ip,
    "System.Title": "Fix login timeout bug",
    "System.WorkItemType": "Product Backlog Item"
  }}' > /tmp/raw-wi-nobrackets.json

bash scripts/build-params.sh --output /tmp/ado-extract-nb.json \
  --slurp-file work_item /tmp/raw-wi-nobrackets.json

bash scripts/template-manager.sh --action extract --params-file /tmp/ado-extract-nb.json
```

Expected: `title_prefix.static` = `""`, `title_prefix.pattern` = `"{title}"`, `slots` = `{}`

- [ ] **Step 5: Commit**

```bash
git add scripts/template-manager.sh
git commit -m "feat: enrich extract_template with title prefix, work type, auto-populate"
```

---

### Task 2: Update `validate_template()` required fields

**Files:**
- Modify: `scripts/template-manager.sh:102-129`

- [ ] **Step 1: Update required fields list**

The current validation checks for `title_prefix_pbi` which no longer exists. Update the `required_fields` array in `validate_template()`.

Replace line 111:
```bash
    local required_fields=("work_item_type" "area_path" "iteration_path_pattern" "title_prefix_pbi" "description_format")
```

With:
```bash
    local required_fields=("work_item_type" "area_path" "iteration_path_pattern" "description_format")
```

The `title_prefix` object is validated structurally — a missing `title_prefix` is acceptable (the system will ask the user for the full title).

- [ ] **Step 2: Test validation**

```bash
# First run the extraction from Task 1 to create a template, then validate
bash scripts/template-manager.sh --action extract --params-file /tmp/ado-extract-params.json | jq '.data' > data/task-template.json
bash scripts/template-manager.sh --action validate
```

Expected: `{"success": true, "data": {"valid": true, ...}}`

- [ ] **Step 3: Commit**

```bash
git add scripts/template-manager.sh
git commit -m "fix: update validate_template required fields for new schema"
```

---

### Task 3: Update schema doc

**Files:**
- Modify: `schemas/task-template.schema.md`

- [ ] **Step 1: Replace schema doc contents**

Replace the entire contents of `schemas/task-template.schema.md` with:

```markdown
# Task Template Schema

## File Location
`data/task-template.json` (gitignored, generated from reference task)

## Purpose
Defines the reusable structure for creating new ADO work items. Generated once from a reference work item via `/ado-tracker-init`, then used for all future PBI/Task creation.

## Fields

| Field | Type | Description |
|-------|------|-------------|
| `source_work_item_id` | number | ID of the reference work item this template was derived from. |
| `work_item_type` | string | e.g., `"Product Backlog Item"` |
| `area_path` | string | e.g., `"MBScrum\\Business Experience\\squad-biz-app"` |
| `iteration_path_pattern` | string | e.g., `"MBScrum\\Sprint {year}-{sprint_number}"` — placeholders replaced with current sprint. |
| `title_prefix` | object | Title prefix configuration (see below). |
| `title_prefix.static` | string | Fixed portion always prepended. e.g., `"[BizApp]"` |
| `title_prefix.pattern` | string | Full pattern with slots. e.g., `"[BizApp][{layer}][{feature}]"` |
| `title_prefix.slots` | object | Map of slot name → `{description, examples}`. |
| `work_type` | object | Work type configuration (see below). |
| `work_type.default` | string | Default work type. e.g., `"New Feature Development"` |
| `work_type.inference_keywords` | object | Map of work type → keyword array for inference from activity. |
| `auto_populate_from_source` | object | Map of ADO field name → activity source key. e.g., `{"Custom.Repo": "repo_name"}` |
| `fields` | object | Key-value pairs of ADO field reference names to default values. |
| `description_format` | string | Markdown template. Supports placeholders: `{overview}`, `{scope}`. |
| `tags` | string[] | Default tags to apply. |
| `priority` | number | Default priority (1-4). |

## Example

```json
{
  "source_work_item_id": 1364772,
  "work_item_type": "Product Backlog Item",
  "area_path": "MBScrum\\Business Experience\\squad-biz-app",
  "iteration_path_pattern": "MBScrum\\Sprint {year}-{sprint_number}",
  "title_prefix": {
    "static": "[BizApp]",
    "pattern": "[BizApp][{layer}][{feature}]",
    "slots": {
      "layer": { "description": "Code layer", "examples": ["Backend"] },
      "feature": { "description": "Feature area or acronym", "examples": [] }
    }
  },
  "work_type": {
    "default": "New Feature Development",
    "inference_keywords": {
      "Customer Committed Features": ["customer", "committed", "client-requested"],
      "Dedicated Tech Excellence": ["tech-excellence", "innovation", "spike", "poc", "prototype"],
      "New Feature Development": ["add", "implement", "create", "expose", "enable", "feature"],
      "Production Support & Incident remediation": ["incident", "outage", "p1", "p2", "sev1", "sev2", "hotfix", "emergency"],
      "Production Systems & Operations": ["infra", "deploy", "pipeline", "ci/cd", "monitoring", "alerting"],
      "Reliability & Stabilization": ["fix", "bug", "flaky", "stabilize", "reliability", "retry", "resilience"],
      "Security & Compliance": ["security", "vulnerability", "cve", "compliance", "audit", "gdpr", "pci"],
      "Software Maintenance": ["update", "upgrade", "migrate", "bump", "deprecate", "refactor", "cleanup", "debt"]
    }
  },
  "auto_populate_from_source": {
    "Custom.Repo": "repo_name"
  },
  "fields": {
    "Microsoft.VSTS.Common.Priority": 4,
    "Microsoft.VSTS.Common.ValueArea": "Business"
  },
  "description_format": "## Overview\n{overview}\n\n## Scope\n{scope}",
  "tags": [],
  "priority": 4
}
```

## What Is Extracted From Reference Task
- Area path
- Iteration path (converted to pattern with `{year}` and `{sprint_number}` placeholders)
- Work item type
- Title prefix pattern (bracket groups parsed into static + slot structure)
- Work type default (from `ScrumMB.WorkType`)
- Work type inference keywords (constant map of all 8 ADO work types)
- Auto-populate mapping (e.g., `Custom.Repo` from activity source)
- Non-instance, non-boolean field values (priority, value area)
- Tags
- Priority

## What Is Filtered Out
- Instance-specific fields (title, description, assigned-to, created-by, dates)
- All `Custom.*` boolean fields (ADO defaults them)
- `Custom.Repo` (auto-populated from activity source at creation time)
- `ScrumMB.WorkType` (moved to `work_type` section)
- Board metadata (`WEF_*` fields)
- Release metadata (`MB.*` fields)
- Attachments, comments, relations/links, history
```

- [ ] **Step 2: Commit**

```bash
git add schemas/task-template.schema.md
git commit -m "docs: update task template schema for enriched extraction"
```

---

### Task 4: Update `ado-tracker-create-pbi.prompt.md`

**Files:**
- Modify: `prompts/ado-tracker-create-pbi.prompt.md`

- [ ] **Step 1: Update prompt instructions**

Replace the entire contents of `prompts/ado-tracker-create-pbi.prompt.md` with:

```markdown
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
   - For each slot, ask the user to provide a value. Show the slot's `description` and `examples`.
     Example prompt: "Layer (e.g., Backend, Frontend, Infra):"
   - Assemble: replace each `{slot}` in `pattern` with the user's value, append the descriptive title
   - Example result: `[BizApp][Backend][Scheduling] Add retry logic`

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
```

- [ ] **Step 2: Commit**

```bash
git add prompts/ado-tracker-create-pbi.prompt.md
git commit -m "feat: update create-pbi prompt for title prefix slots, work type, new description format"
```

---

### Task 5: Update `ado-tracker-apply-updates.prompt.md`

**Files:**
- Modify: `prompts/ado-tracker-apply-updates.prompt.md`

- [ ] **Step 1: Update the description format section**

Replace step 2 (lines 64-74) in `prompts/ado-tracker-apply-updates.prompt.md`:

```
2. Always embed source URLs in descriptions. Use the template's `description_format`:
   ```
   ## Summary
   <summary>

   ## Source
   <PR links, Notion links, commit refs>

   ## Date
   <activity date range>
   ```
```

With:

```
2. Format descriptions using the template's `description_format`:
   - `{overview}`: Summarize from activity source — PR description, Notion page summary, or commit messages
   - `{scope}`: Bullet list of specific changes included — PR links, commit refs, Notion page links
   Include source URLs in the scope section for future dedup matching.

3. **Auto-populate fields**: Read `auto_populate_from_source` from template. For each entry, map the activity source to the ADO field value. For example, if `Custom.Repo` → `repo_name`, set `Custom.Repo` to the repository name from the PR or commit source. Include these in the `fields` object when building params.

4. **Work Type**: Set `ScrumMB.WorkType` in fields using the work type from the proposal (inferred by propose-updates and confirmed by user).
```

Also renumber subsequent steps (old 3→5, old 4→6, old 5→7).

- [ ] **Step 2: Commit**

```bash
git add prompts/ado-tracker-apply-updates.prompt.md
git commit -m "feat: update apply-updates prompt for new description format, auto-populate, work type"
```

---

### Task 6: Update `ado-tracker-propose-updates.prompt.md`

**Files:**
- Modify: `prompts/ado-tracker-propose-updates.prompt.md`

- [ ] **Step 1: Update Phase 4 (Determine state) to include work type inference and title prefix**

Replace Phase 4 (lines 51-63) in `prompts/ado-tracker-propose-updates.prompt.md`:

```
### Phase 4: Determine state

Apply the template's `title_prefix_pbi` to PBI titles (prompt user for `{featureArea}` if needed).
```

With:

```
### Phase 4: Determine title, work type, and state

**Title prefix**: Read `title_prefix.pattern` and `title_prefix.slots` from template. For each proposed PBI:
- The `static` portion (e.g., `[BizApp]`) is always included
- For each slot, infer a value from context (repo name, PR title, activity type) or leave as `{slot}` for user to fill during review

**Work type inference**: For each proposed PBI, infer `ScrumMB.WorkType` from activity text:
1. Collect text signals: PR titles, commit messages, Notion page titles
2. Lowercase all text, scan against `work_type.inference_keywords` from template
3. Count keyword matches per work type category. Highest score wins.
4. Tie or no matches → use `work_type.default` from template
5. Include the inferred work type in the proposal for user to confirm or change

**Auto-populate fields**: Read `auto_populate_from_source` from template. For each mapping (e.g., `Custom.Repo` → `repo_name`), populate the field from the activity source.
```

Also update the Phase 6 proposal format (line 86) to show work type:
```
1. [BizApp][Backend][Feature] Title — source summary
```
becomes:
```
1. [BizApp][Backend][Feature] Title — Work Type: New Feature Development
   Tasks: task1 (Done), task2 (In Progress)
```

And update the output JSON schema (lines 109-121) to include `work_type` and `fields` in the PBI object:
```json
{
  "action": "create",
  "sprint_path": "MBScrum\\Sprint 2026-07",
  "pbi": {"title": "...", "description": "...", "state": "Committed", "assigned_to": "...", "work_type": "New Feature Development", "fields": {"Custom.Repo": "org/repo-name"}},
  "tasks": [{"title": "...", "state": "Done", "description": "..."}]
}
```

- [ ] **Step 2: Commit**

```bash
git add prompts/ado-tracker-propose-updates.prompt.md
git commit -m "feat: update propose-updates with work type inference, title prefix, auto-populate"
```

---

### Task 7: Update `ado-tracker-create-task.prompt.md` and `ado-tracker-breakdown-pbi.prompt.md`

**Files:**
- Modify: `prompts/ado-tracker-create-task.prompt.md`
- Modify: `prompts/ado-tracker-breakdown-pbi.prompt.md`

- [ ] **Step 1: Update create-task description instructions**

In `prompts/ado-tracker-create-task.prompt.md`, replace step 3 item for Description (line 30):
```
   - **Description**: Task-level description
```
With:
```
   - **Description**: Format using `description_format` from template:
     - `{overview}`: Brief task purpose — what this task accomplishes
     - `{scope}`: Specific deliverables — what exactly will be done
```

- [ ] **Step 2: Update breakdown-pbi description instructions**

In `prompts/ado-tracker-breakdown-pbi.prompt.md`, add description guidance after step 4 (line 28), within the task proposal section:

After line 28 (`- Show existing children so the user can see what's already covered`), add:

```
   - For each proposed task, generate a description using `description_format` from template:
     - `{overview}`: What the task accomplishes in the context of the parent PBI
     - `{scope}`: Specific deliverables and acceptance criteria for this task
```

- [ ] **Step 3: Commit**

```bash
git add prompts/ado-tracker-create-task.prompt.md prompts/ado-tracker-breakdown-pbi.prompt.md
git commit -m "feat: update task prompts with new description format placeholders"
```

---

### Task 8: Update init skill and CLAUDE.md

**Files:**
- Modify: `.claude/skills/ado-tracker-init/SKILL.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update init skill template presentation**

In `.claude/skills/ado-tracker-init/SKILL.md`, update Step 4 item 2 (line 97) to present the enriched template:

Replace:
```
2. Present the template to the user (follow the parse-reference-task prompt instructions).
```
With:
```
2. Present the extracted template to the user in a readable format:
   - **Title prefix**: Show `pattern` (e.g., `[BizApp][{layer}][{feature}]`) and the extracted slot examples
   - **Work type**: Show `default` and note that inference keywords are pre-configured
   - **Auto-populate**: Show which fields will be filled from activity sources (e.g., `Custom.Repo`)
   - **Area path** and **iteration pattern**
   - **Description format**: Show the Overview + Scope structure
   - **Fields**: Show remaining default field values
   - **Priority** and **tags**
```

Also update the `desc_format` value in the write step (line 103):
Replace:
```
     --arg desc_format "## Summary\n{summary}\n\n## Source\n{source}\n\n## Date\n{date}" \
```
With:
```
     --arg desc_format "## Overview\n{overview}\n\n## Scope\n{scope}" \
```

- [ ] **Step 2: Update CLAUDE.md template section**

In `CLAUDE.md`, update the template description (line 38):
Replace:
```
- `data/task-template.json` — PBI/Task creation template (title_prefix_pbi, description_format, fields)
```
With:
```
- `data/task-template.json` — PBI/Task creation template (title_prefix with pattern/slots, work_type with inference keywords, auto_populate_from_source, description_format, fields)
```

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/ado-tracker-init/SKILL.md CLAUDE.md
git commit -m "docs: update init skill and CLAUDE.md for enriched template schema"
```

---

### Task 9: Update `ado-tracker-parse-reference-task.prompt.md`

**Files:**
- Modify: `prompts/ado-tracker-parse-reference-task.prompt.md`

- [ ] **Step 1: Update presentation and edit instructions**

In `prompts/ado-tracker-parse-reference-task.prompt.md`, update step 4 (lines 30-34) to present the enriched template:

Replace:
```
4. Present the extracted template to the user in a readable format:
   - Show each field with its value
   - Highlight the area path and iteration pattern
   - Show the description format template
   - Show default tags and priority
```
With:
```
4. Present the extracted template to the user in a readable format:
   - **Title prefix**: Show `pattern` and slot examples extracted from the title
   - **Work type**: Show `default` value; note that inference keywords are pre-configured for all 8 ADO work types
   - **Auto-populate**: Show which fields will be auto-filled from activity sources
   - **Area path** and **iteration pattern**
   - **Description format**: Show the Overview + Scope structure
   - **Fields**: Show remaining default values (priority, value area)
   - **Tags**
```

- [ ] **Step 2: Commit**

```bash
git add prompts/ado-tracker-parse-reference-task.prompt.md
git commit -m "docs: update parse-reference-task prompt for enriched template presentation"
```

---

### Task 10: End-to-end validation

- [ ] **Step 1: Run full extraction pipeline**

```bash
# Simulate the init wizard flow with the real reference work item shape
jq -n \
  --arg ap 'MBScrum\Business Experience\squad-biz-app' \
  --arg ip 'MBScrum\Sprint 2024-21' \
  '{id: 1364772, fields: {
    "System.AreaPath": $ap,
    "System.IterationPath": $ip,
    "System.Title": "[BizApp] [Backend] Expose sorting parameter to FE via BFF",
    "System.WorkItemType": "Product Backlog Item",
    "Microsoft.VSTS.Common.Priority": 4,
    "Microsoft.VSTS.Common.ValueArea": "Business",
    "ScrumMB.WorkType": "New Feature Development",
    "Custom.Repo": "Mindbody.Mobile.BusinessGateway",
    "Custom.CustomerFacing": false, "Custom.Deployable": false,
    "Custom.Deployed": false, "Custom.HasImplementationSwitch": false,
    "Custom.LDFlagPresent": false, "Custom.ReadyforQATesting": false,
    "Custom.Releasable": false, "Custom.Released": false,
    "Custom.SAWork": false, "Custom.SwitchesAreReleased": false,
    "Custom.SwitchesAreRemoved": false
  }}' > /tmp/raw-work-item.json

bash scripts/build-params.sh --output /tmp/ado-extract-params.json \
  --slurp-file work_item /tmp/raw-work-item.json

RESULT=$(bash scripts/template-manager.sh --action extract --params-file /tmp/ado-extract-params.json)
echo "$RESULT" | jq '.data'
```

Verify:
- `title_prefix.static` = `"[BizApp]"`
- `title_prefix.pattern` = `"[BizApp][{layer}][{feature}]"`
- `title_prefix.slots.layer.examples` = `["Backend"]`
- `work_type.default` = `"New Feature Development"`
- `work_type.inference_keywords` has all 8 entries
- `auto_populate_from_source.["Custom.Repo"]` = `"repo_name"`
- `fields` contains only `Microsoft.VSTS.Common.Priority` and `Microsoft.VSTS.Common.ValueArea`
- `description_format` = `"## Overview\n{overview}\n\n## Scope\n{scope}"`
- No `Custom.*` booleans in `fields`

- [ ] **Step 2: Write template and validate**

```bash
echo "$RESULT" | jq '.data' > data/task-template.json
bash scripts/template-manager.sh --action validate
```

Expected: `{"success": true, "data": {"valid": true, ...}}`

- [ ] **Step 3: Final commit with any fixes**

```bash
git add -A
git commit -m "test: verify end-to-end smart template extraction"
```
