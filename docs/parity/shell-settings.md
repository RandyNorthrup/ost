# Teams desktop (Windows, new Teams 2025–2026) parity checklist: App shell, Activity, Search, Presence, Settings, Notifications, Accounts

Scope: functional inventory for a native reimplementation. Behaviour is taken from Microsoft Support / Microsoft Learn / Microsoft 365 Message Center (MC) posts, cited per group. Items marked **[unverified]** come from third-party or university guides only, or are inferred, and should be checked against real Teams on `winpc` before implementing pixel-exact.

Research note: support.microsoft.com rate-limited fetches part-way through and the session's web-search budget ran out, so a few pages (Privacy page wording, Settings and more menu, tray menu, zoom article, offline banners, Copilot app) could not be checked against first-party text. Those items are flagged.

---

## 1. Title bar

- [ ] Back / Forward arrows: sit to the left of the search box. One click steps back or forward one location. Shortcuts: Alt+Left and Alt+Right.
  Source: https://support.microsoft.com/en-US/teams/notifications-settings/use-history-to-return-to-recent-places-in-microsoft-teams ; https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] History menu: hovering over Back or Forward opens a list of up to **12** recently visited places (chats, channels, files, tabs, apps). Ctrl+H opens it from the keyboard. Desktop only.
  Source: https://support.microsoft.com/en-US/teams/notifications-settings/use-history-to-return-to-recent-places-in-microsoft-teams
- [ ] Search box: centred in the title bar. Ctrl+E focuses it. Results start appearing as you type. Enter opens the full results page (see §6).
  Source: https://support.microsoft.com/office/search-for-messages-and-more-in-microsoft-teams-4a351520-33f4-42ab-a5ee-5fc0ab88b263
- [ ] Slash commands in the search box. Typing "/" shows a command list. Documented commands: /available, /busy, /dnd, /brb, /away, /offline, /goto, /unread, /mentions.
  Source: https://support.microsoft.com/office/ce36ed14-6bc9-4775-a33e-6629ba4ff78e ; https://learn.microsoft.com/en-us/training/modules/collaborate-teams-channels-microsoft-teams/7-manage-notifications
