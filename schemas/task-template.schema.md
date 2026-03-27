# Task Template Schema

## File Location
`data/task-template.json` (gitignored, generated from reference task)

## Purpose
Defines the reusable structure for creating new ADO work items. Generated once from a reference work item via `/ado-tracker-init`, then used for all future PBI/Task creation.

## Fields

| Field | Type | Description |
|-------|------|-------------|
| `source_work_item_id` | number | ID of the reference work item this template was derived from. |
| `work_item_type` | string | e.g., `"Product Backlog Item"`, `"Task"` |
| `area_path` | string | e.g., `"Project\\Team\\Area"` |
| `iteration_path_pattern` | string | e.g., `"Project\\Sprint-{number}"` — `{number}` is replaced with current sprint. |
| `fields` | object | Key-value pairs of ADO field reference names to default values. |
| `description_format` | string | Markdown template for the description body. Supports placeholders: `{title}`, `{source}`, `{summary}`, `{date}`. |
| `tags` | string[] | Default tags to apply. |
| `priority` | number | Default priority (1-4). |

## Example

```json
{
  "source_work_item_id": 12345,
  "work_item_type": "Product Backlog Item",
  "area_path": "MyProject\\MyTeam\\Backend",
  "iteration_path_pattern": "MyProject\\Sprint-{number}",
  "fields": {
    "System.State": "New",
    "Microsoft.VSTS.Common.ValueArea": "Business"
  },
  "description_format": "## Summary\n{summary}\n\n## Source\n{source}\n\n## Date\n{date}",
  "tags": ["auto-tracked"],
  "priority": 2
}
```

## What Is Extracted From Reference Task
- Area path
- Iteration path (converted to a pattern with `{number}` placeholder)
- Work item type
- Non-instance-specific field values (state defaults, value area, etc.)
- Description structure/format (converted to a template with placeholders)
- Tags
- Priority

## What Is Filtered Out
- The specific description body text
- Assigned-to and created-by
- Attachments
- Comments
- Relations/links
- History
- Iteration-specific dates
- Any field value unique to that one work item
