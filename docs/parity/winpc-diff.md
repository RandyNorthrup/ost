# Side-by-side: Windows Teams (winpc, ost-test1) vs OST — observed differences

## Group chat "OST group test", Chat tab (2026-11-06 18:06)
- Rail: Windows has a **Copilot** app between OneDrive and Apps (+); OST has none.
- Chat list: Windows has a **Copilot** entry above Quick views, and **Followed threads** under Quick views; OST has neither.
- Chat list: Windows does **not** list the meeting chat "OST calendar test: created from …"; OST does. Find the rule: meeting chats only appear after activity, or under the Meetings filter.
- Chat list: Windows shows a **"New"** badge on the Secure Coast team; OST shows none.
- Team avatar: Windows draws OST Test Team as a pale tile with "OT" in coloured text; OST draws a saturated magenta tile.
- Header: Windows has a **rename pencil** after the group name; OST has none.
- Header tabs: Windows shows Chat, Shared, Notes, Recap, then **+ (Add a tab)**. OST shows **Storyline**, which Windows doesn't show for a group chat, and has no +.
- Header actions: Windows has **Meet now ▾** (video icon plus text), a **people icon with the count "2"**, search, pop-out and **···**. OST has a phone icon ▾ (the wrong control for a group chat), a people icon with no count, search and pop-out, and no ···.
- Timeline: Windows shows **system events**: "OST Test 1 added Randy Northrup to the chat." and "OST Test 1 changed the group name to OST group test.", each with an icon. OST shows neither.
- Timeline: call rows show the duration in **bold** ("51s", "1m 52s"), and the icon and text sit closer to the left edge. OST doesn't bold the duration and indents the rows more.
- Composer: Windows has five icons: Format, Emoji, Attach, **Loop**, +, then Send. OST has no Loop icon.

## OST Test Team › General (2026-11-06 18:11)
- Tabs on Windows: Posts, Shared, **Page**, Notes, +. OST lists no Page tab for this channel: Graph's tab list leaves it out, so find where Teams gets it (the middle tier's pinned tabs?).
- Hovering a channel shows a tooltip with "General / Standard" (name and channel type).
- The channel row in the list shows ··· on hover and when selected. The "Teams and channels" header has its own ···.
- The Posts header has Meet now ▾, search, pop-out and ···. With a non-Posts tab selected, the header becomes **Conversation (show posts in a side panel)**, Meet now ▾ and ···, with no search or pop-out.
- Posts: each post is a card with a reaction button (smiley+) under the body and "Reply in thread" with my avatar. Replies are indented with small avatars. A **"Post in channel"** button sits at the bottom, not a composer.
- **Notes tab**: the first open shows "Please wait...the Notes tab will be ready soon." with the OneNote artwork and a spinner while it provisions the channel's section. Then comes the full OneNote editor:
  - Notebook picker ("OST Test Team Notebook ▾").
  - Ribbon: File, Home, Insert, Draw, View, Help; "Tell me what you want to do"; sync status; Editing ▾; Share ▾; Conversation.
  - Home bar: Undo ▾, Paste ▾, B, I, U, ···, Bullets ▾, Numbering ▾, ···, Styles ▾, Tags ▾, Spelling ▾, Dictate, Sticky notes, Find, Copilot, ···.
  - Navigation rail: notebooks and search. Page list with "+ Add page"; the new section's first page is "Untitled Page". A device icon sits at the bottom left.
  - The page shows a title line, then the date and time ("Friday, November 6, 2026  6:12 PM").
  → Native requirement: a OneNote editor over the OneNote Graph API (sections, pages, page HTML content, PATCH edits).
- **Tab ▾ menu (Notes, the last tab)**, in order:
  1. Open tab in new window
  2. Expand tab
  3. Reload tab
  4. Open in browser
  5. Copy link to tab
  6. (separator)
  7. Rename
  8. App permissions
  9. About this tab
  10. Move left
  11. Move right (shown **disabled**, not hidden)
  12. (separator)
  13. Remove

  Each item has an icon.
  OST's menu (committed f82a451) has only Copy link, Rename, Move left/right and Remove, and **hides** an unavailable move instead of disabling it. That has to be fixed.
- **Page tab**: an empty channel Page reads "Untitled", then "Share ideas with Loop. Just start typing or press / to insert templates. Everyone can add content and @mention people.". The header row has the Loop icon, "Loop paragraph" and three icons on the right (Shared locations, Copy component, See who has access). The insert row at the bottom has Table, Bulleted list, Checklist, Task list, Voting table and ···. The channel header on Page has no Conversation button (only Meet now ▾ and ···).
- **Channel header ··· menu**, in order:
  1. See new posts at top
  2. (separator)
  3. Open in new window
  4. (separator)
  5. Channel notifications
  6. Move to section ›
  7. Hide
  8. (separator)
  9. Edit channel
  10. Manage channel
  11. Copy link
  12. Get email address
  13. Workflows

  Each item has an icon.
- **Meet now ▾** (channel): Meet now; Schedule a meeting.
- **+ (Add a tab)** is a menu, not a dialog: New page, Existing page, New list, Existing list, Apps.

## App shell menus (2026-11-06 18:15)
- **Title bar ··· (Settings and more)**, in order:
  1. Unlock Teams Premium
  2. (separator)
  3. Pin window on top (Ctrl+Shift+T)
  4. Settings (Ctrl+,)
  5. Cast
  6. Downloads
  7. (separator)
  8. Zoom row: "Zoom  —  (100)%  +  [fit/reset icon]"
  9. (separator)
  10. Help (F1)
  11. Feedback ›
  12. Keyboard shortcuts (Ctrl+.)
  13. Get the mobile app, with a blue **New** pill
- **Profile menu**:
  - Header: the org name ("Secure Coast Netw…"), then **Sign out** at the top right.
  - Big avatar, then "OST Test 1", ost-test1@…, and "View account ↗".
  - Rows with ›: Available, Pause notifications, Set work location, Set status message.
  - (separator), then **Add another account** in a grey footer with an icon.
- **Chat list header ··· menu**, in order:
  1. Mark all as read (Shift+Esc) ›, a split item with a submenu
  2. Collapse all sections (Alt+Q)
  3. (separator)
  4. Customize view
  5. (separator)
  6. Your teams and channels
  7. Your communities
- **New-chat ▾ menu**, in order:
  1. New message (Ctrl+N)
  2. New message in new window (Ctrl+Shift+N)
  3. New channel
  4. New storyline post
  5. (separator)
  6. Join team
  7. New team
  8. (separator)
  9. Join communities
- **Filter ▾**: toggles a second row of filters (**Meeting chats**, **Communities**); the button's tooltip becomes "Fewer filters". It's a toggle, not a menu. Note: I left it expanded on winpc.
