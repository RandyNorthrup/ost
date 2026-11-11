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
- The thread at the channel's card width: the post, then its replies; a call end is a row: the video glyph (20, #616161) at 18, 16 down; the time and "Meeting ended: **{duration}**" (12/16) at 54, 14 down. Under it Teams shows the meeting's Attendance card (`attendance-report-message-wrapper`: 321.3 × 49.3, #E6E6E6 (#FAFAFA hovered), radius 4, shadow 2; a 32 px icon and "Attendance" 14/600) at the text column, 32 down; the row is then 93.3 tall. See "Attendance" below.
- "Reply in thread" compose at the bottom.

## Attendance (TASK-0109; measured on winpc 2026-11-11)

- **Who sees the card:** the meeting's organizer and co-organizers (Teams' `recalcHasAttendanceReport`: organizer id or `coOrganizerIds` from the thread's `meeting` property; never for a Broadcast). Under every ended meeting in a meeting chat (28 below the row's top at the text column; the row grows from 36 to 77.3) and in a channel meeting's thread.
- **Clicking it:** in a meeting chat an **Attendance** tab joins Chat, Shared, Recap (Teams moves it out of "+4") showing that meeting; in a channel the Attendance view takes the whole content area (the chat list hides, the header band stays empty; the title bar's back returns).
- **Data** (token for app `c82e1b1b-5ab6-48fb-b4f8-890a5b27b181`, scope `AttendanceReport.Read`):
  - `GET https://teams.microsoft.com/api/attendancereport/prod/attendancereport/history?threadId=…&organizerObjectId=…[&messageId={post}]&pageSize=50&uiSource=meetingchat|channelChiclet` → `{reports: [{callId, ngcCallId, startTimeUtc, endTimeUtc, attendeeCount}]}` (newest first). A call-ended message's `callId` is the report's `ngcCallId`.
  - `GET …/attendancereport?threadId=…&callId=…&organizerObjectId=…&pageIndex=0[&messageId=…]&uiSource=…` → `{summary: {startTime, endTime, duration, attendeeCount, averageAttendeeDuration}, participants: [{displayName, emailAddress, upn, mri, role, joinTime, leaveTime, durationInSeconds, attendanceIntervals}], totalPages}`.
  - Download: `GET …/attendancereport/file?threadId=…&callId=…&organizerObjectId=…&timeZoneId={Windows zone}&locale=en` → UTF-16 tab-separated report (Summary, Participants, In-Meeting Activities); the name comes in Content-Disposition (percent-encoded), e.g. "OST calendar test_ created from OST - Attendance report 11-11-26.csv". Saved to Downloads.
- **View:** the 48 px toolbar (12 in): the meeting picker (#F5F5F5, radius 4, 31.3 tall, "Wednesday, November 11, 2026 6:47 AM - 7:22 AM", chevron 20); More (filter glyph, 14/600, brand when hovered/open); Download at the right. The report 20 in: four cards in two columns 10 apart (93.3 tall, 0.67 #E0E0E0 border, radius 9, padding 14 24; value 32/600 with units 20/600; label 14 #424242): Attended, Start and end time, Meeting duration, Average attendance time. "Participants" 16/600 (24 above, 16 below). The table (0.67 #E0E0E0 border, radius 8, at least 320 tall): header 32 (12/16 #616161: Name, First join, Last leave, In-meeting duration, Role), rows 50 (picture 32, name 14 with the email 12 beside it, then 14/20 values).
- **Picker list:** white, radius 4, padding 4; a group per day ("November 11", 12/600 #616161), meetings 32 tall ("6:47 AM - 1 attendees", check 16 on the chosen one), a line between days.
- **More:** a popover (247.9 wide, padding 16): "Number of participants" 12/600; "Show greater than" with a number box (91 × 24, #F5F5F5); Apply (full width). It keeps meetings with more attendees and picks the first left.
