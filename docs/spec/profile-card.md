# Profile card (live persona card) — Teams desktop behaviour (spec)

Measured on winpc 2026-11-10 by opening a colleague's card from their picture in a chat.

## Layout

- **Sheet:** 840 × 618, centred, just under the title bar (y 47.5), over a dimmed window.
- **Header (padding 24):**
  - The picture (100) with presence sits at 24.7, 24.7.
  - The name (24/32 bold) sits at 144.7, 42.7.
  - Actions are 44 × 32, one every 52 from 144.7, 74.7: Start a chat, Navigate to org chart,
    Start a video call, Start an audio call, and LinkedIn.
  - Close (24) sits at 800, 16.
- **Tabs** at 148.7 (44 tall, 14; the open one is semibold brand): Overview, Profile,
  Organization, LinkedIn.
- **Overview:**
  - "Send a quick message" (739 × 32) with Send.
  - An availability box (773 wide, #E0E0E0 border, radius 4):
    - "Last seen {N hours} ago • Free at {time}" (14/19 semibold), or their status.
    - "Work hours: 8:00 AM - 5:00 PM" (12/16).
    - Then their local time: "{time} - Same time zone as you".
  - "Contact information" (14 bold): Email, Chat (imAddresses) and Work phone, each 237 wide
    (12 #424242 label over the 14 brand value), then "Show more contact information".
  - "Organization": "People reporting to {name} ({n})" with 122 × 156 tiles (a 56 px
    picture, the name 14 semibold, the job title 12 #424242), then "Show organization".

## Data

- **Profile:** Graph `GET /users/{id}`.
- **Organization:** `/users/{id}/manager` and `/users/{id}/directReports`.
- **Availability and work hours:** `POST /me/calendar/getSchedule` for them and you.
  - It returns workingHours (with the time zone) and a 30-minute availability view.
  - "Free at" is the end of what's on their calendar, or the start of their working hours
    when they're outside them.
- **Presence:** the presence service's getpresence: availability, lastActiveTime, note,
  calendarData.isOutOfOffice and workLocation.

## The compact card (hover)

Measured on winpc on 2026-11-12, hovering OST Test 2's picture and name in
the 1:1 chat header.

- Hovering a person's picture or name opens Teams' compact card about 640 ms
  after the pointer arrives (three in-page measurements: 621, 664 and 637 ms).
  It closes 500 ms after the pointer leaves both the trigger and the card
  (Fluent's popover `mouseLeaveDelay`; measured 350–450 ms through VNC).
  Clicking opens the full card.
- It is 340 wide and at most 446 tall (it scrolls), white with a 0.67 white
  border. Teams draws it in its own window, so its shadow is the system's.
  Its left is the hovered item's left and its top is 8 under it.
- The 72 px picture with its 24 px presence at 24, 29; the name 14/700
  #242424 at 116, 52.5.
- Five 44 x 32 buttons every 52 from 24, 106 with 16 px #616161 glyphs:
  Start a chat, Navigate to the org chart, Start a video call, Start an audio
  call, Find LinkedIn profile (the LinkedIn mark in #1177B3).
- "Send a quick message": 255.3 x 32 at 13.7, 163.3, #F3F2F1, radius 4, with
  Send (44 x 32) at 273.7.
- The availability box: 304 x 38 at 14, 208, a hairline border; the 16 px
  status glyph at 25.7 and "Last seen 22 h ago" (12/600) at 55.7. The compact
  card abbreviates ("22 h"); the full one says "22 hours".
- "Profile ›" (12/700 #242424) at 25, 262; the email row (312.7 x 32 at 1,
  292: a mail glyph at 25, the address 12 px brand at 57, Copy at 290.7);
  "Show more" (12 px brand, 92 x 32) at 9, 328.
- Then more sections. On 2026-11-12 they loaded as placeholders and Badges
  said "Something went wrong. Try again".
- Profile › and Show more open the full card on Profile; the org-chart
  button opens it on Organization; the LinkedIn button opens it on a
  LinkedIn tab (only a spinner that day).

## OST status

- **Compact card:** built (`HoverCard.qml`) with Teams' timing, from pictures that open
  profiles (messages, channel posts, the 1:1 header, the people pane), message senders'
  names and a 1:1 chat's title. It shows the hovered name and presence until the person's
  data loads. The LinkedIn button and the sections under Show more aren't in it yet.

- **Built:** the card from people's pictures and names in messages, channel posts and replies, the 1:1
  header and the people pane, with Overview, Profile and Organization.
  - It shows their status message and work location.
  - Chat, calls and the quick message open their 1:1 chat.
- **Not built:**
  - The LinkedIn tab and button (an embedded linkedin.com page).
  - Teams' full org chart layout on the Organization tab.
  - Opening from search results.
