---
id: TASK-0078
title: >-
  Profile flyout items as Teams: Pause notifications, work location, out of
  office, accounts
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T16:14:00Z'
updated_date: '2026-11-22T18:26:00Z'
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
- [x] #4 Add another account behaves as Teams' (OST's sign-in, separate profiles)
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

- 2026-11-22 (agent setI) AC4 measured with two accounts in Teams on winpc (OST Test 2 signed in as a second account with its password typed from creds.md by VNC, "No, this app only"; measured; then signed out again - Teams back to ost-test1 alone, 1280x680, no call): Add another account dialog (440 x 540: the device's Windows accounts, "Create or use another account") -> Microsoft's sign-in -> "Sign in to all apps and websites on this device?" -> the window switches account. Title bar: the profile button becomes a 140 x 28 pill with the organisation's name (12/16 #424242, cut at 107.9) and the 28 px picture. Flyout: other accounts in 80.3 px rows on #F5F5F5 (48 px picture at 16, presence 12, name 14/600 at 76, 8, address 12/16), then the Add another account footer (#E6E6E6 32 px slot). App bar: "Activity in other accounts and orgs" (52 x 48, badge). Accounts and orgs: a card per account in the order added (788 x 121, 28 apart; another account: Manage only, organisation regular). Sign out dialog "Sign out of Teams" with the multiple-accounts tip. Spec: docs/spec/settings.md "More than one account".
  - Built (3f8b560): the pill, the flyout rows and slot, Accounts and orgs cards for the other accounts (order added, their organisation kept in accounts.json), one entry per account (a second profile of the same account isn't listed).
  - Verified on linuxlt (OST Test 2 = test2, --seth-test --seth-accounts): the pill, the flyout listing the device's other accounts and Add another account, the Accounts page cards; Add another account started OST for a fresh profile (account2; stopped by pid, nothing signed in, no folder left). A fresh profile (setI-acct, --seti-signin) loaded Microsoft's sign-in page (login.microsoftonline.com/organizations/oauth2/v2.0/authorize, "Sign in to your account") - OST's own sign-in for the new account.
  - Open: the app bar's "Activity in other accounts and orgs" hub (its window not measured); OST shows each account in its own window instead of switching the window in place.

- 2026-11-22 merged (dca6443). The 'Activity in other accounts and orgs' button moved to TASK-0244; OST's one-window-per-account is recorded on the Remaining Work page.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Profile flyout items as Teams: Pause notifications, work location, out of office, others' status messages, and accounts. With a second account the title bar shows Teams' organisation pill, the flyout lists the other accounts above Add another account, and Accounts and orgs shows one card per account in the order added; each account runs as its own OST profile and window, and Add another account starts OST's sign-in for a new profile. Measured against Teams on winpc with OST Test 2 signed in as a second account (then signed out); verified on linuxlt.
<!-- SECTION:FINAL_SUMMARY:END -->