- [ ] Ctrl+G opens "Go to a specific chat or channel" (the /goto picker).
  Source: https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] **Settings and more** (···) button, left of the profile picture. It opens a menu that includes **Settings** (Ctrl+,), **Keyboard shortcuts** (Ctrl+.), Zoom controls, and **Help** (Help > What's new and other items; F1 opens Help). Other entries such as Download mobile app, Give feedback and Report a problem (Ctrl+Alt+Shift+R) **[unverified as menu items]**.
  Source: https://support.microsoft.com/topic/ee332652-cefc-4b68-94d9-a8e1c391ac47 ; https://learn.microsoft.com/en-us/microsoftteams/teams-client-update ; https://td.usnh.edu/TDClient/60/Portal/KB/ArticleDet?ID=2192
- [ ] **Restart** button next to the ··· button. It appears once an update has been staged and restarts Teams to apply it. If the user does nothing, Windows clients apply the update automatically when the app is idle.
  Source: https://learn.microsoft.com/en-us/microsoftteams/teams-client-update
- [ ] Profile picture button at the far right, carrying a presence badge. It opens the account manager / profile menu (see §2).
  Source: https://support.microsoft.com/office/ce36ed14-6bc9-4775-a33e-6629ba4ff78e
- [ ] Window controls (minimise, maximise, close) are custom-drawn in the title bar. Close obeys the "On close, keep the application running" setting (see §10.1). **[unverified drawing details]**
  Source: https://help.stalbansdiocese.org/teams-training-start-automatically

## 2. Profile / account manager menu

- [ ] Header shows the user's name, organisation, and avatar. "View account" opens myaccount.microsoft.com. Clicking the avatar changes the profile picture. "View your M365 profile" shows name and name pronunciation. **[university source]**
  Source: https://td.usnh.edu/TDClient/60/Portal/KB/ArticleDet?ID=2192
- [ ] Current status row. Selecting it opens the status list (see §3).
  Source: https://support.microsoft.com/office/ce36ed14-6bc9-4775-a33e-6629ba4ff78e
- [ ] **Duration** item under the status list. Pick a status, then a "Reset status after" preset or **Custom** (date and time), then **Done**. Available for every status except Available.
  Source: https://support.microsoft.com/office/ce36ed14-6bc9-4775-a33e-6629ba4ff78e
- [ ] **Reset status** item: ends a manual or timed status and returns to automatic presence (activity, calendar, device state).
  Source: https://support.microsoft.com/office/ce36ed14-6bc9-4775-a33e-6629ba4ff78e
- [ ] **Set status message** dialog:
  - free-text message;
  - checkbox "Show when people message me": shows the note to people who message or @mention you, above their compose box and on your profile card;
  - "Clear status message after" dropdown. Presets include Never, Today and This week; the full list is **[unverified]**;
  - **Done** button;
  - **Schedule out of office** link (see §3.6).
  Source: https://support.microsoft.com/en-us/topic/22e02023-3840-40c7-b701-6676821aeab3 ; https://support.microsoft.com/en-au/office/why-does-teams-say-i-m-away-when-i-m-not-7b17174d-ca33-436b-b153-0da89a8335a0
- [ ] **Set work location**: menu entry with sub-options In the office (with "Add a building", limited to the org's buildings) and Remote, plus Clear. The choice applies to the rest of today's work hours and syncs with Outlook. Others see it on the profile card and hover card.
  Source: https://support.microsoft.com/en-us/topic/6c14a0f5-3cd6-427d-b1d2-aa0365aebf88 ; https://learn.microsoft.com/microsoft-365/places/understanding-work-location
- [ ] Account list: other signed-in accounts and guest orgs, each with an unread/missed badge. Selecting one switches account; each has a **Pin** icon (see §11).
  Source: https://support.microsoft.com/office/manage-accounts-and-organizations-in-microsoft-teams-7b221128-6643-465c-a317-679e48cd2ce9
- [ ] **Add another account**: choose an account used before, or "Create or use another account".
  Source: https://support.microsoft.com/office/manage-accounts-and-organizations-in-microsoft-teams-7b221128-6643-465c-a317-679e48cd2ce9
- [ ] **Sign out**.
  Source: https://td.usnh.edu/TDClient/60/Portal/KB/ArticleDet?ID=2192

## 3. Presence and status semantics

### 3.1 Statuses the user can set (in menu order)
- [ ] Available: green solid check.
- [ ] Busy: red solid dot. Notifications are still delivered.
- [ ] Do not disturb: red dot with a white bar. Banners are suppressed and calls go to voicemail, except for priority-access contacts.
- [ ] Be right back: yellow clock. Never set automatically.
- [ ] Appear away: yellow clock.
- [ ] Appear offline: grey circle with an x. Message notifications are still received.
  Source: https://support.microsoft.com/office/ce36ed14-6bc9-4775-a33e-6629ba4ff78e ; https://learn.microsoft.com/en-us/microsoftteams/presence-admins

### 3.2 States the app sets
- [ ] Available, Out of office: open green check. Shown while automatic replies are on and the user is active.
- [ ] Busy / In a call / In a meeting: red dot. "In a meeting" comes from the Outlook calendar or a live meeting.
- [ ] In a call, out of office: open red circle.
- [ ] Presenting: DND glyph. Set while screen sharing; see the Privacy toggle in §10.3.
- [ ] Focusing: DND glyph. Comes from Viva Insights focus time; notifications are silenced until it ends.
- [ ] Away, and "Away, Last seen <time>".
- [ ] Offline: shown when the user is not signed in on any device for a few minutes.
- [ ] Status unknown: open grey circle.
- [ ] Out of Office: purple circle with an arrow. Set by automatic replies or a calendar event marked "Out of Office".
  Source: https://learn.microsoft.com/en-us/microsoftteams/presence-admins

### 3.3 Automatic rules
- [ ] The computer goes Away after about **5 minutes** of inactivity (not user-configurable), on screen lock, or when the Teams window is minimised. It goes Offline when the computer sleeps.
  Source: https://support.microsoft.com/en-au/office/why-does-teams-say-i-m-away-when-i-m-not-7b17174d-ca33-436b-b153-0da89a8335a0 ; https://learn.microsoft.com/en-us/microsoftteams/presence-admins
- [ ] Mobile goes Away when Teams is in the background, and Offline after 24 hours of inactivity.
- [ ] With several devices, the device active most recently decides presence.
- [ ] A call or meeting switches presence to "In a call" or "In a meeting" unless the user has set DND.
- [ ] Availability order, most to least available: Available > Busy > In a meeting > In a call > DND > BRB > Away > Offline. Outside calls and meetings a user can only pick a status *less* available than the computed one. Inside a call or meeting any status can be picked, and it lasts for the call.
- [ ] A manual status with no duration lasts indefinitely (Appear offline), 1 day (Busy or DND), or 7 days (all others).
- [ ] A duration-limited, more-available status (for example Busy) does not override a less-available computed one (for example Away).
  Source: https://learn.microsoft.com/en-us/microsoftteams/presence-admins ; https://support.microsoft.com/office/ce36ed14-6bc9-4775-a33e-6629ba4ff78e

### 3.4 Do not disturb semantics
- [ ] Chats are always delivered. DND only suppresses banners. Calls go to voicemail except calls from priority-access people. Priority contacts' messages still raise banners.
  Source: https://learn.microsoft.com/en-us/microsoftteams/presence-admins

### 3.5 Status-change alerts ("Notify when available")
- [ ] In a 1:1 chat: More options > **Notify when available**. The same menu offers **Turn off notifications**.
- [ ] Settings > Notifications and activity > **Presence** > **Manage notifications**: "Add people" search box, a "Turn off" button per person, maximum **15** people.
- [ ] When the person becomes available, a banner appears (plus Windows Action Center if enabled).
  Source: https://support.microsoft.com/en-US/teams/notifications-settings/get-notified-when-someone-s-status-changes-in-microsoft-teams

### 3.6 Out of office
- [ ] Entry points: Profile > Set status message > **Schedule out of office**, or Settings > General > **Out of Office** > **Schedule**.
- [ ] Dialog fields:
  - "Turn on automatic replies" toggle;
  - message (required);
  - checkbox "Send replies outside my organization" with a choice of your contacts only or all external senders;
  - checkbox "Send replies only during a time period" with start and end date/time;
  - **Save**.
- [ ] Syncs both ways with Outlook automatic replies.
  Source: https://support.microsoft.com/en-US/teams/notifications-settings/schedule-an-out-of-office-status-in-microsoft-teams

### 3.7 Graph endpoints
- [ ] `GET /users/{id}/presence` (availability, activity, statusMessage, outOfOfficeSettings, workLocation, sequenceNumber). `POST /communications/getPresencesByUserId` reads presence in bulk. Presence also supports change-notification subscriptions.
- [ ] `POST /users/{id}/presence/setUserPreferredPresence`: availability/activity pairs Available/Available, Busy/Busy, DoNotDisturb/DoNotDisturb, BeRightBack/BeRightBack, Away/Away, Offline/OffWork. Takes an optional ISO-8601 `expirationDuration`; the default is 1 day for Busy/DND and 7 days for others. `clearUserPreferredPresence` is the Reset status equivalent. Scope: Presence.ReadWrite.
- [ ] `POST /users/{id}/presence/setStatusMessage` takes `{statusMessage:{message:{content,contentType}, expiryDateTime:{dateTime,timeZone}}}`.
- [ ] Work location: `setManualLocation`, `setAutomaticLocation`, `clearAutomaticLocation`, `clearLocation`.
  Source: https://learn.microsoft.com/en-us/graph/api/resources/presence ; https://learn.microsoft.com/en-us/graph/api/presence-setuserpreferredpresence ; https://learn.microsoft.com/en-us/graph/api/presence-setstatusmessage

## 4. Left app rail (app bar)

- [ ] Default apps, top to bottom: Activity, Chat, Teams (or a combined Chat and Teams view), Calendar, Calls, OneDrive/Files, then any pinned apps. Ctrl+1…Ctrl+9 open the 1st to 9th app. Ctrl+3 is Calendar in the default layout. **[default set and order unverified; varies by policy]**
  Source: https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] **View more apps** (··· in the rail): flyout listing installed apps and a search box. Right-click an app > **Pin** to add it to the rail.
  Source: https://support.microsoft.com/en-US/teams/apps-service/open-an-app-in-a-new-window-in-microsoft-teams ; search result summary of https://support.microsoft.com/cs-CZ/teams/apps-service/pin-an-app-in-microsoft-teams
- [ ] Right-click menu on a rail app: **Pin** / **Unpin** (unpinning does not uninstall), **Open in new window**. Drag and drop reorders apps. Admin-pinned apps can be unpinned only if the app setup policy allows user pinning.
  Source: https://support.microsoft.com/topic/b9c9ca79-cb3d-4e5f-9a03-c0b64b4ead54 ; https://learn.microsoft.com/da-dk/microsoftteams/teams-app-setup-policies
- [ ] **Open in new window** works for Activity, Chat, Channels, Calendar, Calls and Meet. After two pop-out windows are open, a warning says more may slow the system; the user can pick **Proceed**.
  Source: https://support.microsoft.com/topic/b9c9ca79-cb3d-4e5f-9a03-c0b64b4ead54
- [ ] Appearance settings for the rail: "Show app names" toggle (label under each icon), "Auto collapse app bar" toggle, right-click > "Expand app bar" or "Customize app bar".
  Source: https://support.microsoft.com/en-gb/teams/notifications-settings/change-settings-in-microsoft-teams
- [ ] Hamburger (≡) at the top of the rail. Right-click shows **Pin AppBar** to keep a collapsed app bar visible (shipped July 2025).
  Source: https://mc.merill.net/message/MC1112454
- [ ] Badges on rail icons: red count on Activity (new items since last visit; cleared on opening Activity). Chat and Teams show counts of unread unmuted chats, channels with unread personal or tag @mentions, and unread followed threads.
  Source: https://support.microsoft.com/en-US/teams/notifications-settings/catch-up-with-and-manage-badge-count-activity-in-microsoft-teams
- [ ] Bottom of the rail: **Apps** (store) button. **Activity in your other accounts and orgs** icon, shown only when there is more than one account or tenant; it carries a count of missed cross-org activity (see §11).
  Source: https://mc.merill.net/message/MC1184992
- [ ] Copilot app pinned in the rail when licensed, and "Copilot in Chat" toggle in Settings > General. **[university source; rail placement unverified]**
  Source: https://td.usnh.edu/TDClient/60/Portal/KB/ArticleDet?ID=2192

## 5. Activity feed

- [ ] Layout: list pane with notification cards; the selected item opens in the main pane. A red circle on the rail icon means new activity.
  Source: https://support.microsoft.com/en-us/office/explore-the-activity-feed-in-microsoft-teams-91c635a1-644a-4c60-9c98-233db3e13a56
- [ ] Filter pills at the top: **Unread**, **@Mentions**, **Tag mentions** (2025). A **More filters** dropdown holds the full list, including Replies and Reactions (older builds also had Apps, Voicemail and Missed calls).
  Source: https://support.microsoft.com/en-gb/office/02b9ece4-6086-4daa-b4c0-627beeacbf08 ; https://mc.merill.net/message/MC973502 ; https://office365itpros.com/2024/05/29/teams-activity-feed-changes/
- [ ] Text filter: a search/funnel icon (Ctrl+Shift+F) filters the current list by display name or message text, combined with the active pill.
  Source: https://office365itpros.com/2024/05/29/teams-activity-feed-changes/ ; https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] Header ··· menu: **Mark all as read** (Ctrl+Alt+K) and **Notification settings**, which deep-links to Settings > Notifications and activity.
  Source: https://support.microsoft.com/en-gb/office/02b9ece4-6086-4daa-b4c0-627beeacbf08 ; https://support.microsoft.com/help/1cc31834-5fe5-412b-8edb-43fecc78413d
- [ ] Activity shortcuts: Ctrl+Alt+U (unread), Ctrl+Alt+C (missed calls), Ctrl+Alt+M (@mentions).
  Source: https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] Per-item hover ··· menu. Documented: on calendar items, "turn off" calendar notifications. Mark as read/unread per item **[unverified]**.
  Source: https://office365itpros.com/2024/05/29/teams-activity-feed-changes/
