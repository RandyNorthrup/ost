# Find in chat / channel / post

Teams' find pane, as measured on winpc against Teams desktop on 2026-11-10
(OST group test, OST Test Team > General, post OST TEST 80).

## The pane

- **Where it shows**
  - In the main window it's a 360 px pane on the right with a 0.67 px line
    on its left. While it's open, the header's Find button is brand.
  - In a post's own window (Find in post, from ··· or Ctrl+F) the same pane
    covers the window under its title row. It adds a line under the
    header, and its filter pills show their names.
- **Header** (61 px): "Find in chat / channel / post" (14/600, 20.7 px in)
  and Close (32 × 31.3, 312 px in).
- **Keyword box** (12.7, 69; 335.3 × 32)
  - Placeholder "Enter a search keyword...". A search icon sits on the
    right until there's text, then "Clear" (brand).
  - It searches as you type and on Enter. Escape closes the pane.
- **Filter pills** (24 px tall, 12 px text, 8 px apart, 113 px down)
  - Messages ▾ / Files ▾ (brand, 54 px) picks the mode.
  - Filters you turn on go brand with an ×, in the order you turned them
    on. The rest follow, on #E8EBFA.
  - Messages mode: Date ▾, From ▾ (54 px), Attachment, Mentions (36 px).
  - Files mode: Date ▾, From ▾, Type ▾.
  - When the pane is wide the pills show text: Messages (icon, 600),
    Date and From (12 in, chevron 2 px after), Attachment and Mentions
    (icon 6 in, text at 22).
- **Date ▾** opens a 254 × 336.7 popover under the pill, right-aligned with
  it.
  - Today, Yesterday, This week (from Sunday), This month.
  - Below a line: From / To date fields ("Select a date" until picked).
  - Clear, and Apply (enabled once From is set).
  - The pill then reads "This week" etc.
- **From ▾** opens a 254 px popover with "Filter by person" (230 × 33.3,
  #F5F5F5).
  - Each match is a 50 px row: a 32 px picture, the name (14) and address
    (12), with the typed part bold. Your own row reads "(You)".
  - A chat lists its members. A channel searches its team's people
    (userprofilesvc `…/teams/{channel}/users/profilesearch?top=15…`).
- **Type ▾** (Files) lists Excel, Images, Loop, OneNote, PDF, PowerPoint,
  Text file and Word with their file-type icons. Once picked, the pill
  shows the type's icon.
- **Results** are grouped by month ("This month"; 12 px #616161, 8 px above
  and below).
  - A message row:
    - Layout: inset 4.7, padding 12 / 8, radius 3. Hover is #FAFAFA; the
      opened row is #EBEBEB.
    - Header: a 28 px picture with presence, then "You" or the sender's
      name with the time (12 px #616161).
    - Time format: "3:32 AM" today, "Yesterday, 3:32 AM", then "11/7".
    - Text: the whole message (cards' words included) in two lines of
      14/20, ellipsised. Words starting with a search term are marked
      #F9E2AE.
    - A #D1D1D1 line runs 8 px under the row.
  - A channel post row:
    - The textbox icon (16 px, 41 px in) and "You posted".
    - The subject in 14/600 (24 px down).
    - Then "{subject} {text}" (48 px down).
  - A file row (54 px tall):
    - The 32 px file-type icon, the name (14), and "{who}, {time}" (12)
      with the terms bold.
    - ··· holds Open in Browser, Download (not for Loop), Copy link and
      Favorite.
  - Opening a message brings it into view in the conversation, loading
    older pages until it's there, and marks the terms in it. In a pop-out
    window the thread shows the message, and Escape returns to the
    results.
- **Footer:** "Send feedback 👍 👎" (36 px, #FAFAFA; "Send feedback" 12 px
  #616161, then This was helpful and Didn't help at 16 px, 8 px apart, 12 px
  from the right). The thumbs open OST's feedback form (Give a compliment /
  Report a problem) with the search filled in; see
  docs/spec/feedback-and-help.md.
- **Empty states**
  - Before a search: the search-keywords picture (220 px), then "Search in
    this chat" (18/700) and "Find messages, files, and URLs shared in this
    chat." (12 px #616161).
  - With no matches: the search-exclamation picture, "We couldn't find any
    results in this chat" and "Check for spelling, try another search
    keyword, or search in another chat."

## Service

All requests go to `POST https://substrate.office.com/searchservice/api/v2/query`
with a Substrate token and Teams' headers: `x-client-flights` (which, among
other things, scope Files to the chat), `x-anchormailbox` /
`x-routingparameter-sessionkey` set to `OID:{oid}@{tenant}`, and
`x-client-version: T2.1`.

- **Messages**
  - The request is one `Message` entity request, `scenario.Name` powerbar
    and `ContextualTypeahead`, 25 per page.
  - The query string is built in this order:
    `[sent >= {start} AND sent < {end} AND ][hasattachment:yes AND ]
    [mentions:{my oid, no dashes} AND ]clientthreadid:{thread} AND
    {NOT for chats}(…ThreadType_String:(topic OR space)) AND NOT
    (isClientSoftDeleted:TRUE)[ {from address}] {keywords}`.
  - Date bounds are local days written in UTC.
  - The filter term is `conversationType: OneToOne` for chats (group chats
    included) and `groupId: {team}` for channels.
  - From also adds a `People` query annotation (address, user id, tenant).
- **Find in post** uses `clientconversationid:{channel};messageId={post} AND NOT
  (isClientSoftDeleted:TRUE) …` with no filter term.
- **Files**
  - The request is one `File` entity request: `ContextualFilesTypeAhead`,
    sorted by LastModifiedTime, with Teams' SharePoint extended query and
    refiner.
  - A chat searches `OneDriveBusiness` with a `Chat` annotation
    `{id, text: "dummyText"}`.
  - A channel searches `SharePoint` with a `Channel` annotation
    `{threadId, groupId, tenantId, path: "{site}/Shared Documents/{folder}"}`.
  - The query string is
    `[LastModifiedTime >= … AND LastModifiedTime < … AND ][(filetype:x OR …
    OR fileExtension:x …) AND ][{from address} ]{keywords}`.
- **Replies**
  - Results are in `EntitySets[0].ResultSets[0]` (`Total`,
    `MoreResultsAvailable`, `Results`). The words to mark are in
    `EntitySets[0].SearchTerms`.
  - A message's summary is cut short, so each result message is read from
    the chat service (`…/conversations/{thread}/messages/{id}`) for the row
    text.

## Not yet

- A Loop file's ··· has Share in Teams (SharePoint's share dialog).
- A channel's Files results in Teams also listed a "Notes" item from a
  source that wasn't captured.
