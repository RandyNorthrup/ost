---
id: TASK-0062
title: In-meeting More menu items as Teams
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-08T20:41:00Z'
updated_date: '2026-11-09T00:51:00Z'
labels:
  - calls
  - meetings
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' More (…) menu in meetings (verified on winpc): Record and transcribe ▸, Meeting info, Timer, Video effects and settings, Audio settings, Language and speech ▸, Settings ▸, Report a concern, Help. The bar engine already places them from Teams' config; OST shows only Video effects and settings and Audio settings, which open OST's device settings rather than Teams' side panes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Meeting info opens Teams' meeting info pane (title, time, join link, dial-in, copy)
- [ ] #2 Video effects and settings and Audio settings open Teams' side panes, as measured on winpc
- [ ] #3 Language and speech ▸ with Captions, Settings ▸ (Call health, Accessibility, Chat bubbles, Mute notifications), Timer and Help as Teams
- [ ] #4 Record and transcribe ▸ and Report a concern as Teams (no real reports filed while testing)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- AC#1 Meeting info: measured the pane on winpc (calling-right-side-panel) and read calling-meeting-info-panel + the calling service adapter (getExchangeMeetingInfo / getMeetingFormattedTime / recurrence formatter 197544).
- Data: join response meetingDetails (meetingChatProperties subject/location, start/end, iCalUid, shortJoinUrl) + calendar event by iCalUid (Graph body + recurrence).
- Copy join info verified byte-identical to Teams' clipboard (fallback "Join Teams meeting" with the short /meet/ link, as this meeting's body has no me-email-text block).
- Dial-in: the test tenant has no audio conferencing (pstnDetails null), so Teams shows no dial-in block either; not verifiable here.
- Qt rich text needs: <font size> dropped (Qt applies it on top of the span size), pt->px, word joiners in link text so URLs wrap as Chrome does.
<!-- SECTION:NOTES:END -->