- [ ] Notification types, each with its own glyph:
  - @mention of you, @team, @channel, tag mention;
  - reply to your post or to a thread you follow, reaction or like;
  - added to a team, made team owner;
  - trending, suggested;
  - meeting invite, update, cancellation and forward;
  - missed call, voicemail;
  - meeting recap ready (opens the recap);
  - app notifications (Graph `sendActivityNotification`);
  - status-change alert.
  Source: https://support.microsoft.com/en-us/office/explore-the-activity-feed-in-microsoft-teams-91c635a1-644a-4c60-9c98-233db3e13a56 ; https://techcommunity.microsoft.com/blog/microsoftteamsblog/what%E2%80%99s-new-in-microsoft-teams--april-2025/4410002
- [ ] Retention: notifications expire from the feed after **30 days** (older docs said 14).
  Source: https://support.microsoft.com/en-gb/office/02b9ece4-6086-4daa-b4c0-627beeacbf08
- [ ] Graph: apps can post to the feed with `POST /users/{id}/teamwork/sendActivityNotification`, `/chats/{id}/sendActivityNotification`, `/teams/{id}/sendActivityNotification`, or `/teamwork/sendActivityNotificationToRecipients` (up to 100 users). There is no documented public Graph API to *read* the user's feed.
  Source: https://learn.microsoft.com/en-us/graph/teams-send-activityfeednotifications

