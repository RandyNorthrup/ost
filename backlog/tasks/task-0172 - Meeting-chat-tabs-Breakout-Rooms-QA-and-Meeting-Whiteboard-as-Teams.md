---
id: TASK-0172
title: 'Meeting chat tabs: Breakout Rooms, Q&A and Meeting Whiteboard as Teams'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-16T04:53:00Z'
updated_date: '2026-11-16T09:43:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams lists these under '+N' in meeting chats; OST shows Chat, Shared, Recap and Attendance only.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A meeting chat lists Teams' tabs (Chat, Shared, Recap, Attendance, Breakout Rooms for the organizer, Q&A for scheduled meetings, Meeting Whiteboard) with +N overflow, as in Teams
- [x] #2 Breakout Rooms opens natively before the meeting with Teams' empty state and Create rooms
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Built by a subagent with TASK-0173 (e723e84). The tab lists match Teams for both test meetings (Meet now has no Q&A).
- Q&A/Meeting Whiteboard running, and Breakout Rooms with rooms, moved to TASK-0199 (needs TASK-0053).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Meeting chats list Teams' tabs.

- Attendance (organizer, after a call), Breakout Rooms (organizer), Q&A (scheduled meetings only) and Meeting Whiteboard, in Teams' order, with "+N" overflow; matches winpc for a scheduled meeting and a Meet now chat.
- Breakout Rooms is native: loads the rooms before the meeting, Teams' empty-state illustration and Create rooms.
- Q&A and Meeting Whiteboard load Teams' pages; running them needs a TeamsJS host (TASK-0199, after TASK-0053).

Harness: --meeting-tab-test.
<!-- SECTION:FINAL_SUMMARY:END -->
