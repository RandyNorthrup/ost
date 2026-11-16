---
id: TASK-0167
title: 'Group chat avatars as Teams: members in a split circle'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-16T02:42:00Z'
updated_date: '2026-11-16T03:04:00Z'
labels:
  - desktop
  - chat-list
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' chat list (2026-11-15) draws a group chat without its own picture as a circle split between other members: the first member's initials or photo on the left half, the right half split into two quarters for the next two (or one photo when there are only two others). OST shows a generic group glyph.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Group chats without a picture show Teams' split-circle avatar from their members (initials or photos), in the chat list, header and anywhere else Teams uses it
- [x] #2 Measured against Teams on winpc (sizes, split, colours)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Find where Teams gets the picture (CDP on winpc)
2. Fetch it through api::directory::photo with a Chat owner
3. Use it in the chat list row and the header; refresh on member changes
4. Compare with Teams
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Teams doesn't draw the split circle itself: the middle tier renders it (mergedProfilePicturev2, 64 px), used for the row (20) and header (32).
- OST: PhotoOwner::Chat (members from the chat service, names via fetchShortProfile, first three others by name), photo id "chat:<thread>", cached like other pictures; forgotten after OST adds or removes members.
- Compared on screen: OST's three group rows and the OST group test header match Teams'.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Group chats without a picture of their own now show Teams' members picture (the split circle) in the chat list and the chat header.

Changes:
- api::directory: PhotoOwner::Chat fetches Teams' merged picture (mergedProfilePicturev2) for the first three other members by name; group_picture_members / merged_picture_users helpers with a test.
- Desktop: "chat:<thread id>" picture ids (hashed cache keys), used by ChatList rows and the Conversation header; meeting chats keep their calendar glyph.
- The picture is refreshed after OST adds or removes members.
- Spec: chat-list-and-header.md documents which chats Teams lists and the group picture.

Tests:
- cargo test (library) passes, including group_pictures_show_the_first_three_others_by_name.
- Screenshots of OST's list and header compared with Teams on winpc.
<!-- SECTION:FINAL_SUMMARY:END -->