## 6. Search

- [ ] Typeahead (before Enter): top matching people, group chats (including recently visited), and teams and channels. Some filters appear inline as suggestions. A "Search in Viva Connections" option appears if the org uses it.
  Source: https://support.microsoft.com/office/search-for-messages-and-more-in-microsoft-teams-4a351520-33f4-42ab-a5ee-5fc0ab88b263
- [ ] Results page tabs: **All**, **Messages**, **People**, **Files**, **Group chats**, **Teams and channels**. From All, "More group chats" and "View all messages" jump to the matching tabs.
  Source: https://support.microsoft.com/office/search-for-messages-and-more-in-microsoft-teams-4a351520-33f4-42ab-a5ee-5fc0ab88b263 ; https://techcommunity.microsoft.com/blog/microsoftteamsblog/new-and-improved-search-results-experience-on-microsoft-teams/3035064
- [ ] Messages filters:
  - Type (Chats / Channels);
  - Teams and channels;
  - From;
  - Date (preset or range);
  - More: @Mentions me, Has attachments, Hide app and bot messages.
  Source: https://support.microsoft.com/office/search-for-messages-and-more-in-microsoft-teams-4a351520-33f4-42ab-a5ee-5fc0ab88b263
- [ ] Files filters: Team/channel/chat, File type, Person (modified by), Date.
  Source: same
- [ ] Group chats tab: Person filter. Chats idle for more than 180 days may be missing.
  Source: same
- [ ] Query syntax:
  - KQL `From:`, `In:`, `Subject:`, `Sent:` (no space after the colon);
  - prefix wildcard `serv*`;
  - "exact phrase" in quotes;
  - people search tolerates spelling mistakes and nicknames.
  Source: same
- [ ] In-conversation find: Ctrl+F opens "Find in chat" in the right pane. For a channel: channel details > "Find in channel". Clicking a result jumps to the message.
  Source: same ; https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] Graph: `POST /search/query` covers message/event/driveItem/list/listItem/site/person/externalItem. Teams `chatMessage` search is also supported on beta/v1.0 and is delegated-only.
  Source: https://learn.microsoft.com/en-us/graph/search-concept-overview

## 7. Notifications: in-app banners, Windows toasts, badge, tray

- [ ] Banner (toast) appears at bottom-right by default and goes to Windows Action Center/Notification Center afterwards. Position can be set to Bottom right, Top right, Bottom left or Top left. Preview size: Comfy or Compact. **Test notification** button.
  Source: https://support.microsoft.com/help/1cc31834-5fe5-412b-8edb-43fecc78413d ; https://learn.microsoft.com/en-us/training/modules/collaborate-teams-channels-microsoft-teams/7-manage-notifications
- [ ] Inline **Reply** on chat toasts opens a text box inside the toast; Enter sends.
  Source: https://mspoweruser.com/microsoft-teams-now-allows-respond-chat-messages-directly-toast-notifications **[third-party]**
- [ ] Ctrl+Alt+T moves focus to the toast. Win+Shift+Y moves focus to a Windows notification.
  Source: https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] Call toasts: Ctrl+Shift+A accept with video, Ctrl+Shift+S accept audio, Ctrl+Shift+D decline. Meeting-started toast: Ctrl+Shift+J join, Ctrl+Shift+R open meeting chat. Lobby toast: Ctrl+Shift+Y admit.
  Source: https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] Honour Windows Do not disturb (Windows 11 only, since May 2026): an opt-in toggle in Teams settings, off by default. When on, Teams toasts are suppressed while Windows DND or its schedule is active.
  Source: https://mc.merill.net/message/MC1269215
- [ ] Taskbar badge: red number overlay that sums the Chat, Teams and Activity counts. Muted chats are excluded. Clearing paths: open the item, read mentions in the Mentions/Tag quick views, or use ··· > **Mark all as read** at the top of the chat/channel list (Shift+Esc).
  Source: https://support.microsoft.com/en-US/teams/notifications-settings/catch-up-with-and-manage-badge-count-activity-in-microsoft-teams
- [ ] 2026 badge model: badge = unread unmuted chats + direct @mentions + followed threads + tag mentions. A purple dot marks badge-counting chats in the list, and Quick views show a purple number. Mention and Important charms are removed from the list.
  Source: https://mc.merill.net/message/MC1268911
- [ ] System tray icon. Its right-click menu keeps **Quit**, which is the only place Quit lives now. Other items (open Teams, status, settings) **[unverified]**. The tray icon shows notification state **[community report]**.
  Source: https://mc.merill.net/message/MC1184652 ; https://techcommunity.microsoft.com/t5/microsoft-teams/new-teams-no-notification-badges-in-system-tray/td-p/3962948
- [ ] Taskbar jump list (right-click the taskbar icon): upcoming and ongoing meetings (join without opening the full app), **Schedule a meeting**, **New chat**. Quit was removed from it.
  Source: https://mc.merill.net/message/MC1184652

## 8. Windows and multi-window

- [ ] Pop out a chat: Ctrl+Shift+N starts a chat in a new window; Ctrl+O opens the current conversation in a new window. Double-clicking a chat in the list pops it out **[third-party]**. Settings > General has "Starting chats" and "Opening Teams content", each with the choice Main window or New window.
  Source: https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2 ; https://td.usnh.edu/TDClient/60/Portal/KB/ArticleDet?ID=2192
