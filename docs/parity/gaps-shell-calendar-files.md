# Gap list: app shell, Activity, Settings, Calendar, Files and apps

What OST lacks, or does differently, against Teams desktop for Windows in these areas:
- app shell: title bar, search, the ··· menu, profile menu, presence, app rail, windows, tray, notifications;
- Activity;
- Settings;
- Calendar and scheduling;
- Files: the OneDrive app, Shared tabs, sharing, opening files;
- Notes (OneNote), the channel Page (Loop), Whiteboard, Clipchamp;
- Planner / To Do;
- the Store and apps;
- Help.

Each item below was decided by reading OST's code at commit `dd1b394` (branch `desktop/foundation`, 2026-11-06). No code was changed.

## Legend

- **Priority**
  - **[P1]**: core, used every day. A Teams user notices its absence at once.
  - **[P2]**: common.
  - **[P3]**: rare, licensed-only, admin-only, or cosmetic.
- **References**
  - `SS` = `docs/parity/shell-settings.md`
  - `CAL` = `docs/parity/calendar.md`
  - `FA` = `docs/parity/files-apps.md`
  - `NT` = `docs/spec/notes-tab.md`
  - `CT` = `docs/spec/channel-tabs.md`
  - `WD` = `docs/parity/winpc-diff.md` (live observations on winpc)

  A `§` number points into that document.
- **OST file references**
  - QML files are under `desktop/qml/` and named alone, e.g. `Main.qml:104`.
  - Rust is `desktop/src/backend.rs` or `src/api/*.rs`.
  - "absent" means no code for the behaviour exists anywhere in `desktop/` or `src/`.
- **Format**: `- [ ] [Pn] behaviour — Teams: … — OST: … (ref: …; OST: …)`

---

## 1. Title bar and window chrome

- [ ] [P2] History menu on Back/Forward — Teams: hovering Back or Forward lists up to 12 recent places (chats, channels, files, tabs, apps); Ctrl+H opens it — OST: plain Back/Forward buttons; no hover list and no Ctrl+H (ref: SS §1 "History menu"; OST: TitleBar.qml:74-85, Main.qml:45-86)
- [ ] [P2] History depth and granularity — Teams: history is 12 places and includes files, tabs and apps — OST: keeps 50 entries of `{view, chatId}` only, so tabs, files, folders and channel tabs are not recorded (ref: SS §1; OST: Main.qml:109-136)
- [ ] [P3] Restart (update staged) button beside ··· — Teams: appears when an update is staged — OST: absent (ref: SS §1 "Restart", §10.13; OST: absent)
- [ ] [P3] Hamburger / collapsed app bar — Teams: "Collapse app bar" leaves the ≡ button in the rail, and right-click > **Pin AppBar** keeps it visible — OST: the toggle hides the whole rail (width 0) (ref: SS §4 "Hamburger"; OST: AppRail.qml:10-16, TitleBar.qml:69-73)

## 2. Search

- [ ] [P1] Full results page on Enter — Teams: Enter opens a results page with **All, Messages, People, Files, Group chats, Teams and channels** tabs — OST: Enter opens the first suggestion; there is no results page (ref: SS §6 "Results page tabs"; OST: TitleBar.qml:106-109)
- [ ] [P1] Message search — Teams: messages are searched across chats and channels, with filters for Type, Teams and channels, From, Date, @Mentions me, Has attachments, Hide app and bot messages — OST: suggestions match chat names and directory people only; message text is never searched (ref: SS §6 "Messages filters", Graph `POST /search/query`; OST: TitleBar.qml:126-134)
- [ ] [P2] File search, with filters for team/channel/chat, file type, person and date — Teams: Files tab — OST: absent (ref: SS §6 "Files filters"; OST: absent)
- [ ] [P2] Teams and channels in suggestions — Teams: typeahead lists teams and channels, and recently visited group chats — OST: suggestions come from `chatList.chats` (chats) and people only; channels never appear (ref: SS §6 "Typeahead"; OST: TitleBar.qml:128-133, Main.qml:1370)
- [ ] [P2] Ctrl+G "Go to a specific chat or channel" picker — Teams: a dedicated /goto picker — OST: Ctrl+G only focuses the search box (same action as Ctrl+E); only the placeholder text changes (ref: SS §1 "Ctrl+G"; OST: Main.qml:46, TitleBar.qml:112)
- [ ] [P2] Slash commands — Teams: "/" lists commands; documented are /available, /busy, /dnd, /brb, /away, /offline, /goto, /unread, /mentions — OST: absent (ref: SS §1 "Slash commands"; OST: absent)
- [ ] [P3] Query syntax — Teams: KQL `From:` `In:` `Subject:` `Sent:`, prefix wildcard, "exact phrase", fuzzy people match — OST: plain substring match on names (ref: SS §6 "Query syntax"; OST: TitleBar.qml:125-131)

## 3. Settings and more (···) menu

Teams' menu, in order (WD "App shell menus"): Unlock Teams Premium; Pin window on top; Settings; Cast; Downloads; Zoom row; Help (F1); Feedback ›; Keyboard shortcuts; Get the mobile app. OST has only Pin window on top, Settings and Keyboard shortcuts (TitleBar.qml:212-218).
- [ ] [P2] **Zoom** row (− 100% + reset) — Teams: in the menu, with Ctrl+= / Ctrl+- / Ctrl+0 — OST: no menu row and no shortcuts; the UI has no scale factor (ref: SS §8 "Zoom", WD menu item 8; OST: TitleBar.qml:212-218, Main.qml:45-86)
- [ ] [P2] **Help** (F1) entry — Teams: in the menu; F1 opens Help — OST: Help is reachable only from View more apps; no menu entry and no F1 (ref: SS §1, §13; WD menu item 10; OST: TitleBar.qml:212-218, AppRail.qml:118)
- [ ] [P2] **Downloads** — Teams: menu entry listing downloaded files — OST: absent; downloads go silently to `download_dir()` (ref: WD menu item 6; OST: backend.rs:927)
- [ ] [P3] **Feedback ›** submenu (Give feedback, Report a problem Ctrl+Alt+Shift+R) — Teams: in the menu — OST: absent (ref: SS §1, §13; WD menu item 11; OST: absent)
- [ ] [P3] **Cast**, **Get the mobile app**, **Unlock Teams Premium** — Teams: in the menu — OST: absent (ref: WD menu items 1, 5, 13; OST: absent)

## 4. Profile / account manager menu

Teams' profile menu (WD "Profile menu"):
- the org name and Sign out;
- a big avatar, name, e-mail and **View account ↗**;
- rows **Available ›**, **Pause notifications ›**, **Set work location ›**, **Set status message ›**;
- **Add another account**.

OST has the org name, Sign out, avatar, name, e-mail and the status row (TitleBar.qml:324-426).
- [ ] [P1] **Set status message** dialog — Teams: message text, "Show when people message me", "Clear status message after" (Never / Today / This week …), Done, and a **Schedule out of office** link — OST: absent; no UI and no `setStatusMessage` call (ref: SS §2 "Set status message", §3.7; OST: TitleBar.qml:335-387, src/api/presence.rs)
- [ ] [P2] Status **Duration** — Teams: after picking a status, "Reset status after" presets or a Custom date and time, then Done — OST: a status is set with no expiry (ref: SS §2 "Duration", §3.7 `expirationDuration`; OST: TitleBar.qml:400-412, presence.rs:88-115)
- [ ] [P2] **Pause notifications ›** — Teams: profile-menu row — OST: absent (ref: WD profile menu; OST: absent)
- [ ] [P2] **View account ↗** link (myaccount.microsoft.com), and changing your profile picture by clicking the avatar — Teams: in the header — OST: the avatar and name are static (ref: SS §2 header; WD profile menu; OST: TitleBar.qml:358-367)
- [ ] [P3] **Set work location ›** (In the office, with a building / Remote / Clear; syncs with Outlook) — Teams: profile-menu row — OST: absent (ref: SS §2 "Set work location", §3.7 work location API; OST: absent)
- [ ] [P3] Account list with per-account badges and **Add another account** — Teams: footer of the menu — OST: one account only (ref: SS §2, §11; OST: absent)

