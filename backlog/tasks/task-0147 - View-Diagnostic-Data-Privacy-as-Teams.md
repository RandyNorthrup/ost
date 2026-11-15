---
id: TASK-0147
title: View Diagnostic Data (Privacy) as Teams
status: To Do
assignee: []
created_date: '2026-11-15T04:40:00Z'
labels:
  - settings
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' Settings > Privacy > View Diagnostic Data > Manage opens its diagnostic data viewer (privacy_trusted_ui_diagnostic_data_viewer when ECS telemetry.enableTUIDdv), listing the diagnostic events the app sends to Microsoft. OST sends no diagnostic events to Microsoft yet. Decide what the viewer shows for OST (what it sends), then build it with Teams' layout; until then the card is left out.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Privacy shows 'View Diagnostic Data' with a Manage button as Teams
- [ ] #2 Manage opens a viewer laid out as Teams' diagnostic data viewer, listing exactly the diagnostic data OST sends
<!-- AC:END -->
