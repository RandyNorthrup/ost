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
- **Call controls**: Hold and Resume through Teams' hold service (the
  other person hears Teams' hold music; you see "On hold" when they hold
  you), Dial pad (RFC 4733 tones), View (Gallery / Speaker in meetings,
  Full screen, turn incoming video off) and More (Device settings, Full
  screen). OST answers Teams' mid-call re-offers, including the move to
  a media processor that Hold and group escalation make.
- **Planner** (from View more apps): My tasks (private To Do tasks and
  the Planner tasks assigned to you, with All / Private tasks / Assigned
  to me), My day, My plans (your teams' plans), Grid and Board, adding
  and completing tasks, creating a plan in a team. View more apps also
  opens Whiteboard, Clipchamp and Help, which are web apps, in the
  browser.
- **Presence**: your status (set, reset, shown everywhere) and everyone
  else's on their pictures.
- **Notifications**: desktop notifications for new messages, titled
  "<name> mentioned you" for mentions; channel posts notify only when
  they mention you; "Only mentions" in Settings.
- **Settings**: theme (follow the system, light, dark), read receipts,
  Enter to send or to start a new line, notifications, audio devices,
  start with the computer.
- **Search**: people, chats and channels from the title bar.

Not yet: video in meetings and in calls you place, screen sharing, raising hands and reactions in
meetings, transfer, hold and the dial pad. Their buttons are shown disabled rather than hidden or faked.

## Build

Requirements: Rust (stable), Qt 6.8 or newer (developed on 6.11) with
Qt Quick and Qt Quick Controls, a C++ compiler and CMake (for CXX-Qt),
the ALSA development files (calls), and NASM (openh264, video).

```bash
# Arch
sudo pacman -S qt6-base qt6-declarative qt6-svg alsa-lib cmake nasm
# Debian / Ubuntu
sudo apt install qt6-base-dev qt6-declarative-dev qml6-module-qtquick-controls \
  qml6-module-qtquick-window libqt6svg6 libasound2-dev cmake nasm

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
| `$XDG_STATE_HOME/ost/drafts.json` | Unsent drafts |
| `$XDG_CACHE_HOME/ost/photos/` | Profile and team pictures (refreshed daily) |
| `$XDG_DOWNLOAD_DIR` (else `~/Downloads`) | Downloaded attachments |
| `$XDG_CONFIG_HOME/autostart/ost-desktop.desktop` | Only with "Start with the computer" on |

## Environment variables

| Variable | Effect |
| --- | --- |
| `OST_SYSTEM_FRAME=1` | Use the desktop's own window frame instead of Teams' title bar buttons. |
| `OST_NO_KEYRING=1` | Don't use the system keyring for tokens (headless machines, CI). |
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
| Messaging | `Ctrl+F` find in chat, `Ctrl+J` newest message, `Shift+Esc` mark all read, `Ctrl+Alt+U` / `C` / `A` unread, chats, channels, `Ctrl+Alt+Z` clear filters, `Alt+P` details pane, `Alt+1`–`Alt+5` header tabs |
| Calls and calendar | `Ctrl+Shift+M` mute, `Ctrl+Shift+O` camera, `Ctrl+Shift+H` leave, `Alt+Shift+A` start an audio call, `Ctrl+Shift+S` / `Ctrl+Shift+A` accept with audio / video, `Ctrl+Shift+D` decline, `Alt+N` schedule a meeting |

## Test harness

The app doubles as its own end-to-end test driver. With a first argument
that is a PNG path, it captures itself there (and to `<path>-<step>.png`
for multi-step tests) and quits; the flags pick what it does first. Run
it offscreen against a test account:

```bash
QT_QPA_PLATFORM=offscreen QT_SCALE_FACTOR=1.5 \
  target/debug/ost-desktop /tmp/shot.png "" "" --size=1280x680 --view=calendar
```

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
| `--group-test` | Start a named group chat with a first message. |
| `--channel-test` | Post in OST Test Team > General. |
| `--reply-test` | With `--open-chat=<channel>`, reply in the newest post's thread. |
| `--mentions-test` | Open Quick views > Mentions and a mention. |
| `--activity-test`, `--activity-watch` | Open an activity item; log live feed changes. |
| `--status-test` | Set Busy from the profile menu, then reset. |
| `--settings-test` | Switch the theme and read receipts and back. |
| `--calendar-test` | Schedule a Teams meeting tomorrow at 3 PM. |
| `--join-test` | Join that meeting through the pre-join window, capture it, the stage and People, leave (`--join-stay=<s>` stays longer, `--join-muted` joins with the mic off). |
| `--keys-test` | Press the keyboard shortcuts as real key events and check each (needs the QtTest QML module). |
| `--call-test` | Wait for a call, capture the toast, answer, capture, hang up (`--accept-video` answers with video when offered, `--camera-on` turns the camera on once connected). |
| `--call-panes` | As `--call-test`, also opening the Chat and People panes. |
| `--remote-hangup` | Stay in the call until the caller ends it. |
| `--call-out` | Call the first chat. |
| `--onedrive-test` | Visit Home, My files (making and deleting a test folder), a folder, Shared and Libraries. |
| `--hold-test` | In a call: Hold (Teams' music on hold) and Resume, dial-pad tones, and capturing when the other side holds; stays until they hang up. |
| `--planner-test` | Add and complete a private task; create a plan in OST Test Team, add a task, then delete the test plans. |
| `--group-call-test` | Start a group call in "OST group test", capture it and People, hang up. |
| `--cancel-ring` | With `--call-out`, hang up while it rings. |

Unit tests for the engine and the desktop backend run with
`cargo test --workspace`.
