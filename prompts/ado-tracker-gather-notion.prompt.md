# Gather Notion Activity

## Goal
Fetch Notion pages created by the user within a date range.

## Context
- Config: `data/config.json` — read `user.notion_user_id`, `notion.scope`, `notion.excluded_databases`, `notion.filter_types`
- Tool: Notion MCP (`notion-search`)

## Input
- `from_date`: Start date (YYYY-MM-DD)
- `to_date`: End date (YYYY-MM-DD)

## Instructions

1. Read `data/config.json`. Use `user.notion_user_id` — do NOT call `notion-get-users`.

2. Search Notion with the stored user ID:
   ```
   notion-search:
     query: "*"
     filters:
       created_date_range: {start_date: <from_date>, end_date: <to_date + 1 day>}
       created_by_user_ids: [<user.notion_user_id>]
     page_size: 25
     max_highlight_length: 50
   ```

3. Filter results:
   - Only include results where `type` is in `notion.filter_types` (default: `["page"]`). Drop Slack, SharePoint, and other connector results.
   - If `notion.scope` is `"databases"`, only include pages from non-excluded databases.
   - Filter out any databases in `notion.excluded_databases`.

4. For each qualifying page, extract:
   - Page title
   - Page ID and URL
   - Parent context (from the search result metadata)
   - Timestamp

5. Return structured JSON array:
   ```json
   [
     {
       "type": "notion_page",
       "page_id": "abc-123",
       "title": "Architecture Overview — AI Chatbot",
       "url": "https://www.notion.so/abc123",
       "role": "owner",
       "last_edited": "2026-03-27"
     }
   ]
   ```

## Output
JSON array of Notion activity objects (pages only, filtered to user).