- [ ] Pop out a personal app or tab: right-click the app > **Open in new window**, or use the pop-out icon at the top-right of an open app or tab. Works for most apps that have a personal app or tab.
  Source: https://support.microsoft.com/en-US/teams/apps-service/open-an-app-in-a-new-window-in-microsoft-teams
- [ ] **Pin window on top**: the window's ··· > "Pin window on top" (the window shrinks slightly and stays above other apps), then "Unpin". Shortcut Ctrl+Shift+T.
  Source: https://support.microsoft.com/topic/10b32523-75ec-4682-813d-852c65da5550 ; https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] Activity from another account opens in a child window; the main window does not switch account.
  Source: https://support.microsoft.com/office/manage-accounts-and-organizations-in-microsoft-teams-7b221128-6643-465c-a317-679e48cd2ce9
- [ ] Panes: Ctrl+Alt+Enter moves focus to the pane divider (resize with arrows). Ctrl+Shift+Enter restores the default width. Alt+P toggles the details pane.
  Source: https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] Zoom: Ctrl+= zooms in, Ctrl+- zooms out, Ctrl+0 resets. Shared-content zoom uses Alt+Shift+Plus, Alt+Shift+Minus and Alt+Shift+0.
  Source: https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] F11 toggles full screen.
  Source: same

## 9. Keyboard shortcuts (master list; Ctrl+. or Alt+/ opens the dialog)

- [ ] Shortcuts dialog with a "Use shortcuts from other apps" dropdown: **Teams** (default), **Slack**, **Zoom**, **Combined**. The dialog highlights shortcuts that will change, then **Apply**.
  Source: https://support.microsoft.com/topic/ee332652-cefc-4b68-94d9-a8e1c391ac47
- [ ] General:
  - Ctrl+. or Alt+/ show shortcuts;
  - Ctrl+E search;
  - Ctrl+Shift+F filter;
  - Ctrl+N new chat; Ctrl+Shift+N chat in a new window;
  - Ctrl+, Settings;
  - F1 Help;
  - Esc close;
  - Ctrl+= / Ctrl+- / Ctrl+0 zoom;
  - Ctrl+Alt+Shift+R report a problem;
  - Ctrl+G go to;
  - Ctrl+Alt+Enter pane divider; Ctrl+Shift+Enter default pane width;
  - Ctrl+Shift+T pin on top;
  - Ctrl+O open in new window.
- [ ] Navigation:
  - Ctrl+1–9 rail apps;
  - Ctrl+L list; Ctrl+M message pane; Ctrl+R compose;
  - Ctrl+Alt+T toast;
  - Ctrl+H history;
  - Ctrl+F6 / Ctrl+Shift+F6 next / previous section;
  - Ctrl+Alt+Shift+Up/Down move chat or channel;
  - Alt+Left/Right back/forward;
  - Win+Shift+Y notification.
- [ ] Messaging:
  - Alt+Q collapse folders;
  - Shift+Esc mark all read;
  - Ctrl+J jump to last read;
  - Ctrl+F find;
  - Alt+1–9 chat header tabs;
  - Alt+P details pane;
  - Alt+Shift+R reply to last; Ctrl+Alt+R react to last;
  - Ctrl+Alt+U unread; Ctrl+Alt+C chats; Ctrl+Alt+A channels; Ctrl+Alt+B meeting chats;
  - Ctrl+Alt+Z clear filters.
- [ ] Compose:
  - Ctrl+Shift+X expand; Ctrl+Enter send (expanded); Shift+Enter newline;
  - Ctrl+Alt+P paragraph; Ctrl+Alt+1/2/3 headings; Ctrl+Alt+4 quote;
  - Alt+Shift+O attach;
  - Ctrl+B / Ctrl+I / Ctrl+U bold, italic, underline; Ctrl+Alt+X strikethrough;
  - Ctrl+Shift+I important;
  - Alt+A rewrite with Copilot;
  - Alt+Shift+E video recorder;
  - Ctrl+Alt+L or Alt+Shift+L Loop paragraph;
  - Ctrl+K link;
  - Ctrl+Shift+C inline code; Ctrl+Shift+B code block; Ctrl+Alt+5 code.
- [ ] Calls and meetings:
  - Ctrl+Shift+A / S / D accept video / accept audio / decline;
  - Alt+Shift+A / V start audio / video call;
  - Ctrl+Shift+H end call;
  - Ctrl+Shift+M mute; Ctrl+Space temporary unmute (gated by a Privacy toggle);
  - Ctrl+Shift+U speaker;
  - Ctrl+Shift+O video;
  - Ctrl+Shift+K raise hand; Ctrl+Shift+L announce raised hands;
  - Ctrl+Shift+E share tray; Ctrl+Shift+Space sharing toolbar;
  - Ctrl+Shift+Y admit from lobby;
  - Alt+N schedule; Ctrl+S save;
  - Alt+Shift+J join from details; Alt+Shift+S suggested time;
  - Ctrl+Shift+J join from toast; Ctrl+Shift+R meeting chat from toast;
  - Alt+Shift+arrows pan shared content.
- [ ] Calendar: Alt+Shift+1–5 views, Ctrl+Alt+Left/Right period, Alt+Shift+Y today, Alt+F1 left pane, Ctrl+P print, Ctrl+Alt+F forward, Alt+R reply, Ctrl+J join, Ctrl+Shift+Q meeting request.
- [ ] Activity: Ctrl+Alt+K mark all read, Ctrl+Alt+U unread, Ctrl+Alt+C missed calls, Ctrl+Alt+M mentions.
- [ ] Debug: Ctrl+Alt+Shift+1 downloads diagnostic logs.
  Source for all of §9: https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2

## 10. Settings dialog (Settings and more > Settings, Ctrl+,): every page

Settings opens as a separate full-pane "app" with a left page list.

