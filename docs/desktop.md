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
  People. Planner, OneNote and People are native; Whiteboard, Clipchamp
  and Help are embedded, as Teams embeds them (QtWebEngine, with OST's
  own persistent web profile: sign in once). Shifts (it needs a scope
  OST's sign-in doesn't have) and Events open Teams on the web. An app opened
  there takes the rail's one extra slot, as in Teams.
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
| `--join-test` | Join that meeting through the pre-join window, capture it, the stage and People, leave (`--join-stay=<s>` stays longer, `--join-muted` joins with the mic off, `--join-raise` raises and lowers your hand). |
| `--keys-test` | Press the keyboard shortcuts as real key events and check each (needs the QtTest QML module). |
| `--call-test` | Wait for a call, capture the toast, answer, capture, hang up (`--accept-video` answers with video when offered, `--camera-on` turns the camera on once connected). |
| `--call-panes` | As `--call-test`, also opening the Chat and People panes. |
| `--remote-hangup` | Stay in the call until the caller ends it. |
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
| `--hold-test` | In a call: Hold (Teams' music on hold) and Resume, dial-pad tones, and capturing when the other side holds; stays until they hang up. |
| `--app-host-test[=<tab>]` | With `--open-chat=<channel id> --shots=<dir>`: that channel's app tab (default Notes) in OST's TeamsJS host (docs/spec/app-host.md). APPHOST lines: the channel's tabs, the host's events (framed, initialize, appLoaded, success, tabSaved…) after 15, 35 and 55 s, the tab's menu; then Reload tab, Expand tab, Open tab in new window (its own APPHOST window line) and App permissions. Pictures `app-host-{15s,35s,55s,reloaded,expanded,window,permissions}.png`. Quits unless `--app-host-stay` (to inspect the views over `QTWEBENGINE_REMOTE_DEBUGGING`). Opening a channel's Notes for the first time makes its section, as Teams does. |
| `--webapp-test` | Open Whiteboard (`--webapp-help`: Help) from View more apps and capture it once loaded. |
| `--store-test` | Open the Store, capture Home, search "planner", open Whiteboard's details. |
| `--add-tab-test` | With `--open-chat=<chat or channel id> --shots=<dir>`: Teams' Add a tab ("+"; a channel's menu, then Apps): the picker (ADDTAB picker line: grid and collections; See all), Website's configuration with an invalid URL. With `--add-tab-url=<https url>` (and `--add-tab-name=<name>`) it saves the tab for real, posting "I added a tab…" unless `--add-tab-nopost`, logs ADDTAB result and the tabs, and captures the new tab's menu; `--add-tab-remove` removes it again. Pictures `add-tab-*.png` `--add-tab-app=<name>` opens that app's own configuration page instead (in OST's TeamsJS host) and after 20 s logs ADDTAB app config (Teams' validity and settings it reported) with `add-tab-config-app.png`; nothing is saved. |
| `--meeting-tab-test=<tab>` | (`_` for spaces, `QnA` for Q&A.) With `--open-chat=<meeting chat id> --shots=<dir>`: the meeting chat's tabs (MEETINGTAB line), its "+N" menu, then that tab (Breakout Rooms, Q&A, Meeting Whiteboard, Attendance) after 10 and 25 s. Pictures `meeting-tab-*.png`. |
| `--chat-tab-test=<tab>` | (`Notes`, `Recap` or `Storyline`.) With `--open-chat=<chat id> --shots=<dir>`: the chat's tabs (CHATTAB tabs line), then that tab after 10 and 25 s (CHATTAB lines: Notes' state and file, Storyline's page address and title). In a meeting chat Recap also captures Mentions, Transcript and More options; Notes also draws its preparing, deleted and failed pages (nothing sent). Pictures `chat-tab-<tab>-*.png`; quits. Opening Notes makes the chat's notes when it has none, as Teams does. |
| `--channel-files-test` | OST Test Team's General channel, Shared tab: make a folder, capture it, delete it. |
| `--apps-test` | People: add a contact, favorite it, delete it; OneNote: open the first notebook, add a page, read it, delete it. |
| `--planner-test` | Add and complete a private task; create a plan in OST Test Team, add a task, then delete the test plans. |
| `--group-call-test` | Start a group call in "OST group test", capture it and People, hang up. |
| `--cancel-ring` | With `--call-out`, hang up while it rings. |

Unit tests for the engine and the desktop backend run with
`cargo test --workspace`.
