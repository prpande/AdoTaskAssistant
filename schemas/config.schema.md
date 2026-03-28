# Configuration Schema

## File Location
`data/config.json` (gitignored, user-specific)

## Reference
See `config/config.sample.json` for a working example with all fields.

## Fields

### `github`
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `orgs` | string[] | `[]` | GitHub organizations to track. Only PRs in these orgs are scanned. |
| `exclude_repos` | string[] | `[]` | Repos to exclude from tracking (format: `org/repo`). |
| `username` | string\|null | `null` | GitHub username. Auto-detected from `gh api user --jq .login` if null. |

### `notion`
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `scope` | `"all"` \| `"databases"` | `"all"` | Track all pages or only pages in specific databases. |
| `exclude_databases` | string[] | `[]` | Notion database IDs to exclude. |
| `track_ownership` | boolean | `true` | Track pages where user is the creator/owner. |
| `track_edits` | boolean | `true` | Track pages where user made substantial edits (not just comments). |

### `git`
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `repos` | string[] | `[]` | Absolute paths to local git repos to scan. If empty, uses `auto_detect_from`. |
| `auto_detect_from` | string\|null | `null` | Parent directory to auto-discover git repos from. |

### `ado`
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `organization` | string | required | ADO organization URL (e.g., `https://dev.azure.com/your-org`). |
| `project` | string | required | ADO project name. |
| `default_work_item_type` | string | `"Product Backlog Item"` | Default work item type for new items. |
| `use_cli` | boolean | `true` | Use `az devops` CLI as primary ADO interface. |
| `fallback_to_mcp` | boolean | `true` | Fall back to ADO MCP when CLI can't handle an operation. |

### `schedule`
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `daily_time` | string | `"09:00"` | Preferred daily run time (HH:MM, 24h format). |
| `loop_interval` | string | `"24h"` | Interval for `/loop` scheduling. |

### `session_logs`
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | `true` | Whether to parse Claude Code session logs. |
| `path` | string\|null | `null` | Path to Claude Code session logs. Auto-detected if null. |

### `scan`
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `approval_mode` | `"interactive"` \| `"auto-confirm"` \| `"auto-apply"` | `"interactive"` | How scan proposals are approved. `interactive`: show and wait. `auto-confirm`: show then proceed immediately. `auto-apply`: apply without showing. |
| `auto_apply_sources` | string[] | `[]` | Reserved for future per-source auto-apply rules. |
