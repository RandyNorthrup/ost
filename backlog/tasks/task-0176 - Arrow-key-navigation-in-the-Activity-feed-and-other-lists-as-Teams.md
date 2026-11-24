---
id: TASK-0176
title: Arrow-key navigation in the Activity feed and other lists as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-16T04:53:00Z'
updated_date: '2026-11-16T20:22:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OST has Teams' list navigation and the 'Use Enter or Spacebar to show content' setting only in the chat list.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Activity, @mentions and the other lists Teams covers navigate with the arrow keys and honour the setting
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Built by a subagent (dd601ea): Up/Down/Home/End in Activity, @mentions, Followed threads, Saved and Drafts, honouring 'Use Enter or Spacebar to show content' (Drafts always waits for Enter, as Teams). Checked live with the setting off and on.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Activity, @mentions, Followed threads, Saved and Drafts navigate with the arrow keys and honour Teams' Enter/Spacebar setting.
<!-- SECTION:FINAL_SUMMARY:END -->
