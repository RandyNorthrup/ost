---
id: TASK-0053
title: Channel Notes tab natively (OneNote)
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07T03:57:00Z'
updated_date: '2026-11-16T14:45:00Z'
labels:
  - notes
  - tabs
dependencies: []
references:
  - docs/spec/notes-tab.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Notes is OneNote's channel notes page, which Teams embeds (docs/spec/notes-tab.md; contentUrl is microsoft365.com/launch/onenote/officeunihost/teams). OST shows a notice instead. Per the 2026-11-07 scope decision (embed what Teams embeds), host it as Teams does: in OST's web view with a TeamsJS host (initialize, getContext, authentication.getAuthToken served from OST's tokens). Loaded without a host, the page stays blank (checked 2026-11-09).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Provisioning as Teams (team notebook + channel-named section, the wait screen)
- [x] #2 Page list, add page, page title/date, page content view and editing in OneNote's own embedded pages, as Teams embeds them
- [x] #3 Reload / Expand / Open in new window / App permissions act on the tab as Teams' do
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Research 2026-11-09 (TeamsJS traffic of the Notes iframe on winpc, observed read-only):
  - The officeunihost page calls getContext, nestedAppAuth.execute (GetInitContext, then GetToken for client 243c63a3-247d-41c5-9d83-7788c43f1c43, scopes e03a13ee-9730-4cae-8525-47559c8cf18a/.default and https://augloop.office.com/v2/.default, claims xms_cc CP1), authentication.getUser, registerHandler (load, beforeUnload, themeChange, focusEnter, log.request), appInitialization.appLoaded/success, and nestedAppAuth.manageNAATrustedOrigins (adds https://oauth.officeapps.live.com, which then sends its own GetToken).
  - OneNote's WOPI frame (usc-onenote.officeapps.live.com) posts Wac_* boot messages.
- Blocker found: Teams answers GetToken as the NAA broker. AAD refuses that brokering for OST's refresh token: "AADSTS700046: Invalid Reply Address. Reply Address must have scheme brk-1fec8e78-…:// and be of Single Page Application type". The hub's token must come from an SPA (browser, auth-code) sign-in, and OST signs in with the device-code flow.
- Plan: sign OST in through its web view with Teams' SPA flow (auth code + PKCE, teams.microsoft.com origin), keep that refresh token for NAA brokering, and share the web profile's session cookies so embedded pages (Page/Loop, Notes) get SSO as in Teams. Then a frameless TeamsJS host in WebApp: inject window.nativeInterface, answer through window.onNativeMessage.

- 2026-11-16 (subagent, c65b138, merged): OST now hosts Teams' embedded app pages as Teams does (docs/spec/app-host.md): a host page with Teams' origin frames the app and answers TeamsJS by postMessage from an isolated world; NAA tokens come from Rust (auth::broker, brk-multihub://<asking frame's host>). Notes is OneNote's own pages, as Teams embeds them (the native OneNote-API plan was dropped: embed what Teams embeds).
- Verified: General > Notes shows OneNote's editor, edit and undo, Reload, Expand, Open tab in new window and App permissions; first-opening provisioning in OST test channel 2 (wait page, section made, tab saved in Teams' form). Re-checked on the merged build.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The channel Notes tab works as in Teams, on a new TeamsJS host that serves every embedded app page.

- desktop/src/app_host.js + WebApp.qml teamsHost: Teams' framing (hwc-iframe attributes, beforeUnload/load relaunch) and answers to initialize, getContext, getUser, registerHandler, appLoaded/success/failure, NAA (GetInitContext, GetToken, GetTokenPopup, also from nested frames), trusted origins, setSettings/getSettings, setValidityState, executeDeepLink, themeChange, shortcutRelay.
- src/auth/broker.rs: Teams' broker requests, tokens in memory only and never logged. src/api/app_host.rs: Teams' context and valid-domain rule.
- Notes: OneNote's ChannelNotes provisioning and notebook page; the tab saved as Teams saves it.
- Also used by Storyline, Meeting Whiteboard, Q&A and app configuration pages.

Tests: 9 new unit tests; --app-host-test harness; live on linuxlt.
<!-- SECTION:FINAL_SUMMARY:END -->
