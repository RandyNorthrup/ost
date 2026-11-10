# Threads-layout channels

Teams' Threads layout (`chatModalityType: "Conversational"`), as measured on
winpc against Teams desktop on 2026-11-10 (test channel "OST threads test",
posts OST TEST 81–86). A Posts-layout channel (`PostReply`) keeps the post
cards.

## The channel

- The first tab is **Conversation**, not Posts. Messages show as chat bubbles,
  and the compose reads "Message in {channel}".
- Under each message with replies: the last replier's 20 px picture,
  "{N} reply/replies" (12 px, brand, opens the thread) and "Last reply {time}"
  (12 px, #616161).
- Hover bar: reactions | **Reply in thread** (ChatMultiple) | Edit (yours) |
  More. A reply that was also sent to the channel has no Edit, and Reply in
  thread opens its own thread.
- A reply also sent to the channel shows in its place in the conversation.
  Above its text, inside the bubble, is the line "Replied in thread:
  {first message}". The line is a 16 px ChatMultiple icon plus 12 px #616161
  text, with the first message as a brand link that opens the thread. It sits
  10 px down, and the text starts 28 px lower than usual.
- While a thread is open in the pane, its first message has a brand outline.
- Header: **Open threads** / **Close threads** (thread-list-pane-toggle-button,
  32 px) sits just before Find in channel. Its ChatMultiple icon turns filled
  and brand while the pane shows. Under 640 px wide, Open channel details
  moves to the top of the ··· menu (Alt+P), right before Open in new window.
- The ··· menu for a Threads channel has no posts order, Manage channel,
  Recommend or Archive. Owners get only Delete channel, after a divider.

## The threads pane (360 px, right)

The pane has a 0.67 px line on its left and a 61 px header.

**List** (Open threads)
- Header: "Threads" (14/600, 25 px in) and Close (57.7 px from the right).
- One row per thread with replies, newest reply first. Each row is 82.5 px
  tall and inset 2 px:
  - author 32 px (24 in, 10 down)
  - first message (14, #424242, 70 in, 8 down)
  - newest reply's time (12, 14 from the right)
  - "{You|name}: {newest reply}" (14, #616161, 26 down)
  - repliers 20 px in 24 px slots (50.5 down), then "{N} replies" (12)
  - followed mark: ChatMultipleCheckmark filled, 14 px, brand, at the end

**Thread**
- Header: "Threads" (Go to thread list, 20 in) › first message (14/600, 100 in,
  ellipsised), then Follow / Unfollow thread (ChatMultiple / ChatMultipleMinus),
  More and Close.
  - The buttons are 32 px wide, laid out from 16.7 px from the right.
  - More holds Mark as unread, Copy link, Jump to original message and Open
    thread in new window.
- The thread shows as a chat: the first message, a "{N} replies" divider, then
  the replies.
  - The divider is a 28 px item with its 12 px label 12 down. It uses Fluent
    Divider lines (NeutralStroke2) 20 px from the label and spans the pane 14 px
    in from each side.
- A reply that was also sent to the channel carries "Also sent to channel"
  (ChannelArrowLeft 16 px, 12 px #616161) in the same place.
- Compose: the "Send to: thread only ⌄" row is on top.
  - It is 12 px brand with "Send to:" bold, 12 px in and 5 px down, and puts the
    compose in its multi-line form.
  - Its menu opens above it with the radio items Thread only and Thread and
    channel.
  - It goes back to "thread only" after each reply. The placeholder is "Reply
    in thread".

## Service

- A new message:
  - `POST {chatsvc}/v1/users/ME/conversations/{channel}/messages` with
    `subject: ""`, `title: ""`, `policyViolation: null` and
    `crossPostChannels: []`.
  - It has **no** `postType`; Posts channels send `Standard` or `Announcement`.
- A reply: `POST …/conversations/{channel};messageid={root}/messages`.
  - Thread and channel adds `properties.isSharedInMain: true`, the post fields
    above and top-level `replyChainId: "{root}"`.
  - On read, `properties.isSharedInMain` marks the reply.
- Pushes for thread replies name `{channel};messageid={root}`. The open channel
  reloads for them, so counts and shared replies update live.
- Read state:
  - Opening a thread: `PUT …/conversations/{channel}/rcmetadata/{root}` with
    `{"ch": newestReplyId}`.
  - Mark as unread: the same PUT with `{"chb": newestReplyId - 1}`.
- Follow / Unfollow thread: rcmetadata `f`, as for Posts threads.

## Not yet

- Teams bolds an unread thread's "{N} replies" and draws a "Last read" line in
  the pane, from rcmetadata `ch`/`chb`.
- Banner: "A channel owner set this channel to a threads layout. Learn how
  threads work". It shows only in channels converted from Posts.
- At narrow widths, Teams folds the tabs into a "Conversation ⌄" menu under
  the channel name.
