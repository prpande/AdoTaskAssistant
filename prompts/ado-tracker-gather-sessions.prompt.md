# Gather Claude Session & Git Activity

## Goal
Gather git commits and (optionally) Claude Code session data for a date range. Git activity is the primary signal; session data is best-effort bonus context.

## Context
- Config: `data/config.json` — read `git.source_root`, `git.auto_detect`, `git.filter_by_remote_org`, `git.explicit_repos`
- Git extractor: `bash scripts/extract-git-activity.sh`
- Session parser: `bash scripts/parse-session-logs.sh` (best-effort)

## Input
- `from_date`: Start date (YYYY-MM-DD)
- `to_date`: End date (YYYY-MM-DD)

## Instructions

1. Read `data/config.json` for git settings.

2. Extract git activity using the config:
   ```bash
   bash scripts/extract-git-activity.sh --from <from_date> --to <to_date> --auto-detect "<git.source_root>" --filter-org "<git.filter_by_remote_org>"
   ```
   If `git.explicit_repos` is non-empty, also pass `--repos '<json-array>'`.

3. Parse Claude Code session logs (best-effort — if this fails or returns empty, continue without it):
   ```bash
   bash scripts/parse-session-logs.sh --from <from_date> --to <to_date>
   ```

4. Build the output. For each repo with commits, create a dev_activity entry:
   ```json
   [
     {
       "type": "dev_activity",
       "source": "git",
       "repo": "Mindbody.Scheduling",
       "summary": "<brief summary of commits>",
       "commit_count": 20,
       "commits": [{"hash": "abc1234", "subject": "..."}],
       "date_range": "2026-03-25 to 2026-03-27"
     }
   ]
   ```

5. If session data was found, add it as context to matching repo entries where possible. Sessions without matching repos are included as standalone entries.

## Output
JSON array of development activity objects.