Page list, in order: General, Accounts and orgs, Privacy, Notifications and activity, Appearance and accessibility (older builds split this into Appearance and Accessibility), Files and links, Chats and channels, Calls, Devices, App permissions, Recognition, Captions and transcripts (under Accessibility in some builds), About Teams.
Source: https://td.usnh.edu/TDClient/60/Portal/KB/ArticleDet?ID=2192 ; https://support.microsoft.com/en-gb/teams/notifications-settings/change-settings-in-microsoft-teams

### 10.1 General
- [ ] Language and regional formats:
  - "Follow OS settings" toggle;
  - when off: "App language", "Date format", "Time format";
  - **Save and restart** / **Restart** buttons;
  - "Manage Windows settings" link.
  Source: https://support.microsoft.com/en-gb/teams/notifications-settings/change-settings-in-microsoft-teams
- [ ] Time zone section with a "Manage Windows settings" link.
  Source: same
- [ ] Efficiency mode: "Use only when resources are low (Default)", "Never use efficiency mode", "Always use efficiency mode".
  Source: same
- [ ] System:
  - "Auto-start Teams";
  - "Open application in background" (starts without showing a window);
  - "On close, keep the application running" (close sends Teams to the tray).
  Source: https://help.stalbansdiocese.org/teams-training-start-automatically ; https://support.microsoft.com/en-gb/teams/notifications-settings/change-settings-in-microsoft-teams
- [ ] "Opening Teams content in Windows" and "Starting chats": main window or new window.
  Source: https://td.usnh.edu/TDClient/60/Portal/KB/ArticleDet?ID=2192
- [ ] "Copilot in Chat" toggle, if licensed. "Channel recent activity" position: top or bottom.
  Source: same **[university]**
- [ ] Translation: message translation language and options.
  Source: same
- [ ] Out of Office: **Schedule** button (see §3.6).
  Source: https://support.microsoft.com/en-US/teams/notifications-settings/schedule-an-out-of-office-status-in-microsoft-teams
- [ ] Spell check on/off.
  Source: https://td.usnh.edu/TDClient/60/Portal/KB/ArticleDet?ID=2192
- [ ] Keyboard shortcut layout (Teams / Slack / Zoom / Combined) can also be set here.
  Source: https://support.microsoft.com/topic/ee332652-cefc-4b68-94d9-a8e1c391ac47
- [ ] "Register Teams as the chat app for Microsoft 365" **[third-party; unverified]**.
  Source: https://gomomentum.com/wp-content/uploads/2024/01/New-Teams-Settings-101-QRG88.pdf (search snippet only)

### 10.2 Accounts and orgs
- [ ] One notification toggle per org or guest tenant. Guest orgs default to on.
  Source: https://support.microsoft.com/office/manage-accounts-and-organizations-in-microsoft-teams-7b221128-6643-465c-a317-679e48cd2ce9
- [ ] "Manage your account". "Accept invitations from other tenants". Per-org leave/remove **[unverified]**.
  Source: https://td.usnh.edu/TDClient/60/Portal/KB/ArticleDet?ID=2192

### 10.3 Privacy
- [ ] "Do not disturb" > **Manage priority access**: add people whose messages raise banners and whose calls ring through during DND.
  Source: https://learn.microsoft.com/en-us/microsoftteams/presence-admins
- [ ] "Set my status to Do not disturb when I'm sharing my screen" (default on).
  Source: https://support.microsoft.com/office/ce36ed14-6bc9-4775-a33e-6629ba4ff78e
- [ ] **Read receipts** toggle: on by default, admin can lock it. **[third-party wording; may live under Chats and channels in newest builds]**
  Source: https://kb.uwm.edu/66478
- [ ] **Blocked contacts** > "Edit blocked contacts": list of blocked numbers and people, plus "Block calls with no caller ID" (Direct Routing).
  Source: https://support.microsoft.com/office/manage-your-call-settings-in-microsoft-teams-456cb611-3477-496f-b31a-6ab752a7595f
- [ ] "Manage your work location" (consent to auto-detected work location).
  Source: https://td.usnh.edu/TDClient/60/Portal/KB/ArticleDet?ID=2192
- [ ] Other Privacy items:
  - "Delete Copilot activity history";
  - "Surveys": participate in Microsoft Teams surveys;
  - "Turn off camera and mic when screen locks";
  - "Enable keyboard shortcut to unmute" (Ctrl+Space);
  - "View diagnostic data" and "Extended diagnostic data";
  - "Optional connected experiences" (Giphy, URL previews).
  Source: same **[university]**

### 10.4 Notifications and activity
- [ ] General:
  - "Mute all notifications (except for calls and meetings)";
  - "Show message and content previews in notifications";
  - "Show notifications during calls and meetings";
  - **Test notification**.
  Source: https://support.microsoft.com/help/1cc31834-5fe5-412b-8edb-43fecc78413d
- [ ] Sound:
  - "Play sounds with notifications";
  - "Play sounds with urgent and priority contact notifications";
  - "Play sound with incoming calls, requests to join, and meeting start notifications";
  - "Play sounds while I'm busy or in a meeting" (call-waiting beep);
  - one sound dropdown per notification type, with a ▶ preview button; custom sounds on Windows.
  Source: https://support.microsoft.com/en-gb/topic/6992a279-09d6-4c93-be51-f45ddb277827 ; https://support.microsoft.com/office/manage-your-call-settings-in-microsoft-teams-456cb611-3477-496f-b31a-6ab752a7595f
- [ ] Display: Position (Bottom right / Top right / Bottom left / Top left). Preview size (Comfy / Compact).
  Source: https://support.microsoft.com/en-gb/topic/6992a279-09d6-4c93-be51-f45ddb277827
- [ ] Email: "Missed activity emails" frequency dropdown (including Off). Daily digest email.
  Source: same ; https://learn.microsoft.com/en-us/training/modules/collaborate-teams-channels-microsoft-teams/7-manage-notifications
