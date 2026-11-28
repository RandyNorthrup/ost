---
id: TASK-0297
title: 'Personal accounts: app shell, settings and plans'
status: Done
assignee:
  - '@tperE'
created_date: '2026-11-25T15:26:00Z'
updated_date: '2026-11-28T09:17:00Z'
labels:
  - personal-accounts
dependencies:
  - TASK-0292
  - TASK-0290
references:
  - docs/research/personal-accounts-features.md
  - docs/research/personal-accounts-protocol.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
For a personal account Teams' left rail is Chat, Meet, People, Calendar and Activity (no Teams and channels, Files, Calls or Apps store), and Settings has its own set of pages, including Privacy options (who can find, call or add you to groups), People, Files and links, and Plans and upgrades.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A personal account shows Teams' left rail and hides every work-only feature (teams and channels, Files, Calls app, Apps store, Copilot where unavailable, Premium)
- [x] #2 Settings shows the pages and options Teams shows for a personal account, synced with the account, with the personal-account Privacy options
- [x] #3 Plans and upgrades shows what Teams shows; buying opens Microsoft's page in the browser
- [x] #4 Feature flags come from ECS with the personal-account (TflNorthstar) configuration
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Research Teams for personal use (testpc2 desktop personal window via UIA, teams.live.com in headless Chrome as OST Personal 1): rail, Upgrade, hub, Settings pages, Privacy/People/Plans/Insider protocol, ECS.
2. ECS: TflNorthstar query for personal accounts, settings read from TflNorthstar, per-profile/kind cache.
3. Rail: Teams free's fixed bar (only apps OST can open), Upgrade diamond, simple other-accounts hub, Copilot upsell and Communities retirement pages, Settings and more menu.
4. Settings: personal page list, personal Privacy (synced), People, Plans and upgrades, Teams Insider, storage; hide work-only cards.
5. Build (ghbuild), live-check with OST Personal 2 on testpc2 against Teams desktop, PR.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-28 (TASK-0293): with Teams free's middle tier answering (bearer + Skype token, TASK-0293), a personal window's rail now lists Teams free's own app definitions, but their icons draw as black squares; the rail itself (Chat, Meet, People, Copilot, Communities, Calendar, Activity) is this task's.

- 2026-11-28 (tperE) research: Teams desktop 26304 personal window on testpc2 (OST Personal 2, UIA, minimized after each look) and teams.live.com in headless Chrome on linuxlt (OST Personal 1, worker network logged, tokens redacted).
- Rail (fixed, no app menu, no Store or View more apps): Chat 86fcd49b, Meet 40472f6e-…34, People 40472f6e-…35, Copilot 43a6e7fb (colour mark), Communities 3b95919f, Calendar ef56c0de, Activity 14d6962d; bottom: Upgrade (diamond, data-testid premium-upgrade-button; opens Settings > Plans and upgrades and auto-launches the DIME purchase dialog offer.m365.cloud.microsoft/launchpad) and the hub.
- Copilot (free): upsell page, CDN pictures evergreen-assets/m365-subscription-upsell/upsell-{1,2,3}.png; View all benefits opens microsoft.com compare-all-microsoft-365-products; Explore plans now opens DIME. Communities: retirement banner (Learn more fwlink 2375512, Start chat), Create your own/templates open "Create a group chat".
- Settings pages: General, Appearance, Chats, Notifications and activity, Accounts and orgs, Privacy, Accessibility, Devices, People, Files and links, Plans and upgrades, Teams Insider, About Teams.
- Privacy protocol: who can add you to groups / call you = chat-service user properties disableNonContactAddToGroup / disableNonContactCall ("true" = Your contacts); find-you = MT users/me (searchableByProfile, emailsInfo), name via POST users/updateNameAndSkypeAvatar {searchableByProfile}, email via POST scd/searchability?ggEnabled=true {msaEmails:[{address,searchable}],msaPhones:[]}; Your profile = PATCH users/me {msaEmails:[{address,visibility Public|Private}]}; Experiences that analyze your content = GET/POST users/me/analyzecontentsettings. Every setting changed for the capture was put back (Personal 1).
- People: blocklist GET userSettings/blocklist?ggEnabled=true, unblock POST blocklist/manage {remove:[mri]}; sync = GET contacts/syncSettings. Insider: GET/POST/DELETE beta/users/insiders(/status).
- ECS: Teams desktop app id 49 with environment=life, tenantId 9188040d-…, id=aaduserid=personal oid, agents TflNorthstar,TeamsBuilds,Segmentation, no licence filters (answers 200 without auth).

