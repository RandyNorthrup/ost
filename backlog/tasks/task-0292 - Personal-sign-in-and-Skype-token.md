---
id: TASK-0292
title: Personal sign-in and Skype token
status: To Do
assignee: []
created_date: '2026-11-25T15:26:00Z'
updated_date: '2026-11-28T01:04:00Z'
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
- [ ] #1 A personal account signs in on Microsoft's own sign-in page in OST's window and stays signed in across restarts with silent token renewal
- [ ] #2 OST gets the consumer Skype token and the regional service URLs, and refreshes them before they expire
- [ ] #3 teams-cli can sign in with a personal account too
- [ ] #4 Tokens are stored in the keyring per account and never logged
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-27 (t290, PR #69) already in place for this task: BrowserSignIn::personal (client 4b3e8f46, consumers, https://teams.live.com/v2/authv2, Origin https://teams.live.com, scope openid profile offline_access), the work page's hand-off to it (spa::personal_hand_off / is_personal_address), finish_personal_sign_in (id_token identity), personal_tokens (auth.fl authz token -> consumer authz v2 Skype token, regionGtms, skypeid -> MRI; MT and Graph tokens; rotated refresh token kept), refresh() for TEAMS_LIVE_FLOW, AuthConfig::teams_live (AuthConfig::personal removed), skype::AuthzResponse parsing both shapes. Verified live with OST Personal 1 (sign-in, restart through the refresh token). Left here: silent prompt=none renewal before the 24 h refresh token ends (renew_sign_in is work-only), refreshing the 8 h Skype token on its own expiry, teams-cli sign-in, and the keyring/log checks.

Built so far (in open PR #69, TASK-0290 branch, not yet on main): personal sign-in in OST's window, consumer Skype token from authz v2, regional URLs, MT/Graph tokens and refresh-token restart (checked live with OST Personal 1). Left: silent prompt=none renewal, refreshing the 8 h Skype token on expiry (TeamsClient::new only checks access/Graph tokens), teams-cli sign-in for personal accounts, and an explicit keyring/log check.
<!-- SECTION:NOTES:END -->
