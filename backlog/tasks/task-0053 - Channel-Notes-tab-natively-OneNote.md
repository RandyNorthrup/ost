---
id: TASK-0053
title: Channel Notes tab natively (OneNote)
status: To Do
assignee: []
created_date: '2026-11-07T03:57:00Z'
updated_date: '2026-11-09T15:31:00Z'
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
- [ ] #1 Provisioning as Teams (team notebook + channel-named section, the wait screen)
- [ ] #2 Page list, add page, page title/date, page content view and editing through the OneNote API
- [ ] #3 Reload / Expand / Open in new window / App permissions act on the native view as Teams' do
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Research 2026-11-09 (TeamsJS traffic of the Notes iframe on winpc, observed read-only):
  - The officeunihost page calls getContext, nestedAppAuth.execute (GetInitContext, then GetToken for client 243c63a3-247d-41c5-9d83-7788c43f1c43, scopes e03a13ee-9730-4cae-8525-47559c8cf18a/.default and https://augloop.office.com/v2/.default, claims xms_cc CP1), authentication.getUser, registerHandler (load, beforeUnload, themeChange, focusEnter, log.request), appInitialization.appLoaded/success, and nestedAppAuth.manageNAATrustedOrigins (adds https://oauth.officeapps.live.com, which then sends its own GetToken).
  - OneNote's WOPI frame (usc-onenote.officeapps.live.com) posts Wac_* boot messages.
- Blocker found: Teams answers GetToken as the NAA broker. AAD refuses that brokering for OST's refresh token: "AADSTS700046: Invalid Reply Address. Reply Address must have scheme brk-1fec8e78-…:// and be of Single Page Application type". The hub's token must come from an SPA (browser, auth-code) sign-in, and OST signs in with the device-code flow.
- Plan: sign OST in through its web view with Teams' SPA flow (auth code + PKCE, teams.microsoft.com origin), keep that refresh token for NAA brokering, and share the web profile's session cookies so embedded pages (Page/Loop, Notes) get SSO as in Teams. Then a frameless TeamsJS host in WebApp: inject window.nativeInterface, answer through window.onNativeMessage.
<!-- SECTION:NOTES:END -->
