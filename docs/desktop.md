# OST desktop

`ost-desktop` is a native Qt 6 / QML client on the OST engine. It is laid
out and behaves like the Microsoft Teams desktop app for Windows: the
same app bar, chat list, conversation, call window and dialogs, measured
from Teams at 1x. It uses Fluent UI System Icons and the Selawik font
(both MIT, see `desktop/assets/NOTICE.md`) and the OST logo; it carries no
Microsoft branding.

## What it does

- **Chat**: 1:1 and group chats, your own notes chat, Favorites, Drafts and
  Mentions quick views, the Unread / Channels / Chats filters and a name
  filter. Messages with formatting (bold, italic, underline,
  strikethrough, lists), emoji, reactions, edits and deletes, inline
  images, file attachments (send from OneDrive and download), typing
  indicators, read receipts and the "Last read" line. New chat with a
  people picker, including group chats with a name.
- **Channels**: posts as cards with their replies, "Reply in thread",
  "Post in channel", reactions, and the team's picture in the header.
- **Activity**: the Teams activity feed (mentions, reactions, replies,
  missed calls, team changes), live as it changes, with unread state
  synced to Teams.
- **Calls**: 1:1 audio and video calls in and out (your camera on and off
  mid-call, the other person's video on the stage, your mirrored self
  view), with Teams' incoming-call toast,
  ringing, mute, hang-up, decline, and Chat and People panes in the call
  window; group calls from a group chat (its members are rung). Call
  history in the Calls app.
- **Meetings**: join Teams meetings from the calendar, with audio both
  ways, Teams' meeting toolbar, the stage ("Waiting for others to join…"
  or a tile per person), the roster in People, and the meeting chat.
- **Calendar**: day, work week and week views of your Outlook calendar,
  a month picker, event details with Join, and New meeting (optionally
  a Teams meeting).
- **OneDrive**: Home (recent files), My files with folders, Shared with
  you, and Libraries (each team's SharePoint document library); open in
  the browser, download, upload, new folder and delete.
- **OneDrive extras**: Favorites (add or remove files), Recycle bin
  (Restore, Delete permanently), Browse files by People, Meetings
  (recordings) and Media (photos and videos); Create or upload works
  from every view (into My files when you're not in a folder).
- **Raise hand** in meetings: Raise / Lower publishes Teams'
  "raiseHands" state; raised hands show as Teams does (a gold outline
  and "1 ✋" badge on the tile, a hand in People, a red count on the
  People button).
- **Transfer and Consult**: Transfer hands the call to someone you pick
  (Teams' blind transfer; if nobody answers it goes to their voicemail,
  as in Teams). Consult puts the caller on hold and opens a chat with
  the person; the consult banner then offers Transfer or Resume.
- **Call controls**: Hold and Resume through Teams' hold service (the
  other person hears Teams' hold music; you see "On hold" when they hold
  you), Dial pad (RFC 4733 tones), View (Gallery / Speaker in meetings,
  Full screen, turn incoming video off) and More (Device settings, Full
  screen). OST answers Teams' mid-call re-offers, including the move to
  a media processor that Hold and group escalation make.
- **Watching a share**: when the other person shares a screen, window
  or tab, it takes the stage whole (letterboxed) with "<name> is
  presenting", their camera moves to a corner tile, and it's taken down
  when they stop. Works in audio-only calls too, as in Teams.
- **Share** your own screen or a window in a call: the desktop's
  ScreenCast portal shows its picker (xdg-desktop-portal: Hyprland,
  GNOME, KDE and others), OST sends it as Teams' screen-sharing stream
  (H.264, up to 1280x720), shows "You're presenting", and Share becomes
  Stop sharing. Closing the shared window stops it too.
- **View more apps** lists Teams' apps for the account, in Teams'
  order: Shifts, Planner, OneNote, Help, Clipchamp, Whiteboard, Events,
  People. Planner, OneNote and People are native; Whiteboard, Shifts and
  Clipchamp are the apps' own pages in OST's TeamsJS host, signed in as
  Teams hosts them (docs/spec/app-host.md "Personal apps"); Help is
  embedded. Events (a module Teams draws itself) still opens Teams on the
  web. An app opened there takes the rail's one extra slot, as in Teams.
- **Copilot, Share to Outlook, Immersive Reader, Office files**: the chat
  list's Copilot row opens Copilot as Teams hosts it; a message's ··· ▸
  Share to Outlook opens Teams' Outlook dialog on a draft of the
  conversation, and ··· ▸ More actions ▸ Immersive Reader Teams' reader;
  Word, Excel and PowerPoint files open in Office for the web inside OST
  with Settings ▸ Files and links ▸ Teams (the default).
- **Store**: your organization's Teams app catalog, as Teams' Store
  Home shows it: the "Do more in Teams" banner with Search agents and
  apps, Added by your org, Apps from Microsoft and All apps as cards,
  and an app's details. Add installs the app in Teams on the web
  (installing needs a permission OST's sign-in doesn't have); Planner,
  OneNote and People open in OST.
- **Channel tabs** come from the channel itself (Graph): Posts, Shared,
  then the channel's Page, Notes and any apps, in Teams' order. Page
  is drawn as Teams draws it: its header row (the page's icon and name,
  Shared locations, Copy component, See who has access), the live Loop
  page edge to edge (Loop's own app frame hidden), and Teams' insert row
  (Table, Bulleted list, Checklist, Task list, Voting table, and more),
  which types Loop's own "/" commands. It uses OST's web profile; sign
  in there once.
- **Channel tabs and their menus** behave as Teams desktop's, per
  [docs/spec/channel-tabs.md](spec/channel-tabs.md):
  - The tabs come from Teams' middle tier (its pinned tabs), so a channel's Page shows.
  - The selected tab shows a chevron when it has a menu, and a right-click opens a tab's menu.
  - The items, their order and their disabled states are worked out per tab type and
    per the user's rights, as Teams does it. Move left and Move right are disabled at the ends, not hidden.
  - Moves use Teams' order algorithm.
  - Rename and Remove use Teams' dialogs and save through the middle tier.
  - Copy link to tab puts Teams' deep link on the clipboard as rich text, so it reads as the tab's name.
- **Channel Shared tab**: the channel's folder in the team's SharePoint
  library, as Teams shows it: breadcrumb, Share, Copy link, Add shortcut
  to OneDrive, Create or upload (folder, files), Name / Modified /
  Modified By, opening folders and files, deleting.
- **People**: your Outlook contacts as Teams' People app shows them (All
  contacts, Favorites, Categories), Add new contact, add or remove a
  favorite, send or copy an email, delete.
- **OneNote**: your notebooks (Create notebook), a notebook's sections
  and pages beside the page (Add section, Add page), reading and deleting
  pages, and Open in OneNote.
- **Planner** (from View more apps): My tasks (private To Do tasks and
  the Planner tasks assigned to you, with All / Private tasks / Assigned
  to me), My day, My plans (your teams' plans), Grid and Board, adding
  and completing tasks, creating a plan in a team. View more apps also
  opens Whiteboard, Clipchamp and Help, which are web apps, in the
  browser.
- **Presence**: your status (set, reset, shown everywhere) and everyone
  else's on their pictures.
- **Notifications**: Teams' own banners (NotificationBanners.qml), in
  the screen corner and size Settings ▸ Notifications ▸ Display picks:
  chat messages (with Teams' quick reply and quick reaction), @mentions
  ("<name> @mentioned you" over where it was said), meetings that started
  (Join, Message), the test banner and the incoming call. Up to three at
  once, queued and timed as Teams does; hovering holds one. On X11 OST
  places the window itself; on Wayland it is a layer-shell surface through
  KDE's LayerShellQt (KDE, Hyprland, sway and other wlroots desktops).
  On GNOME's Wayland, which has no layer shell, (or with
  OST_SYSTEM_NOTIFICATIONS=1) the desktop's own notifications are used
  instead. Channel posts notify only when they mention you.
- **Updates**: OST is released on GitHub (RandyNorthrup/ost releases).
  It checks for a newer release soon after starting and then daily, and
  Settings ▸ About OST shows Teams' line ("You've got the latest
  version. It was last checked on …" or "An update is available." with
  Update now, which opens the release).
- **Settings**: theme (follow the system, light, dark), read receipts,
  Enter to send or to start a new line, notifications, audio devices,
  start with the computer.
- **Search**: people, chats and channels from the title bar.
- **Help and feedback**: Help (F1) is Teams' Help window with OST's own
  articles (docs/help, built in, searchable). Settings and more ▸ Feedback
  ▸ Report a problem / Give a compliment open Teams' feedback form and send
  it as an issue on OST's GitHub. You submit it there yourself; nothing is
  posted for you. Suggest a feature opens the repo's Ideas discussions (see
  docs/spec/feedback-and-help.md).

