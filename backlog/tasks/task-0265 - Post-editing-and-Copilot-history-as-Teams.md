---
id: TASK-0265
title: Post editing and Copilot history as Teams
status: Done
assignee: []
created_date: '2026-11-24T00:42:00Z'
updated_date: '2026-11-24T09:03:00Z'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-0263: Teams edits a channel post in the full post composer (subject, Change permissions, Post in other channels) where OST uses the plain edit box; the edit box doesn't show a message's existing Loop component or clip; a post view's More menu has View Copilot history; Followed threads has a single-thread view in Teams; Teams also sends appIconPosition in the Copilot app's startup context.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Editing a channel post opens Teams' full post composer with its subject, permissions and post-in-other-channels options, and saves as Teams
- [x] #2 The edit box shows a message's existing Loop component and video clip as Teams and keeps or removes them as Teams
- [x] #3 A post view's More menu has View Copilot history, working as in Teams
- [x] #4 Followed threads opens a single thread view as Teams
- [x] #5 The Copilot app's startup context matches Teams' field for field, including appIconPosition
- [x] #6 A channel meeting's post shows its calendar card, and the post view's second line shows the meeting title, as Teams
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

- Built (posR): post edit = ComposeBox post+editing (Close, cross-post row, no Announcement, Loop button, + with Change permissions / Post in other channels, CrossPostDialog "Choose channels"); new posts get the same + items (outbox replyPermission, cross-post via CSA). api::messages: Teams-shaped edit_body (subject/title/replyPermission/crossPostId/amsreferences/policyViolation/crossPostChannels), EditExtras removed_loops/removed_clips/subject/reply_permission/post/cross_channels, save_post_edit (chatsvc PUT | CSA crosspost add | CSA crossposts PUT), cross_post_channels/new_cross_post. Edit box shows the message's clip (VideoClipCard) and Loop (LoopCard mode "edit", name + link words via editLoopInfo; Discard deletes the file via composeDiscardUrl). PostThread: View Copilot history (CopilotHistoryPane), slice mode, subject subtitle, 30 px card margins under 640. Main: Followed threads single-thread view (PostThread slice beside the list; list compact with Return to list while Copilot is open). Copilot context: appIconPosition -17, no defaultOneNoteSectionId, Teams' key order (app_host.js).
- Verified live on linuxlt (ost-test1, --post-edit-test): post view More = Unfollow, View Copilot history; history pane 360 at the end, link at +45.7/+23.7, Close at W-52 (Teams same). Followed: view 768/512, card 798/452, header Go to channel/pop-out 1189/More 1237; More = Copilot Alt+C, Unfollow thread; Copilot open: list at 68 compact, view 388 (532), Copilot button 845, More 877, pane 920x360 (Teams same); context fields = Teams' 43 keys incl. appIconPosition -17. Restore on the cross-posted plain post: chips [channel 2, source] at 525.7/625.7 with remove at 601.7, tools 484.7..612.7, Post 1079.3, + menu 234.3x205.3 at 511.6 (Teams same) -> PUT crossposts: replyPermission Everyone, channel 2 removed. New post "OST TEST 265 new post" with You and moderators -> replyPermission AuthorAndOwners. Edit adding OST test channel 2 + subject -> POST .../posts/{id}/crosspost: crossPostId set, subject "(edited)". Self chat "OST TEST 263 edit tools" (Loop + clip re-added by edit): edit box showed clip card 400x225 and Loop card with "OST Test 1 (You) Loop paragraph" / "People in your organization with the link can edit"; clip removed + Loop discarded ("Discard draft message") -> cards [], videos [].
- Tests: lib 944 passed.

