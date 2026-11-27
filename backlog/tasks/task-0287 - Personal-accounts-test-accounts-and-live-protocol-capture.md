---
id: TASK-0287
title: 'Personal accounts: test accounts and live protocol capture'
status: To Do
assignee: []
created_date: '2026-11-25T15:26:00Z'
updated_date: '2026-11-27T17:00:00Z'
labels:
  - personal-accounts
dependencies: []
references:
  - docs/research/personal-accounts-features.md
  - docs/research/personal-accounts-protocol.md
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams for personal use (personal Microsoft accounts: outlook.com, hotmail, live.com) uses different sign-in and services from work Teams. The research in docs/research/ is from documentation, Teams' public web client and open-source clients; nothing has been checked with a signed-in personal account. Before building, capture the real flows with dedicated personal test accounts (never the user's own account, so no real people are ever messaged), on teams.live.com and on the Teams desktop app on winpc.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every item of 'Must verify live' in personal-accounts-protocol.md is confirmed or corrected from captures, and the doc marks each as verified
- [ ] #2 Every item of 'Verify on real Teams' in personal-accounts-features.md is checked on winpc's Teams desktop with a personal account next to ost-test1, with screenshots kept outside the repo
- [ ] #3 The test tenant's setting for chat with personal accounts (AllowTeamsConsumer) is known, and enabled if it is off
- [x] #4 Two personal test accounts exist (created or signed in by an agent or the user) and are recorded in ~/coding/.secrets/creds.md
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-26 correction (user): agents may sign in to the test accounts themselves, typing the password (and TOTP) from ~/coding/.secrets/creds.md without printing it. "The assistant may not enter passwords" / "the user has to do it" was never a rule. How: backlog/docs "Signing in to test accounts".

- 2026-11-27: two personal test accounts created by the coordinator: ost-personal1-5135@outlook.com (OST Personal 1) and ost-personal2-0238@outlook.com (OST Personal 2). Passwords in ~/coding/.secrets/creds.md under '# OST personal test account 1/2'. Recovery emails ost-test1/ost-test2@scnetsolutions.com (codes readable with examples/graph_beta_get on linuxlt, OST_PROFILE=test2 for ost-test2). No MFA set up yet.
<!-- SECTION:NOTES:END -->
