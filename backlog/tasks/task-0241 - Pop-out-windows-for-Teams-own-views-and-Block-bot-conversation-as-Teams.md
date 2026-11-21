---
id: TASK-0241
title: Pop-out windows for Teams' own views and Block bot conversation, as Teams
status: In Progress
assignee: []
created_date: '2026-11-21T00:13:00Z'
updated_date: '2026-11-21T08:23:00Z'
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
- [ ] #1 Open in new window on Teams' own app-bar views opens them in their own window as in Teams
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
<!-- SECTION:NOTES:END -->
