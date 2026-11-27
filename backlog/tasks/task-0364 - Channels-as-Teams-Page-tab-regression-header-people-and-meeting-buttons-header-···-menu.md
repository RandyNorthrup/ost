---
id: TASK-0364
title: >-
  Channels as Teams: Page tab regression, header people and meeting buttons,
  header ··· menu
status: In Progress
assignee:
  - '@claude-0364'
created_date: '2026-11-27T18:19:00Z'
updated_date: '2026-11-27T22:10:00Z'
labels: []
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the 2026-11-27 parity audit (scope A), which compared Teams (desktop for some items, Teams on the web teams.microsoft.com/v2 as ost-test1 for the rest; the web app is what new Teams desktop runs) with OST main on linuxlt. Each acceptance criterion is one verified gap; its full entry (what Teams does, what OST does, evidence) is in /home/randy/.local/share/ost-remaining/audit/auditA.md under its number, screenshots in audit/shots-A/.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A-18: Channel "Page" tab is missing; fixed to match Teams desktop, checked side by side
- [x] #2 A-19: Channel header: no people button, and "Meet now" instead of Teams' meeting button; fixed to match Teams desktop, checked side by side
- [x] #3 A-23: Channel header ··· menu: items differ (no "View meetings" or "Mark as unread"; extra admin items); fixed to match Teams desktop, checked side by side
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. A-18: find why Page is missing (data + git history), implement Teams' stand-in ("lie") Page tab and its provisioning.
2. A-19: research Teams' channel header (meetings discoverability): people button + popover, meeting icon button with Meet now / Schedule meeting / View meetings, the Meetings pane (group calendarView).
3. A-23: header ··· menu per Teams' channel-header menu (View meetings, Mark as unread, no Manage channel / Recommend / Archive for standard channels).
4. Unit tests, build on a build box, live checks on linuxlt as OST Test 2 side by side with Teams web (OST Test 2), PR, CI/CodeQL/Codex.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- A-18 cause (2026-11-27): not a code regression. Neither OST threads test nor OST test channel 2 had a Page tab in the channel's data (thread properties / middle-tier tab list held only Files and Notes). Teams draws a client-side stand-in Page (isLieChannelPageTab, module 177792 tu/Zm: fresh tab::{uuid} after the built-in tabs unless the thread property defaultTabHiddenApps::ChannelPageTab is set; tab ids differed between Teams web reloads). OST only ever listed real Page tabs (TASK-0039 was checked in a channel that had a real one), so channels without one lost "Page". git log over src/api/tabs.rs and Conversation.qml: no commit removed such logic.
- Opening the stand-in in Teams web (OST Test 2, OST test channel 2) made "Loop paragraph" right away and wrote a real tab with the stand-in's id: {"id","order":10,"definitionId":Pages,"directive":"channel-page-tab","type":"tab:","settings":{"componentUrl","isLieChannelPageTab":false,"isTabNameSynced":false,"dateAdded"},"name":"Page"} (worker provisionFluidForPageTab / eEt). OST test channel 2 now has that real Page; OST threads test still has only the stand-in.
- Header (Teams web, OST Test 2, 1600 wide): people button channel-audience-participant-count 34x32 "View people, agents and bots" (not in General), then meeting-button 32x32 "View meetings related options" (menu: Meet now, Schedule meeting, View meetings), divider, Find, details, ···. View meetings opens a "Meetings" pane (Date / Organizer pills) from GET graph groups/{group}/calendarView filtered by SkypeTeamsProperties "cid".

- Built (2026-11-27): api::tabs settles Pages as Teams' worker and tab list do: others' link-less Pages dropped (moved from QML), the stand-in "Page" (lie: true, a stable tab::{uuid} per channel while OST runs, after Shared, only Move left/right in its menu) when no Page is left and defaultTabHiddenApps::ChannelPageTab isn't set. Opening it makes the page (existing create flow) and saveComponentUrl {lie: true} writes Teams' provisioned tab (tab_add::provision_lie_page, unit-tested against the property Teams wrote). Removing the last Page sets the hidden flag (Teams' setAppDefaultTabHiddenPermanently). examples/page_tab_hidden toggles the flag (test aid).
- Header: the people button + ChannelAudiencePopover (team roster you first, bots from the team's apps with bots, the team, See all -> Manage team > Members, Add agents -> Store), the CalendarVideo meeting button with Meet now / Schedule meeting / View meetings, and ChannelMeetingsPane (api::channel_meetings: groups/{group}/calendarView, the cid filter, 3 months back newest first + 3 ahead, now line, Date and Organizer filters). While it is open the details button is Teams' Close meetings toggle.
- ··· (ChannelMenu header mode): View meetings first (Sidepane Features group), Mark as unread / Mark as read (bookmark at the latest message), Manage notifications only for shown channels, Manage channel and Archive only for a private/shared channel's owners, no Recommend, Delete for owners or members the team lets delete (CSA teamSettings.deleteChannel).

- Live (linuxlt, --channel-header-test, 1600x900), side by side with Teams on the web (headless Chrome on linuxlt, OST Test 2):
  - OST threads test and OST test channel 2 now list Posts/Conversation, Shared, Page, Notes as Teams; the stand-in has Move left (off) / Move right like Teams' right-click menu.
  - Opening the stand-in in OST (OST threads test, OST Test 2) made "Loop paragraph" and wrote {"id":<stand-in id>,"order":10,...,"isTabNameSynced":false,...,"name":"Page"}, the same as Teams wrote for OST test channel 2; Teams web then listed that Page too.
  - Removing the last Page (ost-test1; OST Test 2's chat-service PUT gets HTTP 500 on that channel, an existing limit) wrote defaultTabHiddenApps::ChannelPageTab = "true"; Teams web then showed no Page. Both test channels were put back to their audit state afterwards (Page removed, flag cleared with examples/page_tab_hidden): Teams and OST show the stand-in again. The two "Loop paragraph.loop" files stay in those channels' folders.
  - Header: people (not in General) + meeting button + menu match Teams' positions (1600: people at W-217, meeting W-183) and items; ··· matches Teams item for item for ost-test1 (owner) in OST test channel 2 and OST Test 2 in General / OST threads test / OST test channel 2 (plus desktop's Open in new window); View meetings shows General's "Design review" (Dec 1) as Teams does, and Teams' empty state elsewhere.
- Found and fixed on the way: a Threads-layout channel showed its composer over other tabs (Page).
<!-- SECTION:NOTES:END -->
