---
id: TASK-0196
title: >-
  Sign in as Teams does (browser auth-code sign-in), so embedded apps get Teams'
  tokens
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-16T05:21:00Z'
updated_date: '2026-11-16T06:32:00Z'
labels:
  - desktop
  - auth
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OST signs in with Teams desktop's own client id through the device-code flow. Microsoft refuses to broker tokens for embedded apps (NAA, used by the channel Notes tab, Loop/Page, Whiteboard and Clipchamp SSO) from a device-code sign-in (AADSTS700046: the reply address must be brk-<client>:// of Single Page Application type). Teams signs in through Microsoft's sign-in page instead. The user asked for OST to sign in the same way (2026-11-16).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 OST's sign-in opens Microsoft's sign-in page as Teams does and keeps the session; existing device-code sign-ins keep working until replaced
- [ ] #2 Embedded apps get their tokens through Teams' broker (NAA) without a separate sign-in, as in Teams
- [ ] #3 Signing out and switching accounts work as in Teams
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Engine (src/auth/spa.rs): Teams web's browser sign-in. Client 5e3ce6c0-2b1f-4285-8d4b-75ee78787346, return address https://teams.cloud.microsoft/v2/authv2, code + PKCE, token calls sent with Origin https://teams.cloud.microsoft. Config remembers the flow, refresh uses the matching client, and device-code sign-ins keep working (CLI/TUI).
2. Desktop sign-in: Microsoft's page in a WebEngineView on OST's persistent web profile (ost-apps), so the session cookies are shared with embedded apps. The return address is caught, then the code is redeemed.
3. Renewal: browser-style refresh tokens last 24 h. Renew silently with prompt=none in a hidden view on the same profile, as Teams web's MSAL does.
4. Broker for embedded apps (NAA): GetToken answered with brk_client_id/brk_redirect_uri as Teams web (follows in TASK-0053's TeamsJS host).
5. Verify with ost-test1 after the user's one-time sign-in; sign out and switch accounts.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-16 research:
  - Teams desktop on Windows signs in through WAM (no MSAL cache in its pages), which doesn't exist on Linux.
  - Teams on the web (teams.cloud.microsoft) uses MSAL.js with client 5e3ce6c0-2b1f-4285-8d4b-75ee78787346.
  - Embedded apps' tokens come from POST {tenant}/oauth2/v2.0/token?client_id=<app>&brk_client_id=5e3ce6c0…&brk_redirect_uri=https://teams.cloud.microsoft/v2/authv2.
  - OST's web profile (linuxlt) has no ESTS session cookie, so each account needs one interactive sign-in by the user (passwords can't be typed by the assistant).

- 2026-11-16: built and tested up to Microsoft's password step:
  - src/auth/spa.rs, AadClient Origin/code redemption, the config's auth_flow, the backend's sign_in_navigated/renew_sign_in, SignIn.qml's web view, and the hidden 12-hour renewer.
  - Microsoft's page loads in OST with Teams on the web's client.
- Blocked: completing it needs ost-test1's password typed once in OST's web profile. The assistant may not enter passwords; the user declined to type it.
  - A work account's page offers no password-free "sign in from another device".
  - The single-page app's 24-hour refresh token also needs that web session to renew.
- Shipped behind OST_BROWSER_SIGN_IN=1; device code stays the default.
- Over waypipe, Qt WebEngine hit a SIGTRAP in the main thread about 30 s after start, twice. Directly on linuxlt it didn't. This is a remote-display issue, not the sign-in code.

- 2026-11-16: the user asked for the browser sign-in to be the default. New sign-ins go to Microsoft's page; existing device-code sign-ins (ost-test1, OST Test 2) keep refreshing with their own client. OST_DEVICE_CODE=1 is the fallback.

- 2026-11-16 22:16: verified live. The user signed in ost-test1 once through Microsoft's page in OST (spatest profile). The code was redeemed with Teams on the web's client and origin, the config shows auth_flow "teams-web" (tokens in the keyring), and OST loaded the account's chats. The Microsoft session was kept in OST's web profile (ESTSAUTH, ESTSAUTHPERSISTENT), so silent renewal can use it.
- Fixed on the way:
  - Closing the sign-in view inside its navigation request crashed Chromium (SIGTRAP); it now closes on the next event-loop turn.
  - The video filter app no longer loads while signed out.
  - The desktop app has no device-code sign-in any more (user's request).

- 2026-11-16: silent renewal verified. Restarting the signed-in profile renewed through the hidden view (prompt=none, OST's web session) with no page or password and stored fresh tokens. Fixed first: at start-up the sign-in screen began a visible sign-in that replaced the renewal's request (state mismatch). The renewal now has its own pending request, and the backend starts a visible sign-in only when nothing is stored.
<!-- SECTION:NOTES:END -->
