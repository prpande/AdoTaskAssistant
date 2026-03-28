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
| `title_prefix.pattern` | string | Full pattern with positional slots. e.g., `"[BizApp][{slot_1}]"` |
| `title_prefix.slots` | object | Map of positional slot name (slot_1, slot_2, ...) to `{description, examples}`. Derived from reference title brackets. |
| `work_type` | object | Work type configuration (see below). |
| `work_type.default` | string | Default work type. e.g., `"New Feature Development"` |
| `work_type.inference_keywords` | object | Map of work type to keyword array for inference from activity. |
| `auto_populate_from_source` | object | Map of ADO field name to activity source key. e.g., `{"Custom.Repo": "repo_name"}` |
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

## What Is Extracted From Reference Task
- Area path
- Iteration path (converted to pattern with `{year}` and `{sprint_number}` placeholders)
- Work item type
- Title prefix pattern (bracket groups parsed into static + positional slot structure)
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
