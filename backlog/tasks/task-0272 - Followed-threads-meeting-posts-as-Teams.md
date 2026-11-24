---
id: TASK-0272
title: 'Followed threads: meeting posts as Teams'
status: In Progress
assignee:
  - '@fthY'
created_date: '2026-11-24T09:04:00Z'
updated_date: '2026-11-24T10:37:00Z'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-0265: in Teams' Followed threads list a channel meeting post's title has a calendar icon before it (OST shows the title only); the meeting card inside the 512-wide Followed threads view wasn't measured for a meeting that isn't cancelled (Teams lists only threads with replies).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Followed threads lists a meeting post with Teams' calendar icon and text
- [ ] #2 A followed meeting post that isn't cancelled shows its card in the Followed threads view as Teams, measured on winpc with a test meeting post that has a reply
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Teams (bundles + winpc CDP 2026-11-24, own test data): the Followed threads row's root line is the thread slice's parentMessageSubject, else parentMessagePreview, after cn(parentMessageType): CalendarRegular (16 px, margin-right 6, vertical-align top, #424242) for activityContext.parentMessageType "Meeting" (cancelled meetings too), DeleteRegular for parentMessagePreviewTemplateOption "deleted". Row: glyph and text at row+34 (text 22 after the glyph start), 12/16; unread = channel + root line 700 and a 4 px #242424 dot at (22, 30) of the row.
- Teams' banner in the 512 Followed view for "OST TEST 272 channel meeting": 420 x 105.3 at card+16 (card 452 x 253), flex gap 10, text column 190.7 (title 2 lines 40, start wraps to 32), More 263.3 / Join 303.3 at y 37. The inline-slice max-width 75% class is not applied there.
- Test data: "OST TEST 272 channel meeting" (tomorrow 10:00, ost-test1 only) made by OST in OST test channel; reply "OST TEST 272 channel meeting reply" and follow from OST (--meeting-post-test=reply).
<!-- SECTION:NOTES:END -->
