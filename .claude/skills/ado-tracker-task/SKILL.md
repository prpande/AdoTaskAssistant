---
name: ado-tracker-task
description: Create a child task under an existing PBI
---

# ADO Tracker — Create Task

Create a child task under an existing PBI.

## Arguments
- First argument: PBI work item ID
- Remaining text: task description

## Instructions

1. Parse the PBI ID and description from the arguments.
2. Execute `prompts/ado-tracker-create-task.prompt.md` with the PBI ID and description.
