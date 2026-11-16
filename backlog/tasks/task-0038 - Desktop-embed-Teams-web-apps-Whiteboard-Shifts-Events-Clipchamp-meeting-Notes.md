---
id: TASK-0038
title: >-
  Desktop: embed Teams' web apps (Whiteboard, Shifts, Events, Clipchamp, meeting
  Notes)
status: Done
assignee:
  - '@claude'
created_date: '2026-11-06T04:53:00Z'
updated_date: '2026-11-16T22:37:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams embeds these web apps in its window; OST opens them in the browser because QtWebEngine isn't installed (qt6-webengine needs a system install). With it, OST could show them in place, as Teams does.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The chat list's Copilot row (top of the list, as Teams) opens Copilot as Teams hosts it
- [x] #2 Share to Outlook (message ··· ▸ Share to Outlook) opens Teams' embedded Outlook compose
- [x] #3 Immersive Reader (message ···) opens Teams' embedded reader
- [x] #4 Word, PowerPoint and Excel files open inside OST (Office for the web) as Teams' 'Teams' choice does, and Settings ▸ Files and links offers that choice as Teams
- [x] #5 A channel's Loop page tab opens signed in, as Teams
- [x] #6 Whiteboard, Shifts and Clipchamp open inside OST, signed in, as Teams hosts them (Events: TASK-0209)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Built by a subagent (a0154b5, merged); spec docs/spec/app-host.md.
- Whiteboard (95de633a), Shifts (42f6c1da) and Clipchamp (Stream embed) open from their app definitions in OST's TeamsJS host with Teams' header rules; checked live, signed in. Re-checked Whiteboard and Copilot on the merged build.
- Copilot row: Teams' hidden form post into the frame; dotted {user.id} placeholders now filled.
- Share to Outlook: Teams' server-made draft, Outlook compose dialog, draft deleted on close (no email sent).
- Immersive Reader: Teams' launch over the window with its token.
- Office files: Word/Excel/PowerPoint pages full screen as Teams' "Teams" choice; Settings > Files and links offers Teams / Desktop app / Browser.
- Channel Loop page tab confirmed signed in.
- Events and in-call Meeting Notes: TASK-0209.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Teams' embedded first-party apps run inside OST, signed in.

- Whiteboard, Shifts and Clipchamp from the app bar in OST's TeamsJS host.
- The chat list's Copilot row opens Copilot as Teams posts it.
- Message ··· > Share to Outlook (draft + embedded Outlook compose, draft removed on close) and Immersive Reader.
- Office files open in Office for the web inside OST; Settings > Files and links offers Teams' three choices.

Harness --embedded-apps-test. Follow-up TASK-0209 (Events, in-call Notes, reader card text).
<!-- SECTION:FINAL_SUMMARY:END -->