## 5. Presence and status semantics

- [ ] [P1] Automatic Away — Teams: you go Away after about 5 minutes idle, on screen lock, or when Teams is minimised, and Offline when the PC sleeps — OST: the endpoint is always published as `Available`/`Available`; no idle, lock or minimise detection (ref: SS §3.3; OST: src/api/presence.rs:120-127, src/trouter/mod.rs:197,283)
- [ ] [P1] In a call / In a meeting / Presenting presence — Teams: a call or meeting sets "In a call" or "In a meeting", and screen sharing sets "Presenting" (DND glyph) — OST: the endpoint activity never changes during calls, meetings or sharing (ref: SS §3.2, §3.3, §10.3 "Set my status to DND when sharing"; OST: presence.rs:120-127, backend.rs:1690-2134 (no presence update))
- [ ] [P1] DND suppresses banners — Teams: under Do not disturb, banners are suppressed except from priority-access contacts — OST: `should_notify` ignores your own presence, so toasts fire during DND (ref: SS §3.4; OST: backend.rs:946-959, 2249-2285)
- [ ] [P2] Your own presence source — Teams: shows your computed or forced presence from the presence service — OST: reads your presence from the self-chat's entry (`isSelf`), polled every 60 s; it falls back to "Available" when that chat is missing (ref: SS §3.7; OST: Main.qml:1365-1368, backend.rs:2208-2245)
- [ ] [P2] Out of office — Teams: Schedule out of office dialog (turn on automatic replies, message, external replies, time period, Save), synced with Outlook; OOO presence (purple) — OST: absent (no `mailboxSettings/automaticReplies`) (ref: SS §3.6, §3.2 "Out of Office"; OST: absent)
- [ ] [P2] App-set states shown on yourself: Away "Last seen", Focusing, Out of office, In a call / out of office — OST: `statusLabel` folds InACall, InAMeeting and BusyIdle to "Busy" and has no OOF or Focusing labels (ref: SS §3.2; OST: TitleBar.qml:319-323)
- [ ] [P3] "Notify when available" status-change alerts (up to 15 people), a banner on change, and Settings > Notifications > Presence > Manage notifications — OST: absent (ref: SS §3.5; OST: absent)
- [ ] [P3] Availability ordering rule — Teams: outside calls you can only pick a status *less* available than the computed one — OST: any status can be forced (ref: SS §3.3; OST: TitleBar.qml:400-412)

## 6. Left app rail

- [ ] [P2] Right-click menu on rail apps: **Pin / Unpin**, **Open in new window** — Teams: on every rail app — OST: the rail has a tap handler only; no context menu (ref: SS §4, FA §20; OST: AppRail.qml:92-93)
- [ ] [P2] Pinning apps from View more apps — Teams: right-click > Pin adds an app to the rail permanently; several pinned apps; drag to reorder — OST: one temporary slot ("the newest replaces the last"); not saved; no drag reorder (ref: SS §4, FA §20; OST: AppRail.qml:40-45)
- [ ] [P2] Ctrl+1…9 follow the rail's order — Teams: the Nth app, so the number moves if apps are reordered or pinned — OST: Ctrl+1-5 are hard-wired to five views; Ctrl+6-9 are absent (ref: SS §4, CAL §1; OST: Main.qml:50-54)
- [ ] [P2] "Show app names" (label under each icon) and "Auto collapse app bar" — Teams: Appearance settings and rail right-click — OST: icons only, with no setting (ref: SS §4, §10.5; OST: AppRail.qml:55-97, SettingsView.qml:12-18)
- [ ] [P2] View more apps lists installed apps — Teams: the flyout lists the user's installed apps and searches them — OST: a hard-coded list of 8; Shifts and Events open teams.microsoft.com in the browser (ref: SS §4, FA §20; OST: AppRail.qml:114-123, 149-154)
- [ ] [P2] Rail badges — Teams: Chat and Teams count unread unmuted chats, channels with unread @mentions, and unread followed threads (2026 model) — OST: Chat shows the plain count of chats flagged `unread`, with no mute, mention or followed-thread rules; only Chat and Activity have badges (ref: SS §4 "Badges", §7 "2026 badge model"; OST: AppRail.qml:76-91, Main.qml:1404-1405)
- [ ] [P3] Copilot app in the rail when licensed (WD: between OneDrive and Apps) — OST: deliberately left out (ref: SS §4, WD rail; OST: AppRail.qml:29)
- [ ] [P3] "Activity in your other accounts and orgs" rail icon and panel — OST: absent (ref: SS §4, §11; OST: absent)

## 7. Windows, multi-window, panes and zoom

- [ ] [P2] Pop out a chat — Teams: Ctrl+O opens the current conversation in a new window; Ctrl+Shift+N starts a chat in a new window; double-click pops out — OST: absent; one main window only (ref: SS §8 "Pop out a chat", §9; OST: Main.qml:45-86 (no Ctrl+O / Ctrl+Shift+N))
- [ ] [P2] Pop out a personal app or tab — Teams: right-click > Open in new window, or the pop-out icon; works for Activity, Chat, Calendar, Calls; warning after two pop-outs — OST: absent (ref: SS §4, §8; CAL §1 "Pop-out calendar"; OST: absent)
- [ ] [P2] "Opening Teams content" / "Starting chats" (Main window / New window) — Teams: Settings > General — OST: absent (ref: SS §8, §10.1; OST: SettingsView.qml:266-279)
- [ ] [P2] Zoom Ctrl+= / Ctrl+- / Ctrl+0 — OST: absent (ref: SS §8 "Zoom"; OST: Main.qml:45-86)
- [ ] [P3] F11 full screen — OST: absent (ref: SS §8; OST: absent)
- [ ] [P3] Pane divider: Ctrl+Alt+Enter focuses it and arrows resize; Ctrl+Shift+Enter restores the default width — OST: list panes have fixed widths (e.g. ActivityView width 379) and no divider (ref: SS §8 "Panes"; OST: ActivityView.qml:26, SettingsView.qml:24)
- [ ] [P3] Pin on top shrinks the window slightly — Teams: pinned windows shrink — OST: sets `WindowStaysOnTopHint` only (ref: SS §8 "Pin window on top"; OST: Main.qml:23-24)

## 8. Tray, taskbar and notifications (toasts)

