---
id: TASK-0265
title: Post editing and Copilot history as Teams
status: In Progress
assignee: []
created_date: '2026-11-24T00:42:00Z'
updated_date: '2026-11-24T01:35:00Z'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-0263: Teams edits a channel post in the full post composer (subject, Change permissions, Post in other channels) where OST uses the plain edit box; the edit box doesn't show a message's existing Loop component or clip; a post view's More menu has View Copilot history; Followed threads has a single-thread view in Teams; Teams also sends appIconPosition in the Copilot app's startup context.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Editing a channel post opens Teams' full post composer with its subject, permissions and post-in-other-channels options, and saves as Teams
- [ ] #2 The edit box shows a message's existing Loop component and video clip as Teams and keeps or removes them as Teams
- [ ] #3 A post view's More menu has View Copilot history, working as in Teams
- [ ] #4 Followed threads opens a single thread view as Teams
- [ ] #5 The Copilot app's startup context matches Teams' field for field, including appIconPosition
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Measured on winpc 2026-11-24 (CDP; own test posts/messages only):
  - Post edit = Teams' post composer in the card's place: Close (not Discard), cross-post row (+ and channel chips) when cross-posted, subject, format bar without Announcement, editor, Emoji/Attach/Copilot/Loop/+ and Post. + = Collaborate with Loop, Set delivery options, Record video clip, Change permissions ("Who can reply": Everyone / You and moderators = replyPermission AuthorAndOwners), Post in other channels ("Post in": This channel / Multiple channels -> chips row, + opens Choose channels).
  - Saves captured: plain post PUT chatsvc (subject, title, replyPermission, postType Standard, crossPostChannels []); adding channels POST {csa}/v1/teams/{team}/channels/{ch}/posts/{post}/crosspost; cross-posted post PUT {csa}/v1/teams/users/me/crossposts/{id} (channels from GET .../crossposts/{id}); new cross-post POST {csa}/v1/teams/users/me/crossposts.
  - Edit box with a message's clip + Loop ("OST TEST 263 edit tools"): clip card 400x225 over the text with Remove video clip; Loop card with header + Discard ("Discard draft message", Graph DELETE of the file at once). Done without: video element dropped (empty <p> stays), amsreferences [], FluidEmbedCard span gone, cards "[]".
  - View Copilot history: post view (non-slice) More = Find in post, Follow/Unfollow, View Copilot history (no divider); opens Teams' own Copilot history pane (48 tall header, "Copilot history" + Learn link, "No history yet." empty state); no request made for ost-test1.
  - Followed threads: picking a post shows the channel L2 (512 wide): no Find, More = Copilot (Alt+C) + Unfollow; Copilot open -> list moves to chat list place (320, Return to list), post 532, Copilot 360.
  - Copilot context: appIconPosition -17 in every capture; no defaultOneNoteSectionId.
- Test data made in Teams: "OST TEST 265 post edit (edited)" and "OST TEST 265 plain post" (cross-posted to OST test channel 2) in OST test channel; self-chat "OST TEST 263 edit tools" lost its Loop (file deleted) and clip in Teams.
<!-- SECTION:NOTES:END -->
