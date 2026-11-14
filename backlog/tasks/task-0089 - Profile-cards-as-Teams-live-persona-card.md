---
id: TASK-0089
title: Profile cards as Teams (live persona card)
status: Done
assignee:
  - '@claude'
created_date: '2026-11-10T09:07:00Z'
updated_date: '2026-11-14T03:26:00Z'
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
- [x] #1 Clicking or hovering a person's avatar or name opens Teams' profile card with the same layout and sections
- [x] #2 The card shows their presence, status message, out of office and work location from the presence service
- [x] #3 Card actions (chat, audio and video call, email, copy) do what Teams' do
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Built (see commit): opens from pictures in messages, channel posts/replies, 1:1 header and people pane; Overview/Profile/Organization; compared with Teams' card for a colleague (same availability, work hours, time zone, contact info, reports). Not built: LinkedIn tab, Teams' org chart drawing, opening from names/search.

- 2026-11-12: hover researched (compact card, ~640 ms open / 500 ms close, layout measured) and built as HoverCard.qml; triggers on avatars that open profiles, message sender names and the 1:1 title. --hovercard-test verifies open/close and Profile ›. Left for AC1: LinkedIn (button + tab), sections under Show more (failing to load in Teams today), opening from search, Teams' org chart drawing.

- 2026-11-13: measured on winpc with OST Test 2: header LinkedIn button ("Find LinkedIn profile for …", MDL2 LinkedInLogo 16 px #1177B3 → linkedin.com people search), LinkedIn tab (no-profile state: logo, "Learn more on LinkedIn", DMA paragraph with privacy setting / Learn more links, Check your own settings, Connect your account; URLs from the LPC code; Connect opens AAD bind?Provider=LinkedIn in Teams — OST opens LinkedIn's Microsoft accounts page), Organization tab (#FAFAFA, Home/Back/Next 32 px nav, no-org bar). Search person result: click opens the chat (as OST already did), hovering the picture opens the hover card (now in OST). Hover card gets the LinkedIn button too.
- Follow-up TASK-0133: org chart drawing with real managers, Show more sections.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Profile cards now match Teams' for the test accounts: Overview, Profile, Organization and LinkedIn tabs, the header actions (chat, org chart, video, audio, LinkedIn), the hover card, and where they open from (pictures and names in chats, channels, the people pane, the 1:1 header and search results).

This round:
- LinkedIn: the header button (LinkedIn's people search) and Teams' LinkedIn tab for someone who shares no profile, with its links (DMA privacy setting, help, your visibility settings, connect your account).
- Organization: Teams' grey tab body, Home / Back / Next navigation through the people you open, and Teams' "We don't have the necessary details…" bar when there's no org data.
- Search: hovering a person result's picture opens the hover card; the hover card has the LinkedIn button.

Tests: --pause-test=profile:<OST Test 2> (pc-org, pc-linkedin) and --hovercard-test on linuxlt, compared with Teams on winpc.

Follow-up: TASK-0133 (the org chart drawing with real managers; Show more sections).
<!-- SECTION:FINAL_SUMMARY:END -->