- [ ] [P1] System tray icon, with **Quit** in its right-click menu (the only place Quit lives) — Teams: always present — OST: no tray. With "On close, keep the application running" (on by default), Close hides the window, and only a notification click brings it back (`activateRequested`). The user can't reopen or quit OST (ref: SS §7 "System tray icon", §10.1 System; OST: Main.qml:102-107, SettingsView.qml:274-278, backend.rs:2320-2328, desktop/src/main.rs (no tray))
- [ ] [P1] Re-launching brings back the running instance — Teams: single instance — OST: no single-instance guard (no lock, socket or D-Bus), so a second launch starts a second client (ref: SS §10.1 "Open application in background", §7; OST: desktop/src/main.rs:15-46)
- [ ] [P1] Meeting-start notification with **Join** (Ctrl+Shift+J) and **Chat** (Ctrl+Shift+R) — Teams: on by default; bypasses Focus and DND — OST: absent; toasts are raised only for pushed chat messages (ref: SS §7 "Meeting-started toast", CAL §24, §30; OST: backend.rs:2249-2334)
- [ ] [P2] Inline **Reply** in chat toasts — Teams: a text box in the toast; Enter sends — OST: the toast has only a default "Open" action (ref: SS §7 "Inline Reply"; OST: backend.rs:2311-2318)
- [ ] [P2] Notification sound — Teams: plays its own sounds per type (Settings > Sound) — OST: no sound of its own; the system default, if any (ref: SS §10.4 "Sound"; OST: backend.rs:2311-2318)
- [ ] [P2] Toasts for reactions, replies, missed calls and other activity per the Settings per-type choices (Banner and feed / Only show in feed / Off) — OST: toasts only for chat messages and channel @mentions (ref: SS §10.4 "Chats and channels"; OST: backend.rs:946-959)
- [ ] [P2] Taskbar badge: a red number overlay summing Chat, Teams and Activity — OST: absent (ref: SS §7 "Taskbar badge"; OST: absent)
- [ ] [P2] Toast position (four corners), Comfy or Compact preview, **Test notification** — OST: absent; positioning is left to the OS notification daemon (ref: SS §7, §10.4 "Display"; OST: SettingsView.qml:332-350)
- [ ] [P3] Ctrl+Alt+T focuses the toast — OST: absent (ref: SS §7; OST: absent)
- [ ] [P3] Honour Windows DND (opt-in toggle) — OST: absent (ref: SS §7, §10.4; OST: absent)
- [ ] [P3] Taskbar jump list: upcoming meetings, Schedule a meeting, New chat — OST: absent (ref: SS §7 "Taskbar jump list"; OST: absent)
- [ ] [P3] Lobby toast with Ctrl+Shift+Y to admit — OST: absent (ref: SS §7; OST: absent)

## 9. Shell keyboard shortcuts

- [ ] [P2] Activity shortcuts — Teams: Ctrl+Alt+K marks all read; Ctrl+Alt+U (unread), Ctrl+Alt+C (missed calls) and Ctrl+Alt+M (mentions) filter **the Activity feed** when in Activity — OST: Ctrl+Alt+U and Ctrl+Alt+C always switch to Chat and set a chat chip; Ctrl+Alt+K and Ctrl+Alt+M are absent (ref: SS §5, §9 Activity; OST: Main.qml:68-70)
- [ ] [P2] Ctrl+Shift+F filters the *current* list (Activity included) — OST: always jumps to the chat list filter (ref: SS §5 "Text filter"; OST: Main.qml:60)
- [ ] [P2] Missing general and navigation keys — Teams: Ctrl+H, Ctrl+O, Ctrl+Shift+N, Ctrl+L, Ctrl+M, Ctrl+F6 / Ctrl+Shift+F6, F1, F11, Ctrl+= / - / 0, Ctrl+Alt+Shift+R, Ctrl+Alt+Shift+1, Ctrl+Alt+Enter / Ctrl+Shift+Enter, Alt+/ — OST: none of these exist (ref: SS §9 General and Navigation; OST: Main.qml:45-86)
- [ ] [P3] Shortcuts dialog: "Use shortcuts from other apps" (Teams / Slack / Zoom / Combined) with Apply, and the full Teams list — OST: lists only OST's own subset; no layout picker (ref: SS §9; OST: KeyboardShortcuts.qml:18-48)

## 10. Activity feed

- [ ] [P2] **More filters** dropdown (Replies, Reactions, older Apps / Voicemail / Missed calls) — OST: only the three pills (ref: SS §5 "Filter pills"; OST: ActivityView.qml:66-94)
- [ ] [P2] **Tag mentions** filter never matches — Teams: tag-mention notifications — OST: the parser never produces kind `tagMention`; tag mentions fall to the generic branch (ref: SS §5; OST: ActivityView.qml:20, src/api/activity.rs:118-160)
- [ ] [P2] Header ··· > **Notification settings** (deep link to Settings > Notifications and activity) — OST: the menu has Mark all as read only (ref: SS §5 "Header ··· menu"; OST: ActivityView.qml:57-62)
- [ ] [P2] Notification types and glyphs — Teams: @team/@channel, tag mention, reply to a followed thread, made owner, trending, meeting invite / update / cancel / forward, meeting recap ready, app notifications, status-change alert — OST: parses reaction, mention, reply, missed call, voicemail and added-to-team; everything else gets a raw "{who}: {type}" title and a chat glyph (ref: SS §5 "Notification types"; OST: activity.rs:118-160, ActivityView.qml:174-183)
- [ ] [P3] Per-item hover ··· (turn off calendar notifications; mark read/unread) — OST: absent (ref: SS §5 "Per-item hover"; OST: ActivityView.qml:131-251)
- [ ] [P3] 30-day feed retention with paging — OST: loads the newest 50 only, with no "load more" (ref: SS §5 "Retention"; OST: backend.rs:1427, 3049-3060)
- [ ] [P3] Opening a meeting recap, Planner task, or app notification item goes to that target — OST: only items with a thread or person open; others do nothing (ref: SS §5, FA §11 notifications; OST: Main.qml:1635-1644)

## 11. Settings

### 11.0 Structure
- [ ] [P2] Page list — Teams: General, Accounts and orgs, Privacy, Notifications and activity, Appearance and accessibility, Files and links, Chats and channels, Calls, Devices, App permissions, Recognition, Captions and transcripts, About Teams — OST: General, Appearance, Chats and channels, Notifications and activity, Devices, About OST. **Accounts and orgs, Privacy, Files and links, Calls, App permissions, Recognition and Captions and transcripts are absent** (ref: SS §10 page list; OST: SettingsView.qml:12-18, 84-100)
- [ ] [P3] "Find in Settings" searches options — Teams: finds settings — OST: filters page names only (ref: SS §10; OST: SettingsView.qml:33-59)

### 11.1 General
- [ ] [P2] "Open application in background" — OST: absent; only Auto-start and On close keep running (ref: SS §10.1 System; OST: SettingsView.qml:266-279)
- [ ] [P2] Out of Office > **Schedule** — OST: absent (ref: SS §10.1, §3.6; OST: absent)
- [ ] [P2] Spell check on/off — OST: absent (ref: SS §10.1; OST: absent)
- [ ] [P2] Language and regional formats (Follow OS settings, App language, Date format, Time format, Save and restart) — OST: absent; dates are fixed US formats such as "h:mm AP" and "M/d" (ref: SS §10.1; OST: ActivityView.qml:116-120, CalendarView.qml:334)
- [ ] [P3] Time zone section — OST: absent (ref: SS §10.1; OST: absent)
- [ ] [P3] Efficiency mode — OST: absent (ref: SS §10.1; OST: absent)
- [ ] [P3] Translation language and options; Copilot in Chat; Channel recent activity position; keyboard shortcut layout; "Register Teams as the chat app" — OST: absent (ref: SS §10.1; OST: absent)

### 11.2 Accounts and orgs (page absent)
- [ ] [P3] Per-org notification toggles; Manage your account; Accept invitations from other tenants — OST: absent (ref: SS §10.2; OST: absent)

### 11.3 Privacy (page absent)
- [ ] [P2] DND **Manage priority access** — OST: absent (ref: SS §10.3; OST: absent)
- [ ] [P2] **Blocked contacts** > Edit blocked contacts; Block calls with no caller ID — OST: absent (ref: SS §10.3, §10.8; OST: absent)
- [ ] [P2] "Set my status to DND when I'm sharing my screen" (default on) — OST: absent (ref: SS §10.3; OST: absent)
- [ ] [P3] Read receipts sits under Chats and channels in OST (Teams may keep it under Privacy) — verify on winpc (ref: SS §10.3, §10.7; OST: SettingsView.qml:321-329)
- [ ] [P3] Surveys; turn off camera and mic on screen lock; keyboard shortcut to unmute (Ctrl+Space); diagnostic data; optional connected experiences; manage work location; delete Copilot history — OST: absent (ref: SS §10.3; OST: absent)

