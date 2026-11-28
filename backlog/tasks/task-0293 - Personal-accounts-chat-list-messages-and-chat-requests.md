---
id: TASK-0293
title: 'Personal accounts: chat list, messages and chat requests'
status: In Progress
assignee:
  - '@tperB'
created_date: '2026-11-25T15:26:00Z'
updated_date: '2026-11-28T04:43:00Z'
labels:
  - personal-accounts
dependencies:
  - TASK-0292
references:
  - docs/research/personal-accounts-features.md
  - docs/research/personal-accounts-protocol.md
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Personal accounts use the consumer chat service (msgapi.teams.live.com) with consumer headers. Teams for personal use also has chat requests: people who aren't your contacts send a request you can preview, accept or block.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The chat list, reading, sending, editing, deleting, reactions and attachments work for 1:1 and group chats with a personal account, with Teams' layout
- [x] #2 New 1:1 and group chats can be started by name, email or phone, as Teams for personal use does
- [x] #3 Chat requests show with Preview, Accept and Block as on Teams desktop, and the sender sees the pending state
- [x] #4 Features Microsoft retired for personal accounts (polls, tasks, location sharing, SMS) are not shown
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Capture Teams free (teams.live.com web client as OST Personal 1, CDP network log; Teams 26304 desktop as OST Personal 2 on testpc2) for the chat list, new chat, requests and compose.
2. Engine: consumer chat service front door and product headers, middle-tier bearer + Skype token, personal short profiles (fetchShortProfile / fetchFederated), pictures with the imageauth cookie, consumer CSA folders, searchUsers people search, chat creation through the groups service, accept/block with the Skype token.
3. UI: Teams free chat list (no Quick views / Teams and channels, pills Unread / Meeting chats / Unmuted, Requests row and pane), request view variant, work-user header/banner, compose toolbar and + menu, tabs.
4. Live-check in OST Personal 2 on testpc2 beside Teams desktop; Personal 1 on the web as the other side.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-28 (tperB) Captured Teams free: teams.live.com web client as OST Personal 1 (headless Chrome on linuxlt, CDP network log, tokens redacted) and Teams 26304 desktop as OST Personal 2 on testpc2 (UI screenshots, window restored and minimized again each time).
- Protocol found: chat list = consumer chat service front door (teams.live.com/api/chatsvc/consumer) with ms-ic3-product tfl / Sfl; folders = teams.live.com/api/csa/api/v1/.../conversationFolders with x-skypetoken only; names = MT fetchShortProfile (Teams free people) and fetchFederated (work users), bearer + Skype token; pictures = MT users/{mri}/profilepicturev2 with the imageauth/cookie cookie; people search = MT searchUsers (emails:[...] for an address, searchKeyWord for a name or phone); new chats = POST teams.live.com/api/groups/v1/threads (groupssvc token + Skype token; 1:1 role User + isStickyThread, group role Admin), then contacts managebuddies add; a non-contact's chat arrives with relationshipState.inQuarantine (personal-to-personal, groups too).
- Accept/Block: Teams free has no accept list (acceptlist/manage answers 405). Its worker (acceptBlockUnblockChat, life build): 1:1 Accept adds the inviter to contacts (managebuddies), group Accept sets your member property relationshipState=Accepted (PUT chatsvc v1/threads/{id}/members/{you}), Block posts blocklist/manage?ggEnabled=true {add:[mri]}.
- Teams free UI (testpc2): chat list with Unread / Meeting chats / Unmuted, a Requests row (mail icon, count) above Favorites, no Quick views or Teams and channels; Requests pane (380 wide, rows by the person who asked, group requests with the group picture) and "Select a chat request item to accept or block."; request view without the "outside your organization" line or disclaimer, its preview bar with the warning at the left; "{name} added you to a group chat" for groups; work users show their address under the name and "X is part of an external organization. ..." banner; compose Emoji, Attach files, Attach media, Loop, + (Show Formatting options, Set delivery options); message menu Reply, Edit, Forward, Copy link, Delete, Pin, Mark as unread, Translation.

- Live (OST Personal 2 in OST on testpc2, build of 7c076fdf): chat list with names/pictures and Teams free's sections/pills/Requests row; send, edit, react and delete in the 1:1 with OST Test 3 (seen in Teams desktop too); new group chat with OST Test 1 and OST Test 3 found by email and made through the groups service; Requests pane, request view, preview bar and group request view; Accept on the group request (inQuarantine false) and on the 1:1 (OST Personal 1 put in contacts, chat opened); Block checked against the service only (blocklist add then remove; no second non-contact test account could send a new request after the 1:1 was accepted).
- Not verified: file and photo attachments in personal chats (the upload path is the work one; Teams free shares files with "Anyone with the link can edit": TASK-0300, Photos tab added there); phone search (Teams free sends a phone number as a keyword search; no test account has a number). Without push (TASK-0294) an answered request can stay in the Requests pane until the next list reload.
- PR #81.
<!-- SECTION:NOTES:END -->
