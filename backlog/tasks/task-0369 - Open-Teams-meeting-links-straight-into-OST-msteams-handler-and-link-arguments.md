---
id: TASK-0369
title: >-
  Open Teams meeting links straight into OST (msteams: handler and link
  arguments)
status: Done
assignee:
  - '@t369'
created_date: '2026-11-27T20:27:00Z'
updated_date: '2026-11-28T00:48:00Z'
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
- [x] #1 The desktop entry (and Flatpak) registers OST for x-scheme-handler/msteams, so clicking 'Open in app'/'Join on the Teams app' in a browser launches OST
- [x] #2 ost-desktop accepts a meeting link argument (msteams:, https://teams.microsoft.com/l/meetup-join/..., teams.microsoft.com/meet/<id>?p=..., teams.live.com/meet/...) instead of rejecting it as an unknown option
- [x] #3 When OST is already running, the link goes to the running window over the single-instance socket; when it isn't, OST starts and opens the link after sign-in
- [x] #4 Opening a meeting link shows the pre-join screen for that meeting (or the lobby for external/anonymous meetings), the same as Teams desktop
- [x] #5 Links for other Teams link types (chat, channel, message, file) open the matching place in OST, or show a clear message when OST can't open that kind of link
- [x] #6 Only Teams meeting/link URLs are accepted; anything else is rejected without being opened or fetched
- [x] #7 Documented in the wiki/README, including how to make OST the msteams: handler (xdg-mime default) and how to use it from the browser
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Research Teams desktop (winpc AppxManifest: msteams, web+msteams, app URI handler hosts teams.microsoft.com/teams.cloud.microsoft) and the web launcher (launcher.js + its server flags) for what the browser hands the OS.
2. desktop/src/teams_link.rs: allowlisted parser (schemes msteams/web+msteams, https on Teams hosts) into a TeamsLink (meeting, meeting ID, Teams free meeting, chat, new chat, channel/team, message, file, in-app, unsupported); unit tests.
3. main.rs: accept one Teams link argument in release builds, hand it over on the instance socket (link\t line, re-parsed by the listener), keep it pending when OST starts; Flatpak-shared socket path.
4. Backend: pending link + take_teams_link/teams_link_json/teams_link_requested; pre-join title and times from the preheated call's meetingDetails.
5. QML: openTeamsLink routes each kind (pre-join, Join with an ID, chat, channel, message, new chat, file viewer, toast with Open in browser); in-message Teams links use it too; positional args skip links.
6. Desktop entries (packaged + generated): MimeType x-scheme-handler/msteams;web+msteams and %u.
7. Docs (docs/desktop.md, README, wiki); live check on linuxlt with a throwaway handler; PR.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Teams desktop (winpc, MSTeams 26304) registers msteams, web+msteams, msteamscanary and an app URI handler for teams.microsoft.com and teams.cloud.microsoft. Its pre-join for an msteams: link shows the meeting title and times.
- Teams' launcher (launcher.42400f39.js and its server flags) hands the desktop web+msteams:<decoded url= path>&deeplinkId&launchAgent=join_launcher&fqdn=teams.microsoft.com (enableWebMsteamsProtocol and enableFQDN are on). On Linux it never offers the app: getAutoJoinWebBehaviour returns ContinueToWebAsOnlyOption, so the page goes straight to web join. Seen live in a fresh Chrome on linuxlt. With a Windows UA the page shows "Join on the Teams app", which reached OST through KDE's portal "Choose Application" (verified). The docs say this and give the Linux routes: ost-desktop '<link>' and xdg-open msteams:.
- Implemented teams_link.rs (allowlist parser), the link\t socket protocol, the pending link that waits for sign-in and the push channel, pre-join title and times from the preheated call's meetingDetails, QML openTeamsLink, and MimeType and %u in both desktop entries. In-message Teams links are routed the same way.
- Live on linuxlt (OST Test 3, virtual mic, throwaway xdg-mime default, undone afterwards): msteams: with OST not running and running, the https argument with OST not running, the /meet/ short link while running, channel, chat, message (scrolls to an older post), new chat (draft prefilled, not sent, cleared), /l/call (toast), teams.live.com (toast). Non-Teams lines on the socket were refused.
- PR #57. Codex P2s fixed (new-chat form reset; chat subviews closed).

- Codex rounds on PR #57 were all fixed. The new-chat form resets; chat subviews, the tab and post details close; a cancelled lookup stops; unfound people are reported and the message isn't placed; the calendar match uses thread plus message id; names come only from OST's lists (security finding: the link's channel name is never shown); reply links open the post's thread. Final head aaf20240: 12/12 checks green, Codex code and security reviews with no open findings, no unresolved threads.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Teams links now open straight in OST, as in Teams desktop (PR #57).

- OST registers for x-scheme-handler/msteams and web+msteams (the packaged entry, and the one OST writes itself for AppImage, tarball and build folders), with Exec … %u. `ost-desktop '<Teams link>'` takes one link.
- A running OST gets the link over the single-instance socket. Otherwise OST opens it after sign-in, once the push channel is up.
- Each link opens what Teams desktop opens:
  - meetup-join: the pre-join, with the title and times from the meeting
  - /meet/<ID>?p=: Join with an ID, then the pre-join
  - a chat, a new chat with people and message prefilled, a channel or team, a message
  - a file, in the viewer (SharePoint only)
  - app and settings links
  - Teams free meetings and other kinds: a toast with Open in browser
- Only msteams:/web+msteams: and https on teams.microsoft.com, teams.cloud.microsoft and teams.live.com are taken. Anything else is refused without being read or fetched.
- The instance socket moves to the Flatpak app runtime folder inside Flatpak.
- Docs: docs/desktop.md, the README, and the wiki page Meeting links. On Linux, Teams' launcher page never offers "Join on the Teams app" (ContinueToWebAsOnlyOption); the docs give the ways around it.
- Tests: unit tests for the parser, argument handling and the desktop entry. CI is green. Live checks on linuxlt are listed in the PR.
- Not verified live: file links, packages other than the self-written entry, and the two Codex follow-up fixes. Teams free meetings wait for TASK-0298.
<!-- SECTION:FINAL_SUMMARY:END -->