- Final build checks: followed view no longer covered by the conversation (fixed), compact list titles no longer overlap the time; tests lib 944 passed, desktop 37 passed. Committed 72ec3394 (worktree agent-a2ac76182fc66cdfb).
- Left: AC4 only for Posts channels — a Threads channel's followed thread still opens its channel (Teams shows the same L2 header over the chat-style thread with Send to). OST's post card doesn't draw a channel meeting's calendar card, so Teams' header subtitle for those posts (the meeting title) shows "Post by" in OST. View Copilot history has only Teams' empty state: Teams made no history request for ost-test1 (bizChat), so entries were never seen.
- Test data: OST TEST 265 posts (3) deleted in OST test channel after their cross-posts were removed; self-chat "OST TEST 263 edit tools" deleted (its Loop files deleted by Discard; the AMS clip objects remain, no delete API).

- posR2 (2026-11-24), the two open ACs. Measured on winpc (CDP, own test data):
  - AC4: Followed threads > OST threads test "OST TEST 81 threads layout": the same L2 header (512 at 1280; Go to channel 1077.2, pop-out 1189, divider, More 1237), second line = the first message; under it Teams' message pane on white (runway padding 22 0 0 32, bubbles end 32 from the right, no "{N} replies" line) and the "Send to: thread only" compose 32 in, one row (text + tools). More = Copilot (Alt+C), Unfollow thread, Mark as unread, Copy link (139.3 wide, 32 items, 4.9 under the button); Copilot open: list to the chat list's place, thread 532, Copilot 360, More = Unfollow, Mark as unread, Copy link.
  - AC6: Teams' header title = channelDrillDownHeaderBaseData (properties.meeting meetingtitle, else title/subject, else Post by). Card = pre-state-schedule-meeting-banner-renderer: 684x70 at a 716 card (+16, 12 over the text), #EBEBEB, 0.67 #E0E0E0, 2 px brand bar 5 in, 32 white box with brand calendar at 20.7, title 14/600 at 62.7 (+17), start 12/16 ("Tuesday, November 24, 2026 10:00 AM"); live: More options 32x31.3 at W-156.7 (menu "Edit meeting details", centred 5 under), Join 96x31.3 white #D1D1D1 20.7 from the right; cancelled: "Canceled: {title}" struck through, no buttons. Clicking the card opens the meeting page. Wire: properties.meeting JSON with `scheduledmeetinginfo` {startTime, endTime, eventType, isCancelled, ...}.
  - winpc Teams had stopped picking up posts: restarted with wv2on (env value removed again).
- Built: messages::ScheduledMeeting (+ meeting_title on any message with properties.meeting); ScheduledMeetingCard.qml in ChannelPosts and PostThread (Join -> pre-join, card/More -> CalendarView.showMeeting(..., page) = the event page); PostThread headerTitle (meeting title / subject / first message / Post by), chatThread mode (More + Mark as unread, Copy link); Main followedChat (Conversation threadPane under the header, paneComposeGut 32, no replies divider, ComposeBox sendToInline); harness --meeting-post-test=create|show|followed|cancel.
- Verified live on linuxlt (spatest = ost-test1): channel card 492/684x70, More 1019.3, Join 1059.3 96x31.3 (Teams same); post view card 476/716x217.7 with the banner at 180, header "OST TEST 265 channel meeting"; cancelled OST CAL posts struck through, no buttons. Followed threads > OST threads test: view 768/512, header Go to channel/pop-out 1189/More 1237, title "OST TEST 81 threads layout", chat 512 under it, compose 800/448 one row; More = Copilot Alt+C, Unfollow, Mark as unread, Copy link; Copilot open: list 68 compact, chat 388/532, pane 920/360, More = Unfollow, Mark as unread, Copy link (Teams same).
- Tests: lib 949 passed.
- Test data: "OST TEST 265 channel meeting" (made by OST, ost-test1 only) cancelled; its post and cancel reply deleted.

- Tests: lib 949 passed, desktop 37 passed. Committed 02fe3bde (worktree agent-adf81594029a632e2).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Post editing, a message's own Loop component and clip in its edit box, View Copilot history, Followed threads' single-thread view (Posts channels) and Copilot's startup context, measured on winpc (2026-11-24) and verified live on linuxlt as ost-test1.

