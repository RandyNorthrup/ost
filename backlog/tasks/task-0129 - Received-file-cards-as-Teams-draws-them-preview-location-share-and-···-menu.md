---
id: TASK-0129
title: 'Received file cards as Teams draws them: preview, location, share and ··· menu'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-13T20:09:00Z'
updated_date: '2026-11-13T23:56:00Z'
labels:
  - desktop
  - messages
  - files
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams draws a file in a message (OST TEST 117, 2026-11-13) as a card: a header with the file's icon and name, its location under it (chicletBreadcrumbs, e.g. 'personal > ost-test1_…'), a share button and a ··· menu, over a preview picture. OST still draws a 48 px header with Open in browser and Download only.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A received file shows Teams' card: header with icon, name and location, share and ··· buttons, and the preview
- [x] #2 The share button and ··· menu offer what Teams' do and work
- [x] #3 Verified side by side with Teams on winpc
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Measure Teams' card, menu, Share, Copy link and Favorite on winpc (CDP read-only, VNC clicks; favorites reverted)
2. Location from chicletBreadcrumbs (Teams' rule), site URL; SharePoint favorites call
3. FileCard.qml; menu, Share this file, Copy link (Link copied) and toasts with Undo in Conversation
4. Harness --filecard-test [--filecard-live]; compare with Teams
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Teams: Share opens Share this file; ··· = Open in Browser, Download, Share, Copy link, Favorite/Unfavorite (SP v2.1 favorites/followedListItems/oneDrive.add|remove); Copy link goes straight to "Link copied"; toasts wrap, Unfavorite has Undo
- Share this file now starts from the file's default link (commands' defaultLinkDescription) and shows its "Add a message (optional)" hint (rich text was never empty)
- Harness run on linuxlt: card/menu/Copy link (reused link 67083923) /Share; live favorite → Unfavorite → Undo → off; file ends un-favorited
- Follow-up TASK-0131: Teams opens a message's file in its own full-pane viewer
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
A file in a message now looks and works as in Teams.

Changes:
- FileCard.qml: Teams' card (320 wide, radius 6, #FAFAFA head with icon, name and location, Share and ··· buttons, 16:9 preview); the location follows Teams' breadcrumb rule (files.rs `location`).
- Conversation: the ··· menu (Open in Browser, Download, Share, Copy link, Favorite/Unfavorite), Share this file, Copy link straight to "Link copied" (FileActions.copyLinkNow), favorites toasts with Undo.
- backend driveAction card_item (Files item + favorite state) and card_favorite (drive::set_favorite_by_url, Teams' SharePoint call).
- Main toast: wraps and carries an action (Undo).
- ShareFileDialog: starts from the file's default link; the message hint shows.
- Spec: messages-and-composer.md §17 "A file in a message".

Tests: cargo test --lib (495), desktop tests, harness --filecard-test [--filecard-live] on linuxlt, compared with Teams on winpc.

Follow-up: TASK-0131 (Teams' in-app viewer).
<!-- SECTION:FINAL_SUMMARY:END -->
