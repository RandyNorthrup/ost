---
id: TASK-0287
title: 'Personal accounts: test accounts and live protocol capture'
status: In Progress
assignee:
  - '@agent-personal287'
created_date: '2026-11-25T15:26:00Z'
updated_date: '2026-11-27T17:43:00Z'
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
- [x] #3 The test tenant's setting for chat with personal accounts (AllowTeamsConsumer) is known, and enabled if it is off
- [x] #4 Two personal test accounts exist (created or signed in by an agent or the user) and are recorded in ~/coding/.secrets/creds.md
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-26 correction (user): agents may sign in to the test accounts themselves, typing the password (and TOTP) from ~/coding/.secrets/creds.md without printing it. "The assistant may not enter passwords" / "the user has to do it" was never a rule. How: backlog/docs "Signing in to test accounts".

- 2026-11-27: two personal test accounts created by the coordinator: ost-personal1-5135@outlook.com (OST Personal 1) and ost-personal2-0238@outlook.com (OST Personal 2). Passwords in ~/coding/.secrets/creds.md under '# OST personal test account 1/2'. Recovery emails ost-test1/ost-test2@scnetsolutions.com (codes readable with examples/graph_beta_get on linuxlt, OST_PROFILE=test2 for ost-test2). No MFA set up yet.

- 2026-11-27 AC3: read with Teams PowerShell (Connect-MicrosoftTeams device login as Randy). Get-CsTenantFederationConfiguration (Global): AllowTeamsConsumer True, AllowTeamsConsumerInbound True, AllowFederatedUsers True, AllowedDomains AllowAllKnownDomains, ExternalAccessWithTrialTenants Blocked. External access policy Global: EnableTeamsConsumerAccess True, EnableTeamsConsumerInbound True; ost-test1 and ost-test2 have no policy of their own (Global applies). Already on: nothing changed in the tenant.

- 2026-11-27 AC1 capture setup: two isolated headless Chrome profiles on this PC (CDP ports 9333/9334, own user-data dirs, fake media devices, no real mic) signed in to teams.live.com as OST Personal 1 and 2; a redacting CDP capture (tokens shown only as prefix/length/segments, JWT claims decoded without signatures). Sign-in needed the email code to the recovery mailbox (read with graph_beta_get). Probe script redeemed its own PKCE code and tried scopes/endpoints directly.
- AC2 setup: testpc2 Teams: OST Personal 2 added via profile menu > Add another account (Verify your email > Use your password instead > password > "Use this account everywhere on your device": chose "Microsoft apps only"; no email code was needed there). Opens in its own window. WebView2 CDP on testpc2 hung twice when Teams opened a new window/flyout, so the desktop checks use UIA + screenshots (screenshots in ~/.local/share/ost-remaining/personal/).
<!-- SECTION:NOTES:END -->
