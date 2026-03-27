# Gather Claude Session & Git Activity

## Goal
Gather Claude Code session activity and git commits for a date range. These are combined because they represent closely related local development work.

## Context
- Session parser: `bash scripts/parse-session-logs.sh --from <date> --to <date>`
- Git extractor: `bash scripts/extract-git-activity.sh --from <date> --to <date>`
- Config: `data/config.json` — read `git.repos`, `git.auto_detect_from`, `session_logs`

## Input
- `from_date`: Start date (YYYY-MM-DD)
- `to_date`: End date (YYYY-MM-DD)

## Instructions

1. Read `data/config.json` for git and session log settings.
2. Extract git activity:
   ```bash
   bash scripts/extract-git-activity.sh --from <from_date> --to <to_date> --repos '<repos-json>'
   ```
   Or if using auto-detect:
   ```bash
   bash scripts/extract-git-activity.sh --from <from_date> --to <to_date> --auto-detect "<auto_detect_from>"
   ```
3. Parse Claude Code session logs (if enabled):
   ```bash
   bash scripts/parse-session-logs.sh --from <from_date> --to <to_date>
   ```
4. Correlate sessions with git commits where possible:
   - If a session description mentions a repo that also has commits, group them
   - Sessions without matching commits are still included as standalone activity
5. Return structured JSON array:
   ```json
   [
     {
       "type": "dev_activity",
       "source": "git+session",
       "repo": "Mindbody.Api.Rest",
       "summary": "Refactored auth middleware — 4 commits",
       "commit_count": 4,
       "commits": [
         {"hash": "abc1234", "subject": "Extract auth logic to middleware"}
       ],
       "session_description": "Refactored authentication middleware for the REST API",
       "date": "2026-03-27"
     }
   ]
   ```

## Output
JSON array of development activity objects combining git and session data.
