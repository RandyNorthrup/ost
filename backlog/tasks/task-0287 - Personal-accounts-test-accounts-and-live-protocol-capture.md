---
id: TASK-0287
title: 'Personal accounts: test accounts and live protocol capture'
status: To Do
assignee: []
created_date: '2026-11-25T15:26:00Z'
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
- [ ] #1 Two personal test accounts exist, created or signed in once by the user, and are recorded in ~/coding/.secrets/creds.md
- [ ] #2 Every item of 'Must verify live' in personal-accounts-protocol.md is confirmed or corrected from captures, and the doc marks each as verified
- [ ] #3 Every item of 'Verify on real Teams' in personal-accounts-features.md is checked on winpc's Teams desktop with a personal account next to ost-test1, with screenshots kept outside the repo
- [ ] #4 The test tenant's setting for chat with personal accounts (AllowTeamsConsumer) is known, and enabled if it is off
<!-- AC:END -->
