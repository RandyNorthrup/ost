---
id: TASK-0112
title: 'Share this file as Teams: the search file card''s Share'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-12T03:35:00Z'
updated_date: '2026-11-12T05:29:00Z'
labels:
  - search
  - files
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' search file cards (Grid view's ··· and the list) offer Share, which opens Teams' 'Share this file' dialog: Add recipients (people, groups, tags, chats, channels), a message preview with the file's card and link permission ('People with existing access can use the link'), the link settings (···), Copy link and Share (posts the file to the picked chats). OST's grid menu leaves Share out until this exists.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The search page's file cards offer Share and it opens Teams' Share this file dialog with the same layout (measured on winpc)
- [x] #2 Share posts the file with the optional message to the picked people, chats or channels as Teams does, and Copy link copies the link Teams copies
- [x] #3 The link settings (···) show and apply Teams' sharing-link options
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-11: measured Teams' "Share this file" (600 wide, padding 32: title 20/28 600, "You can share to any chat or channel." 14/28 #616161; ··· (Share outside Teams) and Close; "Add recipients *" (12/20) over a 534.67 x 33.33 #F0F0F0 combobox "Enter name, email, group or tag"; "Message preview" over a #F5F5F5 box (0.67 #E0E0E0, radius 6) with "Add a message (optional)" and the file card (320 x 236: 32 px icon, name 14/16 600, the link line "People with existing access can use the link" as a button, the c960x540 preview), formatting and emoji buttons; Copy link (outline) and Share (disabled until a recipient)). Share outside Teams opens OneDrive's dialog, now built (TASK-0052, 2295a1b).

- 2026-11-11 (a527a0b): built ShareFileDialog.qml (spec docs/spec/share-this-file.md). Recipients on Substrate peoplepicker.newChat (api::search::recipients, Teams' best-match order and second-line rule from its bundle: UPN alias in capitals, "(ALIAS) Job title"), CheckPermissions access bar + Give access, Link settings via OneDrive's dialog in chatMode (+ "People currently in this chat" = ShareLink kind 6 restrictShareMembership), Share = ShareLink + chat post with Teams' files record (api::files::shared_record), ··· Share outside Teams. Verified: OST's "OST test 109" record matches Teams' "OST test 108" in the test 1:1 (same chat link reused).
- AC#1 left open: the message box's Format button (Teams' formatting bar) isn't there yet; Emoji is. Also: M365 groups are left out of the suggestions; "(You)" isn't returned to OST by the service.
<!-- SECTION:NOTES:END -->
