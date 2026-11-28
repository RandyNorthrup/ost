---
id: TASK-0293
title: 'Personal accounts: chat list, messages and chat requests'
status: Done
assignee:
  - '@tperF'
created_date: '2026-11-25T15:26:00Z'
updated_date: '2026-11-28T08:13:00Z'
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
- [x] #1 The chat list, reading, sending, editing, deleting, reactions and attachments work for 1:1 and group chats with a personal account, with Teams' layout
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
5. AC #1 attachments (with TASK-0300, same branch): files and photos sent as Teams free does (OneDrive Chat Files, anyone edit link, picture previews in the media store).
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

- Codex review (PR #81): Attach media now sends a copy (the upload removes pasted pictures); picking yourself opens your notes chat; a chat opened from search/activity closes the Requests pane. CodeQL cleartext alert #40 (moved code of #38 on main) dismissed as false positive. CI green; Codex re-review: no major issues.
- Left open: AC #1 stays unchecked only for attachments (file and photo sending in personal chats were not exercised live; TASK-0300 owns Teams free's file sharing and has the Photos tab AC).

Built so far: personal accounts' chat list (Teams free sections, pills, Requests row and pane), reading, sending, editing, deleting and reactions in 1:1 and group chats, new 1:1 and group chats by name, email or phone (searchUsers, groups service), chat requests with Preview, Accept and Block (1:1 and group) and the sender's start card, and the retired features (polls, tasks, apps, location, SMS) left out; verified live (PR #81). Missing: AC #1's attachments, i.e. sending files and photos in a personal chat as Teams free does (OneDrive "Anyone with the link" sharing; the Photos tab is on TASK-0300). The personal window keeps OST's default app bar (Teams free's rail is TASK-0297). (2026-11-28)

- 2026-11-28 coordinator follow-up: the personal window's rail drew Teams free's app icons as black squares once this PR's middle-tier auth let aggregatedEntitlements answer; app_bar::load now refuses for personal accounts, so the window keeps OST's default bar as before (Teams free's rail: TASK-0297). Live (testpc2, fresh OST Personal 2 sign-in, build of 67a09488's code): the rail draws Activity, Chat, Calendar, Calls, OneDrive, Apps and More icons; the 1:1 with OST Personal 1 is named in full.

- 2026-11-28 (tperF, with TASK-0300 on branch task-0300-0293-personal-files): attachments in personal chats now work as Teams free sends them (OneDrive Chat Files upload, anyone edit link, picture previews, cloud files, Download, Open in Browser); verified live between OST Personal 2 in OST (testpc2) and OST Personal 1 on teams.live.com.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
A personal (Teams free) account's chats now work as in Teams for personal use (PR #81).

Changes:
- Engine: Teams free's chat service front door with its product headers; folders from Teams free's CSA; middle-tier calls with the mtsvc.fl token plus the Skype token; names from fetchShortProfile (ggEnabled) and fetchFederated; pictures with the imageauth cookie; Skype-name MRIs count as consumers.
- New chats: searchUsers by name, email or phone; 1:1 and group chats through teams.live.com/api/groups, the person added to contacts.
- Requests: Teams free's Requests row and pane, request and group-request views and preview bar; Accept (contacts for a 1:1, relationshipState=Accepted for a group) and Block (block list) as Teams free's worker does them.
- Layout: Teams free's chat list sections and pills, the work-user header and banner, start-of-chat card, compose toolbar and + menu (no apps, polls or tasks), message menu, Chat and Files tabs.

Verified live with OST Personal 2 beside Teams 26304 on testpc2 and OST Personal 1 on teams.live.com: list, send/edit/react/delete, new group chat by email, Requests, group and 1:1 Accept; Block against the service. Not verified: attachments (TASK-0300), phone search, Block pressed in the UI.

Attachments (AC #1, with TASK-0300): files and photos in personal chats as Teams free sends them (OneDrive Chat Files, anyone edit link, picture previews, cloud files), opened in the browser and downloaded by redeeming the link; verified live between OST Personal 2 in OST and OST Personal 1 on teams.live.com.
<!-- SECTION:FINAL_SUMMARY:END -->