Not yet: video in meetings and in calls you place, screen sharing, raising hands and reactions in
meetings, transfer, hold and the dial pad. Their buttons are shown disabled rather than hidden or faked.

## Build

Requirements: Rust (stable), Qt 6.9 or newer (developed on 6.11) with
Qt Quick, Qt Quick Controls, Qt Multimedia (video clips in messages) and
Qt WebEngine (embedded apps), FFmpeg's libraries (editing recorded clips,
playing video backgrounds), a C++ compiler and CMake (for CXX-Qt),
the ALSA development files (calls), NASM (openh264, video), and the
PipeWire development files plus clang (screen sharing; at run time an
xdg-desktop-portal backend for your desktop).

```bash
# Arch
sudo pacman -S qt6-base qt6-declarative qt6-svg qt6-multimedia qt6-webengine ffmpeg alsa-lib cmake nasm \
  pipewire clang xdg-desktop-portal
# Debian / Ubuntu
sudo apt install qt6-base-dev qt6-declarative-dev qml6-module-qtquick-controls \
  qml6-module-qtquick-window libqt6svg6 qml6-module-qtmultimedia qt6-webengine-dev qml6-module-qtwebengine \
  libavfilter-dev libavformat-dev libavcodec-dev libavutil-dev libswscale-dev \
  libasound2-dev cmake nasm libpipewire-0.3-dev clang xdg-desktop-portal

cargo build --release -p ost-desktop
```

On machines with little memory, keep the build parallelism low
(`cargo build -j 2 …`); the C++ parts are heavy.

## Install and run

```bash
desktop/packaging/install-user.sh          # binary, menu entry and icon in ~/.local
ost-desktop
```

The first start shows the sign-in page (Microsoft's device-code sign-in,
the same as `teams-cli login`). Tokens are kept in the system keyring.

Files OST keeps:

| Path | What |
| --- | --- |
| `$XDG_CONFIG_HOME/ost/desktop.json` | Settings |
| `$XDG_STATE_HOME/ost/drafts.json` | Unsent drafts, with their formatting |
| `$XDG_CACHE_HOME/ost/photos/` | Profile and team pictures (refreshed daily) |
| `$XDG_DOWNLOAD_DIR` (else `~/Downloads`) | Downloaded attachments |
| `$XDG_CONFIG_HOME/autostart/ost-desktop.desktop` | Only with "Start with the computer" on |

## Environment variables

| Variable | Effect |
| --- | --- |
| `OST_SYSTEM_FRAME=1` | Use the desktop's own window frame instead of Teams' title bar buttons. |
| `OST_NO_KEYRING=1` | Don't use the system keyring for tokens (headless machines, CI). |
| `OST_DUMP_RTP=<file>` | Append every decrypted RTP packet of payload type `OST_DUMP_RTP_PT` (default 113, x-much2) to the file, length-prefixed (protocol research). `OST_OFFER_MUCH=1` offers x-much2 in meetings even with spatial audio off. |
| `OST_TROUTER_DUMP_DIR=<dir>` | Write every push frame (and call SDP) there, owner-only. Frames contain message text and call links: for protocol work only. |
| `RUST_LOG=info` | Engine and backend logging (to stderr). Logging is kept to shapes and states, not message text or tokens. |
| `QT_SCALE_FACTOR=1.5` | Qt's own scaling; used to line OST up with Teams captured at 150 %. |

## Keyboard shortcuts

`Ctrl+.` lists them in the app. OST supports these Teams shortcuts:

| Area | Shortcuts |
| --- | --- |
| General | `Ctrl+.` shortcuts, `Ctrl+E` / `Ctrl+G` search, `Ctrl+N` new chat, `Ctrl+Shift+F` filter, `Ctrl+,` settings, `Ctrl+Shift+T` pin window on top |
| Navigation | `Ctrl+R` compose box, `Alt+Left` / `Alt+Right` back and forward, `Ctrl+1`–`Ctrl+5` apps |
| Compose | `Shift+Enter` new line, `Alt+Shift+O` attach file, `Ctrl+B` / `Ctrl+I` / `Ctrl+U` / `Ctrl+Alt+X` bold, italic, underline, strikethrough, plus the usual undo, redo, cut, copy, paste and select all |
| Messaging | `Ctrl+F` find in chat, `Ctrl+J` newest message, `Shift+Esc` mark all read (asks first, with "Don't ask again"), `Alt+Q` collapse all sections, `Ctrl+Alt+U` / `C` / `A` unread, chats, channels, `Ctrl+Alt+Z` clear filters, `Alt+P` details pane, `Alt+1`–`Alt+5` header tabs |
| Calls and calendar | `Ctrl+Shift+M` mute, `Ctrl+Shift+O` camera, `Ctrl+Shift+H` leave, `Alt+Shift+A` start an audio call, `Ctrl+Shift+S` / `Ctrl+Shift+A` accept with audio / video, `Ctrl+Shift+D` decline, `Alt+N` schedule a meeting |

## Test harness

The app doubles as its own end-to-end test driver. With a first argument
that is a PNG path, it captures itself there (and to `<path>-<step>.png`
for multi-step tests) and quits; the flags pick what it does first. Run
it offscreen against a test account:

```bash
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=rhi QT_SCALE_FACTOR=1.5 \
  target/debug/ost-desktop /tmp/shot.png "" "" --size=1280x680 --view=calendar
```

`QT_QUICK_BACKEND=rhi` makes offscreen runs draw on the GPU as the app
does. Otherwise Qt falls back to its software renderer, which draws no
shader effects (the menus' and dialogs' Fluent shadows).

The second argument, when not empty, is a message to send in the opened
chat. Tests that talk to Teams act on the signed-in account for real
(they send messages, start chats, schedule a meeting), so use a test
account.