- Live (OST Personal 2 in a fresh OST profile on testpc1; testpc2 already has another agent's personal profile, so OST refused a second one as Teams does): rail Chat, Copilot (colour mark), Communities, Activity, Upgrade and the hub; Copilot upsell page with Teams' pictures; Communities page with its animation and Create a group chat dialog; Settings and more matches Teams 26304 (Upgrade | Pin, Settings | Zoom | Help, Feedback, Keyboard shortcuts, Get the mobile app | Teams Insider | What's new); Settings lists Teams free's 12 pages; personal data all loaded from the consumer middle tier (users/me, analyzecontentsettings, blocklist, contacts/syncSettings, insiders/status) and Graph (5 GB quota, 1.2 MB used).
- Fixed from that check: the not-available placeholder covered the two new pages; the simple hub flyout had no height; plan cards overflowed a narrow window (now stacked); work-only rows in Chats/Sound/Files.

- Live after the fixes (build ef6e6dee + QML): Communities' animation sits on the page (black keyed out), the hub flyout matches Teams (each other account with Switch and Pin, then Unread chat messages / Mentions / Missed calls), Plans and upgrades stacks its cards in a 1000 px window, rail Upgrade opens Plans and upgrades; window title "General | Settings | Personal | <email> | OST".
- Sync check: Privacy > Manage who can add you to groups set to Your contacts in OST, Teams desktop 26304 (OST Personal 2, testpc2) then showed Your contacts; set back to Anyone in OST.
- ECS: the personal profile cached ecs-<profile>-life.json with TflNorthstar (core.isPremiumButtonInAppBarEnabled, communities.disableCommunitiesCreation true).
- Not verified live: the browser opening Microsoft's plans page (WSL has no browser; the URL, fwlink 2360700, resolves to microsoft.com compare-all-microsoft-365-products); Join/Leave Teams Insider, name/email searchability, email visibility and Unblock were not pressed in OST (the same calls were captured from Teams free and put back; changing them would affect other agents' search tests); Verify subscription / Start using Copilot (a Skype-token renewal) not pressed.
- Left for other tasks: Meet and Calendar (TASK-0298) and People (TASK-0295) stay off the personal bar until their views exist: set AppRail.personalReady.<key> to true there. Synced contacts' Remove and From your mobile device are TASK-0295's (contact sync). Files and links shows Teams free's Browser choice; opening personal files is TASK-0300's.

- PR #88. Codex review: Teams Insider menu row opened General (now teams_insider), the personal hub flyout could outgrow the window (now capped at 0.7 and scrolling), and a personal account's unset file-opening choice still opened Office in OST (now Browser, matching Files and links). Fixed in b25235ef, checked live (Insider page, hub with 3 accounts); threads answered and resolved.

- Rebased on main after #84 (TASK-0298/0299): its personal default bar (Chat, Meet, Calendar, Activity) gave way to this task's Teams free bar, and personalReady now has Meet and Calendar on (their views exist); the not-available page knows meet, tfl-copilot and tfl-communities; the protocol doc keeps #84's §10 and this task's section as §11. People stays off until TASK-0295.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
A personal (Teams for personal use) account's window now has Teams free's own shell, Settings and plans.

Changes:
- App bar: Teams free's fixed bar (Chat, Copilot, Communities, Activity; Meet, Calendar and People join via AppRail.personalReady once TASK-0298/0295 build them), no app menus, Store or View more apps, and the Upgrade gem over the other-accounts hub. Copilot shows Teams' upsell page; Communities its retirement page (banner, animation, Create a group chat dialog).
- Activity in other accounts and orgs: Teams free's simpler flyout (each account with Switch and Pin, then the kinds of activity waiting).
- Settings and more: Upgrade, Pin, Settings, Zoom, Help, Feedback, Keyboard shortcuts, Get the mobile app, Teams Insider, What's new; no Cast, Downloads or Teams Premium.
- Settings: Teams free's pages; Privacy's personal options synced with the account (groups/calls user properties, find-you via MT searchability and updateNameAndSkypeAvatar, profile card visibility, content analysis); People (blocked users with Unblock, synced contacts); Plans and upgrades (Upgrade opens Microsoft's plans page in the browser; Verify subscription re-reads the licence); Teams Insider; Microsoft cloud storage; work-only cards and rows left out.
- ECS: asked as Teams desktop asks for a personal account (environment=life, TflNorthstar), read from TflNorthstar, cached per profile and account kind.
- Docs: personal-accounts-protocol.md §10.

Tests: ecs::personal_accounts_ask_for_tfl_northstar, personal_settings::* (GitHub harness-tests, 22 passed); clippy -D warnings (GitHub). Live on testpc1 with OST Personal 2 against Teams desktop 26304 on testpc2 and teams.live.com: see notes (groups setting round-tripped to Teams desktop).

Not verified live: the browser launch on WSL, Insider Join/Leave, searchability/visibility/unblock presses, Verify subscription.
<!-- SECTION:FINAL_SUMMARY:END -->
