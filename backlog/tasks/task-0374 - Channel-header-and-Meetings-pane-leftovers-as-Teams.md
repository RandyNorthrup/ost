---
id: TASK-0374
title: Channel header and Meetings pane leftovers as Teams
status: Done
assignee:
  - '@t374'
created_date: '2026-11-27T23:15:00Z'
updated_date: '2026-11-28T02:39:00Z'
labels:
  - desktop
  - channels
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-0364 (PR #60). Still different from Teams: the people popover's Agents and bots lists every bot in the team (Teams listed only Forms; filter unknown) and People shows the team roster instead of Teams' recent channel contributors; the channel Meetings pane has no per-meeting ··· menu, no custom From/To range, an Organizer list instead of people search, is 360 wide (Teams 419 at the same window size), and opens a meeting's details only for meetings in your own calendar; the pop-out channel window still has the old Meet now header; and builds crash at startup with OST_QML_DIR set on the default profile.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Agents and bots and People in the channel people popover list what Teams lists (rule researched and documented)
- [x] #2 The channel Meetings pane matches Teams: per-meeting ··· menu, custom From/To range, Organizer people search, Teams' width, and details for any listed meeting
- [x] #3 The pop-out channel window has the same meeting button and menu as the main window
- [x] #4 OST starts with OST_QML_DIR set on the default profile
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Research Teams (bundles 26304 on linuxlt + Teams on the web as OST Test 2 / ost-test1): people popover rules (RECENT_CONTRIBUTORS, useInstalledAgents), Meetings pane width (end slot), card ··· menu, Date custom range, Organizer people picker, what a listed meeting opens.
2. People: recent contributors from the channel's newest page, members to fill to six; Agents: installed bots less notification-only and the outgoing webhook app.
3. Meetings pane: Teams' pills and Date/Organizer popups, Edit / Chat / ··· (Copy link) per meeting, Theme.endSlotWidth, details for any meeting (team calendar event page with Add to calendar).
4. Pop-out ChannelWindow: people + meeting buttons and menu, the Meetings pane in the window.
5. OST_QML_DIR: reproduce on the default profile, find why, fix the interceptor.
6. Unit tests, build, live checks on linuxlt side by side with Teams on the web, PR.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Research (2026-11-27, Teams 26304 bundles on linuxlt; Teams on the web, headless Chrome on linuxlt, as OST Test 2 and ost-test1, 1600x900):
- People (#1): the popover's People is GraphQL channelByID.membersConnection(filter RECENT_CONTRIBUTORS) -> worker ChannelInfoPaneGetDataHelper.getMergedRecentContributorsAndChannelMembers: reply chains (20) by latestDeliveryTime desc, each chain's messages by originalArrivalTime desc, their creators (users), unique, up to 6 (sV); fewer than 6: the thread's members (team thread for standard channels, the channel for private/shared; pageSize 20, KFe) appended until 6; cached 5 min (channelInfoPaneRecentContributorsRequestDebounceTime 3e5). Agentic users are filtered in the UI.
- Agents and bots (#1): useInstalledAgents (module 8465): installedAppsV2 scope Team, entitlementTypeFilter APP + AGENTIC_USER; kept: installed (Installed/InstalledAndFavorited/InstalledAndPermanent/AdminPreInstalled) with bots or AGENTIC_USER; skipped: outgoingWebhookAppId (aa39b2f8-3c8d-4ce1-8b8b-7fe02c59ae3e) and bots[0].capabilities.isNotificationOnly; sorted by name. OST Test Team's aggregatedEntitlements: Polls, Updates, Power BI are notification-only, Forms isn't -> Teams lists Forms only (seen in Teams web as ost-test1 in OST test channel 2: People = OST Test 2, OST Test 3, OST Test 1; Agents and bots (1) Forms).
- Meetings pane width (#2): Teams' end slot --slot-width by window width (async-entry map): <947 32rem, >=947 36rem, >=1440 42rem, >=1680 48rem, >=1920 60rem, >=2560 72rem, and the main slot keeps 32rem; measured 1000->332, 1280->360, 1600->420, 1700->480, 1920->600, 2560->720.
- Card ··· (#2): contextual-search cards hide Join/RSVP/Chat-in-menu/Show as; the menu showed only Copy link for both OST Test 2 (attendee) and ost-test1 (organizer). Copy link puts <a href=url>{subject} | Meeting | Microsoft Teams</a> + the url. The organizer's card also has Edit (calv2-edit-button 65x24) before Chat with participants.
- Date (#2): Today/Yesterday/This week/This month (checkmark on the chosen one), From (Select a date) / To (today) with nothing after today, Clear / Apply; ranges per getDateRange (week from Sunday, custom to the end of To). Pill: brand with the choice ("This week", "Nov 1, 2026 - Nov 27, 2026") and a × part (18).
- Organizer (#2): people picker "Filter by person"; before typing the team thread's members (selectMemberRoles=User|Admin|Guest, pageSize 50) less you; typing: POST userprofilesvc teams/{thread}/users/profilesearch?top=15&includeBots=false&enableGuest=true {keyword}; the pill then shows only the person's 20 px picture and ×.
- A listed meeting (#2): clicking the card opens the meeting's full page from the team calendar (calendarType Channel: Add to calendar, Copy link, Forward, Show as greyed); Add to calendar = calendar service AddToMyCalendar (beta/teams/{smtp}/addtomycalendar/{eventId}?useICalUId=false).
- Pop-out (#3): the channel header in a secondary window is the same ChannelHeaderLayout (no popout-specific hiding of the people / meeting buttons).
- OST_QML_DIR (#4): main's build with main's QML started fine on the default profile in four tries (with and without assets beside the QML, a relative path, the channel header harness, remote debugging). TASK-0364's two segfaults were with QML copied without its assets; the interceptor matched only the qrc:/ spelling of the module's files, so a module file could still load from qrc (its ahead-of-time code then meets the disk copy's types; AudioRecapPlayer.qml warned from qrc: while the rest came from file:).

Built (2026-11-27):
- People / Agents and bots: api::channels::channel_people (recent_contributors over the channel's newest page + fill_contributors from thread_members_in_order, 5-minute cache) and api::store_content::channel_agents (bots less notification-only and the outgoing webhook app); the popover passes {own} for private/shared channels.
- Meetings pane: Teams' pills (choice + ×, a person's picture), Date popup with presets + From/To (Theme-free DatePickerField, nothing after today), Organizer people picker (channel-organizers op: the roster in the service's order; typing: findPeople profile search), Edit (your own meetings, by SkypeTeamsProperties uid; group calendars say isOrganizer for everyone), Chat with participants, ··· Copy link (rich link + url). Width: Theme.endSlotWidth(window, left) = Teams' end slot map, main keeps 320.
- Details for any listed meeting: CalendarView.showChannelMeeting opens your copy (by iCalUId, once its week loads) or the team calendar's (showGroupMeeting: calendar_id group:<id>, event_detail_in reads /groups/{g}/events/{id}); MeetingForm.teamCalendarEvent shows Add to calendar (api::channel_meetings::add_to_my_calendar, MT beta/teams/{group mail}/addtomycalendar/{id}?useICalUId=false) and Copy link instead of the answers; the team itself is left out of Tracking and the organizer is the person.
- Pop-out ChannelWindow: people + CalendarVideo meeting button with Meet now / Schedule meeting / View meetings, the Meetings pane in the window (end slot by the window's width: 268 at 588).
- OST_QML_DIR: the interceptor now matches the module's files by scheme + path (any qrc spelling), so AudioRecapPlayer.qml (and the rest) load from disk too (it warned from qrc: before, file: after), and a file the disk QML names beside it (../assets, ../shaders) that the checkout lacks falls back to the compiled-in one.

Live (linuxlt, harness builds with OST_QML_DIR, 1600x900):
- --channel-header-test, default profile (ost-test1) in OST test channel 2: People OST Test 2, OST Test 3, OST Test 1; Agents and bots: Forms for Microsoft Teams — the same as Teams on the web as ost-test1 there. Also with a QML-only dir (no assets) + remote debugging (TASK-0364's crash setup): starts and runs the harness; main's build with the same setup never got past start-up steps.
- --meetings-pane-test as OST Test 2 in General: width 420 (Teams 420 incl. its line); Organizer suggestions OST Test 3, OST Test 1 and "ost" -> OST Test 3, OST Test 2 (You), OST Test 1 (Teams the same); OST Test 1 keeps Design review; This week and Nov 1 - Nov 27 find none (Teams the same); pills as Teams' ("This week" ×, the picture ×, "Nov 1, 2026 - Nov 27, 2026" ×). Design review (not in OST Test 2's calendar: theirs has another Design review with a different iCalUId) opened from the team calendar with Add to calendar / Copy link / Show as greyed, Tracking OST Test 1 organizer.
- --add-to-calendar as OST Test 2: addtomycalendar answered OK, the event appeared in OST Test 2's calendar (organizer OST Test Team, accepted) and the pane then opened that copy; the added copy was deleted again afterwards (examples/delete_event), leaving their calendar as it was.
- --channel-window-test as OST Test 2 (OST test channel 2): the pop-out header has people (34) + meeting (32) buttons, the menu Meet now / Schedule meeting / View meetings, the popover as the main window's, View meetings opens the pane (268 wide).
- Unit tests: recent contributors order/cap/fill, channel agents (OST Test Team's entitlements -> Forms), team calendar event paths.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The channel header's people popover, the Meetings pane and the pop-out channel window now follow Teams, and OST_QML_DIR loads every QML file from disk.

Changes:
- People: the channel's recent contributors (reply chains by latest activity, newest first, six), then its members, as Teams' RECENT_CONTRIBUTORS; Agents and bots: installed apps with a bot that isn't notification-only, less the outgoing webhook app (OST Test Team: Forms only, as Teams).
- Meetings pane: Teams' end-slot width (420 at 1600, 480 at 1700, 600 at 1920…, the main area keeps 320); Teams' pills; Date with Today/Yesterday/This week/This month and a From/To range; Organizer as a people search (team members first, then the team's profile search); Edit for your own meetings, Chat with participants and ··· Copy link on each meeting.
- Any listed meeting opens: your copy when it is in your calendar, else the team calendar's event page (Add to calendar, Copy link), with the person as organizer.
- Pop-out channel window: people and meeting buttons with Meet now / Schedule meeting / View meetings, and the Meetings pane in the window.
- OST_QML_DIR: module files are matched by scheme and path, so none still loads from qrc next to disk copies (the mix behind TASK-0364's start-up segfaults); assets/shaders missing beside the QML fall back to the compiled-in ones.

Tests: unit tests for contributors, agents and team calendar paths; live on linuxlt with --channel-header-test, --meetings-pane-test (incl. Add to calendar as OST Test 2, undone after), --channel-window-test, side by side with Teams on the web.

Left / unverified: the team event page has no Forward (Teams has one); Teams desktop's pop-out window itself wasn't driven (winpc was in another agent's use; Teams' code shows the same header there); the ··· Copy link wasn't clicked in OST live; TASK-0364's exact segfault didn't reproduce on main, so the fix is for the mixing that was seen.
<!-- SECTION:FINAL_SUMMARY:END -->
