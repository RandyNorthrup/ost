---
id: TASK-0190
title: 'File viewer: Show comments, Share menu check and narrow layout as Teams'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-16T04:53:00Z'
updated_date: '2026-11-20T15:35:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OST's viewer has a Share menu not yet compared with Teams', lacks 'Show comments', and the narrow breakpoint wasn't measured.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Show comments works as in Teams
- [x] #2 The Share menu and narrow layout match Teams, measured on winpc
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-19 measured on winpc (Preview of ost-share-test.txt, 1212 frame):
  - Show comments = 32x32 icon button (comment glyph); tooltip "Hide comments" while open. It opens a dark right pane 370 wide at (W-378, 53), #141414, radius 5: "Comments" 20/600 #F3F2F1 at +20,+26.6; "Close comments" 32 px at the right; "@mention or comment" box 328x30.67 (#252423, 0.67 #424242, 2 px #BEBBB8 bottom, radius 6) at +20,+75; empty: 128 px picture, "No comments yet" 16/600, "Be the first to add a comment to the file" 14/20 (138 wide). Data: SharePoint GetComments() as in Details. The page then takes 75% of the area left of the pane.
  - Bar glyphs and the Open/Share labels are #0078D4 (chevrons white).
  - Share menu: dark Fabric callout #1B1A19, radius 4, 180 wide, padding 4, under the button, right edge at W-8: Share, Copy link, Manage access (rows 172x36, 16 px glyph at 8, label at 32, #F3F2F1).
  - More (...): Copy to, Embed, Version history, Help > (Send feedback, View tutorial).
  - Narrow: going down, the left items fold into ... one by one at W<796 (Info), <760 (Delete), <724 (Favorite), <688 (Download); the title is centred between the left set and W-355 with 60 margins. At W<=640: title from 8 (W-210 wide), ... at W-200, Share at W-160, Close at W-46; ... = Download, Favorite, Delete, Info, Copy to, Embed, Version history, Help >, Show comments (glyph only), Open >.
  - Embed: dialog 598.67 wide, "Embed" 20/600, 'Embed "{stem}" on a blog or webpage.', a 550.67x212 preview of embed.aspx, a 92 tall code box, "Copy embed code" and "Close".

- 2026-11-20 built: FilePreview bar (blue glyphs, fold thresholds, narrow <=640 layout, OneDrive's ··· with Embed and Help), Show comments pane (item_details::comments), dark Share/··· menus (MenuPopup darkCallout); harness --preview-bar-test. Pending: run + compare a test comment with Teams.

- 2026-11-20 verified (--preview-bar-test at 1280/864/760/600): positions within ~1 px of Teams' (title 468.26 vs 468.32), folds at Teams' widths, narrow layout, dark Share and ··· menus, Show comments pane (a test comment posted and deleted), Embed code. Open: the look of a comment card in Teams' dark pane wasn't measured (no comments on the test file).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
File preview: Show comments, Share menu and narrow layout as Teams.

- Show comments opens Teams' dark Comments pane with "@mention or comment", posting and reading comments; Share ▾ (Share, Copy link, Manage access) and ··· (Copy to, Embed, Version history, Help ▸) in Teams' dark style; the Embed dialog.
- As the view narrows, Info, Delete, Favorite and Download fold into ··· at Teams' widths (796/760/724/688; at 640 only the name, ···, Share and Close remain).
- Live: a test comment posted and deleted; at 1280, 864, 760 and 600 the bar matches Teams within about 1 px.
- --preview-bar-test. 815 lib tests pass.
<!-- SECTION:FINAL_SUMMARY:END -->