| Flag | What it does |
| --- | --- |
| `--size=WxH` | Start at that size. |
| `--theme=light\|dark\|system` | Force a theme. |
| `--view=<app>` | Open that app (activity, chat, calendar, calls, onedrive, settings). |
| `--open-chat=<id>` | Open that chat or channel before capturing. |
| `--assume-focused` | Treat the offscreen window as focused (read receipts). |
| `--nav-test` | Visit apps, then back and forward. |
| `--draft-test` | Type a draft, switch chats, check it survives. |
| `--draft-format-test` | In OST group test (or `--open-chat=<id>`), type a draft with every format and a table, switch chats and back, capture it and check its HTML came back as typed; nothing is sent. A second run with `--draft-format-restart` checks it after the restart, then clears the draft. |
| `--presend-test[=<chat name>]` | With `--shots=<dir>`: in that chat (default OST Test 2), with the compose box in dry run so nothing can be sent, try Teams' pre-send checks: an empty box, spaces, 91 KB of text, a scheduled time in the past, a clip still uploading, a bot mention in a reply also sent to the channel, and a fine message. Logs `PRESEND <case> "<banner>" kept <n>` (and `PRESEND would send` for the fine one); pictures `presend-<case>.png`; then quits. |
| `--attach-test` | With `--shots=<dir>`: Teams' Attach in OST group test: the popover (and a search with no results), the cloud file picker's Home, Navigation Pane, People, Meetings, Media and My files, then ost-share-test.txt picked into the compose box. `--attach-send` sends it ("OST TEST 119"); `--attach-channel` does it in OST Test Team > OST layout test through Browse Teams and Channels ("OST TEST 121"). Logs ATTACH lines. |
| `--attach-link-test` | With `--shots=<dir>`: in OST group test, the Attach popover's first suggested file into the compose box, then its card's Link settings set to "People currently in this chat" and applied (the link is made). `--attach-link-send` then sends it as "OST TEST 173 link settings from OST". Logs ATTACHLINK lines (menu, card, linked); pictures `attach-link-*.png`. |
| `--thread-attach-test` | With `--shots=<dir>`: OST Test Team > General's newest post in its post view; Attach in its reply box opens Teams' Attach popover (with Browse Teams and Channels) and the cloud file picker. Nothing is sent. Logs THREADATTACH lines; pictures `thread-attach-*.png`. |
| `--picker-bar-test` | With `--shots=<dir>`: the cloud file picker's My files with its command bar, Compact List, Tiles, People and Create a folder (opened, Dark blue picked, closed: nothing is made). Logs PICKERBAR lines; pictures `picker-bar-*.png`. |
| `--copilot-test` | With `--shots=<dir>`, ost-test1 (a Copilot licence): Write with Copilot in OST group test (`--copilot-channel`: OST Test Team > OST test channel 2). The popover with an empty box, a harmless test draft, Rewrite (loading and answer), Proofread, Adjust ▸ Concise and the menu, Custom ("add a cheerful good morning"), Previous and Replace; the box is cleared at the end and nothing is sent. Logs COPILOT lines (the state, each answer); pictures `copilot-*.png`. |
| `--draft-roam-test=<out\|in\|conflict>[,<chat name>]` | Run with `OST_ROAM_DRAFTS=1` (Teams roams drafts only where `enableRoamMessageDraft` is on; it is off on this tenant) and `--shots=<dir>`; default chat OST Test 2. `out`: type a draft with a mention, let it roam (log line `DRAFT roam saved <id>`), check the Drafts view and the box after switching back, then clear it (`DRAFT roam deleted <id>`). `in`: wait for another device's draft (put there first, e.g. with `cargo run --example drafts_raw -- POST <body.json>`), capture the box and the Drafts view; `--draft-roam-clear` then clears it. `conflict`: type OST's own draft, reopen the chat until the other device's draft shows Teams' conflict banner, capture it and "Saved draft", then Discard it (or `--draft-roam-use`: "Use this version") and clear. Logs `DRAFTROAM <mode> <step> <json>`; pictures `draft-roam-<mode>-*.png`. Nothing is sent. |
| `--filter-test` | Try each chat list filter. |
| `--search-test` | Search "Ran" and capture the suggestions. |
| `--header-test` | Shared tab, a placeholder tab, find and participants. |
| `--emoji-test` | Open the emoji picker. |
| `--format-test` | Send a message with bold text. |
| `--edit-test` | Send two messages, edit one, delete the other. |
| `--react-test` | Add and remove a reaction. |
| `--typing-test` | Send typing for 12 s and watch for the other side's. |
| `--send-file=<path>` | Attach a file and send it. |
| `--new-chat`, `--new-chat-test` | Open New chat; search a person and open the chat. |
| `--new-chat-form-test` | With `--shots=<dir>`: Teams' new chat form before picking (suggestions, the note, the compose box), after picking the first suggestion you have a chat with (its messages under the To row), with the group name open, and with two people; NEWCHAT lines, `newchat-*.png`. Never sends; the form is closed at the end. |
| `--new-chat-compose-test` | With `--shots=<dir> --new-chat-to=<name>[,<name>…]` (and optionally `--new-chat-name=<group name>`, `--new-chat-text=<text>`, `--new-chat-file=<path>`, `--new-chat-urgent`): the new chat form's compose box as a chat's. The people are picked from Teams' suggestions (or searched), bold and italic text goes in, a file from this device is attached, "+" (Teams' short list) is captured and the delivery option set to Important (or Urgent). Only with `--new-chat-send` is it sent: the chat is made and the message goes from its compose box. NEWCHATSEND lines; `newchat-compose-{plus,ready,sent}.png`. |
| `--list-keys-test` | With `--shots=<dir>`: Up / Down in Activity, @mentions and Followed threads, first as Teams opens each row as you arrive, then with "Use Enter or Spacebar to show content" on (synced; put back after), where Down only moves and Enter opens. LISTKEYS lines; `listkeys-<list>-{auto,enter}.png`. |
| `--reorder-test=<section name\|teams>` | With `--shots=<dir>`: reordering in that section (Favorites or one of yours) or in Teams and channels. Turns "Turn on single pointer controls" on (put back at the end) and captures Settings ▸ Accessibility, the second row's menu with Start reordering, the Move Up / Move Down mode; Move Up then Move Down (back as it was); then a drag of the first row below the second (captured mid-drag with the overlay and drop line) and a drag back. REORDER lines with the order shown and kept; `reorder-*.png`. The order ends as it started. `--reorder-only-up` stops after Move Up and leaves it moved (to look at Teams; the same run again moves it back when there are two). |
| `--team-live=<action>` | With `--shots=<dir>`, live, only on teams named "OST TEST…": `create:<name>` (Create team from scratch, public; logs the body and where it lands), `join:<name>` (Join a team: search, Join), `add:<team>:<person>` (Add member; only OST Test 2 or "OST Guest…"), `delete:<team>` (Delete with the checkbox ticked). TEAMLIVE lines; `teamlive-*.png`. |
| `--custom-emoji-test=<png>` | With a positional `<out.png>`: adds a custom emoji for the org from the picture (`--custom-emoji-name=<name>`, default "ost-test"), captures the dialog, the result and the picker; without `--custom-emoji-nosend` it then sends it in OST group test and reacts with it. `--custom-emoji-delete` (same name flag) deletes it. CUSTOM lines. |
| `--leave-test=<chat name>` | With `--shots=<dir>`, only for a chat named "OST TEST…": its list menu, Teams' "Leave this chat?" (with the Remove chat history checkbox), then Leave; logs whether the list still has it. `--leave-remove-others` first removes everyone else from it (so nobody stays in the test chat). LEAVE lines; `leave-*.png`. |
| `--chatlist-menu-test` | With `--shots=<dir>`: the chat list's ··· menu and its Mark all as read options (CHATLIST menu rows), Shift+Esc's confirmation opened and closed (nothing marked), and the list width: the default for the window, a drag to 400 and under 280, a 20 px step, the kept vw and a reset; `chatlist-*.png`. The width setting is put back. |
| `--tab-dropdown-test` | With `--open-chat=<id> --size=<narrow> --shots=<dir>`: under 640 the tabs fold into Teams' dropdown under the title; TABDROPDOWN lines (header width, the menu's rows), `tabdropdown-*.png`. |
| `--group-test` | Start a named group chat with a first message. |
| `--channel-test` | Post in OST Test Team > General. |
| `--reply-test` | With `--open-chat=<channel>`, reply in the newest post's thread. |
| `--mentions-test` | Open Quick views > Mentions and a mention. |
| `--activity-test`, `--activity-watch` | Open an activity item; log live feed changes. |
| `--status-test` | Set Busy from the profile menu, then reset. |
| `--settings-test` | Switch the theme and read receipts and back. |
| `--calendar-test` | Schedule a Teams meeting tomorrow at 3 PM. |
| `--cal-test` | With `--shots=<dir>`: the calendar (docs/spec/calendar.md). `--cal-date=YYYY-MM-DD` picks the week, `--cal-view=day\|workweek\|week\|month` the first view. Alone it captures each view, the card and event page of `--cal-peek=<subject>`, the RSVP-with-note dialog, the form, Meet now and Join with an ID (`cal-*.png`). `--cal-respond=<subject>\|<Accept\|Tentative\|Decline\|Follow>\|<1 for the series>\|<note>` answers an invitation from its card; `--cal-rsvp-note=<subject>\|<Accept\|Tentative\|Decline\|Follow>\|<note>` answers it from its event page's RSVP with note (`cal-rsvp-note-open.png`). With browser sign-in both go through Outlook (RespondToCalendarEvent), with device code through Teams' calendar service; the log says which. `--cal-schedule=<title>` fills Teams' form (`--cal-attendee=<mail>`, `--cal-channel=<team>/<channel>`, `--cal-start=<ISO>`, `--cal-minutes=30`, `--cal-repeat=<menu index>` with `--cal-until=<date>`, `--cal-location`, `--cal-body`) and sends it (`--cal-save-only` stops before). `--cal-cancel=<subject>` (`--cal-cancel-note=`) cancels your meeting from its event page. `--cal-edit=<subject>\|<new title>` sends an update from the event page; `--cal-channel-header=<team>/<channel>` opens that channel's header Schedule a meeting and captures the form, unsent. `--cal-joinid=<meeting ID>\|<passcode>` joins with an ID up to the pre-join (captured as `cal-joinid-prejoin.png`, then cancelled; never joined). `--cal-live` with `--cal-wait=<seconds>` stays for a scheduled meeting to start and captures the join bar (`cal-live-*.png`) and, with several meetings live, the Live meetings dialog (`cal-live-dialog.png`); its start notification shows as a banner. `--cal-extras` (TASK-0220) captures the Filter menu and its Meetings, Categories and Show as submenus, Appointments unchecked and checked again, the view menu with Time scale, Day and Saved views, 15-minute time scale, 3 days, the Save current view dialog and its charms, Copilot's suggestions and pane, and New ▸ Event's form; each setting is put back, since they roam to Teams (`CALTEST state` lines). `--cal-propose=<subject>\|<Tentative\|Decline>\|<start ISO>\|<minutes>\|<note>` proposes a new time on an invitation (`cal-propose-dialog.png`, `cal-proposed.png`); `--cal-proposals=<subject>` captures your meeting's card and page with the proposals. `--cal-event-form` opens New ▸ Event's form and keeps it open for `--cal-wait` seconds (drive it with QTWEBENGINE_REMOTE_DEBUGGING); `--cal-popout` also opens it in a window of its own (Open in new window) and captures that (`cal-popout.png`). `--cal-live-one` with `--cal-live` opens the Live meetings dialog for a single live meeting too and logs the rosters. `--cal-more=menus` captures the toolbar's "…" (and Filter ▸ Meetings in it) and the right-click menu of `--cal-peek` with its Charm picker and Show as; `--cal-more=instr` opens Instructions ▸ on `--cal-peek`'s menu, then Create instruction (Copilot's pane with the draft) and Manage instructions (Outlook's settings); `--cal-more=split` ticks every other calendar (or those named by `--cal-split-only=<text>`), turns on Split view and puts both back; `--cal-more=copilot` hands `--cal-prompt=<suggestion>` to Copilot's pane and captures "…" with the pane open; `--cal-more=outlook --cal-outlook=<event subject>\|<command>` (or `surface\|Share`, `surface\|Print`, `surface\|Calendar settings`) opens Outlook's own page and command, kept `--cal-wait` seconds; more steps follow (`surface\|Print\|Print` prints Outlook's print preview; with `--cal-print-quiet` the PDF in Downloads isn't opened; `CALTEST printed`). "~" in a value stands for a space. Logs `CALTEST` lines. |
| `--join-test` | Join that meeting through the pre-join window, capture it, the stage and People, leave (`--join-stay=<s>` stays longer, `--join-muted` joins with the mic off, `--join-raise` raises and lowers your hand). |
| `--join-new-controls` | With `--join-test --join-stay=80` (and `--join-url=<link>`): turn on Teams' New meeting controls for the test (put back after) and capture the bar at 1280, More with View ▸ / Join info ▸ / Settings ▸, React (raising and lowering your hand), Chat's right-click menu, People unpinned (bar and More), Reset, then 700 (overflow, More) and 460 (the compact bar); `JOIN nmc` lines log each layout (`-nmc-*.png`). |
| `--join-nmc-drag` | With `--join-test --join-stay=150` (and `--join-url=<link>`): New meeting controls on for the test (put back after) at 856 wide, then drag and drop between the bar and More (TASK-0208): Chat right past People (reorder), Chat onto More (unpin), Chat from More's grid back onto the bar (pin), People over Mic (not allowed), Copilot then Escape (cancelled), each captured mid-drag and after the drop; Reset; then for about 75 s it waits for a real drag from outside (`JOIN drag screen` gives Chat's, People's, More's and Copilot's screen points). `JOIN drag` lines (`-drag-start.png`, `-drag-reorder.png`, `-drag-reordered.png`, `-drag-unpin.png`, `-drag-unpinned-more.png`, `-drag-pin.png`, `-drag-pinned.png`, `-drag-blocked.png`, `-drag-escaped.png`). |
| `--join-event` | With `--join-test --join-url=<a town hall or webinar> --join-stay=90` or more: the event as joined (`JOIN event` lines: call_event_json, your role, the bar and its end slot, attendees; `-event-green.png`), People (`-event-people.png`), `--join-event-qna` opens Q&A (`-event-qna.png`), `--join-event-start` asks Start meeting and confirms it (`-event-start-dialog.png`, `-event-starting.png`, then `-event-live.png`), `--join-event-end` ends it for attendees near the end (`-event-end-dialog.png`, `-event-ended.png`). Only on test events that notify nobody but test accounts. |
| `--join-copilot` | With `--join-test --join-stay=60` or more (and `--join-url=<link>`), signed in with a Copilot licence: the bar's Copilot, Teams' "Start transcription to use Copilot" alert (when the transcript is off), Start (the spoken-language confirmation, then the transcript), and the Copilot pane hosting the Microsoft 365 Copilot app told the meeting; `--join-copilot-stop` stops the transcript again before leaving. `JOIN copilot` lines (`-copilot-bar/-ask/-language/-pane/-pane-later.png`). |
| `--call-window=<w>x<h>` | The call window's size (e.g. 1280x680, Teams' reference window). |
| `--join-subject=<title start>` | With `--join-test`: join the calendar's meeting whose title starts so ("~" for spaces) instead of "OST calendar test". |
| `--join-copilot-turn-on` | With `--join-copilot`, in a meeting whose Allow Copilot is "Only during the meeting" (copilotMode Enabled): Copilot asks the spoken language straight away (as Teams desktop does) and starts Copilot alone (no transcript is kept); the pane opens and Teams' "Copilot is available in this meeting" notice shows (`JOIN copilot notice shown`, in `-copilot-pane.png`); `--join-copilot-stop` stops Copilot again before leaving. |
| `--cqf-setting-test` | Settings ▸ Privacy's call quality survey opt-in in the Surveys card: as found (off by default), turned on and captured, then put back. `CQFSET` lines; pictures `-cqfset-off.png`, `-cqfset-on.png`. |
| `--cqf-test[=good]` | With a call that ends (e.g. `--join-test --join-stay=20`) and `--cqf-always` (or `OST_CQF_ALWAYS=1`: opted in and asked after every call instead of Teams' 10% sample): the call quality survey once the call ends — the rating page, then Had issues, the second category with two reasons ticked and Send feedback (Report a problem opens filled in with the reasons and the call's technical details; it is closed unsent) and the thank-you; `=good` answers Good. `CQF` lines; pictures `-cqf-rate/-issues/-ticked/-feedback/-thanks.png`. |
| `--join-present` | With `--join-test --join-stay=60` or more: present as Teams (TASK-0210). `--join-present-mode=<Weatherperson\|SideBySide\|NewsAnchor>` turns the camera on and picks that presenter mode in the tray (`--join-present-bg=<aplBackground_0nn>` opens Add a background and picks it); Window opens the desktop's picker (pick a harmless window within a minute; `--join-present-screen` shares a screen instead, which can be controlled). While sharing: the Sharing control bar expanded and, 4 s later, minimized; `--join-present-accept` accepts a control request (the desktop's remote control portal then asks once), `--join-present-give` gives control to the first viewer who can take it; `--join-present-switch=<mode>` switches the layout at the end; then Stop sharing. `JOIN present` lines (`-present-tray.png`, `-present-tray-backgrounds.png`, `-present-bar.png`, `-present-bar-min.png`, `-present-request.png`, `-present-bar-given.png`). |
| `--join-content=<whiteboard\|ppt\|excel>` | With `--join-test --join-stay=120` or more (TASK-0214; docs/spec/content-sharing.md): present a Microsoft Whiteboard, PowerPoint Live or Excel Live share (`--join-content-file=<name in your OneDrive's root>`, "~" for spaces, for ppt and excel; Excel Live gives the meeting's people edit access), capture the stage after 50 and 70 s (`-content-stage.png`, `-content-stage-later.png`), move to the next slide (ppt, `-content-stage-moved.png`), stop near the end and leave. `--join-content=` (empty) with `--join-content-watch` only watches what others present (`-content-watch-<step>.png` every 40 s). `--join-content-cameo` (ppt, a deck with a cameo, with `OST_CAMERA_DEVICE`): the camera on, then Layout ▸ Cameo instead of the next slide (`-content-cameo.png`). `CONTENT` lines log call_content_json with addresses cut at their query; a Join with an ID that opens its pre-join screen late is joined again (`JOIN retry`). |
| `--join-present-annotate` | With `--join-present --join-present-screen`: Annotate (the Sharing control bar's) 20 s after sharing starts, its overlay window over the shared screen (kept out of the share), stopped a little before the share; `JOIN present annotate` lines. |
| `--join-take-control` | With `--join-test --join-stay=60` or more, while someone else presents: once their screen can be controlled (their AvailableAck), Take control ▸ "Request control?" ▸ Request; once given control, a click in the middle of their picture and "OST TEST" typed there, then Stop control. The stage is captured every 10 s while they present (their presenter mode composited). `JOIN control` lines (`-control-capable.png`, `-control-request-dialog.png`, `-control-waiting.png`, `-control-controlling.png`, `-control-typed.png`, `-control-released.png`, `-control-stage-<step>.png`). |
| `--join-lobby-wait` | With `--join-test --join-url=<link>` as an account the meeting holds in its lobby: capture the waiting screen (`-inlobby.png`), wait to be admitted or denied, capture the meeting (`-admitted.png`), stay `--join-stay=<s>`, leave. `JOIN lobby-wait` lines. |
| `--join-lobby-data` | With `--join-lobby-wait` (and `--join-stay=240`): once admitted, use the data channel that came back after the media moved (TASK-0213): live captions on (someone speaks), then take control of whoever presents as `--join-take-control` does (click the middle of their picture, type "OST TEST", Stop control), then captions off. `JOIN lobby-data` lines (`-lobby-captions.png`, `-lobby-control-capable.png`, `-lobby-controlling.png`, `-lobby-control-typed.png`); the log's `MCP session up` lines show the new channel. |
| `--join-content-camera[=whiteboard\|document\|video]` | With `--join-test --join-stay=80` or more and `OST_CAMERA_DEVICE=<a test camera>`: Share ▸ Content from camera ▸ that type (default whiteboard) opens Teams' setup dialog (TASK-0214): its info, Got it, the preview while it looks for the board and once the edges are found (the processed frame saved as `-ccam-preview.png`), then Share: the processed camera on the screen-sharing line (`-ccam-shared.png`, a frame as sent), and Stop sharing 20 s later. `JOIN ccam` lines with the dialog's and the camera's state (`-ccam-tray.png`, `-ccam-info.png`, `-ccam-looking.png`, `-ccam-detected.png`, `-ccam-sharing.png`). |
| `--content-camera-test[=whiteboard\|document\|video]` | With `OST_CAMERA_DEVICE=<a test camera>` and a picture path: Teams' Content from camera setup dialog over the main window, no call (TASK-0214): its info (`-ccam-info.png`; Don't show again is left alone), Got it, the preview looking for the board (`-ccam-looking.png`), the edges found (`-ccam-detected.png`, the processed frame `-ccam-preview.png`), Overlay presenter off (`-ccam-overlay-off.png`) and on (`-ccam-overlay-on.png`, the frame `-ccam-overlay-frame.png`; the test camera's presenter walks in once the edges are found), Rotate (`-ccam-rotated.png`) and back, Scan Again (`-ccam-scan-again.png`), Detect edges off (`-ccam-edges-off.png`), then closed. `--content-camera-fail` (a camera without a board) waits for Teams' 11 s timeout instead (`-ccam-still-looking.png`, `-ccam-no-edges.png`, `-ccam-no-edges-after.png`). CCAM lines with the dialog's state and the camera's (`scanVideoEffect`). |
| `--join-share-tray` | With `--join-test --join-stay=60` or more: Share opens Teams' share tray (captured), Include sound on, Window (the desktop's picker for windows: pick a harmless window within a minute), sharing with the computer's sound mixed in, then Stop sharing. `JOIN share` lines (`-tray.png`, `-tray-sound.png`, `-sharing.png`); `system sound` lines in the log count the linked streams. |
| `--phone-audio-test` | Teams' phone audio (docs/spec/call-and-meeting-window.md §1.8k) in a solo meeting of your own (a calendar event "OST TEST 187 phone OST" with nobody invited, now for 30 minutes): the pre-join window's Phone audio (`PHONE prejoin` lines), joining with it, "Use phone for audio" as it opens by itself, a number typed and left (Call me is never pressed), Dial in manually, More with Call me and Facilitator ▸, and Meeting info's dial-in block; then it leaves, logs the call state and deletes the event. Pictures `-phone-{prejoin,prejoin-selected,dialog,number,dialin,more,info}.png`. `--phone-audio-invalid-call` also has the meeting call +1 000 000 0000 (no phone has it) and logs the answer (`-phone-calling`, `-phone-call-result`); `--phone-audio-facilitator` turns Facilitator on (its alert, then the transcript), captures More ▸ Facilitator ▸ and turns it off (`-phone-facilitator-{ask,on,off}`). `--phone-audio-subject=<title>` uses an existing meeting of yours instead (kept). |
| `--preheat-test` | Teams' pre-join preheat (TASK-0215; docs/spec/call-and-meeting-window.md §1.8k) in `--join-url=<link>` (`--preheat-subject=<title>` names it), else in a solo meeting of yours made now for 30 minutes ("OST TEST 215 preheat", deleted at the end): the pre-join window opens and joins the meeting's call hidden; `PREHEAT` lines log its Phone audio state every 2 s (`-preheat-prejoin.png`, `-preheat-phone.png`). Then `--preheat-cancel` cancels (its call is left), `--preheat-join` joins muted (held in a lobby it waits up to 2 minutes to be let in), `--preheat-expire` waits 70 s (the preheated call is left after a minute) and joins afresh; it stays `--join-stay=<s>` and leaves (`-preheat-call.png`). `--preheat-host` instead joins at once and, for `--join-stay`, logs whom the roster and the lobby show (someone in pre-join shows in neither); `--preheat-host-admit` also lets in whoever waits. `--preheat-in-call=<link>` first joins that meeting (muted) and opens the pre-join once in it (Teams preheats there too; use with `--preheat-cancel`; the first meeting is left at the end). |
| `--test-call-test` | Settings ▸ Devices (captured), Make a test call: Teams' test call with the Echo bot in the call window (captured), its end when the bot leaves (or leaving after 120 s), the results screen, its Device settings pane and Close. `TESTCALL` lines (`-devices`, `-call`, `-report`, `-report-devices`). |
| `--test-call-copilot` | With `--test-call-test`: Copilot in the test call (a calling scenario): Teams' question for calls (`TESTCALL copilot ask` line, `-copilot-ask.png`), then dismissed. |
| `OST_CAMERA_DEVICE=/dev/videoN` | This instance's camera instead of Settings ▸ Devices' choice (for tests on a machine whose settings file other instances share, e.g. a v4l2loopback camera fed by ffmpeg: stopping the feeder freezes it, `chmod 000` takes the permission away). |
| `--voicemail-greeting-test` | Settings ▸ Calls ▸ Voicemail (captured `-vm-card`), Record a greeting: Teams' call to your own voicemail in the call window (`-vm-call`; VOICEMAIL lines with the bar), `--voicemail-keys=<keys>@<s>,…` sends dial-pad keys that many seconds after it connects, `--voicemail-stay=<s>` (default 60) leaves then (`-vm-ended`). |
| `--camera-controls-test[=<device>]` | Settings ▸ Devices ▸ Video settings' "Automatically adjust camera controls" on the chosen camera (choose a test camera first: the page shows its preview): switch off, Open camera settings, one control changed and put back, switch on; CAMCTL lines with the camera's V4L2 values, `-cam-*.png`. With `=<device>` it does the same on that camera with backend calls only and no pictures (for a real camera). |
| `--spatial-audio-test` | Settings ▸ Devices' Spatial audio row (SPATIAL row: on, usable, capable, place; `-spatial-devices.png`); `--spatial-audio-on` / `--spatial-audio-off` set it first. With `--join-test` the call window's tile places and who speaks are logged every 2 s while in the meeting (SPATIAL tiles; `-spatial-call.png`); `--spatial-audio-admit` lets in whoever waits in the lobby (our test guests, as not bots), `--spatial-audio-hide-me` turns on Hide for me (the others side by side), `--spatial-audio-layout=speaker` picks Speaker view, `--spatial-audio-toggle=on@<step>,off@<step>` turns Spatial audio on or off mid-meeting at those 2 s steps after joining (the meeting's audio is renegotiated: x-much2 or the mix). |
| `--tty-test[=on\|off]` | Settings ▸ Accessibility's Teletypewriter (TTY) mode: TTY lines (card state and Teams' card list) and `-tty-before.png`; `=on` / `=off` sets it and captures Teams' "Changes will be applied for your next call" notice (`-tty-after.png`). |
| `--keys-test` | Press the keyboard shortcuts as real key events and check each (needs the QtTest QML module). |
| `--call-test` | Wait for a call, capture the toast, answer, capture, hang up (`--accept-video` answers with video when offered, `--camera-on` turns the camera on once connected). |
| `--call-panes` | As `--call-test`, also opening the Chat and People panes. |
| `--remote-hangup` | Stay in the call until the caller ends it. |
| `--call-person=<oid>` | Call that person as the Calls app does (open the 1:1 chat with them and call), then behave as `--call-out`. |
| `--call-out` | Call the first chat. |
| `--onedrive-test` | Visit Home, My files (making and deleting a test folder), a folder, Shared and Libraries. |
| `--link-preview-test[=<text>]` | In OST group test, types a link into compose as keys (AutoLink on Space) and logs the preview (LINKPREVIEW). `--link-preview-send` sends it and reads the sent message's preview back. `--link-preview-remove-only` removes the preview from your newest message that has one. `--link-preview-privacy` turns Optional connected experiences off, checks that no preview is made or shown, then turns it back on. Pictures go in /tmp/act. |
| `--app-card-test[=<text>]` | With `--shots=<dir>`: in OST group test, types a link to a site with a Teams app (default a Wikipedia page) into compose and logs the app's card (APPCARD compose, `app-card-compose.png`). `--app-card-collapse` collapses it first (`app-card-collapsed.png`). `--app-card-send` sends it and logs the sent message's card or preview (APPCARD sent, `app-card-sent.png`). `--app-card-messages` only logs the chat's newest link cards and captures them (`app-card-messages.png`). |
| `--smart-reply-test[=<chat name>]` | With `--shots=<dir>`: opens that chat (default "OST Test 1", for OST Test 2's profile) and logs the suggested replies Teams' rules show (SMARTREPLY, `smart-replies.png`). Then it opens the feedback form (`smart-feedback.png`) and Share a file's attach menu (`smart-share-file.png`). `--smart-reply-fake` puts a set with a file suggestion, then one with a meeting, on the newest message (`smart-meeting.png`), to draw the chips the tenant's features turn off. |
| `--everyone-test[=<chat>]` | In a big group chat (default "OST large chat test": ost-test1, ost-test2 and 52 guests), waits for the roster, types "@Everyone" as keys, picks it with Return and logs Teams' "# people will be notified" banner (EVERYONE), which has no Close button and goes after 3 s. Compose is cleared after. Pictures go in /tmp/act. |
| `--menu-test` | Settings and more as Teams': logs the menu's place and rows (MENU), zooms in twice then resets, and captures the menu, Get the mobile app, Unlock Teams Premium, Downloads (OST's download history) and Cast (searching, then after 20 s nothing found). Pictures go in /tmp/act. |
| `--premium-test` | Teams Premium as it stands for the account (PREMIUM line: mode, days left), the title bar's button and menu, then each page of the Premium dialog (offer, pending, active, home, licensed, benefits, cancel). Pictures go in /tmp/act. |
| `--zoom-test` | Holds 150% zoom for 12 s with the menu open (for a screen capture), then resets to 100% (ZOOM line). |
| `--work-location-test` | Settings ▸ Privacy's Manage my work location with the work-location detection policy: logs the card's state and geometry (WORKLOC), captures the card, its "Why set my work location automatically?" dialog, the Stationary device location page and its building list. `--work-location-off` then turns the automatic work location off and reads it back from the chat service. Pictures go in /tmp/act. |
| `--headset-test[=prejoin]` | Teams' headset call controls (TASK-0156): Settings ▸ Devices (`/tmp/act/headset-devices.png`), then HEADSET lines every 2 s (the headset service's status, the call's state and mute, the pre-join mic) while a script presses the headset's buttons; it never answers, mutes or hangs up by itself. `=prejoin` opens a pre-join screen (not joined) for its mic. Quits 10 s after a call ends or after `--headset-stay=<s>` (600). The emulated headset on linuxlt: `sudo sh ~/byod-gadget.sh headset` (USB HID gadget 0b0e:2400 with a Jabra-style telephony descriptor, a udev uaccess rule for its hidraw node, and `~/hs-emu.py`, the device's side: LEDs logged to /tmp/hs-emu.log and /tmp/hs-led.txt, Teams' ASP answered, buttons pressed by writing `hook 1`, `hook 0`, `mute`, `flash`, `reject`, `teams short` or `teams long` to /tmp/hs-cmd), `sh ~/byod-gadget.sh headset-audio` (its PipeWire speaker and mic); `headset-down` / `headset-audio-down` remove them. TASK-0223: `--headset-transfer-at=<step>` captures Teams' transfer prompt if it's up then and answers Transfer controls; `--headset-take-at=<step>` uses Devices' "Transfer controls to this app"; `--headset-shots=<prefix>` names their pictures; `--headset-mute-steps=<n>,…` toggles OST's own mute at those steps of a connected call; HEADSET-PROMPT, HEADSET-TAKE and HEADSET-BUTTON lines. `sudo sh ~/byod-gadget.sh ucq-headset [noucq]` is an unknown-vendor headset (16c0:0ab1) with a UCQ string at string 0x21 (or none), `ucq-headset-audio` its PipeWire nodes. A Bluetooth HFP headset: the session scratchpad's hs/bt-rig.sh (`up`: btvirt's two virtual controllers, one a BlueZ adapter, the other driven by Bumble as the headset, ~/hf-emu.py, paired and connected; buttons by writing `answer`, `hangup`, `mute`, `unmute` or `vgm <n>` to /tmp/hf-cmd, its log /tmp/hf-emu.log; `pw-on` WirePlumber with contrib/pipewire's patched plugin and setting, `pw-off` and `down` undo them). |
| `--rooms-test` | Teams' tenant rooms in Room audio (TASK-0161): a pre-join screen (Meet now, not joined) with Room audio, ROOMS lines (Other Suggestions, Nearby with the Bluetooth state, the search and the pick) and `/tmp/act/rooms-picker.png`, `-search.png` (`--rooms-query=<text>`, default "OST"), `-picked.png`. `--rooms-join=<channel id>` then joins a Meet now there with the room, logs it being added (ROOM lines), stays `--rooms-stay=<s>` (40) and leaves. An emulated Teams Rooms Bluetooth beacon for OST Test Room: the session scratchpad's hid/mtr-beacon.sh (bluetoothctl advertising Microsoft's manufacturer data). |
| `--room-audio-test` | The pre-join window with Teams' Room audio: the connected room devices and Teams' pick (ROOMS), the audio choices' geometry (CARDS), the room picker open, cleared (Join disabled); `--room-audio-join=<channel id>` then joins a Meet now in that channel with the room device (muted), logs the "Connected to a room device" notice (CALL) and leaves; `--manage-devices` captures Settings ▸ Devices ▸ Manage devices instead. Pictures in /tmp/act. |
| `--about-test` | About OST after a real update check, then with an update shown (set locally): ABOUT lines and pictures. |
| `--recognition-states` | Settings ▸ Recognition in each of Teams' card states (set locally, nothing sent): CARDS and CARDROWS lines and pictures. |
| `--recognition-test=<photo.jpg>,<voice.wav>` | Teams' face capture fed that photo and the voice capture fed that 16 kHz WAV, to the completion step; enrolls them (remove afterwards with `examples/biometric`). |
| `--notif-banner-test[=hold]` | Teams' notification banners in each corner and size (test, chat message with quick reply, @mention, meeting started), BANNERS lines and a picture of each; puts the position and size back. `=hold`: shows them bottom right for 45 s, for clicking. |
| `--notif-banner-live-test=<text>` | The first real chat banner is answered from it: a heart reaction and a quick reply saying `<text>`. |
| `--transfer-test=<oid>` | Once a call connects, transfer it to that person (`--consult`: consult first, then Transfer from the banner); stays until the call ends. |
| `--share-test` | In a call (with `--call-test --remote-hangup`): share a screen once connected (the portal's picker asks what), capture it after 30 s, then stop. |
| `--tab=<name>` | With `--open-chat`, open that tab of the chat or channel before capturing. |
| `--loop-test --loop-steps=<file>` | A Page view (Loop, page only) driven by the file's steps, one every 5 s: a JavaScript line, `SHOT <name>`, `INSERT <command>` (the insert row) or `TYPE <keys>` (`<END>` is Ctrl+End, `<RET>` Return). Needs `QML_XHR_ALLOW_FILE_READ=1`. Use a scratch page of the test account's own. |
| `--consult-call=<oid>` | With `--call-test --remote-hangup`, 5 s after a 1:1 call connects: consult that person by call (this call held, a second call placed); once they answer, `--consult-transfer` transfers this call to them (replacing the consult call) or `--consult-merge` merges both calls, else the consult is ended after 20 s and this call resumed. CONSULT lines (`-consult-{calling,connected,after,done}.png`). |
| `--unpark-dialog-test` | Opens the Calls app and its "Pick up a parked call" dialog and captures it (`-unpark-dialog.png`). |
| `--clock-log` | Every 5 s in a call, CLOCK lines: the call window's clock in seconds, the call state and the peer (does the clock run on across a transfer, merge or park pickup). |
| `--hangup-after=<s>` | With `--call-test --remote-hangup`: leaves the call `<s>` seconds after it connects, whatever it has become (a merge's group call, a transferred call), capturing `-before-hangup.png` first; HANGUP lines (peer, thread). |
| `--park-test` | With `--call-test --remote-hangup` (or `--call-out`), 8 s after a 1:1 call connects: logs whether Park Call is offered (PARK lines: `callCanPark`, the More items) and captures `-park-more.png`, then More ▸ Park Call; once the pickup code comes back, PARK code, the parked view `-parked.png`, and the window is closed. |
| `--unpark=<code>` | Once signed in, retrieves the parked call with that pickup code (a call to Teams' park server, `4:*11`, carrying `unparkContent {pickupCode}`) stays 25 s (`-unparked.png`) and hangs up; UNPARK lines (call state, peer). |
| `--call-encryption` | With `--call-test` (or `--call-out`), 4 s after a 1:1 call connects: opens the encryption card under the bar's shield (Teams' Encryption status) and captures it (`-encryption.png`); ENCRYPTION lines (end-to-end encrypted or not, the numbers, the card's place). |
| `--e2ee-setting-test[=on\|off]` | Settings ▸ Privacy's End-to-end encrypted calls card: E2EE lines (your choice, whether the tenant allows it) and `-e2ee-card.png`; `=on` / `=off` saves that choice where Teams keeps it, reloads and logs what the service holds (`-e2ee-card-saved.png`). |
| `--hold-test` | In a call: Hold (Teams' music on hold) and Resume, dial-pad tones, and capturing when the other side holds; stays until they hang up. |
| `--app-host-test[=<tab>]` | With `--open-chat=<channel id> --shots=<dir>`: that channel's app tab (default Notes) in OST's TeamsJS host (docs/spec/app-host.md). APPHOST lines: the channel's tabs, the host's events (framed, initialize, appLoaded, success, tabSaved…) after 15, 35 and 55 s, the tab's menu; then Reload tab, Expand tab, Open tab in new window (its own APPHOST window line) and App permissions. Pictures `app-host-{15s,35s,55s,reloaded,expanded,window,permissions}.png`. Quits unless `--app-host-stay` (to inspect the views over `QTWEBENGINE_REMOTE_DEBUGGING`). Opening a channel's Notes for the first time makes its section, as Teams does. |
| `--webapp-test` | Open Whiteboard (`--webapp-help`: Help) from View more apps and capture it once loaded. |
| `--embedded-apps-test[=<list>]` | Teams' embedded first-party apps as OST hosts them (docs/spec/app-host.md), one after another, about 40 s each; `<list>` from `whiteboard,shifts,clipchamp,copilot,settings,office,sto,ir` (default all). `whiteboard`, `shifts`, `clipchamp`: the app bar's personal apps in OST's TeamsJS host; `copilot`: the chat list's Copilot row; `settings`: Settings ▸ Files and links; `office`: `ost-open-test.docx` from My files with the "Teams" choice (the device setting is put back); `sto`: Share to Outlook on your newest message in `--embed-chat=<chat id>` (default OST group test), closed without sending, which discards the draft; `ir`: Immersive Reader on that message (`--embed-message=<text>`: the newest message containing that text instead, such as a card's message; its EMBED line shows the reader's card text), then closed. EMBED lines: each app's host events (initialize, appLoaded, success, failure…), the dialog's events, the reader's state. Pictures `embed-<item>.png`. Quits unless `--embed-stay`. |
| `--events-test[=create\|townhall]` | Teams' Events app as OST draws it (docs/spec/events.md), opened from View more apps: Discover, Manage, Create event and the New event form, each logged (EVENTS lines: the page, the lists' sizes, Manage's totals and draft names) and captured (`events-{discover,manage,create,form}.png`). `=create` also saves a draft named "OST TEST 209 draft <hh:mm>" with nobody invited (`events-save.png`, `events-draft.png`), cancels it (Teams deletes a draft) and reloads Manage (`events-manage-after.png`). Quits unless `--events-stay`. `=townhall` does the same with the Town hall template (the form with Set up experience and options open; the draft "OST TEST 184 town hall draft <hh:mm>"). |
| `--call-notes-test` | A solo Teams meeting of your own (a calendar event "OST TEST 209 notes OST" with nobody invited, now for 30 minutes; OST has no calendar Meet now) joined with camera, mic and audio off, then the call window's Notes (docs/spec/app-host.md "Meeting Notes"): MEETINGNOTES lines every 5 s (how the notes were found or made: the call's shared link, Teams' meeting-notes service, or made as Teams makes them; the Loop host's state), pictures `call-notes-{open,ready,end}.png`; then it hangs up, logs the call state and deletes the event. `--call-notes-stay` keeps the call two minutes longer. Notes OST makes are a `.loop` file in your OneDrive's Meetings folder. |
| `--store-test` | Open the Store, capture Home, search "planner", open Whiteboard's details. |
| `--add-tab-test` | With `--open-chat=<chat or channel id> --shots=<dir>`: Teams' Add a tab ("+"; a channel's menu, then Apps): the picker (ADDTAB picker line: grid and collections; See all), Website's configuration with an invalid URL. With `--add-tab-url=<https url>` (and `--add-tab-name=<name>`) it saves the tab for real, posting "I added a tab…" unless `--add-tab-nopost`, logs ADDTAB result and the tabs, and captures the new tab's menu; `--add-tab-remove` removes it again. Pictures `add-tab-*.png` `--add-tab-app=<name>` opens that app's own configuration page instead (in OST's TeamsJS host) and after 20 s logs ADDTAB app config (Teams' validity and settings it reported) with `add-tab-config-app.png`; nothing is saved unless `--add-tab-save`: it then waits up to 3 minutes for the page to report a valid setup (pick its item yourself, e.g. over `QTWEBENGINE_REMOTE_DEBUGGING`), saves as Teams (settings.save, then the tab), and logs and captures as for a website (`--add-tab-nopost`, `--add-tab-remove` apply). |
| `--add-tab-choice=<newList\|existingList\|existingPage>` | With `--open-chat=<channel id> --shots=<dir>`: a channel's "+" choice as Teams. New list / Existing list add the Lists tab and open SharePoint's page in OST's TeamsJS host; Existing page needs `--add-tab-link=<Loop link>` (looked up, its card, then Confirm). ADDTAB choice lines: the tabs, the result, the tabs after, the page's host events after 20 s. `--add-tab-remove` removes the new tab; `--add-tab-stay` keeps OST open. Pictures `add-tab-choice-{menu,page-dialog,page-card,added,page-20s}.png`. |
| `--task-dialog-test=<findmeetingtime\|createaplanner\|remindme>` | With `--open-chat=<chat id> --shots=<dir>`: the workflow suggestion's Workflows dialog (Teams' task module, 800 x 600) in OST's TeamsJS host, TASKDIALOG state lines (size, title, frame, host events) after 15 and 30 s with `task-dialog-{15s,30s}.png`, then Close; nothing is submitted. |
| `--tab-cleanup=<name\|name…>` | With `--open-chat=<chat or channel id>`: removes those tabs as Teams' Remove does (the thread property to null), one every 5 s (TABCLEANUP lines); quits. For tidying up after tab tests. |
| `--workflows-test` | With `--open-chat=<channel id> --shots=<dir>`: the channel's Workflows dialog (Teams' task module, in OST's TeamsJS host), WORKFLOWS line and `wf.png` after 15 s; quits unless `--workflows-stay`. |
| `--meeting-tab-test=<tab>` | (`_` for spaces, `QnA` for Q&A.) With `--open-chat=<meeting chat id> --shots=<dir>`: the meeting chat's tabs (MEETINGTAB line), its "+N" menu, then that tab (Breakout Rooms, Q&A, Meeting Whiteboard, Attendance) after 10 and 25 s (Meeting Whiteboard: the meeting's own board, the host's events, the frame's address without values). Pictures `meeting-tab-*.png`; `--meeting-tab-stay` keeps OST open. |
| `--chat-tab-test=<tab>` | (`Notes`, `Recap` or `Storyline`.) With `--open-chat=<chat id> --shots=<dir>`: the chat's tabs (CHATTAB tabs line), then that tab after 10 and 25 s (CHATTAB lines: Notes' state and file, Storyline's page address and title). In a meeting chat Recap also captures Mentions, Transcript and More options; Notes also draws its preparing, deleted and failed pages (nothing sent). Pictures `chat-tab-<tab>-*.png`; quits. Opening Notes makes the chat's notes when it has none, as Teams does. |
| `--loop-test=<notes\|page\|newpage>` | With `--open-chat=<chat or channel id> --shots=<dir>`: a Loop page in OST's Loop page host (docs/spec/loop-host.md). `notes` opens the chat's Notes tab, `page` the channel's Page tab named `--loop-tab=<name>`, `newpage` the channel's "+" › New page (the "Untitled page" tab, then Loop makes "Loop paragraph" in the channel's folder and the tab is pointed at it). LOOPTEST lines: the tabs, the host's state and events every 5 s until the page is drawn (or about 90 s), the page's text; with `--loop-type=<text>` it types the text at the end of the page as real keys, reads the page back (typed found/missing), then deletes it again with Backspace (removed gone/still there). `--loop-remove` removes a new page's tab and deletes its file (to the site's recycle bin) afterwards. Pictures `loop-<which>-{open,ready,typed,removed}.png`. Quits unless `--loop-stay`. `--loop-delete-file=<drive id>\|<item id>` alone deletes one test page's file (to the recycle bin) and quits. |
| `--channel-files-test` | OST Test Team's General channel, Shared tab: make a folder, capture it, delete it. |
| `--apps-test` | People: add a contact, favorite it, delete it; OneNote: open the first notebook, add a page, read it, delete it. |
| `--planner-test` | Add and complete a private task; create a plan in OST Test Team, add a task, then delete the test plans. |
| `--group-call-test` | Start a group call in "OST group test", capture it and People, hang up. |
| `--group-call-nmc=<chat name>` | ("~" for spaces; TASK-0208.) Join that group chat's ongoing call (`--group-call-start` calls the chat, `--group-call-huddle` starts its Meet now, `--group-call-answer` waits for its call to ring and answers with audio), mute, then log the bar and More (`GCNMC off-1280`, `off-856`, `on-1280` with the ubar JSON; `GCNMC grid` / `list` with More's rows) with New meeting controls off and on (put back after), capturing each (`-gc-*.png`); `--group-call-stay=<s>` stays longer before hanging up (`GCNMC after` logs the call state). Use a chat of test accounts only (e.g. "OST TEST group call"). |
| `--cancel-ring` | With `--call-out`, hang up while it rings. |

Unit tests for the engine and the desktop backend run with
`cargo test --workspace`.
