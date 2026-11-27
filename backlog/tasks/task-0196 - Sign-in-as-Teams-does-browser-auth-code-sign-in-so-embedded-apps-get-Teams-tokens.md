---
id: TASK-0196
title: >-
  Sign in as Teams does (browser auth-code sign-in), so embedded apps get Teams'
  tokens
status: Done
assignee:
  - '@claude'
created_date: '2026-11-16T05:21:00Z'
updated_date: '2026-11-27T05:08:00Z'
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
- [x] #2 Embedded apps get their tokens through Teams' broker (NAA) without a separate sign-in, as in Teams
- [x] #3 Signing out and switching accounts work as in Teams
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
  - OST's web profile (linuxlt) has no ESTS session cookie, so each account needs one interactive sign-in. An agent does it, typing the password (and TOTP) from ~/coding/.secrets/creds.md.

- 2026-11-16: built and tested up to Microsoft's password step:
  - src/auth/spa.rs, AadClient Origin/code redemption, the config's auth_flow, the backend's sign_in_navigated/renew_sign_in, SignIn.qml's web view, and the hidden 12-hour renewer.
  - Microsoft's page loads in OST with Teams on the web's client.
- Completing it needs ost-test1's password typed once in OST's web profile. An agent types it from creds.md; see backlog/docs "Signing in to test accounts".
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

- 2026-11-16: Teams' broker (NAA) built in the engine: auth::brokered_token(app client, app origin, scope, claims) and AadClient::broker_refresh.
  - Captured from Teams on the web running in OST's own web profile: the token POST carries the app's client_id in the query and body, brk_client_id=5e3ce6c0… and brk_redirect_uri=https://teams.cloud.microsoft/v2/authv2, redirect_uri=brk-multihub://<the app page's host>, scope "<app scope> openid profile offline_access", client_info=1, and optional claims (xms_cc CP1).
  - Verified: a token for Viva Engage (f4060917…, aud engage.cloud.microsoft/teams-branded-exp) minted from OST's sign-in.
  - Channel Notes (243c63a3…) still needs its page's real host: the TeamsJS host will pass the asking frame's origin.
- Left for AC2: answer TeamsJS nestedAppAuth GetToken in OST's app host (WebApp) with this broker.

- 2026-11-16: the app side, from MSAL's NAA bridge source and TeamsJS's nestedAppAuthUtils:
  - Apps post {messageType:"NestedAppAuthRequest", requestId, method:GetInitContext|GetToken|GetTokenPopup, tokenParams:{clientId, scope, correlationId, claims, authority…}} to window.nestedAppAuthBridge.
  - The host answers {messageType:"NestedAppAuthResponse", requestId, success, initContext | token{access_token, id_token, expires_in, scope, authority} + account | error{status, code, description}}.
  - TeamsJS won't polyfill the bridge in a frameless window, so OST's frameless app view must inject window.nestedAppAuthBridge itself, answering with auth::brokered_token, the page's origin and a check on the allowed client ids.
  - The first app that needs it is channel Notes (TASK-0053), whose page also needs the TeamsJS host (initialize, getContext…). The bridge goes in with that task.

- 2026-11-16: sign-out and back in verified on the test profile.
  - After signing out, OST opens Microsoft's "Pick an account" with OST Test 1 marked "Signed in", as Teams shows it. One click on the tile, with no password, signed back in (auth_flow teams-web).
  - Switching to another account is the page's "Use another account" (that account's own sign-in). Adding a second account side by side is TASK-0078.
- Left:
  - Move the main ost-test1 profile to this sign-in: sign out, then one click. Wait until no agent uses that profile.
  - The app-side bridge, with TASK-0053.

- Agent run finished; the default ost-test1 profile is free to move to the browser sign-in.

- 2026-11-16: the main ost-test1 profile (default OST_PROFILE) on linuxlt moved to the browser sign-in: logout, then one click on "OST Test 1 · Signed in" in Microsoft's picker (the div.table[role=button] tile). auth_flow = teams-web; a restart signs in from the stored sign-in and loads chats.
- Left: OST Test 2 (profile test2) and the app-side NAA bridge with TASK-0053.

- Embedded apps get NAA tokens through OST's host (TASK-0053): OneNote's editor and its nested frames, Storyline and Whiteboard sign in with no separate sign-in.

- 2026-11-26 correction (user): agents may sign in to the test accounts themselves, typing the password (and TOTP) from ~/coding/.secrets/creds.md without printing it. "The assistant may not enter passwords" / "the user has to do it" was never a rule. How: backlog/docs "Signing in to test accounts".
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
OST signs in exactly as Teams on the web does, and embedded apps get their tokens through Teams' broker.

- src/auth/spa.rs: Teams on the web's single-page-app sign-in (client 5e3ce6c0…, auth code + PKCE, return address teams.cloud.microsoft/v2/authv2, Origin header), shown in OST's web view; silent renewal every 12 h with prompt=none from the web profile's Microsoft session.
- auth::brokered_token / broker: Teams' NAA broker requests (brk_client_id, brk-multihub://<app host>) for embedded apps.
- Sign-out shows Microsoft's Pick an account; one click signs back in.
- The main ost-test1 profile moved to this sign-in; device-code sign-ins keep working until replaced (OST Test 2 still uses one).

Tests: sign-in URL, return address, broker address and renewal unit tests; live sign-in, renewal, sign-out/in, and NAA tokens for Engage, OneNote and Storyline.
<!-- SECTION:FINAL_SUMMARY:END -->
