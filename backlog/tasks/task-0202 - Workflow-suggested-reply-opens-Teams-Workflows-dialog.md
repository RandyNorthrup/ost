---
id: TASK-0202
title: Workflow suggested reply opens Teams' Workflows dialog
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-16T11:48:00Z'
updated_date: '2026-11-16T17:31:00Z'
labels:
  - desktop
dependencies:
  - TASK-0053
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-0170: when the tenant turns workflow suggestions on, Teams opens its Workflows dialog (an embedded page); OST opens the Workflows page in the browser instead. Needs a TeamsJS host (TASK-0053).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The workflow suggestion opens the Workflows dialog in OST, as Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built so far (16a17d0): a general TeamsJS dialog host (TaskModuleDialog, dialog.url / tasks.startTask, Teams' size and result/cancel answers). The channel and chat Workflows dialogs run in it; the suggestion opens app 25b07509… "Workflows" 800 × 600 with suggestedAction/{page} and subEntityId as Teams launches it.

Left: the suggestion's page stays blank ("Initial app state does not contain valid QSP", "User ID or Tenant ID is empty"): Teams adds parameters not yet traced. Workflow suggestions are off in this tenant, so Teams' own result can't be seen.
<!-- SECTION:NOTES:END -->
