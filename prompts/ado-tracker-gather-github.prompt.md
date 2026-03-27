# Gather GitHub Activity

## Goal
Fetch GitHub PRs authored or reviewed by the user within a date range, filtered by configured organizations.

## Context
- Config: `data/config.json` — read `github.orgs`, `github.exclude_repos`, `github.username`
- Tool: `gh` CLI (must be authenticated)

## Input
- `from_date`: Start date (YYYY-MM-DD)
- `to_date`: End date (YYYY-MM-DD)

## Instructions

1. Read `data/config.json` for GitHub settings.
2. Detect username if not configured:
   ```bash
   gh api user --jq .login
   ```
3. For each configured org, search for PRs authored by the user in the date range:
   ```bash
   gh search prs --author=<username> --created=<from_date>..<to_date> --owner=<org> --json number,title,repository,state,createdAt,updatedAt,url --limit 100
   ```
4. Also search for PRs reviewed by the user:
   ```bash
   gh search prs --reviewed-by=<username> --created=<from_date>..<to_date> --owner=<org> --json number,title,repository,state,createdAt,updatedAt,url --limit 100
   ```
5. Filter out any repos in `github.exclude_repos`.
6. Deduplicate (a PR you authored and reviewed should appear once, tagged as both).
7. Return structured JSON array:
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
