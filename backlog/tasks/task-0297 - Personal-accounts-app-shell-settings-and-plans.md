---
id: TASK-0297
title: 'Personal accounts: app shell, settings and plans'
status: In Progress
assignee:
  - '@tperE'
created_date: '2026-11-25T15:26:00Z'
updated_date: '2026-11-28T07:29:00Z'
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
- [ ] #1 A personal account shows Teams' left rail and hides every work-only feature (teams and channels, Files, Calls app, Apps store, Copilot where unavailable, Premium)
- [ ] #2 Settings shows the pages and options Teams shows for a personal account, synced with the account, with the personal-account Privacy options
- [ ] #3 Plans and upgrades shows what Teams shows; buying opens Microsoft's page in the browser
- [ ] #4 Feature flags come from ECS with the personal-account (TflNorthstar) configuration
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
<!-- SECTION:NOTES:END -->