### 11.4 Notifications and activity
- [ ] [P1] Per-type delivery dropdowns (chat messages, @mentions, tag / everyone mentions, replies, reactions, channel posts) with Banner and feed / Only show in feed / Off, and channel presets — OST: one on/off switch plus "Only mentions" (ref: SS §10.4 "Chats and channels"; OST: SettingsView.qml:332-350)
- [ ] [P2] General: Mute all notifications (except calls and meetings); Show message previews in notifications; Show notifications during calls and meetings; Test notification — OST: absent (ref: SS §10.4 General; OST: SettingsView.qml:332-350)
- [ ] [P2] Sound: four sound toggles and a sound dropdown per type with ▶ preview — OST: absent (ref: SS §10.4 Sound; OST: absent)
- [ ] [P2] Meetings: meeting start notifications, Show meeting join bar, meeting chat notifications (accepted / tentative), Meet now start notifications — OST: absent (ref: SS §10.4 Meetings, CAL §30; OST: absent)
- [ ] [P2] Calendar: invites, updates, cancellations, forwarded — OST: absent (ref: SS §10.4 Calendar; OST: absent)
- [ ] [P2] Per-channel override (channel ··· > Channel notifications: All activity / Off / Custom) and per-thread turn off — OST: absent (ref: SS §10.4 "Per-channel override"; OST: absent)
- [ ] [P3] Display position and preview size; missed-activity e-mail frequency; Presence > Manage notifications; Apps per-app toggles; Windows DND — OST: absent (ref: SS §10.4; OST: absent)

### 11.5 Appearance and accessibility
- [ ] [P2] Chat density Comfy / Compact, and "Show message previews in your chat list" — OST: absent (ref: SS §10.5; OST: SettingsView.qml:282-294)
- [ ] [P2] High contrast (contrast themes) and "Always use dark theme for calls and meetings" — OST: system / light / dark only (ref: SS §10.5 Theme; OST: SettingsView.qml:285-293)
- [ ] [P3] Emoji skin tone; Teams list layout Grid / List; app bar options; sign language view; TTY mode; reduce motion — OST: absent (ref: SS §10.5; OST: absent)

