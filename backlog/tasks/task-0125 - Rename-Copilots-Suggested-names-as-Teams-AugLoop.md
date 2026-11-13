---
id: TASK-0125
title: 'Rename: Copilot''s Suggested names as Teams (AugLoop)'
status: To Do
assignee: []
created_date: '2026-11-13T01:56:00Z'
labels:
  - files
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' Rename offers Copilot's Suggested names for some files (a .txt, not an .mp4): a folded row that, expanded, asks OneDrive's AugLoop LLM service (llmScenarioGuid f44f84d5-dd13-4369-9939-c8cb945fe62f) for 3 names (docs/spec/file-actions.md). On 2026-11-12 Teams itself answered 'Something went wrong.' for OST Test 1, so the AugLoop exchange could not be captured. Needs: when Teams offers the row, the AugLoop websocket protocol and token, and a working answer to match.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Rename shows the Suggested names row for the files Teams shows it for, folded and expandable
- [ ] #2 Expanding it asks Copilot as Teams does and shows its three names, the AI notice with thumbs, and Teams' error and Try again
<!-- AC:END -->
