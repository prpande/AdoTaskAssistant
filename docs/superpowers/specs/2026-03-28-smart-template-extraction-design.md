# Smart Template Extraction Design

## Problem

The current template extraction (`template-manager.sh extract`) produces a flat template with minimal intelligence. It dumps all non-instance fields into a `fields` blob, uses a hardcoded `title_prefix_pbi` string, and has a description format with placeholders (`{summary}`, `{source}`, `{date}`) that don't match how work items should actually be described. Users must manually configure most of the template after extraction.

## Goal

Make template extraction intelligent: parse the reference work item's structure to auto-derive title prefix patterns, work type defaults with inference rules, auto-populated fields, and a useful description format. The template becomes the single source of truth for how PBIs and tasks get created.

## Decisions (from brainstorming)

| Topic | Decision |
|-------|----------|
| Title prefix | Extract bracket pattern from reference title. User picks `{layer}` and `{feature}` slots at creation time. No auto-inference of slots. |
| Custom.* booleans | Exclude entirely. ADO defaults them to false. |
| Custom.Repo | Exclude from template `fields`. Auto-populate from activity source at creation time. |
| Work type | Default from reference. Infer from activity keywords. User confirms before creation. |
| Description format | `## Overview\n{overview}\n\n## Scope\n{scope}`. No date/source sections. |

## Template Schema

