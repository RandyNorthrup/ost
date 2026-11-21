---
id: TASK-0241
title: Pop-out windows for Teams' own views and Block bot conversation, as Teams
status: In Progress
assignee: []
created_date: '2026-11-21T00:13:00Z'
updated_date: '2026-11-21T02:31:00Z'
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

- 2026-11-20 merged as 0509286: Block bot conversation done and verified (Polly blocked and unblocked; messagingdisabled read from the thread). AC1: Chat, Activity and Calls windows open at 946x593 with Teams' content; open: the Chat window's tabs row, Events and Teams windows.
<!-- SECTION:NOTES:END -->
