---
id: TASK-0272
title: 'Followed threads: meeting posts as Teams'
status: Done
assignee:
  - '@fthY'
created_date: '2026-11-24T09:04:00Z'
updated_date: '2026-11-24T11:50:00Z'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-0265: in Teams' Followed threads list a channel meeting post's title has a calendar icon before it (OST shows the title only); the meeting card inside the 512-wide Followed threads view wasn't measured for a meeting that isn't cancelled (Teams lists only threads with replies).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Followed threads lists a meeting post with Teams' calendar icon and text
- [x] #2 A followed meeting post that isn't cancelled shows its card in the Followed threads view as Teams, measured on winpc with a test meeting post that has a reply
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Teams (bundles + winpc CDP 2026-11-24, own test data): the Followed threads row's root line is the thread slice's parentMessageSubject, else parentMessagePreview, after cn(parentMessageType): CalendarRegular (16 px, margin-right 6, vertical-align top, #424242) for activityContext.parentMessageType "Meeting" (cancelled meetings too), DeleteRegular for parentMessagePreviewTemplateOption "deleted". Row: glyph and text at row+34 (text 22 after the glyph start), 12/16; unread = channel + root line 700 and a 4 px #242424 dot at (22, 30) of the row.
- Teams' banner in the 512 Followed view for "OST TEST 272 channel meeting": 420 x 105.3 at card+16 (card 452 x 253), flex gap 10, text column 190.7 (title 2 lines 40, start wraps to 32), More 263.3 / Join 303.3 at y 37. The inline-slice max-width 75% class is not applied there.
- Test data: "OST TEST 272 channel meeting" (tomorrow 10:00, ost-test1 only) made by OST in OST test channel; reply "OST TEST 272 channel meeting reply" and follow from OST (--meeting-post-test=reply).

- Built: api::quick_views QuickItem parent_subject / parent_icon ("meeting" for parentMessageType Meeting, "deleted" for parentMessagePreviewTemplateOption deleted; a root record uses its own preview); deleted-thread records (activityReason "deleted") drop the thread. QuickListView: root line = subject else preview after the 16 px calendar-20 / delete-20 glyph (+22), unread bold (700) channel and root line plus the 4 px dot; channel threads whose channel OST doesn't know are skipped (Teams needs the conversation). ScheduledMeetingCard: 10 px gap before the buttons and the start wraps. Harness --meeting-post-test=reply | followed-meeting (+ --meeting-post-show-unread).
- Verified live on linuxlt (spatest = ost-test1, fm2/fm3/fm5): meeting row glyph 16x16 at the line start, text +22, "OST TEST 272 channel meeting" (Teams same); cancelled OST CAL rows show the glyph as in Teams; unread drawing (forced) bold + dot at 410/root-4 (Teams 410, root-4); 512 view card 452x253, banner 420x105.3 at 814/180, More 1077.3 / Join 1117.3 at y 217 (Teams 263.3/303.3/37 in the banner, same). After cleanup OST's list = Teams' (OST CAL OST2, OST, test, OST threads test; no empty deleted rows or rows for unknown agent channels).
- Cleanup: meeting cancelled from OST (--meeting-post-test=cancel); its post, the reply and the cancel reply deleted ("left []").

- Tests: lib 954 passed, desktop 37 passed. Committed 5cb84c93 (worktree agent-afe1865969a8b1665).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Followed threads now shows a channel meeting post the way Teams does. Measured on winpc (2026-11-24) with "OST TEST 272 channel meeting", a test post made from OST as ost-test1, and verified live on linuxlt.

Teams:
- The row's root line is parentMessageSubject, else parentMessagePreview. Before it, 6 px apart, Teams draws a 16 px glyph: CalendarRegular when activityContext.parentMessageType is "Meeting" (cancelled meetings too), DeleteRegular when parentMessagePreviewTemplateOption is "deleted". On an unread thread the channel and root line are bold (700), with a 4 px dot.
- In the 512 wide view the banner is 420 x 105.3. The flex row's 10 px gap leaves 190.7 px for text, so the title and the start both wrap (card 452 x 253).
- Deleting a thread's post turns its 48:threads record into activityReason "deleted", and Teams drops the thread. Teams also drops threads whose conversation it doesn't know.

Changes:
- api::quick_views: parent_subject and parent_icon; a record for the root post uses its own preview; deleted threads are skipped (with tests).
- QuickListView: the glyph and the subject/preview on the root line, unread bold and dot; channel threads of unknown channels are skipped.
- ScheduledMeetingCard: the 10 px gap, and the start now wraps.
- New harness phases: --meeting-post-test=reply and followed-meeting (--meeting-post-show-unread). Spec updated.

Verified: the meeting row's glyph and text, the cancelled meeting rows, and the banner and card geometry in the Followed view all equal Teams'. The unread look (forced) also equals Teams'. After cleanup OST lists the same threads as Teams, in the same order.
Tests: lib 954 passed, desktop 37 passed.
Test data: the meeting was cancelled; its post, reply and cancel reply were deleted.
<!-- SECTION:FINAL_SUMMARY:END -->
