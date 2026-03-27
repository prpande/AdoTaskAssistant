# Gather Notion Activity

## Goal
Fetch Notion pages owned or substantially edited by the user within a date range.

## Context
- Config: `data/config.json` — read `notion.scope`, `notion.exclude_databases`, `notion.track_ownership`, `notion.track_edits`
- Tool: Notion MCP (`notion-search`, `notion-fetch`)

## Input
- `from_date`: Start date (YYYY-MM-DD)
- `to_date`: End date (YYYY-MM-DD)

## Instructions

1. Read `data/config.json` for Notion settings.
2. Use the Notion MCP `notion-search` tool to find recently edited pages:
   - Search with a broad query or use `notion-query-data-sources` for database-scoped searches
   - Filter results to the date range
3. For each page found, determine the user's relationship:
   - **Owner**: User created the page
   - **Editor**: User made substantial edits (not just comments)
   - Skip pages where the user only added comments
4. If `notion.scope` is `"databases"`, only include pages from non-excluded databases.
5. Filter out any databases in `notion.exclude_databases`.
6. For each qualifying page, fetch enough detail to generate a meaningful task title:
   - Page title
   - Parent database or workspace location
   - Last edited time
7. Return structured JSON array:
   ```json
   [
     {
       "type": "notion_page",
       "page_id": "abc-123",
       "title": "Q2 Onboarding Flow Redesign",
       "url": "https://notion.so/abc-123",
       "parent": "Design Specs database",
       "role": "owner",
       "last_edited": "2026-03-27"
     }
   ]
   ```

## Output
JSON array of Notion activity objects.
