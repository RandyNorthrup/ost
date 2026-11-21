---
id: TASK-0130
title: 'Cloud file picker and attachment card: the rest of Teams'' details'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-13T21:53:00Z'
updated_date: '2026-11-21T01:18:00Z'
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
- [x] #1 The attachment card's link description opens Teams' Link settings and the choice applies to what is sent
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

- 2026-11-20 (chatC): measured on winpc (Attach cloud files from OST group test). The picker is ODSP build 2026-11-06.005. The Media view is OneDrive Photos' AllPhotosView (spofilepickerwebpack 2503.js and 414.js; strings in en-us/photos.resx.js). Scratch copies are in chatC/fp6.
  - Data: `{OneDrive}/_api/v2.1/drives/me/items/root/items?$filter=photo ne null and photo/takenDateTime ge 1900-01-01T00:00:00.000Z&orderby=photo/takenDateTime desc&select=createdBy,createdDateTime,cTag,description,driveId,file,fileSystemInfo,id,image,lastModifiedDateTime,location,name,parentReference,photo,shared,sharepointIds,size,video,webUrl&top=100`. Thumbnails come from items/{id}/thumbnails/0/c39….
  - Bar: Select layout 32 x 31.3 at 796.7, 29.3; Toggle Compact View at 836.7 ("…, active" / "inactive"); a line; Zoom controls at 893.3.
  - Select layout opens a menu: "View as" with River (default), Waterfall and Square, each with a check; a line; "Inline dates" (off) and "Show file names" (on), both checkable.
  - Zoom controls opens a popover (189.3 x 48.7, white, radius 4): Zoom out, a 100 px "Photo zoom level" slider (6 to 20, step 1, value 8, so zoom = value x 25 px: 150 to 500, default 200) and Zoom in. The buttons' labels are "Zoom out, photo zoom level at 200 pixels".
  - Layouts (code `t_` = uxSetting.layoutAlgorithm or "river"):
    - River: justified rows of maximum height = zoom.
    - Waterfall: masonry columns of maximum width = zoom.
    - Square: a grid of square cells of maximum size = zoom.
    - Settings are kept in OneDrive uxSetting (layoutAlgorithm, zoomLevel).
  - Compact: on, a 2 px gap (265.8 x 149.5 tiles, 3 to a row); off, 20 px (253.8 x 142.7). Show file names adds a 44 px name block (14 px #242424, 12 in) under each tile.
  - With Inline dates off: one sticky #F5F5F5 heading, 64 tall, at 104, 78, 18/600. It names the visible range, oldest to newest: "Nov 17 - Nov 20, 2026" (short - long; one day: long; different years: long - long).
  - With Inline dates on: that heading goes, and each day starts with its own heading ("Nov 20", "Nov 19", "Nov 17"; long format in another year), placed over that day's first tile in the row.
  - A 44 px "Timeline" scrubber on the right: 4 px dots 68 apart; the year at the bottom; hovering shows the month.
  - A video tile has a play mark; on hover or selection, its duration ("1:54"). A selected tile has a brand border and a check circle.
- People (Browse by > People), measured: today only OST Test 2 is listed, with the files they shared with you. The "files you shared" from 11-16 are no longer listed.
  - The files cell runs from 353 to 939. Chips are 41.3 tall and 12 apart, filled until the cell is full; the last one's name is shortened. The rest go under a "+N" button that opens the person's page.
- All picker settings were put back (River, Inline dates off, compact on).
<!-- SECTION:NOTES:END -->