- [ ] Chats and channels: one dropdown per type.
  - Types: chat messages, personal @mentions, tag mentions, everyone mentions, replies, likes and reactions, posts in shown and pinned channels.
  - Choices: "Banner and feed", "Only show in feed", "Off".
  - Channel presets: **All activity**, **Mentions & replies**, **Custom**.
  Source: https://learn.microsoft.com/en-us/training/modules/collaborate-teams-channels-microsoft-teams/7-manage-notifications ; https://td.usnh.edu/TDClient/60/Portal/KB/ArticleDet?ID=2192
- [ ] Meetings:
  - "Meeting start notifications";
  - "Show meeting join bar";
  - "Meeting chat notifications for meetings I've accepted" (default on);
  - "...meetings marked as tentative or no response" (default "Mute until I join or send a message");
  - "Meet now start notifications".
  Source: https://support.microsoft.com/en-gb/topic/6992a279-09d6-4c93-be51-f45ddb277827
- [ ] Presence: **Manage notifications** (status-change list, maximum 15).
  Source: https://support.microsoft.com/en-US/teams/notifications-settings/get-notified-when-someone-s-status-changes-in-microsoft-teams
- [ ] Calendar: meeting invites, updates, cancellations, forwarded meetings. Each has a dropdown or Off.
  Source: https://support.microsoft.com/en-gb/topic/6992a279-09d6-4c93-be51-f45ddb277827
- [ ] Apps: one toggle per app; some offer Activity / Activity and banner / Off. An app appears here only after its first notification.
  Source: same
- [ ] Per-channel override: channel ··· > Channel notifications.
  - Options: All activity / Off / Custom.
  - Custom: new posts (Banner and feed / Only show in feed / Off), "Include thread replies", "Follow all new threads".
  - Per thread: ··· > "Turn off notifications"; follow or unfollow.
  Source: https://learn.microsoft.com/en-us/training/modules/collaborate-teams-channels-microsoft-teams/7-manage-notifications ; https://support.microsoft.com/office/c72b8c07-37e1-4a0b-82c9-fdfda04f15b2
- [ ] Windows DND toggle (see §7). Exact label **[unverified]**.
  Source: https://mc.merill.net/message/MC1269215

### 10.5 Appearance and accessibility
- [ ] Theme: Follow operating system theme, Light, Dark, High contrast (or Contrast themes). "Always use dark theme for calls and meetings".
  Source: https://support.microsoft.com/en-gb/teams/notifications-settings/change-settings-in-microsoft-teams ; https://td.usnh.edu/TDClient/60/Portal/KB/ArticleDet?ID=2192
- [ ] Chat density: **Comfy** (default) or **Compact**. "Show message previews in your chat list" toggle.
  Source: https://support.microsoft.com/en-au/office/customize-your-teams-chat-interface-with-chat-density-settings-c93fd71d-4a35-4712-961a-be76bad50925
- [ ] Emoji skin tone preference. Layout (Grid / List) for the Teams list.
  Source: https://td.usnh.edu/TDClient/60/Portal/KB/ArticleDet?ID=2192
- [ ] App bar options: "Show app names", "Auto collapse app bar".
  Source: https://support.microsoft.com/en-gb/teams/notifications-settings/change-settings-in-microsoft-teams
- [ ] Accessibility:
  - "Sign language view";
  - "Teletypewriter (TTY) mode";
  - Captions (see §10.10);
  - animations / reduce motion toggle **[unverified]**.
  Source: https://td.usnh.edu/TDClient/60/Portal/KB/ArticleDet?ID=2192 ; https://support.microsoft.com/office/manage-your-call-settings-in-microsoft-teams-456cb611-3477-496f-b31a-6ab752a7595f
- [ ] Message font size is set per message (compose toolbar Font size: small / medium / large), not app-wide. App-wide text scaling is done with zoom.
  Source: https://support.microsoft.com/en-us/office/change-message-font-size-in-teams-1e5ee8cc-ce92-4d11-b853-5e7980981d28

### 10.6 Files and links
- [ ] "Always open Word, PowerPoint, and Excel files in": **Teams** / **Desktop app** / **Browser**. Kept in sync with the Office file-open preference.
  Source: https://support.microsoft.com/topic/open-file-links-directly-in-microsoft-365-desktop-apps-from-teams-and-classic-outlook-7c1a08d0-54d0-499e-992e-2c41f70b59a1
- [ ] "Link open preference": **Microsoft Edge** (default; opens the link with Teams in the Edge sidebar side-by-side) or **Default browser**. Shared with Outlook. Can be locked by the "Choose which browser opens web links" policy. A first-run banner offers "Try Edge" / "Manage my settings".
  Source: https://learn.microsoft.com/en-us/outlook/troubleshoot/message-body/view-emails-and-web-links-in-browser
- [ ] Downloads: download location, and ask where to save each time.
  Source: https://td.usnh.edu/TDClient/60/Portal/KB/ArticleDet?ID=2192

### 10.7 Chats and channels
- [ ] Followed-thread behaviour (auto-follow when you reply, are mentioned, or someone starts a thread from your message). Read receipts may live here in 2026 builds.
  Source: https://mc.merill.net/message/MC1268911 ; https://support.microsoft.com/help/1cc31834-5fe5-412b-8edb-43fecc78413d

### 10.8 Calls
- [ ] Call answering rules ("Call handling and forwarding"):
  - Ring me / Forward my calls (to a contact, number, voicemail or delegates);
  - Also ring;
  - If unanswered: ring time, then voicemail, number or group.
  Detailed labels come from a separate article **[unverified labels]**.
  Source: https://support.microsoft.com/office/manage-your-call-settings-in-microsoft-teams-456cb611-3477-496f-b31a-6ab752a7595f
- [ ] Ringtones: separate dropdowns for "Calls for you" and "Forwarded calls" (delegated calls too), set per device.
  Source: same
