---
id: TASK-0089
title: Profile cards as Teams (live persona card)
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-10T09:07:00Z'
updated_date: '2026-11-13T04:52:00Z'
labels:
  - desktop
  - parity
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams opens a person's profile card from their avatar or name in chats, channels, the people pane and search: their picture, name, presence and status message, out of office, work location, contact actions (chat, call, video, email), contact details, organization and files. OST has no profile card.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Clicking or hovering a person's avatar or name opens Teams' profile card with the same layout and sections
- [x] #2 The card shows their presence, status message, out of office and work location from the presence service
- [x] #3 Card actions (chat, audio and video call, email, copy) do what Teams' do
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Built (see commit): opens from pictures in messages, channel posts/replies, 1:1 header and people pane; Overview/Profile/Organization; compared with Teams' card for a colleague (same availability, work hours, time zone, contact info, reports). Not built: LinkedIn tab, Teams' org chart drawing, opening from names/search.

- 2026-11-12: hover researched (compact card, ~640 ms open / 500 ms close, layout measured) and built as HoverCard.qml; triggers on avatars that open profiles, message sender names and the 1:1 title. --hovercard-test verifies open/close and Profile ›. Left for AC1: LinkedIn (button + tab), sections under Show more (failing to load in Teams today), opening from search, Teams' org chart drawing.
<!-- SECTION:NOTES:END -->
