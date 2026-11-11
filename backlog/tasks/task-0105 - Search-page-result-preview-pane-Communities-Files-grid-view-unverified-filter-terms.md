---
id: TASK-0105
title: >-
  Search page: result preview pane, Communities, Files grid view, unverified
  filter terms
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-11T03:01:00Z'
updated_date: '2026-11-11T03:17:00Z'
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
- [ ] #3 Files has Grid view and List view as Teams
- [ ] #4 Type ▸ Channel and In ▸ channel / team send the terms Teams sends (captured)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Preview pane done: SearchPreview.qml (measured: 40% of the page, 61 px header; chat: picture, name 18/700, ··· Go to chat / Open in new window / Mark as unread / Copy link, Close; channel post: team picture, channel 14/600 + subject 12, Go to channel, Open in new window, ···, Close). The chat or thread loads as a live window conversation with the found message brought into view and its terms marked; selected cards turn #FAFAFA. Your notes chat (48:notes) can now open in windows and previews.
<!-- SECTION:NOTES:END -->