- [ ] Incoming call view: **Large window** / **Small window**.
  Source: same
- [ ] Delegates: add or remove; per-delegate "make and receive calls" and "change call and delegate settings" permissions.
  Source: same
- [ ] **Manage voicemail**:
  - record a greeting;
  - default greeting language;
  - text-to-speech greeting;
  - out-of-office greeting (when it plays, custom text);
  - call answer rules (5 options, including leave a message, end call without greeting, transfer to a person or number).
  Source: same
- [ ] Call group and call queue notifications: per-queue toggles.
  Source: same
- [ ] TTY mode. Blocked contacts. "Block calls with no caller ID". Open PSTN calls in a browser app (admin-gated).
  Source: same

### 10.9 Devices
- [ ] Audio:
  - "Manage devices" (Bluetooth Teams devices);
  - audio device, speaker and microphone dropdowns;
  - "Automatically adjust mic sensitivity";
  - "Sync device buttons";
  - **Make a test call** (desktop only);
  - "Noise suppression" (levels per the accessibility doc: three levels, Windows desktop);
  - "Voice isolation" (needs a voice profile);
  - "High fidelity music mode";
  - "Spatial audio";
  - "Secondary ringer" (default None).
  Source: https://support.microsoft.com/en-us/topic/6245254d-1d1f-4c71-9286-67f053acb49f ; https://support.microsoft.com/office/make-your-microsoft-teams-meetings-calls-and-messages-accessible-to-people-with-disabilities-4cdfa998-df97-48f4-8bfc-04b8131870ed
- [ ] Video:
  - Camera dropdown with live preview;
  - "Automatically adjust camera controls";
  - Camera settings (opens the driver dialog);
  - "Adjust brightness";
  - "Soft focus";
  - "Green screen";
  - "Mirror my video".
  Source: same ; https://td.usnh.edu/TDClient/60/Portal/KB/ArticleDet?ID=2192

### 10.10 Captions and transcripts
- [ ] "Automatically identify me in live captions and live transcripts" (turn off to show as anonymous). "Always show live captions in meetings" **[university]**. Caption style options **[unverified]**.
  Source: https://support.microsoft.com/topic/a1095e1a-a2f0-453e-8101-eca76429ff04 ; https://canisius.atlassian.net/wiki/x/E4D2Bw

### 10.11 Recognition (only if admin-enabled)
- [ ] Voice recognition: opt in (profile auto-built at the next eligible meeting), or **Create**/**Update** now: choose mic, read the passage, "Start voice capture", wait for "Voice profile complete".
- [ ] Face recognition: "Start face capture", nine photos. Unused face profiles are deleted after 1 year.
- [ ] **Opt out** deletes a profile. **Export** saves voice clips to Downloads.
  Source: https://support.microsoft.com/topic/f0084478-52a7-4c52-bcdc-9063ed0e0bc0

### 10.12 App permissions
- [ ] Per-app device permissions: camera, mic, location, notifications, MIDI, open external links.
  Source: https://td.usnh.edu/TDClient/60/Portal/KB/ArticleDet?ID=2192 **[permission list unverified]**

### 10.13 About Teams
- [ ] Version, with an "up to date" message or an **Update now** button. Privacy and legal links. "Early access" (Public preview) toggle when policy allows.
  Source: https://support.microsoft.com/en-us/office/find-the-version-of-teams-you-re-using-e6d3421f-b4f2-4fc6-a69e-ebc528fb1216 ; https://td.usnh.edu/TDClient/60/Portal/KB/ArticleDet?ID=2192
- [ ] Update cadence: checks at start-up and every few hours. Twice-monthly releases. The update installs when idle, or immediately through the title-bar Restart button. Clients 1–3 months old get an in-app alert; clients older than 3 months get a blocking page (Update now / contact IT / use web).
  Source: https://learn.microsoft.com/en-us/microsoftteams/teams-client-update

## 11. Multiple accounts and orgs

- [ ] Add account, switch account, and guest orgs appear automatically (see §2).
  Source: https://support.microsoft.com/office/manage-accounts-and-organizations-in-microsoft-teams-7b221128-6643-465c-a317-679e48cd2ce9
- [ ] "Activity in your other accounts and orgs" panel, opened from the bottom-left rail icon (shown only with more than one account or tenant).
  - Badge: total missed cross-org count.
  - Panel lists missed notifications grouped by tenant; tenants with no missed activity are hidden.
  - Clicking an item opens it in a child window.
  Source: https://mc.merill.net/message/MC1184992
- [ ] Pin up to **3** accounts or tenants to the sidebar.
  - A pinned tenant stays visible even with no activity.
  - Clicking it shows only that tenant's notifications, with **Switch** and **Unpin** buttons.
  - Pinned tenants' items are removed from the main panel.
  Source: same ; https://support.microsoft.com/office/manage-accounts-and-organizations-in-microsoft-teams-7b221128-6643-465c-a317-679e48cd2ce9
- [ ] Notifications from non-active orgs follow the per-org toggles in Settings > Accounts and orgs.
  Source: same

## 12. Connectivity and resilience

- [ ] Offline / reconnecting banner at the top of the main pane ("You're offline…" / "Reconnecting…"), with sends queued and retried. **[unverified: no first-party page fetched; confirm wording on winpc]**
- [ ] Users with no Teams session show as Offline after a few minutes. Messages sent while the user is offline are delivered on the next sign-in.
  Source: https://learn.microsoft.com/en-us/microsoftteams/presence-admins

## 13. Help and diagnostics

- [ ] F1 opens Help. Help > What's new shows release highlights.
  Source: https://learn.microsoft.com/en-us/microsoftteams/teams-client-update ; https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] Ctrl+Alt+Shift+R opens Report a problem. Ctrl+Alt+Shift+1 downloads diagnostic logs to Downloads.
  Source: https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