### 11.6 Files and links (page absent)
- [x] [P1] "Always open Word, PowerPoint and Excel files in" Teams / Desktop app / Browser — OST: Desktop app (the desktop's app for Word files, a downloaded copy) and Browser, applied wherever files open; Teams' in-window Office for the web isn't embedded (docs/spec/file-actions.md; OST: Backend::open_file, SettingsView.qml)
- [ ] [P2] Link open preference (Edge / Default browser) — OST: absent (ref: SS §10.6; OST: absent)
- [ ] [P2] Download location; ask where to save each time — OST: absent; fixed `download_dir()` (ref: SS §10.6; OST: backend.rs:927)

### 11.7 Chats and channels
- [ ] [P3] Followed-thread auto-follow behaviour — OST: absent (ref: SS §10.7; OST: SettingsView.qml:297-329)

### 11.8 Calls (page absent)
- [ ] [P2] Call answering rules (Ring me / Forward my calls / Also ring / If unanswered) — OST: absent (ref: SS §10.8; OST: absent)
- [ ] [P2] Manage voicemail (greeting, language, TTS, OOO greeting, answer rules) — OST: absent (ref: SS §10.8; OST: absent)
- [ ] [P2] Ringtones (Calls for you, Forwarded calls); incoming call view Large / Small — OST: absent (ref: SS §10.8; OST: absent)
- [ ] [P3] Delegates; call group / queue notifications; TTY — OST: absent (ref: SS §10.8; OST: absent)

### 11.9 Devices
- [ ] [P2] **Make a test call** — OST: absent (ref: SS §10.9 Audio; OST: SettingsView.qml:353-373)
- [ ] [P2] Camera dropdown with live preview, mirror, brightness, soft focus — OST: absent; camera picked automatically (ref: SS §10.9 Video; OST: SettingsView.qml:353-373, backend.rs:934)
- [ ] [P2] Noise suppression levels — OST: absent (ref: SS §10.9 Audio; OST: absent)
- [ ] [P3] Automatically adjust mic sensitivity; sync device buttons; voice isolation; high-fidelity music; spatial audio; secondary ringer; Manage devices — OST: absent (ref: SS §10.9; OST: absent)

### 11.10–11.13 Captions, Recognition, App permissions, About
- [ ] [P3] Captions and transcripts page (identify me in captions, always show captions) — OST: absent (ref: SS §10.10; OST: absent)
- [ ] [P3] Recognition page (voice and face profiles) — OST: absent (ref: SS §10.11; OST: absent)
- [ ] [P3] App permissions page (per-app camera, mic, location, notifications, links) — OST: absent; the web views deny every permission (ref: SS §10.12; OST: WebApp.qml:187)
- [ ] [P3] About: up-to-date / Update now, privacy and legal links, Early access — OST: version only (ref: SS §10.13; OST: SettingsView.qml:376-385)

## 12. Calendar and scheduling

### 12.1 Data and sync
- [ ] [P1] Event data model — Teams: attendees with response status, responseStatus, categories, sensitivity, recurrence type / series, isCancelled, body, reminder — OST: `$select` reads only id, subject, start, end, isAllDay, location, organizer, isOnlineMeeting, onlineMeeting, showAs, bodyPreview, isOrganizer (ref: CAL §32 "Event fields to model"; OST: src/api/calendar.rs:9-26, 34-37)
- [ ] [P2] Live sync with Outlook — Teams: changes made elsewhere appear — OST: events reload only when the range changes or after your own edit; no polling or delta (ref: CAL §1, §32 `/calendarView/delta`; OST: backend.rs:2394-2425, CalendarView.qml:58-64)

### 12.2 Command bar
- [ ] [P1] **Meet now** with a ▾ holding **Join with an ID** — Teams: primary actions, first in the bar — OST: absent (ref: CAL §2, §24, §25; OST: CalendarView.qml:200-277)
- [ ] [P2] **New** split button (Webinar, Town hall, Virtual appointment, templates) — OST: a plain New button (ref: CAL §2, §17; OST: CalendarView.qml:259-274)
- [ ] [P2] Month label opens a date picker — OST: a static label (ref: CAL §2, §4; OST: CalendarView.qml:226-231)
- [ ] [P2] **Filter** (event types checklist) and **More options** (Calendar settings, Share, Print, Filter) — OST: absent (ref: CAL §2; OST: CalendarView.qml:200-277)
- [ ] [P3] Weather; work-location indicator; calendar search (Alt+Q) — OST: absent (ref: CAL §2; OST: absent)

### 12.3 Views
- [ ] [P1] **Month** view (with the agenda pane, Alt+Shift+5) — OST: Day, Work week and Week only (ref: CAL §3; OST: CalendarView.qml:14, 252-257)
- [ ] [P2] Day view with N days (1–7, Alt+1..7) — OST: a single day only (ref: CAL §3; OST: CalendarView.qml:23)
- [ ] [P2] Work week follows your work days; hours outside work hours shaded — OST: work week is fixed to Mon–Fri with no shading (ref: CAL §3 "Work week", "Hour rows outside working hours"; OST: CalendarView.qml:23, 40-44, 326-341)
- [ ] [P2] Week starts on your first day of week — OST: Week always starts on Sunday and Work week on Monday (ref: CAL §26 Appearance; OST: CalendarView.qml:45-53)
- [ ] [P3] **Time scale** (5/6/10/15/30/60 min), **Saved views**, **Split view** / combined view for several calendars — OST: a fixed 80 px per hour with half-hour lines (ref: CAL §3; OST: CalendarView.qml:21, 312-349)

### 12.4 Event rendering
- [ ] [P1] All-day and multi-day events in an all-day strip — OST: all-day events are **filtered out and never drawn** (ref: CAL §6 "All-day events", "Multi-day events"; OST: CalendarView.qml:363)
- [ ] [P1] Overlapping events side by side within a day — OST: each event takes the full column width, so overlapping events draw over each other (ref: CAL §6 "Overlapping events"; OST: CalendarView.qml:369-374)
- [ ] [P1] Events that cross midnight or span days — OST: an event is placed only in its start day's column; its height runs past midnight off the grid (ref: CAL §6 "Multi-day events"; OST: CalendarView.qml:369-374)
- [ ] [P2] Show-as styling (Free, Tentative hatched, Busy, OOF, Working elsewhere) — OST: `show_as` is loaded, but every event is the same brand tint (ref: CAL §6 "Show-as states"; OST: CalendarView.qml:376-377, calendar.rs:20-21)
- [ ] [P2] RSVP state styling (not responded, declined, following) — OST: absent (ref: CAL §6 "RSVP state"; OST: CalendarView.qml:364-387)
- [ ] [P2] Cancelled events ("Canceled:" label or strike-through) — OST: absent (ref: CAL §6; OST: calendar.rs:34-37)
- [ ] [P2] Category colours — OST: absent (ref: CAL §6, §14; OST: absent)
- [ ] [P2] Inline **Join** on Teams meeting tiles near the start time — OST: Join only in the peek card (ref: CAL §6, §24; OST: CalendarView.qml:364-387)
- [ ] [P3] Private lock icon; recurring and exception icons; webinar / town hall / channel-meeting badges — OST: absent (ref: CAL §6; OST: absent)

### 12.5 Interaction on the grid
- [ ] [P2] Drag an event to reschedule (with an availability check) — OST: absent (ref: CAL §6, §23; OST: CalendarView.qml:364-387)
- [ ] [P2] Quick create on clicking a slot, with Expand to the full form — OST: a click opens the one simple form (ref: CAL §7; OST: CalendarView.qml:351-359)
- [ ] [P2] Right-click menu (Categorize, Show as, Private, Duplicate, Delete / Cancel, Join) — OST: absent (ref: CAL §7; OST: absent)
- [ ] [P2] Event keyboard: Enter opens, Delete deletes, Ctrl+J joins, Tab between events — OST: absent (ref: CAL §7, §31; OST: absent)

### 12.6 Peek card and the View event page
- [ ] [P1] **RSVP** (Accept / Tentative / Decline / Follow; this event or the whole series; RSVP with note) — OST: absent; no accept / tentativelyAccept / decline calls (ref: CAL §21, §32 RSVP; OST: CalendarView.qml:408-510, src/api/calendar.rs)
- [ ] [P1] **View event** full details page (attendee tracking, full body, Chat, Recap, Attendance, Options, Copy join link, Send update) — OST: the peek card only, with a 4-line description preview (ref: CAL §20; OST: CalendarView.qml:408-510)
- [ ] [P2] Past-meeting **Recap** and **Chat** in the peek — OST: Chat only (ref: CAL §7 peek; OST: CalendarView.qml:448-459)
- [ ] [P2] Attendee list with response per person — OST: absent (ref: CAL §20 "Tracking"; OST: calendar.rs:34-37)
- [ ] [P2] Show meeting info (ID, passcode, dial-in) — OST: absent (ref: CAL §20; OST: absent)
- [ ] [P3] Attendance report tab with CSV download — OST: absent (ref: CAL §20; OST: absent)

### 12.7 New meeting form
- [ ] [P1] Required attendees via a **people picker** (directory search) — OST: a free-text box of comma-separated e-mail addresses (ref: CAL §8 "Required attendees"; OST: CalendarView.qml:607)
- [ ] [P1] Start date and time, end date and time pickers — OST: the date is fixed to the clicked slot or now (no date picker); start in 30-minute steps; length limited to 15 min, 30 min, 1 h or 2 h (ref: CAL §8; OST: CalendarView.qml:609-629)
- [ ] [P1] Details / body rich-text editor — OST: absent (ref: CAL §8 "Rich-text details"; OST: CalendarView.qml:591-664)
- [ ] [P1] Location "Search for a room or location" with room suggestions — OST: absent (ref: CAL §8, §11; OST: CalendarView.qml:591-664)
- [ ] [P1] **Repeat** (presets plus custom recurrence and range) — OST: absent (ref: CAL §9; OST: CalendarView.qml:591-664, calendar.rs:50-69)
- [ ] [P1] **Send** vs **Save** — Teams: Save for an appointment, Send for invites, **Send update** on edit; Ctrl+S, Ctrl+Enter, Esc — OST: one "Save" button for all, no keyboard (ref: CAL §8 "Save actions"; OST: CalendarView.qml:643-663)
- [ ] [P1] Editing attendees and other fields of an existing meeting — OST: the edit form changes only the title and time; the attendee field is hidden and attendees are removed from the PATCH (ref: CAL §23 "Edit as organizer"; OST: CalendarView.qml:577-586, 607, calendar.rs:71-89)
- [ ] [P2] Optional attendees (Response options > Add optional attendees) — OST: absent (ref: CAL §8, §13; OST: absent)
- [ ] [P2] **All day** toggle — OST: absent (ref: CAL §8; OST: absent)
- [ ] [P2] **Scheduler** (free/busy grid via `getSchedule`) and suggested times (`findMeetingTimes`, Alt+Shift+S) — OST: absent (ref: CAL §8, §10, §32; OST: absent)
- [ ] [P2] **Add channel** (channel meeting) — OST: absent (ref: CAL §8, §12; OST: absent)
- [ ] [P2] **Show as**, **Remind me**, **Category**, Private — OST: absent (ref: CAL §8, §14; OST: absent)
- [ ] [P2] **Meeting options** from the form (lobby, presenters, chat, recording …) — OST: absent (ref: CAL §8, §15; OST: absent)
- [ ] [P2] Schedule from a chat (pre-filled with the chat's members) — OST: absent (ref: CAL §8 "Schedule from chat"; OST: absent)
- [ ] [P3] Time zone per event; target calendar picker; attachments; Add an agenda (Loop notes); Response options (Request responses, Allow forwarding, Hide attendee list) — OST: absent (ref: CAL §8, §13; OST: absent)

### 12.8 Edit, cancel, series
- [ ] [P2] Cancel a meeting with an optional message (`/cancel`) vs delete an appointment — OST: always `DELETE /me/events/{id}`, with no message (ref: CAL §23, §32 organizer actions; OST: calendar.rs:91-98, CalendarView.qml:491-508)
- [ ] [P2] Series scope prompt (This event / This and following / All events) — OST: absent (ref: CAL §23; OST: absent)
- [ ] [P2] Attendee's cancelled meeting: "Remove from calendar" — OST: absent (ref: CAL §23; OST: absent)
- [ ] [P3] Forward (Ctrl+Alt+F); Duplicate event; propose a new time — OST: absent (ref: CAL §22, §23; OST: absent)

### 12.9 Navigation pane and multiple calendars
- [ ] [P2] Other calendars: colleagues' calendars, Birthdays, Holidays, calendar groups with More options (New group, Move to, Delete), per-calendar colours — OST: one "Calendar" checkbox (ref: CAL §5; OST: CalendarView.qml:163-183)
- [ ] [P3] F6 / Ctrl+Shift+Tab region navigation — OST: absent (ref: CAL §5; OST: absent)

### 12.10 Join, Meet now and the join bar
- [ ] [P1] Live meeting **join bar** (title, Join, count of other live meetings, View meetings) — OST: absent (ref: CAL §24 "Live meeting join bar"; OST: absent)
- [ ] [P2] Meet now flyout (meeting name, Get a link to share, Start meeting) — OST: absent in Calendar (ref: CAL §25; OST: CalendarView.qml:200-277)
- [ ] [P2] Join with an ID (meeting ID and passcode) — OST: absent (ref: CAL §24; OST: absent)
- [ ] [P3] Join from a non-Teams link opens the browser — Teams: parses both invite formats — OST: only `/l/meetup-join/` links go to pre-join; others open externally (ref: CAL §24 "Invite link format"; OST: Main.qml:1474-1478)

### 12.11 Calendar settings, sharing, printing, work plans, channel calendars
- [ ] [P2] Calendar settings dialog (Work hours and location, Appearance, Time zones, Events and invitations, Weather) — OST: absent (ref: CAL §26; OST: absent)
- [ ] [P2] Share your calendar (permissions view-busy … delegate; org default) — OST: absent (ref: CAL §27; OST: absent)
- [ ] [P3] Print (Ctrl+P) with its options — OST: absent (ref: CAL §27; OST: absent)
- [ ] [P3] Work plans: Add work location, day location icons, who's in the building — OST: absent (ref: CAL §28; OST: absent)
- [ ] [P3] Channel calendar tab (filtered group calendar; Add to calendar) — OST: absent (ref: CAL §29; OST: absent)
- [ ] [P3] Webinar, town hall and virtual appointment flows (`/solutions/virtualEvents`), and personal templates — OST: absent (ref: CAL §17-19; OST: absent)
- [ ] [P3] Event reminders (default 15 min) as a toast with snooze and dismiss — OST: absent (ref: CAL §14, §30; OST: absent)

### 12.12 Calendar shortcuts
- [ ] [P2] Alt+Shift+1–4 views; Ctrl+Alt+Left/Right period; Alt+Up/Down week; Alt+PageUp/PageDown month; Alt+Shift+Y or Home today; Alt+F1 pane; Ctrl+N new event — OST: only Alt+N exists (ref: CAL §31, SS §9 Calendar; OST: Main.qml:78)

## 13. Files

### 13.1 OneDrive app
- [x] [P1] Per-item **Share** (share dialog, §13.4) — OST: Share in the item's menu (FileActions.qml) and the row's hover ···, Share and favorite buttons, with Teams' Modified wording, Sharing, New mark and Activity column from SharePoint's rows (ref: FA §1 "Per-item hover Share", §4; docs/spec/onedrive-rows.md; OST: OneDriveView.qml, src/api/list_rows.rs)
- [x] [P1] **More actions**: Rename, Move to, Copy to, Copy link, Open in (Teams / Desktop app / Browser), Open in OneDrive — OST: Teams' OneDrive context menu (right-click / ···) with Open ▸, Share, Copy link, Manage access, Delete, favorites, Download, Rename, Open in OneDrive, Move to, Copy to, Duplicate; Preview, Add shortcut, Version history and Details are follow-ups (ref: FA §1 "Per-item More actions"; docs/spec/file-actions.md; OST: FileActions.qml)
- [ ] [P1] Opening a file inside Teams (viewer with the Office ribbon) — OST: every file opens `web_url` in the external browser (ref: FA §5; OST: OneDriveView.qml:369-372)
- [ ] [P2] Search and filter inside OneDrive — OST: absent (ref: FA §1 "Search and filter"; OST: OneDriveView.qml:84-150)
- [ ] [P2] **Create or upload** > new Word / Excel / PowerPoint file by name — OST: Folder and Files upload only (ref: FA §1 "Create or upload"; OST: OneDriveView.qml:107-116)
- [x] [P2] Multi-select (circle checks) with bulk Move / Copy / Delete — OST: selection circles, Ctrl+click and select all, and Teams' selection bar (Open, Share, Copy link, Delete, ···; several: Delete, Add to favorites, Download, Duplicate, Move to, Copy to in one copy job); Sort, view switch and Details done (TASK-0120), the zip download is TASK-0116 (ref: FA §1 "Multi-select"; docs/spec/onedrive-rows.md; OST: OneDriveView.qml)
- [ ] [P2] **Quick access** (channel libraries you opened) and **More places…** — OST: static hint text. OST adds a "Libraries" view that Teams doesn't list (ref: FA §1 "Quick access"; OST: OneDriveView.qml:125-126, 141-148)
- [ ] [P2] Drag-and-drop upload onto the list; upload progress — OST: absent (ref: FA §3 "Upload", §2 "Large-file upload"; OST: OneDriveView.qml:424-430)
- [x] [P3] Sort by column — OST: Sort ▾ and sortable column headers as Teams, plus List / Compact List / Tiles (ref: FA §1; docs/spec/onedrive-rows.md "Sort and views"; OST: OneDriveView.qml)
- [ ] [P3] Open OneDrive in a new window — OST: absent (ref: FA §1; OST: absent)

### 13.2 Chat Shared tab and attachments
- [ ] [P2] Chat **Shared** tab with **Recent / Files / Links** pills and Copy link — OST: two lists built from the messages loaded so far (50), so older files are missing; no pills and no Copy link (ref: FA §2 "Chat Shared tab"; OST: Conversation.qml:853-927, backend.rs:974)
- [ ] [P2] Attachment **More attachment options** (Open in browser, Download, Copy link, Open in desktop app) — OST: tap opens in the browser; a download button (ref: FA §2; OST: Conversation.qml:890-901)
- [ ] [P2] Inline attachment previews (image, PDF, video) and the Preview button — OST: absent in the Shared tab (generic file icon) (ref: FA §2 "Automatic attachment previews"; OST: Conversation.qml:884)
- [ ] [P3] Pre-send permission check with Give access / Update access — OST: absent (ref: FA §2; OST: src/api/files.rs:99-375)

### 13.3 Channel Shared tab (SharePoint library)
- [ ] [P2] **In Post** (files and links from posts) / **In library** split — OST: library only (ref: FA §3 "Channel Shared tab"; OST: ChannelFiles.qml:5-8)
- [ ] [P2] **New**: Word, Excel, PowerPoint, OneNote notebook, Visio, Forms for Excel, Link — OST: Folder and Files upload only (ref: FA §3 "Toolbar New"; OST: ChannelFiles.qml:97-102)
- [x] [P2] Row actions: Rename, Move to, Copy to, Open in, Download — OST: the same Files menu as the OneDrive app (ref: FA §3 "Per-item More actions"; docs/spec/file-actions.md; OST: FileActions.qml)
- [ ] [P2] **Share** opens the share dialog — OST: opens the folder's web URL in the browser (ref: FA §3, §4; OST: ChannelFiles.qml:81)
- [ ] [P3] More commands > **Sync**, **Open in SharePoint**; upload folder or template; drag and drop — OST: absent (ref: FA §3; OST: ChannelFiles.qml:78-104)

### 13.4 Share dialog and link settings
- [ ] [P1] Share dialog: Copy link, link settings (gear), recipients, permission (Can edit / Can review / Can view / Can't download), message, Send — OST: absent everywhere (ref: FA §4; OST: absent)
- [ ] [P2] Link audience (Org / People you choose / Anyone / Existing access), Block download, expiration, password; **Manage Access** — OST: absent (ref: FA §4; OST: absent)

### 13.5 Viewing, editing, versions
- [ ] [P1] In-Teams file viewer header (Comments, Catch up, Editing / Reviewer, Share, Close back to Teams) — OST: absent (ref: FA §5 "Header actions"; OST: absent)
- [x] [P2] Open in desktop app (Office URI schemes `ms-word:ofe|u|…`) — OST: Linux has no Office URI handlers; OST opens a downloaded copy in the desktop's app for the file (Files menu ▸ Open ▸ Open in app, and the Desktop app setting) (ref: FA §5 "API, open in desktop app"; OST: FileActions.qml, Backend::open_file)
- [ ] [P2] Version history with Restore — OST: absent (ref: FA §6; OST: absent)
- [ ] [P3] Tab conversation beside a file tab; file as a tab — OST: absent (ref: FA §3, §5; OST: absent)

## 14. Notes (OneNote)

### 14.1 Channel Notes tab
- [ ] [P1] Channel **Notes** tab — Teams: the channel's section of the team notebook, with a OneNote editor (notebook picker, ribbon, page list with + Add page, title and date line, rich body) — OST: placeholder text "Notes isn't available in OST yet." (ref: NT "Native implementation requirements", FA §9, WD Notes tab; OST: Conversation.qml:940-950)
- [ ] [P1] Provisioning: create the channel-named section (and "<Team> Notebook" if missing); show "Please wait...the Notes tab will be ready soon." meanwhile — OST: absent (ref: NT "Backing data", "Provision"; OST: absent)
- [ ] [P2] Group notebooks — Teams: `/groups/{id}/onenote/...` — OST: reads `/me/onenote/...` only, so team notebooks are not reachable (ref: FA §9 API, NT "Backing data"; OST: src/api/onenote.rs:64-123)
- [ ] [P2] Notes tab menu actions — Teams: Open tab in new window, Expand tab, App permissions, each with an effect — OST: the items are listed, but popOut, expandTab and devicePermissions have no handler and do nothing (ref: CT "Menu contents", "Verified on the live client"; OST: Conversation.qml:972-981, src/api/tabs.rs:152-160)

### 14.2 OneNote personal app
- [ ] [P1] Editing existing pages — Teams: full editing — OST: pages are read-only rich text; new pages are plain text; no PATCH (ref: FA §9 "Update a page", NT "Editor"; OST: OneNoteView.qml:177-258, onenote.rs (no update))
- [ ] [P2] Page formatting (bold, lists, tables, tags), images and ink shown — OST: images, objects and styles are stripped from page HTML (ref: FA §9 API; OST: onenote.rs:125-139)
- [ ] [P2] Page order as in OneNote (subpages, manual order) — OST: pages sorted by last modified (ref: FA §9, NT "Editor (page list, ordering)"; OST: onenote.rs:119-122)
- [ ] [P2] Section groups — OST: only top-level sections are listed (ref: FA §9 "list notebooks, section groups, sections"; OST: onenote.rs:81-94)
- [ ] [P2] Search in notebooks — OST: absent (ref: FA §9 "Notes tab capabilities: search"; OST: absent)
- [ ] [P3] Notebook hover More options > Open (web) / **Open in desktop** — OST: one "Open in OneNote" (browser) button (ref: FA §9 "OneNote personal app"; OST: OneNoteView.qml:119-132)
- [ ] [P3] Page paging (>100) — OST: `$top=100`, with no next link (ref: FA §9 "20 by default, max 100"; OST: onenote.rs:100)

## 15. Channel Page (Loop) and chat Notes

- [ ] [P1] Channel **Page** tab content — Teams: the Loop page with a header row (Loop icon and name, Shared locations, Copy component, See who has access), the canvas, and the insert row — OST: the tab is listed (kind ChannelPage), but its content area is **blank**: `webTab` is hard-wired to `null` and no pane matches "Page". The web-view Page renderer exists only for `--loop-test` (ref: FA §8, WD "Page tab"; OST: Conversation.qml:55-57, 932-938, Main.qml:717-749, src/api/tabs.rs:18,120)
- [ ] [P2] **Add a tab** menu: New page / Existing page (paste link > Add page) — OST: absent (ref: FA §8, WD "+ (Add a tab)"; OST: absent)
- [ ] [P2] Page tab menu: popOutChannelPage — OST: no handler (ref: CT "Verified on the live client" Page row; OST: Conversation.qml:972-981)
- [ ] [P2] Group-chat **Notes** tab (Chat Page, `com.microsoft.chattabs.chatnotes`) — OST: placeholder text (ref: CT "Tab types"; WD group chat header tabs; OST: Conversation.qml:51, 940-950)
- [ ] [P2] Loop components in chat and channel messages (insert, live edit, Copy component) — OST: none (out of scope here; see FA §7) (ref: FA §7; OST: absent)
- [ ] [P3] Loop workspace tab — OST: absent (ref: FA §8; OST: absent)

## 16. Whiteboard

- [ ] [P2] Whiteboard app — Teams: board gallery and a native canvas (pens, sticky notes, shapes, templates, Loop components) — OST: an embedded web view of whiteboard.cloud.microsoft (a gap by the project's rule) (ref: FA §10; OST: Main.qml:1493-1510, WebApp.qml)
- [ ] [P3] Whiteboard tab in chats and channels; meeting Share tray > Whiteboard; Whiteboard tab in the meeting chat afterwards — OST: absent (ref: FA §10 "Entry points"; OST: absent)

## 17. Clipchamp and video clips

- [ ] [P2] **Record a video clip** (camera, screen up to 1 min, audio; trim; Send) from Actions and apps — OST: absent (ref: FA §18; OST: absent)
- [ ] [P3] Clipchamp app — Teams: video hub and editor — OST: an embedded web view of app.clipchamp.com (a gap by the project's rule) (ref: FA §18; OST: Main.qml:1498, WebApp.qml)

## 18. Planner / To Do

- [ ] [P1] Task details — Teams: open a task to edit title, notes, checklist, due and start dates, priority, progress, assignees, labels, bucket — OST: rows can only be completed; no task opens (ref: FA §11 plan views; Graph plannerTaskDetails / todoTask; OST: PlannerView.qml:263-293)
- [ ] [P2] **My Day** — Teams: auto-includes due-today tasks plus manual adds, reorderable, clears nightly — OST: a client-side filter of due-today tasks (ref: FA §11 "My Day"; OST: PlannerView.qml:224-225)
- [ ] [P2] **My Plans** includes To Do lists, personal plans, Loop and meeting-notes plans, with filters Recent / Shared / Personal / Pinned / My teams / Recommended and keyword — OST: lists your teams' basic plans only, with no filters (ref: FA §11 "My Plans"; OST: PlannerView.qml:186-216)
- [ ] [P2] Create a personal plan (no group) or from a template — OST: a team is required; no templates (ref: FA §11 "Create a plan"; OST: PlannerView.qml:353-409)
- [ ] [P2] Delete a task / delete a plan — OST: `remove` and `deletePlan` signals exist but nothing in the UI raises them (ref: FA §11 API; OST: PlannerView.qml:20-23)
- [ ] [P2] Board drag between buckets; add a task in a bucket; plan views Schedule and Charts — OST: a read-only board; Grid and Board only (ref: FA §11 "Plan views"; OST: PlannerView.qml:297-336)
- [ ] [P3] Pinned plans — OST: static text "Pinned items will appear here." (ref: FA §11 My Plans filter Pinned; OST: PlannerView.qml:111-114)
- [ ] [P3] Planner channel tab — OST: absent (ref: FA §11 "Planner channel tab"; OST: absent)

## 19. Store / apps

- [ ] [P2] **Add** installs the app (personal / team / chat / meeting) — Teams: Add, then configure — OST: Add opens teams.microsoft.com in the browser (ref: FA §20 "Add targets", API installedApps; OST: StoreView.qml:159-166)
- [ ] [P2] Categories, **Filter** (Ready to add / Requires approval), **Request** for blocked apps — OST: absent (ref: FA §20; OST: StoreView.qml:39-127)
- [ ] [P2] App detail page: overview, reviews, details, where it appears (capabilities), permissions — OST: a dialog with name, short text and description (ref: FA §20, §25; OST: StoreView.qml:137-185)
- [ ] [P2] Installed apps shown and openable; personal-app tabs rendered (or opened via `websiteUrl`) — OST: only Planner, OneNote and People open natively (ref: FA §20, §21 API; OST: StoreView.qml:21)
- [ ] [P3] Compose-box apps (Actions and apps, pin to compose bar); private-channel app management — OST: absent (ref: FA §20; OST: absent)

## 20. Help and diagnostics

- [ ] [P2] Help app: Get help / Topics, Video training, **What's new**, Give feedback — OST: an embedded web view of support.microsoft.com/teams; no F1 (ref: FA §19, SS §13; OST: Main.qml:1499, AppRail.qml:118)
- [ ] [P3] Report a problem (Ctrl+Alt+Shift+R); download diagnostic logs (Ctrl+Alt+Shift+1) — OST: absent (ref: SS §13; OST: absent)

## 21. Multiple accounts and connectivity

- [ ] [P2] Offline / Reconnecting banner at the top of the main pane, with sends queued and retried — OST: a red error strip of `statusText` at the bottom; no offline state (ref: SS §12; OST: Main.qml:1708-1720)
- [ ] [P3] Several accounts and guest orgs: switch, pin up to 3, cross-org activity panel, child windows — OST: absent (ref: SS §11; OST: absent)

---

## 22. Native path per embedded experience

| Experience | Where OST stands | Native path (per FA) |
|---|---|---|
| **Notes / OneNote** (channel Notes tab, OneNote app) | App: Graph OneNote, read and create only (`/me` only). Channel tab: placeholder (Conversation.qml:940-950) | **Published.** Graph OneNote API, delegated only (FA §9 API):<br>- list group notebooks, sections and pages under `/groups/{id}/onenote`;<br>- provision the channel section with `POST …/notebooks/{nb}/sections`;<br>- `GET pages/{id}/content?includeIDs=true`;<br>- create with `POST sections/{id}/pages` (multipart HTML);<br>- edit with `PATCH pages/{id}/content` (append, insert, prepend or replace on `data-id`; tables replaced whole);<br>- `DELETE`.<br>The HTML model is lossy, so expect partial-fidelity editing (layout and ink). |
| **Channel Page / Loop** (and chat Notes, Loop components) | Blank tab (Conversation.qml:57); web view only in `--loop-test` | **None published** (FA §7, §8 API):<br>- `.loop` files are reachable as driveItems (list, share, version, delete), but their Fluid content format is undocumented;<br>- `@fluidframework/odsp-client` opens only an app's own containers.<br>Native fallback, which is Teams' own behaviour with Loop disabled: render the page as a link card (name and icon from driveItem metadata) that opens in the browser. Tab pin, rename and remove go through the middle tier's pinned tabs or Graph `teamsTab`. A real native editor would need the unpublished Fluid / Loop protocol. |
| **Whiteboard** | Embedded web view (Main.qml:1497) | **None published** (FA §10 API):<br>- no Graph Whiteboard resource;<br>- `.whiteboard` files are driveItems with an undocumented format;<br>- WhiteboardAdmin PowerShell is admin-only tooling.<br>Native fallback: list boards as driveItems and open the board's web URL externally. |
| **Clipchamp** | Embedded web view (Main.qml:1498) | **Editor: none published.** Clips: **published** (FA §18 API): record natively, upload with Graph upload sessions, post as a `reference` chatMessageAttachment. Videos are ordinary driveItems (stream or download). Editing: open the web URL externally. |
| **Help** | Embedded web view (Main.qml:1499) | **None published** (FA §19). Content is support.microsoft.com pages: link out, or build a native shell of topic links that open in the browser. |

Also relevant, for files viewed or edited "in Teams" (FA §5–6):
- **viewing**: `/content?format=pdf|jpg`, files up to 2 MB only; `driveItem: preview` is a web URL;
- **editing in Teams**: none published (WOPI is partner-only); open in the desktop app with the Office URI schemes, or open `webUrl` in the browser;
- **co-authoring**: none published;
- **versions**: `listVersions` and `restore` are published.

## 23. Gap counts

| Priority | Count |
|---|---|
| P1 | 37 |
| P2 | 133 |
| P3 | 66 |
| **Total** | **236** |

## 24. Ordered build plan

Ordered by user impact first, then by dependency (shared building blocks before the features that use them).

1. **Shell survival**
   - system tray (Open, status, Quit);
   - single-instance guard: a second launch raises the first;
   - only then keep "On close, keep running" on by default.

   This fixes the unrecoverable hidden window (§8).
2. **Presence correctness**
   - publish the endpoint's activity: Away on idle, lock or minimise; In a call / In a meeting / Presenting;
   - DND suppresses toasts;
   - set status message and durations (`setStatusMessage`, `expirationDuration`) (§4, §5).
3. **Calendar rendering**
   - extend `CalendarEvent`: attendees, responseStatus, categories, sensitivity, type / seriesMasterId, isCancelled, body;
   - all-day strip; overlap layout; multi-day spanning;
   - show-as, RSVP and cancelled styling;
   - Month view (§12.1, §12.3, §12.4).
4. **Calendar actions**
   - RSVP (accept, tentative, decline with note, series scope);
   - View event page with the attendee list;
   - cancel with a message;
   - meeting-start toast and live join bar;
   - Meet now / Join with an ID (§12.6, §12.8, §12.10, §8).
5. **New meeting form, rebuilt**
   - people picker (reusing the directory search);
   - date, time and end pickers; all day;
   - rich body (reusing the composer editor);
   - location and rooms; Repeat;
   - Send / Save / Send update; full edit; Scheduler (`getSchedule`) (§12.7).
6. **Search**
   - results page backed by Graph `POST /search/query`: messages, people, files, chats, channels;
   - channels in typeahead; Ctrl+G picker; slash commands (§2).
7. **Files core**
   - shared share dialog (createLink / invite / permissions);
   - item actions (rename, move, copy, copy link, open in desktop via URI schemes);
   - Files and links setting; native viewer for images and PDF (convert-to-PDF for Office files ≤ 2 MB);
   - search; multi-select; Create Word/Excel/PPT;
   - channel In Post / In library; chat Shared pills built from Graph rather than loaded messages (§13).
8. **Notes tab (native)**
   - group notebooks and the channel section provisioning flow;
   - an editor over PATCH (shared with the OneNote app, which then gains editing, section groups and page order);
   - Notes tab menu actions (§14).
9. **Notifications and Settings depth**
   - per-type delivery dropdowns, sounds, test notification, meeting and calendar notifications;
   - toast inline reply; taskbar badge;
   - Privacy page (priority access, blocked contacts, DND-while-sharing);
   - Calls page (forwarding, voicemail, ringtones);
   - Devices (camera preview, test call) (§8, §11).
10. **Rail and windows**
    - right-click Pin / Unpin / Open in new window; persisted pinned apps and order;
    - Ctrl+N follows the order; Show app names;
    - pop-out chat windows (Ctrl+O, Ctrl+Shift+N); zoom; history menu (Ctrl+H) (§1, §6, §7).
11. **Activity**
    - tag-mention parsing; full notification types and glyphs;
    - More filters; Notification settings link; Activity-scoped shortcuts; paging (§10).
12. **Planner**
    - task details editor; To Do-backed My Day; My Plans with To Do lists and filters;
    - personal plans; delete task / plan UI; board drag (§18).
13. **Embedded apps without a published API**
    - Page / Loop, chat Notes, Whiteboard and Clipchamp: replace the web views with native link cards that open in the browser, per §22;
    - native video-clip recording;
    - Help as native links.

    Revisit only if Microsoft publishes a Loop or Whiteboard API (§15–17, §20).
14. **Store, calendar extras, rare settings**
    - Store install via `installedApps`; categories, request flow;
    - calendar settings, sharing, print, other calendars, work plans, webinars and town halls;
    - language and regional formats; accounts and orgs; multi-account; Recognition; Captions; About / update (§11, §12.11, §19, §21).
