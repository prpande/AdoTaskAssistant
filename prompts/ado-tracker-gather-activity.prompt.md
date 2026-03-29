# Gather All Activity

## Goal
Collect activity from GitHub, Notion, and Git for a date range in a single pass.

## Context
- Config: `data/config.json` — read once for all sources
- Tools: `gh` CLI, Notion MCP (`notion-search`), `bash scripts/extract-git-activity.sh`, `bash scripts/parse-session-logs.sh`

## Input
- `from_date`: Start date (YYYY-MM-DD)
- `to_date`: End date (YYYY-MM-DD)

## Instructions

1. Read `data/config.json` once. Extract all needed settings:
   - `user.github_username`, `github.organizations`, `github.excluded_repos`
   - `user.notion_user_id`, `notion.scope`, `notion.excluded_databases`, `notion.filter_types`
   - `git.source_root`, `git.auto_detect`, `git.filter_by_remote_org`, `git.explicit_repos`

### GitHub Activity

2. For each org in `github.organizations`, search for PRs authored by the user:
   ```bash
   gh search prs --author=<username> --created=<from_date>..<to_date> --owner=<org> --json number,title,repository,state,createdAt,updatedAt,url --limit 100
   ```
   If results return exactly 100, paginate with `--page 2` etc.

3. Also search for PRs reviewed by the user:
   ```bash
   gh search prs --reviewed-by=<username> --created=<from_date>..<to_date> --owner=<org> --json number,title,repository,state,createdAt,updatedAt,url --limit 100
   ```

4. Filter out repos in `github.excluded_repos`. Deduplicate by URL. If a PR appears in both authored and reviewed, keep one entry with `role: "author+reviewer"`.

5. If GitHub collection fails, note "GitHub scan skipped — <error>" and continue.

### Notion Activity

6. Search Notion with the stored user ID:
   ```
   notion-search:
     query: "*"
     filters:
       created_date_range: {start_date: <from_date>, end_date: <to_date + 1 day>}
       created_by_user_ids: [<user.notion_user_id>]
     page_size: 25
     max_highlight_length: 50
   ```

7. Filter results: only include `type` in `notion.filter_types` (default: `["page"]`). Drop Slack, SharePoint, connector results. Exclude databases in `notion.excluded_databases`.

8. If Notion collection fails, note "Notion scan skipped — <error>" and continue.

### Git & Session Activity

9. Extract git activity:
   ```bash
   bash scripts/extract-git-activity.sh --from <from_date> --to <to_date> --auto-detect "<git.source_root>" --filter-org "<git.filter_by_remote_org>"
   ```
   If `git.explicit_repos` is non-empty, also pass `--repos '<json-array>'`.

10. Parse session logs (best-effort):
    ```bash
    bash scripts/parse-session-logs.sh --from <from_date> --to <to_date>
    ```

11. If Git collection fails, note "Git scan skipped — <error>" and continue.

### Combine and Output

12. Combine all activity into a single JSON array. Each item has a `type` field (`github_pr`, `notion_page`, or `dev_activity`).

13. Report collection summary: "Found X PRs, Y Notion pages, Z repos with commits." Note any skipped sources.

## Output
A flat JSON array saved to the activity file path. Each item MUST have a top-level `type` field.

**GitHub PR items:**
```json
{"type": "github_pr", "title": "...", "url": "https://github.com/org/repo/pull/N", "number": N, "repository": {"name": "...", "nameWithOwner": "..."}, "state": "open|merged|closed", "createdAt": "ISO8601", "updatedAt": "ISO8601", "role": "author|reviewer|author+reviewer"}
```

**Notion page items:**
```json
{"type": "notion_page", "title": "...", "url": "https://notion.so/...", "last_edited": "ISO8601"}
```

**Dev activity items (one per repo):**
```json
{"type": "dev_activity", "repo": "RepoName", "commit_count": N, "commits": [{"hash": "...", "subject": "...", "date": "YYYY-MM-DD HH:MM:SS +TZ"}]}
```

After combining, report: "Found X PRs, Y Notion pages, Z repos with commits." Note any skipped sources.
