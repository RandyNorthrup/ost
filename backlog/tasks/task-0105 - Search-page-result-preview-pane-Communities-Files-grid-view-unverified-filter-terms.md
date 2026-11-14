---
id: TASK-0105
title: >-
  Search page: result preview pane, Communities, Files grid view, unverified
  filter terms
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-11T03:01:00Z'
updated_date: '2026-11-14T03:40:00Z'
labels:
  - search
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' search results page (TASK-0051) leaves these to do: clicking a message result opens a preview pane on the right (the conversation, Go to chat/channel, pop-out, ···, close; OST opens the chat instead); the Communities tab (Viva Engage search); Files' Grid view / List view toggle; and filter terms not yet captured from Teams (Type ▸ Channel, In ▸ channel / team; assumed from Find in chat's).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A message result opens Teams' preview pane beside the results (measured), with Go to chat/channel
- [ ] #2 The Communities tab searches Viva Engage as Teams does, or is omitted only if the account has no Viva Engage
- [x] #3 Files has Grid view and List view as Teams
- [x] #4 Type ▸ Channel and In ▸ channel / team send the terms Teams sends (captured)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Preview pane done: SearchPreview.qml (measured: 40% of the page, 61 px header; chat: picture, name 18/700, ··· Go to chat / Open in new window / Mark as unread / Copy link, Close; channel post: team picture, channel 14/600 + subject 12, Go to channel, Open in new window, ···, Close). The chat or thread loads as a live window conversation with the found message brought into view and its terms marked; selected cards turn #FAFAFA. Your notes chat (48:notes) can now open in windows and previews.

- Captured from Teams: Type ▸ Channel sends "(…ThreadType_String:(topic OR space)) AND NOT (isClientSoftDeleted:TRUE) {kw}" with no filter term. In ▸ channel sends "clientthreadid:{channel} AND NOT (isClientSoftDeleted:TRUE) {kw}" with Filter {"Term":{"GroupId": team}}. Both applied.
- In ▸ team: not captured yet (the pick missed); OST sends the thread-type clause with the GroupId term.

- 2026-11-11: Files Grid view / List view (42a6fc9). Measured on winpc: toggle (30.67+32 x 31.33 outline pair, chosen icon filled #4F52B2, kept via setSearchResultLayout); grid of 242.27 x 186.27 cards, 3 a row, 15.6 apart, column at width/2-323 (list at width/2-357); thumbnail = RichFilePreview c960x540 from the OneDrive thumbnail API (OST: Graph /shares/u!{url}/driveItem/thumbnails/0/c960x540/content); footer name 14/600, "OST T." + ago; ··· menu Open in Browser / Download / Share / Copy link / Favorite. Grid asks for 24 a page (FILES_GRID).
- List card corrected to Teams: line from FileAnnotations ("Shared by"/"Created by"/"Modified by", else Author alone), place line from ParentLink with 8 px chevrons, capitalized, 320 max; two-line summary; feedback row 28; onepart -> generic icon, mp4 -> video icon.
- Follow-ups: TASK-0112 (Share this file dialog; Share left out of the grid menu until then), TASK-0113 (team-site titles in the place line).

- 2026-11-13: In ▸ team captured (OST Test Team, Messages tab, searchservice/api/v2/query): "clientthreadid:{team thread, its General channel} AND NOT (isClientSoftDeleted:TRUE) {kw}" with Filter {"Term":{"GroupId": team}} — same shape as In ▸ channel. OST now sends that (search.rs message_query; test).
<!-- SECTION:NOTES:END -->
