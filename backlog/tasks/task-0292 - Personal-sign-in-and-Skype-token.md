---
id: TASK-0292
title: Personal sign-in and Skype token
status: Done
assignee:
  - '@tperA'
created_date: '2026-11-25T15:26:00Z'
updated_date: '2026-11-28T04:41:00Z'
labels:
  - personal-accounts
dependencies:
  - TASK-0288
  - TASK-0290
references:
  - docs/research/personal-accounts-features.md
  - docs/research/personal-accounts-protocol.md
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Sign in with a personal Microsoft account the way Teams on the web for personal use does (its client, the consumers authority, teams.live.com redirect and origin), then get the Skype token and service map from teams.live.com's consumer authz. The leftover AuthConfig::personal() can't work (wrong redirect, refused scope) and is replaced.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A personal account signs in on Microsoft's own sign-in page in OST's window and stays signed in across restarts with silent token renewal
- [x] #2 OST gets the consumer Skype token and the regional service URLs, and refreshes them before they expire
- [x] #3 teams-cli can sign in with a personal account too
- [x] #4 Tokens are stored in the keyring per account and never logged
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Research live how Teams on the web for personal use keeps a session past the 24 h SPA refresh token (MSAL cache, silent iframe renewal, login.live.com cookies) and document it.
2. Renew a personal account's tokens each on its own expiry: oauth::refresh_expired (Skype token from authz v2 with ms-teams-authz-type TokenRefresh, MT, Graph), used by TeamsClient::new and Trouter; one refresh at a time per process (rotating refresh tokens).
3. teams-cli login --personal: device code with Teams' native client for personal accounts (8ec6bc83, consumers; the SPA client is refused device codes), stored as flow teams-live-device; refusals that keep work and personal profiles apart.
4. Token hygiene: Debug of Config/StoredToken/TokenSet/DeviceCode/authz answers redacts tokens; log scrubber covers five-part JWEs; tests for personal token shapes in logs, debug prints and config.toml.
5. Live checks on linuxlt with OST Personal 1/2 (expiry renewal, CLI sign-in), CI + Codex.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-27 (t290, PR #69) already in place for this task: BrowserSignIn::personal (client 4b3e8f46, consumers, https://teams.live.com/v2/authv2, Origin https://teams.live.com, scope openid profile offline_access), the work page's hand-off to it (spa::personal_hand_off / is_personal_address), finish_personal_sign_in (id_token identity), personal_tokens (auth.fl authz token -> consumer authz v2 Skype token, regionGtms, skypeid -> MRI; MT and Graph tokens; rotated refresh token kept), refresh() for TEAMS_LIVE_FLOW, AuthConfig::teams_live (AuthConfig::personal removed), skype::AuthzResponse parsing both shapes. Verified live with OST Personal 1 (sign-in, restart through the refresh token). Left here: silent prompt=none renewal before the 24 h refresh token ends (renew_sign_in is work-only), refreshing the 8 h Skype token on its own expiry, teams-cli sign-in, and the keyring/log checks.

Built so far (in open PR #69, TASK-0290 branch, not yet on main): personal sign-in in OST's window, consumer Skype token from authz v2, regional URLs, MT/Graph tokens and refresh-token restart (checked live with OST Personal 1). Left: silent prompt=none renewal, refreshing the 8 h Skype token on expiry (TeamsClient::new only checks access/Graph tokens), teams-cli sign-in for personal accounts, and an explicit keyring/log check.

- 2026-11-28 (tperA) How Teams on the web keeps a personal session past 24 h (captured live in an isolated headless Chrome on linuxlt, docs/research/personal-accounts-protocol.md §9.1): MSAL renews in a hidden iframe with prompt=none once its 24 h refresh token ends; login.live.com answers with a code when the browser holds the persistent "Stay signed in" cookie __Host-MSAAUTHP (390 days; MSPAuth/MSPProf/WLSSC too). OST's own silent URL (/consumers, openid profile offline_access, login_hint) returns a code too; without those cookies the answer is login_required. PR #69's interaction_required was not reproduced (an untrusted-device sign-in still renewed).
- Silent renewal re-enabled for personal accounts (desktop renew_sign_in at start and every 12 h with BrowserSignIn::personal(hint, prompt=none)). When it fails the account keeps using its refresh token (refresh), and once that is refused the sign-in page opens (unchanged). Verified live on linuxlt (profile tperAp1, OST Personal 1): restart -> "browser sign-in renewed"; with the keyring refresh token made unusable and every token expired -> renewed silently, Trouter connected; with login.live.com's session cookies removed -> login_required, carried on from the refresh token; both gone -> "personal account's session ended: signing in again".
- Skype token on its own expiry: oauth::refresh_expired renews only the lapsed tokens of a personal account (Skype token via authz v2 with ms-teams-authz-type TokenRefresh; MT 28,799 s; Graph 1 h), one refresh at a time per process (REFRESHING mutex; rotating refresh tokens). TeamsClient::new and the Trouter reconnect use it; work accounts refresh as before (plus an expired Skype token now triggers it). Live (CLI, tperAp2): Skype token marked expired in the keyring -> only "Personal account's Skype token renewed", MT and Graph untouched.
- teams-cli: `teams-cli login --personal` signs in with Teams' native client for personal accounts (8ec6bc83, "Microsoft Teams-T4L"; device code at microsoft.com/link; the SPA client is refused device codes, AADSTS70002). auth_flow teams-live-device; its refresh token isn't held to 24 h. Refusals keep personal and work profiles apart. Live: OST Personal 2 signed in on linuxlt, status/whoami/chats work.
- Tokens: Debug of Config/StoredToken/TokenSet/DeviceCode/authz answers now redacts tokens (length only); the log scrubber also covers five-part JWEs. Tests: feedback::personal_accounts_tokens_never_reach_the_log, storage_tests::a_personal_accounts_tokens_stay_out_of_the_file_and_debug_prints, login_tests. Live: config.toml of the CLI profile and the sign-in log hold no token shapes (grep eyJ/EwA/EwB/M.C: 0); tokens_in_keyring = true.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
A personal account now stays signed in past the 24-hour single-page-app refresh token, renews its 8-hour Skype token on its own expiry, can sign in from teams-cli, and its tokens stay out of logs, debug prints and the config file.

Research (docs/research/personal-accounts-protocol.md §9.1-9.2): Teams on the web for personal use renews with a hidden prompt=none sign-in that login.live.com answers from its persistent "Stay signed in" cookie (__Host-MSAAUTHP). OST's web view keeps that cookie, so the silent renewal works there too; PR #69's interaction_required was not reproduced.

Changes:
- Desktop: personal accounts renew silently at start and every 12 h like work ones (BrowserSignIn::personal, prompt=none); if login.live.com wants the user, OST carries on with the refresh token, then shows the sign-in page once that is refused.
- auth::oauth::refresh_expired renews only a personal account's lapsed tokens (Skype token via authz v2 with ms-teams-authz-type TokenRefresh, middle tier, Graph), one refresh at a time per process; TeamsClient::new and Trouter use it. Work accounts also refresh when their Skype token lapses.
- teams-cli login --personal: device code with Teams' native client for personal accounts (8ec6bc83; the web client is refused device codes), flow teams-live-device; personal and work profiles are kept apart.
- Redacted Debug for Config, StoredToken, TokenSet, DeviceCode and the authz answers; the log scrubber covers five-part JWEs.

Tests: login_tests (refusals, per-token expiry), storage_tests::a_personal_accounts_tokens_stay_out_of_the_file_and_debug_prints, feedback::personal_accounts_tokens_never_reach_the_log, skype/presence/trouter units.

Live (linuxlt, OST Personal 1 and 2): silent renewal at restart, with an unusable refresh token, without the Microsoft session (refresh-token fallback) and with both gone (sign-in page); Skype token renewed alone on expiry; teams-cli login --personal, status, whoami, chats; no token shapes in config.toml or the log.
<!-- SECTION:FINAL_SUMMARY:END -->
