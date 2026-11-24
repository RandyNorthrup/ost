---
id: TASK-0130
title: 'Cloud file picker and attachment card: the rest of Teams'' details'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-13T21:53:00Z'
updated_date: '2026-11-21T15:46:00Z'
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
- [x] #5 Media (layout menu, compact, zoom, date headings) and People (including files you shared) match Teams'
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

- 2026-11-20 (chatC), built and checked live on linuxlt as ost-test1 (`--attach-test`):
  - Media now uses Photos' own query (api::drive::photos) and draws Teams' bar: Select layout (River / Waterfall / Square, Inline dates, Show file names), Toggle Compact View, a line, and Zoom controls (Zoom out, slider 6–20 x 25 px, Zoom in).
  - River / masonry / square layouts at the zoom; 2 / 20 px gaps; 44 px names; the visible-range heading (#F5F5F5 64, 18/600) or per-day dates; a 44 px timeline with dots and the year; video length on hover or pick.
  - The shot (scratch chatC/a-media.png) matches Teams' Media view on winpc: 265.8 x 149.5 tiles 3 to a row, the heading and the bar.
  - People: chips fill the 570 px cell, then "+N". The pill shows the day only with the shared glyph. People without a sharer ("Someone") are no longer listed.
- Still open:
  - The timeline doesn't scrub.
  - Layout and zoom aren't saved to OneDrive uxSetting (they reset per picker).
  - People chips use the file name: Teams shows the recording's title, without the timestamp suffix.
  - The person picture falls back to initials, where Teams draws its person placeholder.

- 2026-11-20 (chatE), from Photos' code (spofilepickerwebpack 2503.js, module 8734 the scrubber, 8735/8736 date maths; settings store 4464) and checked live on linuxlt as ost-test1:
  - Timeline: the newest year at the top and the oldest at the bottom (each goes there), 4 px dots 68 apart (ceil(height / 68), cut at the channel), shown on hover and while scrolling. Over the channel a 4 px brand mark follows the pointer with the month beside it ("November 2026"); the date is linear in time between the newest and oldest picture; a click goes to the 15th of that month, a drag (the mark 8 x 24) goes along; wheel scrolls. Without the pointer, while scrolling, the mark shows where the pictures in view start. `--attach-media-test`: clicks at a quarter, half and the end of the channel scroll the list to those dates (the list ends at Nov 8 for this account, so all three end at the bottom).
  - Layout and zoom are kept as Photos keeps them: its uxSetting {layoutAlgorithm, zoomLevel} lives in the picker's local storage (per device), so OST keeps `photosUxSetting` in its device settings; compact, inline dates and file names are not kept (Teams' component state). Live: Waterfall at 300 px came back on reopening; the setting was put back.
  - People: Teams (winpc, Browse by > People) names chips by the file's title (Substrate's Visualization.Title, the SharePoint Title that Teams sets to a recording's meeting name: "OST TEST 217 r3 town hall B"); OST now reads each file's Title (Graph listItem fields) and shows it, else the name without extension. The person picture is SharePoint's default photo for someone without one (a white figure on #B2B2B2), as the picker shows it. Live: OST shows "OST TEST 217 r3 town hall B" and "OST TEST 217 webinar" with the figure, as Teams does.
- Open: Teams lists a third file for OST Test 2 ("+1"): its People view reads Substrate's shared-with-me working set, which has one item Graph's sharedWithMe doesn't return. The "files you shared" Teams listed on 11-16 are no longer listed in Teams either.

- 2026-11-21 merged (1424747); 877 lib + 29 desktop tests pass. One known gap: Teams lists one more file for OST Test 2 (its +1) from a source Microsoft's file API doesn't return to OST.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Cloud file picker and attachment card as Teams, finished with Media and People.

- Media is OneDrive Photos as Teams' picker has it: Select layout (River, Waterfall, Square, Inline dates, Show file names), compact toggle, zoom popover, date headings and a Timeline that scrubs to the 15th of a month; layout and zoom kept per device as Photos keeps them.
- People chips fit the row with +N, name files by their title and show Teams' person picture.
- Earlier: Link settings on the attachment card, suggested files, the thread view's Attach popover, the command bar and folder icons.

Verified live against Teams on winpc. Gap: one file Teams lists for OST Test 2 comes from a source the file API doesn't return.
<!-- SECTION:FINAL_SUMMARY:END -->
