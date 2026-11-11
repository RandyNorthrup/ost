# Channel meetings in a channel's posts

Measured on winpc (Teams desktop 26288, OST Test Team ▸ General) on 2026-11-10, CSS px.

## The data
- A meeting started in a channel (Meet now, or a scheduled channel meeting) posts its `Event/Call` callStarted message as a **root** post. Its `properties.meeting` (a JSON string) carries `meetingJoinUrl` (`/l/meetup-join/19:…@thread.tacv2/<post id>?context={Tid,Oid}`), `organizerId`, `tenantId` and `meetingtitle` (null for Meet now). The content carries `<conversationStartTime>` (UTC, "MM/DD/YYYY HH:MM:SS"), `<conversationUrl>` and `<callId>`.
- Each later conversation of the same meeting (a rejoin after everyone left) posts a callStarted **root** with `properties.linkedRootMessageId` = the meeting's post, plus a callStarted reply in the meeting's thread. Teams folds these into the meeting's post.
- A conversation's end is a callEnded reply (`<ended/>`, participants with durations) in the thread.
- Call events carry no display name: Teams resolves the author by MRI (`POST {mt}/beta/users/fetchShortProfile`).

## The post
- The normal post card: author (32 px picture, name, time), then the subject line (18/600, line 25.7): the meeting's title, or `Meeting in "<channel>"`; once no conversation is live, `… ended`. No body; the reactions row with the add button.
- **Live** (`channel-ongoing-meeting-banner`): under the reactions, 2 px down, the card's full width, 70 tall, #333357, radius 4, white text:
  - a 32 px tile (#5B5FC7, radius 4) 20 in and 19 down with the video glyph (20, white);
  - the title (14/600) 10 after the tile;
  - from the right: Join (`channel-ongoing-meeting-banner-join-button`, 96 × 32, #5B5FC7, radius 4) 20 in; the people in it (28 px pictures, 18 apart) 15 before Join; the time since the conversation started (`meeting-duration`, 14/400, mm:ss) 15 before them.
  - Join opens the pre-join screen for the meeting's link.
- **Ended**: a 40.7 tall response row with "See details" (12 px brand, 18 + 3.7 in, 12 down); it opens the post view.

## The post view (Teams' L2 view; "See details", or a post's thread)
- Header 61 tall: the team's picture (32, radius 2) 20 in; the channel's name (14/600, line 20) at 62, 9.7 down; "Post by {author}" (12/16 #616161) 31.7 down. At the right: Go to channel (`close-l2-view-button`, text, 31.3 tall), Open in new window (`btn-l2-popout`, 32), a divider, Find in post (`channel-search-toggle-button`, 32) and More (32: Find in post Ctrl+F, Follow thread), 11 from the right.
- The thread at the channel's card width: the post, then its replies; a call end is a row: the video glyph (20, #616161) at 18, 16 down; the time and "Meeting ended: **{duration}**" (12/16) at 54, 14 down. Under it Teams shows the meeting's Attendance card (`attendance-report-message-wrapper`: 321.3 × 49.3, #E6E6E6, radius 4, shadow 2; a 32 px icon and "Attendance" 14/600; "Download the attendance report").
- "Reply in thread" compose at the bottom.