```json
{
  "source_work_item_id": 1364772,
  "work_item_type": "Product Backlog Item",
  "area_path": "MBScrum\\Business Experience\\squad-biz-app",
  "iteration_path_pattern": "MBScrum\\Sprint {year}-{sprint_number}",

  "title_prefix": {
    "static": "[BizApp]",
    "pattern": "[BizApp][{slot_1}]",
    "slots": {
      "slot_1": { "description": "Title tag 1 (from reference: Backend)", "examples": ["Backend"] }
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

### Schema changes from current

| Field | Before | After |
|-------|--------|-------|
| `title_prefix_pbi` | string (e.g., `"[BizApp]"`) | Removed. Replaced by `title_prefix` object. |
| `title_prefix` | Did not exist | Object: `static`, `pattern`, `slots` (positional: slot_1, slot_2, ...) |
| `work_type` | Did not exist (was inside `fields` as `ScrumMB.WorkType`) | Object: `default`, `inference_keywords` |
| `auto_populate_from_source` | Did not exist | Object mapping ADO field names to activity source keys |
| `description_format` | `"## Summary\n{summary}\n\n## Source\n{source}\n\n## Date\n{date}"` | `"## Overview\n{overview}\n\n## Scope\n{scope}"` |
| `fields` | Included all Custom.* booleans, Custom.Repo, ScrumMB.WorkType | Excludes Custom.* booleans, Custom.Repo, ScrumMB.WorkType (moved to dedicated sections) |

## Extraction Logic Changes

File: `scripts/template-manager.sh`, function `extract_template()`

### Title prefix parsing

1. Read `System.Title` from the work item
2. Match all leading bracket groups: regex `(\[[^\]]+\])\s*` at start of title (handles both `[A][B]` and `[A] [B]` with optional whitespace between brackets)
3. First bracket group becomes `title_prefix.static` (e.g., `[BizApp]`, `[Platform]`, `[Mobile]` — whatever the team uses)
4. Remaining bracket groups become positional slots (`slot_1`, `slot_2`, etc.):
   - Each slot's `description` includes the reference value for context
   - Each slot's `examples` array contains the reference value
5. Assemble `pattern` from static bracket + `{slot_N}` placeholders
6. If title has no brackets, set `static` to empty string and `pattern` to `"{title}"` (no prefix convention detected)

This is fully generic — works for any team's prefix convention:

Example: `[BizApp] [Backend] Expose sorting...` produces:
- `static`: `[BizApp]`
- `pattern`: `[BizApp][{slot_1}]`
- `slots.slot_1`: `{description: "Title tag 1 (from reference: Backend)", examples: ["Backend"]}`

Example: `[Platform] [Payments] [Checkout] Add retry...` produces:
- `static`: `[Platform]`
- `pattern`: `[Platform][{slot_1}][{slot_2}]`
- `slots.slot_1`: `{description: "Title tag 1 (from reference: Payments)", examples: ["Payments"]}`
- `slots.slot_2`: `{description: "Title tag 2 (from reference: Checkout)", examples: ["Checkout"]}`

Example: `[Mobile] Fix login timeout` produces:
- `static`: `[Mobile]`
- `pattern`: `[Mobile]`
- `slots`: `{}` (no additional slots — just the static prefix)

### Work type extraction

1. Read `ScrumMB.WorkType` from the work item → `work_type.default`
2. `work_type.inference_keywords` is a constant map seeded with all 8 known ADO work types and their keyword associations (not derived from the reference item)

### Field filtering

Exclude from `fields`:
- All existing exclusions (System.*, instance-specific)
- All `Custom.*` boolean fields (value is `true` or `false`)
- `Custom.Repo` (moved to `auto_populate_from_source`)
- `ScrumMB.WorkType` (moved to `work_type`)

### Auto-populate mapping

If `Custom.Repo` exists in the reference work item, add `{"Custom.Repo": "repo_name"}` to `auto_populate_from_source`. This tells creation prompts to fill `Custom.Repo` from the activity's repository name.

## Caller Changes

### Prompts that populate descriptions

All prompts that create PBIs need to use `{overview}` and `{scope}` instead of `{summary}`, `{source}`, `{date}`.

**`ado-tracker-apply-updates.prompt.md`**
- `{overview}`: Inferred from activity source (PR description summary, Notion page summary, commit message summary)
- `{scope}`: Bullet list of specific changes, PRs, commits included in this work item

**`ado-tracker-create-pbi.prompt.md`**
- `{overview}`: User-provided description, summarized
- `{scope}`: User-provided or generated from conversation context

**`ado-tracker-create-task.prompt.md`**
- `{overview}`: Brief task purpose
- `{scope}`: Specific deliverables for the task

**`ado-tracker-breakdown-pbi.prompt.md`**
- `{overview}`: Inherited from parent PBI or task-specific summary
- `{scope}`: Task-specific scope

### Prompts that handle title prefix

**All PBI creation prompts** must:
1. Read `title_prefix.pattern` and `title_prefix.slots` from template
2. For manual creation: ask user for each slot value
3. For automated creation (apply-updates): present inferred slot values for user confirmation
4. Assemble the full title: `pattern` with slots filled + description text

### Prompts that handle work type

**`ado-tracker-propose-updates.prompt.md`** (automated scan):
1. Collect text from activity source (PR titles, commit messages, Notion page titles)
2. Lowercase, scan against `work_type.inference_keywords`
3. Count keyword matches per category, highest score wins
4. Tie or no matches → `work_type.default`
5. Present inferred work type in proposal, user confirms or changes

**`ado-tracker-create-pbi.prompt.md`** (manual creation):
1. Ask user to pick work type from the 8 options
2. Default to `work_type.default`

### Prompts that handle auto-populate fields

**`ado-tracker-apply-updates.prompt.md`**:
1. Read `auto_populate_from_source` from template
2. For each entry, map the activity source key to the field value (e.g., PR repo name → `Custom.Repo`)
3. Include in the `fields` object when creating the work item

### Schema doc update

**`schemas/task-template.schema.md`** must be updated to reflect the new template structure.

### CLAUDE.md update

Update the template description to mention the new sections.

## Files Changed

| File | Change |
|------|--------|
| `scripts/template-manager.sh` | Update `extract_template()` jq filter |
| `schemas/task-template.schema.md` | New schema with title_prefix, work_type, auto_populate_from_source |
| `prompts/ado-tracker-apply-updates.prompt.md` | New description placeholders, work type inference, title prefix slots, auto-populate |
| `prompts/ado-tracker-create-pbi.prompt.md` | New description placeholders, title prefix slot prompting, work type selection |
| `prompts/ado-tracker-create-task.prompt.md` | New description placeholders |
| `prompts/ado-tracker-breakdown-pbi.prompt.md` | New description placeholders |
| `prompts/ado-tracker-propose-updates.prompt.md` | Work type inference logic, title prefix inference |
| `.claude/skills/ado-tracker-init/SKILL.md` | Updated template presentation during init |
| `CLAUDE.md` | Updated template section |

## What Doesn't Change

- `scripts/ado-cli.sh` — passes `description` as a string, format-agnostic
- `scripts/build-params.sh` — JSON construction helper, format-agnostic
- `template-manager.sh` `read`/`write`/`update`/`validate` actions — handle any JSON shape
- `scripts/extract-git-activity.sh` — activity gathering, unrelated
- `scripts/parse-session-logs.sh` — session parsing, unrelated
