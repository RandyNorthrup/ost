---
id: TASK-0164
title: 'Compose: Write with Copilot as Teams'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-15T23:27:00Z'
updated_date: '2026-11-16T16:42:00Z'
labels:
  - desktop
  - copilot
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
With a Copilot licence (ost-test1 since 2026-11-15) Teams' compose toolbar adds 'Write with Copilot' (between Attach files and Loop components). OST's toolbar doesn't have it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 OST shows 'Write with Copilot' in compose where Teams does, only for licensed users
- [x] #2 Its menu and rewrite flow work as Teams' (measured on winpc)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Built by a subagent (1050c4e, merged as 8229940); spec docs/spec/messages-and-composer.md.
- Teams' rule: Compose enableComposeCopilot + AugLoop enableAugLoopService + licence isCopilot. Button between Attach files and Loop components in chats, new posts and replies (Alt+A, not in calls).
- Rewrite / Proofread / Adjust (Custom, Concise, Longer, Casual, Professional, Confident, Enthusiastic) over AugLoop with ost-test1's token; pager and Replace; popover position and height equal Teams'.
- Re-checked on the merged build: real Copilot answers for Rewrite, Proofread, Concise, Custom; Replace; OST Test 2 (no licence) gets no button.
- Left: the thumbs only mark the answer (Teams opens Microsoft's feedback form, which OST doesn't send to).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Write with Copilot in compose, as Teams.

- Shown only for Copilot-licensed users, where Teams shows it (chats, new channel posts, replies; Alt+A).
- CopilotPopover.qml: Rewrite, Proofread, Adjust with its seven choices, empty / ready / generating states, the answers pager and Replace.
- src/api/compose_copilot.rs: Teams' AugLoop requests (tone and length per choice, the draft as first asked), streamed HTML answers.

Tests: unit tests for the requests; --copilot-test live with real answers; OST Test 2 shows no button.
<!-- SECTION:FINAL_SUMMARY:END -->
