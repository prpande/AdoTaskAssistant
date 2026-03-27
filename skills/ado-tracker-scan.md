---
name: ado-tracker-scan
description: Run an ad-hoc ADO Tracker scan for a custom date range
---

# ADO Tracker — Ad-hoc Scan

Execute an ad-hoc scan for a custom date range.

## Arguments
- `--from YYYY-MM-DD` — Start date
- `--to YYYY-MM-DD` — End date

If dates are not provided as arguments, ask the user.

## Instructions

1. Parse `--from` and `--to` from the arguments.
2. Execute `automations/ado-tracker-adhoc.automation.md` with the parsed date range.
