---
id: TASK-0241
title: Pop-out windows for Teams' own views and Block bot conversation, as Teams
status: Done
assignee: []
created_date: '2026-11-21T00:13:00Z'
updated_date: '2026-11-21T20:12:00Z'
labels:
  - desktop
  - apps
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' app bar menu offers Open in new window for its own views (Chat, Calendar and others) and Block bot conversation for bots. OST shows Open in new window only on hosted apps and has no Block bot conversation item (found in TASK-0238).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Open in new window on Teams' own app-bar views opens them in their own window as in Teams
- [x] #2 Block bot conversation appears for bots and works as in Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-20 research (Teams 26304 bundles + winpc): the tile menu's Open in new window is shown when the app node's canLaunchOut is set: platform apps with a personal tab (Extensibility enablePersonalAppsPopOut) or core apps listed in ECS core.allowedCoreAppsPopOut (prod default for desktop: simple collab 3b64df9d, chat 86fcd49b, channel 2a84919f, activity 14d6962d, calling 20c3440d, events a63f7012); Calendar only via the M365 calendar's openM365CalendarInNewWindow action. On winpc each window is 946 x 593 with the 32 px child-window title row (app name, Settings and more) and no app bar; Chat: the whole chat list (280) + the chat's entity header (61) and messages; Activity: feed (280) + empty main until an item is picked; Calls: the Calls page (header 61, dial 332, history, speed dial).
- Block bot conversation: Teams' BCt adds it (ProhibitIcon, "Block bot conversation" / "Unblock bot conversation") after About and Share for a non-core app with bots[0].id when you have a 1:1 chat with the bot (hasBotChat); its resolver finds the chat with 28:<bot>, flips the thread property messagingdisabled ("true"/"false") with PUT {chat}/v1/threads/{id}/properties?name=messagingdisabled and records isBotBlocked.
- Built: CoreAppWindow.qml (Chat/Teams: ChatList + the picked chat kept live under win:<chat>; Activity: the 280 feed + the item's chat; Calls, Events: their pages; what they open elsewhere goes to the main window), rail menu item on the allowed core keys; Block / Unblock: api::app_bar bot_id, api::bot_chat (reads the thread: the conversations list omits messagingdisabled), api::set_messaging_disabled, backend blockBotChat. Harness --app-bar-test window/wshot/wclose/block/unblock/botchat.
- Live (linuxlt default = ost-test1): Polly (has a chat) shows Block bot conversation, Workflows (no chat) doesn't, as Teams' rule; Block set the thread's messagingdisabled "true", then Unblock showed and set it "false" (Polly left unblocked). Open in new window on Chat, Activity and Calls opened 946 x 593 windows titled Chat / Activity / Calls; Chat showed the list and OST Test 2's chat beside it, Activity the feed, Calls its page.
- Open: the Chat window's conversation uses the pop-out chat header (no tabs row) where Teams shows the full entity header with tabs; Events isn't pinned for ost-test1 so its window wasn't compared; the Teams (channels) window wasn't checked live.

- 2026-11-20 round 2: Chat window now keeps the chat's tabs row (Conversation windowTabs): live (spatest, --app-bar-test wshot/wtab) OST Test 2's chat in the Chat window shows Chat, Shared, Notes, Recap, Storyline beside the name, like Teams' window (Teams also shows its '+' Add a tab, which OST's pop-outs leave out). Events: Teams opens its Events window from View more apps (no pin needed; winpc measured 946 x 593, header 61 with Events / Discover / Manage, Pin app, Filters, Create event, then the Discover page); OST's Events window from the flyout shows the same header and page (its Discover was still empty when pictured, and Teams caps the page width where OST's banner runs wider). Teams window (core:teams, split view's Teams app): OST layout test's posts with Posts / Shared and Post in channel beside the list; the list showed the combined pane, fixed to Teams' teams pane (and split view's Chat window to chats only), not yet rechecked live.

