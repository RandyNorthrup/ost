---
id: TASK-0290
title: 'Several accounts: add a personal account, switch, sign out one'
status: Done
assignee:
  - '@t290'
created_date: '2026-11-25T15:26:00Z'
updated_date: '2026-11-28T01:56:00Z'
labels:
  - personal-accounts
dependencies:
  - TASK-0288
references:
  - docs/research/personal-accounts-features.md
  - docs/research/personal-accounts-protocol.md
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams desktop runs one personal account next to work accounts: the profile menu has Add another account, lists the accounts to switch between, and signs out of one account without the others. OST signs in to one account per profile today.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The profile menu lists the signed-in accounts with Add another account and Sign out, matching Teams desktop (verified side by side on winpc)
- [x] #2 Each account keeps its own tokens, settings and caches; switching shows the other account without signing in again
- [x] #3 Only one personal account can be added, with Teams' message when a second is tried
- [x] #4 Signing out of one account leaves the others signed in
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Reuse the work multi-account machinery (profiles, switch_account, add_account, MtmaHub, Accounts and orgs). New: a personal (MSA) account as one of the profiles.
1. Sign-in: Microsoft's page opens at the common authority, so a personal email is accepted as in Teams' Add another account; OST catches the hand-off to login.live.com and continues with Teams free's web sign-in (client 4b3e8f46, consumers, return https://teams.live.com/v2/authv2, Origin https://teams.live.com) with the same email.
2. Personal tokens: redeem the code, identity from the id_token (name, email, oid -> 8:live:.cid.<hex>), consumer authz v2 for the Skype token and regionGtms; refresh() renews them for the personal flow (TASK-0292 keeps the silent 24 h renewal, teams-cli and the rest).
3. Accounts list: kind per account; a second personal account is refused after its sign-in with Teams' dialog (Multiple personal accounts aren't supported in Teams yet. / Open Teams on the web / Cancel), and its tokens, profile folder and web storage are removed.
4. Profile menu as Teams: personal window header Personal + Sign out, My Microsoft account, no Pause notifications or Set work location; work window keeps the round avatar when the only other account is personal; window titles gain Personal/org and email once a second account exists.
5. Sign out of one account: only that profile's tokens and storage go; with other accounts signed in, its window closes instead of returning to sign-in.
6. Personal window loads its shell without the work-only calls failing it (chat list etc. come in TASK-0293).
7. Tests (spa, identity, config, skype parsing), build on a build box, live: two work profiles (test2+test3) for AC1/2/4, OST Personal 1 + 2 for AC3 and the personal menu; Teams desktop reference on testpc2.
8. TASK-0291: check its ACs live against Teams on a test PC; check off what holds, note the rest, build small gaps.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-27 (t290) PR #69. Built: personal sign-in route (work page's hand-off to login.live.com through Azure AD's MSA federation client 51483342…, or its "can't sign in here with a personal account" refusal + realm discovery, then Teams free web's sign-in for that address); personal tokens (id_token identity 8:live:.cid, consumer authz v2 Skype token + regionGtms + skypeid, MT and Graph tokens, refresh); account kind in accounts.json; second personal refused with Teams' dialog (PersonalRefusedDialog.qml) and its profile removed; personal profile menu (Personal header, My Microsoft account, no Pause notifications / work location); org pill only beside another work account; window titles name the account; Accounts and orgs "Personal"; sign-out of one account closes its window and removes its profile, others stay; quit via exit() (Qt 6 quit() was swallowed by keep-running's hide); app-definition load backoff (Avatars app looped on a refused token).
- Gotcha: OST Personal 1 is a B2B guest in scnetsolutions (TASK-0287), so the plain work sign-in signed it in as a guest (GuestUserNotRedeemed). The hand-off catch prevents that.
- Live on linuxlt (isolated XDG dirs, profiles t290w=ost-test2, t290x=ost-test3, t290p=OST Personal 1, t290q=OST Personal 2): AC1 flyouts and Accounts and orgs match Teams 26304 on testpc2 (ac2-02/ac2-11/ac2-set-04); AC2 switch raises the running window with no sign-in, the personal account survives a restart; AC3 Personal 2 gets Teams' dialog after its sign-in, Cancel closes the window and removes profile/web storage/keyring entry; AC4 signing out of t290x and then t290p closed each window and removed its profile while the others stayed signed in.
- The AC says side by side on winpc; the Teams reference used is testpc2 (Teams 26304, OST Test 2 + OST Personal 2, the primary reference), since winpc's Teams has no personal account and other agents use it.
- Not live: Open Teams on the web (opens a browser); the first profile's sign-out with others left (it shares the real default keyring entry on linuxlt). Email codes for the personal accounts were read with ~/ost-coord/graph_beta_get (ost-test1 / OST_PROFILE=test2).

- Review rounds (Codex on PR #69): exact state-file names on profile removal; a failed app-definition load signals ready again after its 60 s wait; personal accounts now renew their 24 h browser session silently too (auth::browser_session, BrowserSignIn::personal(hint, prompt=none)) - not run live yet; a legacy Skype name becomes 8:<name>, not 8:orgid:.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
OST can now add one personal Microsoft account next to its work accounts, as Teams desktop does. Each account keeps its own profile and window.

Changes:
- Sign-in: when Microsoft's work page hands a personal address to login.live.com (Azure AD's Microsoft-account federation), or refuses it, OST continues with Teams on the web for personal use's sign-in for that address. Without this, a personal account that is a guest in a work tenant was signed in as that guest.
- Personal tokens: identity from the id_token (8:live:.cid MRI), consumer authz v2 Skype token, regionGtms and skypeid, MT and Graph tokens, refresh and silent renewal. AuthConfig::personal() is replaced by teams_live().
- Account kind in accounts.json. A second personal account gets Teams' "Multiple personal accounts aren't supported in Teams yet." dialog after its sign-in, and its profile is removed.
- Teams' personal profile menu (Personal, My Microsoft account, no Pause notifications or work location). The org pill shows only next to another work account. Window titles name the account. Accounts and orgs lists the account under "Personal".
- Signing out of one account closes its window and removes its profile (config, keyring entry, web storage, state files); the others stay signed in.
- Quit uses exit(): Qt 6 quit() was swallowed by keep-running's hide, so sign-out, Save and restart and Refresh license and restart never quit in a plain launch.
- A failed app-definition load backs off for a minute (the Avatars app looped on a refused token).
- Harness --accounts-cmd / OST_ACCOUNTS_CMD. Docs: help sign-in page, desktop.md.

Verified live on linuxlt (ost-test2, ost-test3, OST Personal 1 and 2; Teams 26304 reference on testpc2): all four ACs, see notes. Tests: spa, identity, skype, config units; CI green.

Not verified live: Open Teams on the web; the first profile's sign-out with other accounts left; the personal silent renewal (added in review). The personal window's content and work-only calls are TASK-0293..0297, and teams-cli sign-in is TASK-0292.
<!-- SECTION:FINAL_SUMMARY:END -->
