---
id: TASK-0098
title: Meeting recap card on a meeting's ended row, as Teams
status: To Do
assignee: []
created_date: '2026-11-10T17:18:00Z'
labels:
  - desktop
  - messages
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams adds a recap card under a meeting's "Meeting ended: {duration}" row. Seen on winpc on 2026-11-10 in OST calendar test (Sunday 8:53 PM), it holds:
- the meeting title (bold) and its date range ("Saturday, November 7, 2026 7:24 PM - Sunday, November 8 8:53 PM");
- a Share icon and a brand "View recap" button;
- a "Content" section with a "Transcript" chip;
- a recording thumbnail labelled "5 recordings", with "Set to expire" under it.

It is built from the call-end XML (MeetingDetails) plus the recording messages folded into it (docs/spec/message-types.md §20). Teams' UI module 174639 hasn't been traced yet. "View recap" opens the meeting's Recap tab.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A meeting chat's ended row shows the recap card with Teams' layout, title, date range, transcript chip and recordings thumbnail/count
- [ ] #2 View recap, the transcript chip and the thumbnail open what Teams opens
- [ ] #3 Verified side by side with Teams on winpc
<!-- AC:END -->