Teams (winpc, own test posts/messages; requests captured):
- Editing a post opens the post composer in the card's place: Close, the cross-post row, subject, no Announcement, Emoji/Attach/Copilot/Loop/+ and Post. + adds Change permissions (Everyone / You and moderators = replyPermission AuthorAndOwners) and Post in other channels (This channel / Multiple channels, Choose channels).
- Saves: chatsvc PUT; CSA POST teams/{team}/channels/{ch}/posts/{post}/crosspost when channels are added; CSA PUT users/me/crossposts/{id} for a cross-post; new cross-posts POST users/me/crossposts.
- The edit box shows a message's clip and Loop component; Discard deletes the Loop file; Done leaves them out.
- A post view's More: Find in post, Follow/Unfollow, View Copilot history (Teams' own Copilot history pane).
- Followed threads shows the post's L2 beside the list (no Find, Copilot in More); with Copilot open the list moves into the chat list's place.
- Copilot's context: appIconPosition -17, no defaultOneNoteSectionId.

Changes:
- ComposeBox post edit mode, cross-post row, permission/post-in menus, CrossPostDialog; existing clip (VideoClipCard) and Loop (LoopCard "edit") in edit boxes.
- api::messages: Teams-shaped edit_body, EditExtras (removed loops/clips, subject, permission, post, cross channels), save_post_edit and cross-post calls; outbox replyPermission and new cross-posts; loop_page::link_description; backend editLoopInfo/composeDiscardUrl/cross-post-channels.
- PostThread: View Copilot history (CopilotHistoryPane), slice mode, subject subtitle, 30 px card margins under 640. Main: Followed threads view; QuickListView compact mode.
- Copilot launch appIconPosition; context without defaultOneNoteSectionId, in Teams' key order.
- Harness --post-edit-test; specs; i18n ids.

Verified: composer geometry, + menu, permission/post-in menus, chips equal Teams'; all three save paths changed the posts as Teams; edit box clip/Loop shown and removed; history pane and Followed view/Copilot layout equal Teams'; context fields equal Teams'.
Tests: lib 944 passed, desktop 37 passed.

Open: Threads channels' followed threads (still open the channel); meeting posts' subtitle; Copilot history entries (never shown for this account).

Follow-up (posR2, 2026-11-24): the two remaining ACs, measured on winpc and verified live on linuxlt as ost-test1.

Teams:
- A Threads channel's followed thread shows the post view's header (its first message as the second line) over the thread as a chat: the message pane 32 in, no replies line, and the "Send to: thread only" compose on one row. More is Copilot, Unfollow thread, Mark as unread and Copy link.
- A channel meeting's post carries properties.meeting (scheduledmeetinginfo). Teams draws its pre-state banner: 684x70 at a 716 card, the calendar box, the title and start, and More options (View / Edit meeting details) with Join. A cancelled meeting's banner reads "Canceled: {title}", struck through, with no buttons. The post view's second line is the meeting title.

Changes:
- messages::ScheduledMeeting, and meeting_title from properties.meeting on every message.
- ScheduledMeetingCard.qml in ChannelPosts and PostThread (Join opens the pre-join; the card opens the meeting page in Calendar).
- PostThread headerTitle and chatThread mode; Main followedChat; ComposeBox sendToInline; Conversation paneComposeGut and threadRepliesDivider.
- Harness --meeting-post-test; specs; i18n.

Verified: the card's geometry and buttons equal Teams' in the channel and the post view; the Threads followed view, its More menus and the Copilot layout equal Teams'.
Tests: lib 949 passed, desktop 37 passed.
Open: Teams' Followed threads list puts a calendar glyph before a meeting post's title (OST shows the title only); the live banner inside the 452 wide Followed view was not measured, because Teams lists only threads with replies.
<!-- SECTION:FINAL_SUMMARY:END -->
