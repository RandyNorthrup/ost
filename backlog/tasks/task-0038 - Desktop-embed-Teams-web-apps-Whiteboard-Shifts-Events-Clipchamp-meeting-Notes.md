---
id: TASK-0038
title: >-
  Desktop: embed Teams' web apps (Whiteboard, Shifts, Events, Clipchamp, meeting
  Notes)
status: To Do
assignee: []
created_date: '2026-11-06T04:53:00Z'
updated_date: '2026-11-16T14:55:00Z'
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
- [ ] #1 Whiteboard, Shifts, Events and Clipchamp open inside OST, signed in
- [ ] #2 Meeting Notes opens in the call window
- [ ] #3 The chat list's Copilot row (top of the list, as Teams) opens Copilot as Teams hosts it
- [ ] #4 Share to Outlook (message ··· ▸ Share to Outlook) opens Teams' embedded Outlook compose
- [ ] #5 Immersive Reader (message ···) opens Teams' embedded reader
- [ ] #6 Word, PowerPoint and Excel files open inside OST (Office for the web) as Teams' 'Teams' choice does, and Settings ▸ Files and links offers that choice as Teams
- [ ] #7 A channel's Loop page tab opens signed in, as Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built so far: Whiteboard and Clipchamp open inside OST (QtWebEngine, OST's own web profile; the same hosting serves Help, Communities, channel Page tabs and Workflows). Shifts and Events still open in the browser; meeting Notes, Copilot, Share to Outlook, Immersive Reader and Office for the web aren't embedded yet. (Audit 2026-11-16)

- 2026-11-16: unblocked by OST's TeamsJS host and broker (TASK-0053, TASK-0196). Today the app bar's Whiteboard opens Whiteboard's own site and shows Microsoft's Pick an account (OST Test 1 · Signed in); Teams runs it in its host, signed in.
<!-- SECTION:NOTES:END -->
