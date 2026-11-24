---
id: TASK-0121
title: 'Details pane comments as Teams: edit, replies, likes, mentions'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-12T17:48:00Z'
updated_date: '2026-11-13T02:57:00Z'
labels:
  - files
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OneDrive's Details pane comment cards have Edit comment (Show actions), a Reply box under each card, likes and @mentions. OST's DetailsPane.qml shows, adds and deletes comments only (docs/spec/details-pane.md).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Edit comment changes a comment as Teams does
- [x] #2 Replies show under their comment and the Reply box adds one
- [x] #3 Likes and @mentions in comments work as in Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Researched on winpc 2026-11-12 with a test comment on ost-share-test.txt: Edit comment = PATCH Comments(id) {"mentions":[],"text"} 204; Reply = POST Comments(id)/replies {"text"} 201; GetComments with $expand=replies,likedBy; "Edited" from modifiedDate.
- Teams' pane has no like control and no mention picker (plain input; "@OST" shows nothing). OneDrive's code has both for other hosts. AC#3 met by matching that, plus mention names rendered.
- Teams leaves reply activities out of the feed and shows back-to-back edits once; OST now does too.
- All test comments (Teams' and OST's) deleted.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Details pane comments as Teams: Edit comment, replies and the Reply box.

Changes:
- api::item_details: GetComments with replies; FeedItem gains source/edited/replies; comment time in the files-list wording, replies in client wording; `@mention{n}` rendered as names; edit_comment (PATCH) and add_reply (POST replies); feed drops reply activities and repeated edits.
- sharing::send_with: SharePoint calls with any method.
- DetailsPane.qml: Show actions has Edit comment; edit box (2 px brand, Cancel/Submit); "• Edited"; replies under each comment; Reply box.
- Spec: docs/spec/details-pane.md (incl. why there are no likes or mention picker: Teams has none in this pane).

Tests:
- cargo test --lib (new comment/reply/mention and feed tests)
- --comments-test on linuxlt: posts, edits, replies, shows the edit box, deletes (live, cleaned up).
<!-- SECTION:FINAL_SUMMARY:END -->
