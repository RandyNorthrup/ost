---
id: TASK-0078
title: >-
  Profile flyout items as Teams: Pause notifications, work location, out of
  office, accounts
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-09T16:14:00Z'
updated_date: '2026-11-21T19:37:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The rest of Teams desktop's profile flyout, measured on winpc: each item behaves as in Teams, with the same data and services, so OST's flyout matches item for item.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Pause notifications works as Teams' (durations, the flyout row, banners held while paused)
- [x] #2 Set work location shows and sets the same location Teams does, when the tenant offers it
- [x] #3 Schedule out of office opens Teams' out-of-office dialog and saves the same automatic replies
- [ ] #4 Add another account behaves as Teams' (OST's sign-in, separate profiles)
- [x] #5 Others' status messages show in their profile cards and the 1:1 chat header as in Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Pause notifications done (see commit): durations, paused card with edit/resume, Custom dialog with Fluent date picker, DND banner; verified both ways with Teams on winpc (OST pause showed "Notifications paused, Until 12:29 AM" in Teams; OST resume put Teams back to Available). Banner Change settings opens Notifications until Settings gets Privacy (TASK-0088).

- Set work location done: Office / Remote / Clear as Teams (PUT v1/me/workLocation/ with location 1/2/0, captured from Teams); OST-set Office showed "In the office" in Teams; cleared from OST and Teams showed Set work location again.

- Own pinned status message banner (presence-statusmessage-banner) and banner queue as Teams (9da2f31); verified against Teams on winpc (same text and date format; dismissing DND revealed the note banner in both).

- AC #5 (others' status message / out of office above compose, profile cards): strings found ("Status of {memberOne}: {message}", "{memberOne} is out of office and may not respond"); measuring the compose banner needs a second account's view (Randy's Teams web) and the Chrome Control extension is disconnected (native host registered to app/current, server is versions/1.11.0; needs browser_extension_install or the user to reload). Profile cards don't exist in OST yet: TASK-0089.

- Schedule out of office: opens Settings > General > Out of office (Teams' page), saving Teams' automatic replies (updateAutomaticRepliesSetting); OST saved on/off, checked with the server read.

- AC5: profile cards (TASK-0089) show others' status messages; the compose status/OOF banner still needs measuring from a second account.

- AC5 (2026-11-11): measured Teams' bar over a 1:1's compose box with OST Test 2's pinned status message seen by OST Test 1 ("Status of OST Test 2: …", 29.33 tall, #E6E6E6, Close notification); OST shows the same from its presence refresh (peerNote on chat entries), plus Teams' out-of-office line. Teams' 1:1 header shows no status message; profile cards do (TASK-0089). Test note cleared afterwards.

- AC4 research (2026-11-11): Teams' flyout ends with "Add another account"; with more accounts it lists them ("Switch to account {upn}, Status {availability}") and has an "Accounts and orgs" settings page and "Activity in other accounts and orgs" (new window). Its two-account layout can't be measured here without signing a second account into Teams on winpc (a password in Microsoft's sign-in), so AC4 waits for that view.

- 2026-11-21 (agent setH) AC4 built, as far as one account in Teams allows measuring:
  - Teams (winpc, one account): the flyout ends with a footer row "Add another account" (me-control-menu-add-account: 65 tall under a 1.3 px #F5F5F5 rule on #F0F0F0, a 32 px round slot at 26 with a 16 px person-add glyph #616161, the text 14/600 at 76). Teams' MTMA strings (nova) for more accounts: "Switch to account {upn},  Status {availability}", "Activity in other accounts and orgs".
  - OST: each account lives in its own profile (OST_PROFILE: its own config folder, keyring entry, instance socket and windows). The device's accounts are kept in ~/.config/teams-cli/accounts.json (teams_cli::config::Account / accounts / record_account, recorded at sign-in, removed at sign-out, with each account's presence). The flyout lists your other accounts (picture, name, e-mail, presence; "Switch to account …" brings that account's window forward, or starts it) and ends with Teams' "Add another account" footer, which starts OST for a new profile (account2, account3, …), where OST's own sign-in runs.
  - Verified on linuxlt (OST Test 2, --seth-test --seth-accounts): the flyout listed OST Test 1 (the default profile) above Add another account (picture sh-flyout); Add another account started a new OST with OST_PROFILE=account2 (stopped by pid, nothing signed in; its window was still blank 20 s in, so the sign-in page wasn't seen loading).
  - Open: Teams' layout with two accounts signed in (it needs a second account signed in to Teams on winpc, which takes a password at Microsoft's sign-in, so the user has to do it), and Teams' "Activity in other accounts and orgs" window.
<!-- SECTION:NOTES:END -->