- 2026-11-20 round 3: Teams window list now the teams pane (live: Quick views, Teams and channels, Communities). Pop-out Chat window: '+' (Add a tab) beside the tabs (opens the main window's tab picker; Teams opens its picker in that window). Events: Teams' page is a centred container at most 1100 wide (12 px padding, content 1076 at 1212) and 706 in its 946 window (winpc); OST's Events page now uses those widths, and each Events view tags its requests so a second Events view (the window) no longer swallows the main one's answers (likely why the window's Discover showed empty). Built in e6; the Events window and the '+' weren't pictured live again this round (profile time went to the notes test). Note: a property named 'left' broke QML loading (Item.left is FINAL), renamed pageLeft.

- 2026-11-21 live (spatest, e6): Events window from View more apps, 946 x 593, the page now centred at Teams' 706 width (intro card 120 in), header as Teams'; Discover still shows OST's empty state where Teams lists 'Catch up on past events' (OST TEST 217 r3 town hall), so the window's Discover data is still missing (open). Not done: the split-view Chat window check (split view is a synced Teams setting, left unchanged) and the Add a tab picker inside the pop-out.

- 2026-11-21 (teamsG) Discover's "Catch up on past events": the Events window asks exactly Teams' DISCOVER_PAST query, now at the regional service as Teams does (ECS useRegionalVirtualEventsServiceEndpointResolver on; it was the global virtualevents/prod address). The service answers past = [] for ost-test1 (logged live). Teams on winpc still showed OST TEST 217 r3 town hall only because its stored DISCOVER_PAST slot (IndexedDB one-events-manager, read-only) was last synced 2026-11-19 13:25Z: Teams refreshes only UP_NEXT and UPCOMING on its interval and activation, and the past slot only at start. So the empty past list matches the service, and Teams' list is a stale copy. Live: Events window 946 x 593 with Discover loaded (now 0, upcoming 0, past 0, no error).
- Add a tab in the pop-out: the Chat window now opens Teams' Add a tab picker and the tab configuration inside itself (CoreAppWindow has its own AgentStore and TabConfigDialog; app details, Get more apps and Manage apps go to the main window). Live (spatest, --app-bar-test wplus:chat): the picker opened in the Chat window (901 x 561 within 946 x 593) and not in the main window, then closed without adding anything. Harness ops wplus:<key>[:close] and wevents:<key>.
- Split-view Chat window: not checked this round (the winpc slots went to the reads above). OST passes split view (Teams' simpleCollabUserSettings) to the window, which then lists chats only.

- 2026-11-21 (teamsH) split view, measured on winpc (Settings > Chats and channels > Separate for the test, put back to Combined after; previews/timestamps came back as they were): the app bar's Chat menu has Open in new window, New message, New message in new window, Move up, Move down, Unpin, Customize app bar (OST's matches). Teams' Chat window: 946 x 593, the list 266 wide (tree at x 14), pills Unread / Chats / Unmuted with Meeting chats under More filters, Copilot row, Quick views Mentions / Drafts / Saved, Favorites, Chats with previews and time stamps (split's defaults), and the chat you were last in (OST Test 2) open beside it. The split Teams app: pills Unread / Channels / Communities; quick views Followed threads, Discover, Drafts.
- OST before: pills Unread / Chats / Meeting chats, quick views Followed threads / Saved, no Copilot row, empty chat pane, and a preview with line breaks spilling over three lines.
- Built: split Chat pills Unread, Chats, Unmuted (Ctrl+Alt+Q; unmuted chats only), Meeting chats (under More filters when they don't fit); no Followed threads in the Chat pane; the window passes the main window's drafts, mentions and Copilot row and sends Mentions / Drafts / Saved / Copilot to the main window; the window opens on the main window's chat (a chat for split Chat, a channel for Teams); previews one line (line breaks as spaces) everywhere. Add a tab picker: Math.min(901.3, W - 46) x Math.min(647.3, H - 28), Teams' 900 x 565 at 23, 14 in the 946 x 593 pop-out.
- Live (spatest, --app-bar-test=split:on,...,split:off; new ops split:on|off and wlist:<key>): window 946 x 593, pills ["Unread","Chats","Unmuted"] + more ["Meeting chats"], one-line previews; the window's Add a tab picker 900 x 565 at 23, 14.5 (was 901 x 561). Quick views showed only Saved in that run: OST shows Mentions and Drafts when its activity feed has mentions and it has drafts (the main window's data), which that run hadn't loaded; Teams showed both. Split view put back to Combined.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Open in new window for Teams' own views (Chat, Teams, Activity, Calls, Events) as Teams, and Block bot conversation.

This round (split view, measured on winpc with Separate on for the test): the split Chat window's pills (Unread, Chats, Unmuted, Meeting chats under More filters), quick views without Followed threads, the Copilot row, opening on the chat you were in, one-line previews, and the Add a tab picker at Teams' 900 x 565 in the 946 x 593 pop-out.

Tests: --app-bar-test with the new split:on|off and wlist ops (spatest); split view put back to Combined. Known: Mentions / Drafts quick views follow OST's own data (activity mentions, local drafts), where Teams uses its cloud drafts.
<!-- SECTION:FINAL_SUMMARY:END -->
