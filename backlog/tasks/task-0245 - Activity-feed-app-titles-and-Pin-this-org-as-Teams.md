---
id: TASK-0245
title: Activity feed app titles and Pin this org as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-22T21:18:00Z'
updated_date: '2026-11-23T00:12:00Z'
labels:
  - desktop
  - shell
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-0244: OST's Activity feed (and the other-accounts hub that reuses it) shows some app activities as raw template names, e.g. 'Q&A: teamsQnAEnabledForMeeting' where Teams shows 'Q&A is enabled for this event. Ask your questions!'. The hub's Account settings > Pin this org (Teams pins the org as its own app-bar tile) isn't built.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 App activities in the Activity feed show Teams' text for each template, verified against Teams on winpc
- [x] #2 Pin this org pins the other account's org to the app bar as Teams does
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-22 (agent shellL) research: Teams 26304 GraphActivityProcessor words msGraph items from the app manifest (activities.activityItems[type==subtype, any case].templateText, {params} from activityContext.templateParameters, then {actor}); drops items without a definition/type/params, a valid customTapAction or a readable sourceThreadId. Location: Custom (date markup worded by renderer 542284), GroupChatId -> chat topic (Event Group Chat:/Planning Group: for backrooms), TeamId -> Team > Channel. ost-test1 feed kinds: Q&A teamsQnAEnabledForMeeting, Meeting Recaps recapIsReadyV2, Audio Recap recapPodcastReady, Teams invitationAccepted, bot mention in a threads channel ("<app> mentioned you in a thread", Team > Channel), missed calls, voicemail, mentions/reactions in chat, addedToTeam. OST Test 2 adds Calendar privateMeetingUpdated, Teams invitationSent, teamShareTeamOwnerNotify.
- Measured on winpc (OST Test 2 signed in as second account, No this app only; pinned, measured, unpinned, signed out): pinned org tile 52x48 above the hub tile, 28px colourful square initial at 12,10, count at 30,4; org leaves the hub (empty: "We couldn't find any results."); tile flyout = hub flyout for that org under a 72.67 header (32px initial, name 14/600, address 12/20, Tenant settings: Switch / Unpin this org).

- Built (agent shellL): src/api/activity.rs second pass `resolve` (app definitions + thread facts, cached per session, 4 threads at a time) words msGraph items from templateText (+params, {actor}), drops what Teams drops, sets the app icon (Channel Agent icon from the evergreen CDN), places (Custom / chat topic with Event Group Chat:/Planning Group: / Team > Channel); bot names from sourceAppDisplayName; "in a thread" mention/reaction titles; teamShareTeamOwnerNotify; feed page 200 (Teams lists the older items too). ActivityView: app icon picture (or person + app-icon badge), Team > Channel with a chevron, one-line previews; Theme.activityPlace words Teams' date markup. Hub: app entries get the Apps badge.
- AC2 built: config hub-pins.json (device-wide, pin order, max 2); backend pinnedOrgsJson / setOrgPinned, hub entries carry `pinned`; MtmaHub: Pin this org in the org submenu (disabled at two with Teams' tooltip), pinned tiles above the hub tile (28 px colourful square initial, count, tooltip org / Current org), the org flyout (72.67 header, Tenant settings: Switch / Unpin this org), pinned orgs leave the hub (empty: search illustration + "We couldn't find any results.", 476 tall as Teams). Harness --pin-org, --activity-dump.
- Verified live on linuxlt: spatest --activity-dump: 44 items; titles and places match Teams' feed on winpc item by item (Audio recap ready…, Q&A … with OST TEST 212 recap long / Event Group Chat: … / webinar plain, Recap ready: … with "Nov 20, 8:23 PM - 9:02 PM", OST Test 2 accepted an invite…, "OST TEST channel Agent mentioned you in a thread" with OST TEST 206 agent I > OST TEST channel, missed calls, mentions, reactions, voicemail, added to team). test2 --activity-dump: Calendar "OST Test 1 updated" (Nov 20, 5:00 PM - 5:30 PM), "invited your team to a shared channel", "shared a channel with your team" (Unavailable conversation: test2 can't read that thread, as Teams' MM). --pin-org on spatest and test2: tile, org flyout (380x562 bottom on the bar), Tenant settings, hub without it, two pinned -> empty hub 476 tall, unpinned; hub-pins.json removed afterwards.
- Open: one Q&A item (OST TEST 184 town hall, 11/17) showed its topic without "Event Group Chat:" in one run (its thread's backroom facts weren't readable then; the chat list's backroom kind is now the fallback, not re-verified); the hub's app entries show the place but not Teams' extra preview line.

- 2026-11-22 merged (0c517ed6). Not re-checked live: the event-chat name fallback, the 'Current org' tile; OST Test 2/3 rows in accounts.json lack org names.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Activity feed app items and Pin this org as Teams.

- App activities take the app manifest's activity type and fill its template (actor, parameters), hidden where Teams hides them; second lines with Teams' date wording, chat names (Event Group Chat: …) or Team › Channel; app icons; bots under their app's name; "… in a thread" for threads channels; the whole 200-item page is read. Verified item by item against Teams' feed on winpc (44 items).
- Pin this org gives another account's org its own app-bar tile and flyout (Tenant settings: Switch / Unpin), at most two, kept per device in hub-pins.json; the hub drops pinned orgs and shows Teams' empty state. Verified live with OST Test 2 as a second account in Teams (signed out again).
<!-- SECTION:FINAL_SUMMARY:END -->
