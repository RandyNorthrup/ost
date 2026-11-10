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

## OST status

- **Built:** the card from people's pictures in messages, channel posts and replies, the 1:1
  header and the people pane, with Overview, Profile and Organization.
  - It shows their status message and work location.
  - Chat, calls and the quick message open their 1:1 chat.
- **Not built:**
  - The LinkedIn tab and button (an embedded linkedin.com page).
  - Teams' full org chart layout on the Organization tab.
  - Opening from names and search results.
