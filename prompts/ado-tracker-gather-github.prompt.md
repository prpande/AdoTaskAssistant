# Gather GitHub Activity

## Goal
Fetch GitHub PRs authored or reviewed by the user within a date range, filtered by configured organizations.

## Context
- Config: `data/config.json` — read `user.github_username`, `github.organizations`, `github.excluded_repos`
- Tool: `gh` CLI (must be authenticated)

## Input
- `from_date`: Start date (YYYY-MM-DD)
- `to_date`: End date (YYYY-MM-DD)

## Instructions

1. Read `data/config.json`. Use `user.github_username` — do NOT call `gh api user`.

2. For each org in `github.organizations`, search for PRs authored by the user:
   ```bash
   gh search prs --author=<username> --created=<from_date>..<to_date> --owner=<org> --json number,title,repository,state,createdAt,updatedAt,url --limit 100
   ```
   If results return exactly 100, fetch the next page with `--page 2` and continue until fewer than 100 results are returned.

3. Also search for PRs reviewed by the user:
   ```bash
   gh search prs --reviewed-by=<username> --created=<from_date>..<to_date> --owner=<org> --json number,title,repository,state,createdAt,updatedAt,url --limit 100
   ```

4. Filter out any repos in `github.excluded_repos`.

5. Deduplicate by PR URL. If a PR appears in both authored and reviewed results, keep one entry with `role: "author+reviewer"`.

6. Return structured JSON array:
   ```json
   [
     {
       "type": "github_pr",
       "pr_number": 1234,
       "title": "Add retry logic",
       "repo": "org/repo-name",
       "url": "https://github.com/org/repo/pull/1234",
       "state": "merged",
       "role": "author",
       "created_at": "2026-03-27",
       "updated_at": "2026-03-27"
     }
   ]
   ```

## Output
JSON array of PR activity objects.
