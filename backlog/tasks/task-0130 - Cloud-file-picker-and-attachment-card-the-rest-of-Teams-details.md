---
id: TASK-0130
title: 'Cloud file picker and attachment card: the rest of Teams'' details'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-13T21:53:00Z'
updated_date: '2026-11-20T22:08:00Z'
labels:
  - desktop
  - files
  - messages
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
What TASK-0085's Attach left of Teams' cloud file picker and compose card (docs/spec/messages-and-composer.md §17, measured 2026-11-13): the picker's command bar (New folder, Upload, view switch), People as Teams (OneDrive's collaborators, GetCollaboratorsAsStream, and their files), Media's date headings and layout and zoom controls, Teams' shared-folder icons, Home rows Teams adds without an open time (the OST Test Team Notebook), the card's Link settings (its description opens them, with 'People currently in this chat'), the Attach popover's suggestion rows (unmeasured: ost-test1 has none), and the attach menu in a post's thread view (PostThread).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The attachment card's link description opens Teams' Link settings and the choice applies to what is sent
- [x] #2 Suggested files in the Attach popover look as Teams draws them (measured with an account that has suggestions)
- [x] #3 A post's thread view offers the same Attach popover
- [x] #4 The picker's command bar (New folder with Teams' colours, Upload, view switch) and folder icons match Teams'
- [ ] #5 Media (layout menu, compact, zoom, date headings) and People (including files you shared) match Teams'
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built so far (1050c4e, merged as 8229940): command bar (New folder with Teams' Create a folder dialog and 16 colours, Upload files or a folder, List / Compact / Tiles), shared and coloured folder icons, People in OneDrive's order; Link settings from the attachment card (People currently in this chat, as Teams' OST TEST 172; OST's 173 matched in Teams on winpc); Recent cloud files suggestions with Teams' rows; the Attach popover in a post's thread view.

Left: Media's layout menu, compact toggle, zoom and date headings (measured in the spec, date-grouping rule unknown); People's files you shared (only in OneDrive's picker cache); the Created folder toast; Tiles thumbnails; Home's AllItems.aspx row and repeated Loop entries.

- 2026-11-20 (chat agent): not worked on in this pass (time went to TASK-0085's Loop components and installed apps, 0098, 0203, 0234, 0202). AC1 and AC5 stay as the notes above say.

- 2026-11-20 (chatB): AC1 rechecked live (`--attach-link-test`, ost-test1): the card's link description opens Link settings, "People currently in this chat" makes the link (ShareLink with the chat's people) and the card reads "People currently in this chat with the link can edit"; that this link is what's sent was checked earlier (OST TEST 173 in Teams). The same dialog now serves a compose Loop component's Link settings (with Teams' three choices there). AC5 (Media's layout menu, compact, zoom, date headings; People's files you shared) not worked on this pass.
<!-- SECTION:NOTES:END -->
