---
id: TASK-0369
title: >-
  Open Teams meeting links straight into OST (msteams: handler and link
  arguments)
status: To Do
assignee: []
created_date: '2026-11-27T20:27:00Z'
labels:
  - desktop
  - meetings
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A Reddit user asked whether meeting links can open straight in OST. Today they can't: the desktop entry claims no URL scheme and ost-desktop rejects unknown arguments. Teams' web 'Open in app' / launcher pages hand the browser an msteams: link (msteams:/l/meetup-join/...), and people also paste https://teams.microsoft.com/l/meetup-join/..., teams.microsoft.com/meet/<id>?p=..., and teams.live.com/meet/... links. OST should register as the msteams: handler and accept these links on the command line, passing them to the running window through the existing single-instance socket, then show the same pre-join screen Teams shows.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The desktop entry (and Flatpak) registers OST for x-scheme-handler/msteams, so clicking 'Open in app'/'Join on the Teams app' in a browser launches OST
- [ ] #2 ost-desktop accepts a meeting link argument (msteams:, https://teams.microsoft.com/l/meetup-join/..., teams.microsoft.com/meet/<id>?p=..., teams.live.com/meet/...) instead of rejecting it as an unknown option
- [ ] #3 When OST is already running, the link goes to the running window over the single-instance socket; when it isn't, OST starts and opens the link after sign-in
- [ ] #4 Opening a meeting link shows the pre-join screen for that meeting (or the lobby for external/anonymous meetings), the same as Teams desktop
- [ ] #5 Links for other Teams link types (chat, channel, message, file) open the matching place in OST, or show a clear message when OST can't open that kind of link
- [ ] #6 Only Teams meeting/link URLs are accepted; anything else is rejected without being opened or fetched
- [ ] #7 Documented in the wiki/README, including how to make OST the msteams: handler (xdg-mime default) and how to use it from the browser
<!-- AC:END -->
