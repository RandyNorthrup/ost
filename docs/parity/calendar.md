# Teams desktop (new Teams, Windows) - Calendar & Scheduling parity checklist

Scope: the "new calendar" in new Teams (Outlook/OWA calendar components hosted in Teams; GA for commercial
tenants 4 Feb 2025; the old/new toggle is being removed, Jan-Feb 2026 per MC1129730). Prefer Windows desktop.

Conventions:
- `[Outlook-derived]` = documented for new Outlook / Outlook on the web, whose calendar surface the new Teams
  calendar reuses. Verify the exact label in Teams on winpc before cloning.
- `[3rd-party]` = only third-party or forum sourced. Treat as a hint; verify on winpc.
- `[verify visually]` = rendering detail no Microsoft doc states. Capture it from real Teams on winpc.

Research note: the session's WebSearch budget ran out partway through. The remaining Microsoft Support pages were
read directly in a browser, so every item without a tag above comes from a Microsoft page read in full.

---

## 1. App entry, shell and availability

- [ ] Calendar app in the left app rail: label **Calendar** and calendar icon. Opens the calendar surface. The default position is the 3rd app, so **Ctrl+3** opens it; the number follows the app's position in the rail if the user reorders apps.
  Source: https://support.microsoft.com/en-US/accessibility/teams/keyboard-shortcuts-for-microsoft-teams
- [ ] Calendar shows everything scheduled in Teams, Exchange and Outlook (one mailbox calendar). Events created in Teams appear in Outlook and vice versa.
  Source: https://support.microsoft.com/en-us/teams/meetings/manage-your-calendar-in-microsoft-teams
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-meeting-in-microsoft-teams
- [ ] Pop-out calendar: right-click the Calendar icon in the app rail to open the calendar in a separate window.
  Source: https://mc.merill.net/message/MC908116
  Source: https://office365itpros.com/2024/10/17/teams-calendar-app/
- [ ] Exchange Online mailbox requirement: without one, **Meet now** and **Join with an ID** are hidden in the calendar. Admin requirements: the Calendar app ID is `ef56c0de-36fc-4ef8-b417-3d82ba9d073c` in the app setup policy, and EWS must be allowed.
  Source: https://support.microsoft.com/en-us/teams/meetings/start-an-instant-meeting-in-microsoft-teams
  Source: https://learn.microsoft.com/en-us/answers/questions/4420408/how-do-i-find-my-calendar-app
- [ ] New/classic toggle (historical): a **New Calendar** toggle sat at top-right or in More options. It is being removed and the new calendar becomes the only one. Do not clone the toggle.
  Source: https://mc.merill.net/message/MC1129730
  Source: https://techcommunity.microsoft.com/blog/microsoftteamsblog/the-new-calendar-in-microsoft-teams-now-generally-available/4373598
- [ ] Known gaps in the new calendar: Teams **live events** cannot be scheduled from it, and Premium meeting templates were initially unsupported. Microsoft said to switch back to classic for these.
  Source: https://support.microsoft.com/office/get-started-with-the-new-calendar-in-microsoft-teams-98f3b637-5da2-43e2-91b3-f312ab3e4dc5
- [ ] Copilot help prompts appear at the top of calendar help. Copilot features in the calendar (managed booking) need Copilot. Low priority for a clone.
  Source: https://techcommunity.microsoft.com/blog/microsoftteamsblog/the-new-calendar-in-microsoft-teams-now-generally-available/4373598

## 2. Command bar / toolbar

- [ ] Command bar layout (new calendar): it was rearranged to put the primary actions **Meet now** and **Join with ID** first. It also carries filters, the view switcher (month and split views), time scale, saved views, sharing, printing and settings.
  Source: https://mc.merill.net/message/MC908116
- [ ] **Today** button: returns to the current date.
  Source: https://support.microsoft.com/en-us/teams/meetings/manage-your-calendar-in-microsoft-teams
- [ ] Previous/next arrows beside the month label: step by day, week or month depending on the view.
  Source: https://support.microsoft.com/en-us/teams/meetings/manage-your-calendar-in-microsoft-teams
- [ ] Month-and-year label at top-left. Clicking it opens a date picker to jump to any past or future date.
  Source: https://support.microsoft.com/en-us/teams/meetings/manage-your-calendar-in-microsoft-teams
- [ ] View switcher button labelled with the current view (default **Work week**). The dropdown holds **Day** (with an arrow to choose the number of days), **Work week**, **Week**, **Month**, **Split view** (checkable), **Time scale** and **Saved views**.
  Source: https://support.microsoft.com/en-us/teams/meetings/manage-your-calendar-in-microsoft-teams
  Source: https://support.microsoft.com/en-us/teams/meetings/customize-your-calendar-in-microsoft-teams
  Source: https://support.microsoft.com/en-us/teams/meetings/view-multiple-calendars-in-microsoft-teams
- [ ] **Filter** button (at the top of the calendar, and also under More options): checklist of event types; clearing a type hides it.
  Source: https://support.microsoft.com/en-us/teams/meetings/customize-your-calendar-in-microsoft-teams
- [ ] **Show navigation pane** toggle at top-left: shows or hides the left pane (mini month, calendars, groups). Shortcut Alt+F1.
  Source: https://support.microsoft.com/en-us/teams/meetings/get-started-with-the-microsoft-teams-calendar
  Source: https://support.microsoft.com/en-US/accessibility/teams/keyboard-shortcuts-for-microsoft-teams
- [ ] **Meet now** button (upper right) with an attached dropdown arrow whose menu holds **Join with an ID** (# icon).
  Source: https://support.microsoft.com/en-us/teams/meetings/join-a-meeting-in-microsoft-teams
- [ ] **New** split button: the main part opens the new-event form. The dropdown arrow lists event templates: **Webinar**, **Town hall**, **Virtual appointment**, the user's templates under **Your templates**, **Create template**, and **View all templates**.
  Source: https://support.microsoft.com/en-us/teams/meetings/get-started-with-the-microsoft-teams-calendar
  Source: https://support.microsoft.com/en-gb/teams/meetings/personal-meeting-templates-in-microsoft-teams
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-webinar-in-microsoft-teams
- [ ] **More options** (…) menu: **Calendar settings**, **Share**, **Print**, **Filter**.
  Source: https://support.microsoft.com/en-us/teams/meetings/share-your-calendar-in-microsoft-teams
  Source: https://support.microsoft.com/en-us/teams/meetings/customize-your-calendar-in-microsoft-teams
- [ ] Weather display for the user's current location in the calendar header, if configured.
  Source: https://mc.merill.net/message/MC908116
  Source: https://techcommunity.microsoft.com/blog/microsoftteamsblog/the-new-calendar-in-microsoft-teams-now-generally-available/4373598
- [ ] Work location indicator next to the current date: an **Add work location** button, or the current location icon. See section 27.
  Source: https://support.microsoft.com/en-gb/teams/meetings/work-plans-in-microsoft-teams
- [ ] Search your calendar: Alt+Q per the shortcut table; uses the global search box.
  Source: https://support.microsoft.com/en-US/accessibility/teams/keyboard-shortcuts-for-microsoft-teams

## 3. Calendar views

- [ ] Default view is **Work week** (Monday to Friday, or the user's work days).
  Source: https://support.microsoft.com/en-us/teams/meetings/manage-your-calendar-in-microsoft-teams
- [ ] **Day** view: agenda-style time grid for one day. An arrow next to Day picks 1 to 7 days (Alt+1 to Alt+7; Alt+3 gives the three-day view).
  Source: https://support.microsoft.com/en-us/teams/meetings/manage-your-calendar-in-microsoft-teams
  Source: https://support.microsoft.com/en-US/accessibility/teams/keyboard-shortcuts-for-microsoft-teams
- [ ] **Work week** view: time grid for the work days.
  Source: https://support.microsoft.com/en-us/teams/meetings/manage-your-calendar-in-microsoft-teams
- [ ] **Week** view: time grid for all 7 days.
  Source: https://support.microsoft.com/en-us/teams/meetings/manage-your-calendar-in-microsoft-teams
- [ ] **Month** view: month grid. It was added by the new calendar; classic had no month view.
  Source: https://support.microsoft.com/en-us/teams/meetings/manage-your-calendar-in-microsoft-teams
  Source: https://office365itpros.com/2024/10/17/teams-calendar-app/
- [ ] Agenda pane inside Month view: "Open agenda in Month view" (Alt+Shift+5) shows a side agenda for the selected day.
  Source: https://support.microsoft.com/en-US/accessibility/teams/keyboard-shortcuts-for-microsoft-teams
- [ ] No standalone Agenda/List view in the new calendar. The shortcut table lists "List view - No shortcut". Microsoft's statement that agenda view isn't supported appears only in search snippets, so verify on winpc.
  Source: https://support.microsoft.com/en-US/accessibility/teams/keyboard-shortcuts-for-microsoft-teams
  Source: https://learn.microsoft.com/en-us/answers/questions/5807698/agenda-view
- [ ] **Split view**: with more than one calendar selected, each calendar renders as its own side-by-side column set, in the order selected, with horizontal scrolling. It is the **default** when several calendars are selected. Toggle it by opening the view dropdown and checking or clearing **Split view**.
  Source: https://support.microsoft.com/en-us/teams/meetings/view-multiple-calendars-in-microsoft-teams
- [ ] **Combined view**: events from all selected calendars overlay one grid, each calendar in its own colour.
  Source: https://support.microsoft.com/en-us/teams/meetings/view-multiple-calendars-in-microsoft-teams
- [ ] **Time scale**: view dropdown, then **Time scale**, then pick a scale. It applies immediately; a larger scale shows more time with less detail. Outlook offers 5, 6, 10, 15, 30 and 60 minutes. [Outlook-derived: confirm Teams offers the same list]
  Source: https://support.microsoft.com/en-us/teams/meetings/customize-your-calendar-in-microsoft-teams
  Source: https://support.microsoft.com/en-US/outlook/calendar/change-the-calendar-time-scale-in-outlook
- [ ] **Saved views**: view dropdown, **Saved views**, **Save current view**, enter a name, **Save**. A saved view stores filters, calendar groups and other presets. Apply one by picking it under Saved views. Delete it with **>** then **Delete** and confirm with the trash icon.
  Source: https://support.microsoft.com/en-us/teams/meetings/customize-your-calendar-in-microsoft-teams
- [ ] View-switch shortcuts: Alt+Shift+1 Day, Alt+Shift+2 Work week, Alt+Shift+3 Week, Alt+Shift+4 Month. Also Ctrl+Alt+1 Day, Ctrl+Alt+2 Work week, Ctrl+Alt+4 or Alt+= Month, and Alt+- full Week. The table is internally inconsistent (Ctrl+Alt+2 is listed for both Week and Work week).
  Source: https://support.microsoft.com/en-US/accessibility/teams/keyboard-shortcuts-for-microsoft-teams
- [ ] Current-time indicator line in day and week grids, and today's column highlighted. [verify visually]
  Source: (no doc; capture from winpc)
- [ ] Hour rows outside working hours shaded differently, driven by the Work hours setting. [Outlook-derived] [verify visually]
  Source: https://support.microsoft.com/en-gb/teams/meetings/work-plans-in-microsoft-teams

## 4. Date navigation

- [ ] Click the month label to open a date picker for any date.
  Source: https://support.microsoft.com/en-us/teams/meetings/manage-your-calendar-in-microsoft-teams
- [ ] Mini-month in the navigation pane: click a date to jump to it.
  Source: https://support.microsoft.com/en-us/teams/meetings/view-multiple-calendars-in-microsoft-teams
- [ ] Keyboard: Ctrl+Alt+Left/Right for previous/next period; Alt+Up/Down for previous/next week; Alt+PageUp/PageDown for previous/next month; Alt+Shift+Y or Home for today.
  Source: https://support.microsoft.com/en-US/accessibility/teams/keyboard-shortcuts-for-microsoft-teams
- [ ] Forum users report that month view had no continuous month-to-month scrolling at GA; navigation used the arrows.
  Source: https://techcommunity.microsoft.com/blog/microsoftteamsblog/the-new-calendar-in-microsoft-teams-now-generally-available/4373598

## 5. Navigation pane and multiple calendars

- [ ] Left pane with **Show navigation pane** holds the mini-month, **My calendars**, other people's calendars, birthday and holiday calendars, and calendar groups.
  Source: https://support.microsoft.com/en-us/teams/meetings/get-started-with-the-microsoft-teams-calendar
- [ ] Below the mini-month, a checkbox per calendar selects what to display. Clearing one hides it.
  Source: https://support.microsoft.com/en-us/teams/meetings/view-multiple-calendars-in-microsoft-teams
- [ ] Add other people's calendars (colleagues in the org), subject to their sharing permission.
  Source: https://support.microsoft.com/en-us/teams/meetings/view-multiple-calendars-in-microsoft-teams
- [ ] Add **Birthdays** and **Holidays** calendars.
  Source: https://support.microsoft.com/en-us/teams/meetings/view-multiple-calendars-in-microsoft-teams
- [ ] Calendar groups. Create: hover a calendar, **More options**, **New calendar group**, type a name, Enter saves and Esc cancels.
  Source: https://support.microsoft.com/en-us/teams/meetings/view-multiple-calendars-in-microsoft-teams
- [ ] Move a calendar into a group by dragging its name, or with **More options**, **Move to**, then the group. A person can be in only one group at a time.
  Source: https://support.microsoft.com/en-us/teams/meetings/view-multiple-calendars-in-microsoft-teams
- [ ] Delete a group or calendar: hover, **More options**, **Delete**.
  Source: https://support.microsoft.com/en-us/teams/meetings/view-multiple-calendars-in-microsoft-teams
- [ ] Per-calendar colour, used in combined view. Custom colours use a picker or hex/RGB in Outlook. [Outlook-derived; 3rd-party]
  Source: https://support.microsoft.com/en-us/teams/meetings/view-multiple-calendars-in-microsoft-teams
  Source: https://geekchamp.com/?p=1057154
- [ ] Delegate access to another person's calendar: create, respond and edit on their behalf (see section 26).
  Source: https://support.microsoft.com/en-us/teams/meetings/share-your-calendar-in-microsoft-teams
- [ ] Pick the target calendar for a new event from a calendar dropdown at the top of the form, when the user owns or delegates more than one. [Outlook-derived]
  Source: https://support.microsoft.com/en-gb/outlook/create-modify-or-delete-a-meeting-request-or-appointment-in-outlook-on-the-web
- [ ] F6 or Ctrl+Shift+Tab moves between calendar regions (pane, toolbar, grid); Tab and Shift+Tab move between events.
  Source: https://support.microsoft.com/en-US/accessibility/teams/keyboard-shortcuts-for-microsoft-teams

## 6. Event rendering on the grid

- [ ] Event block shows the title and, space permitting, the location and organizer. Height is proportional to duration on the time scale. [verify visually]
  Source: (capture from winpc)
- [ ] Category colour: an event with categories is tinted with the category colour; several categories are allowed per event. Channel meetings can't be categorized.
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-meeting-in-microsoft-teams
- [ ] Calendar colour in combined view: each calendar's events are drawn in that calendar's colour.
  Source: https://support.microsoft.com/en-us/teams/meetings/view-multiple-calendars-in-microsoft-teams
- [ ] Show-as states: **Free**, **Working elsewhere**, **Tentative**, **Busy**, **Away** (out of office). Each is styled distinctly (for example, tentative is usually hatched or striped). The Graph values are free, tentative, busy, oof, workingElsewhere and unknown. [verify visually]
  Source: https://learn.microsoft.com/en-us/graph/api/resources/event?view=graph-rest-1.0
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-meeting-in-microsoft-teams
- [ ] RSVP state on own invites: not responded, accepted, tentative, declined, or follow. Following marks the time as Free. Declined events can stay visible with distinct styling, controlled by a Filter option. [verify visually]
  Source: https://support.microsoft.com/en-us/teams/meetings/manage-your-calendar-in-microsoft-teams
  Source: https://office365itpros.com/2024/05/14/follow-response-meetings/
- [ ] All-day events render in an all-day strip at the top of day and week grids. The **All day** toggle is on the form. [Outlook-derived]
  Source: https://support.microsoft.com/en-gb/outlook/create-modify-or-delete-a-meeting-request-or-appointment-in-outlook-on-the-web
- [ ] Multi-day events span columns in the all-day strip and span cells in month view. Multi-day all-day events start and end at midnight in one time zone, per Graph. [verify visually]
  Source: https://learn.microsoft.com/en-us/graph/api/resources/event?view=graph-rest-1.0
- [ ] Overlapping events lay out side by side within a day column. [verify visually]
  Source: (capture from winpc)
- [ ] Private events show a lock indicator. Others viewing a shared calendar see only busy time, not details.
  Source: https://support.microsoft.com/en-gb/outlook/create-modify-or-delete-a-meeting-request-or-appointment-in-outlook-on-the-web
  Source: https://m365admin.handsontek.net/microsoft-teams-calendar-show-as-in-meetings/
- [ ] Recurring-series indicator icon; a modified occurrence (exception) shows a broken-series icon. [Outlook-derived] [verify visually]
  Source: https://learn.microsoft.com/en-us/graph/api/resources/event?view=graph-rest-1.0
- [ ] Cancelled meetings stay until removed and show as "Canceled:" with a strike-through or label. Graph exposes isCancelled. [verify visually]
  Source: https://learn.microsoft.com/en-us/graph/api/resources/event?view=graph-rest-1.0
- [ ] Inline **Join** button on Teams meeting tiles near start time. See section 23 for timing.
  Source: https://support.microsoft.com/en-us/teams/meetings/join-a-meeting-in-microsoft-teams
- [ ] Event type badges for webinar, town hall, virtual appointment and channel meeting (channel name shown). [verify visually]
  Source: https://support.microsoft.com/en-us/teams/meetings/see-all-your-meetings-in-microsoft-teams
- [ ] Drag an event to a new slot to reschedule. Teams shows invitee availability before the update is sent.
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-meeting-in-microsoft-teams
- [ ] Ctrl-drag to duplicate (works in new Outlook; unconfirmed in Teams). [3rd-party]
  Source: https://techcommunity.microsoft.com/idea/microsoft365developerplatform/fix-hold-ctrl-while-dragging-event-to-duplicate-event-in-new-outlook-calendar-/3686495

## 7. Selection, context menu and peek (quick view)

- [ ] Click a timeslot to open **quick create** (a quick view to create a meeting in a few steps), with an option to expand to the full form.
  Source: https://techcommunity.microsoft.com/blog/microsoftteamsblog/the-new-calendar-in-microsoft-teams-now-generally-available/4373598
- [ ] Click an event to open the **peek** card with summary, **Join**, **RSVP** and **View event**. For past meetings it shows the artifacts: **Recap** and **Chat**.
  Source: https://mc.merill.net/message/MC908116
  Source: https://support.microsoft.com/en-us/teams/meetings/get-started-with-the-microsoft-teams-calendar
  Source: https://support.microsoft.com/en-us/teams/meetings/manage-your-calendar-in-microsoft-teams
- [ ] Right-click context menu on an event: **Categorize** (pick a colour, or **New category**), **Show as**, **Private**, **Duplicate event**, **Delete**/**Cancel**, **Join**. Only Categorize is confirmed for Teams; the rest are [Outlook-derived].
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-meeting-in-microsoft-teams
  Source: https://support.microsoft.com/en-us/outlook/sharing/new-outlook-tips-for-executive-admins-and-delegates
- [ ] Keyboard on a selected event: Enter opens, Esc closes, Delete deletes, Ctrl+J joins, Alt+R replies to the meeting, Ctrl+Alt+R replies all, Ctrl+Alt+F forwards.
  Source: https://support.microsoft.com/en-US/accessibility/teams/keyboard-shortcuts-for-microsoft-teams

## 8. New meeting form - core fields

- [ ] Open with **New**, by clicking a timeslot, with Alt+N or Ctrl+N, or with **Schedule a meeting** from a chat or channel.
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-meeting-in-microsoft-teams
  Source: https://support.microsoft.com/en-US/accessibility/teams/keyboard-shortcuts-for-microsoft-teams
- [ ] Title field ("Add a title").
  Source: https://support.microsoft.com/en-gb/outlook/create-modify-or-delete-a-meeting-request-or-appointment-in-outlook-on-the-web
- [ ] **Required attendees** field with people picker (directory search; full email for external invitees).
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-meeting-in-microsoft-teams
- [ ] Optional attendees: **Response options**, **Add optional attendees**, then the **Invite optional attendees** field. (Classic used "Optional +".)
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-meeting-in-microsoft-teams
- [ ] Start date and time, end date and time pickers. Inline availability hints for invitees appear below the date and time.
  Source: https://support.microsoft.com/en-gb/outlook/create-modify-or-delete-a-meeting-request-or-appointment-in-outlook-on-the-web
- [ ] **All day** toggle.
  Source: https://support.microsoft.com/en-gb/outlook/create-modify-or-delete-a-meeting-request-or-appointment-in-outlook-on-the-web
- [ ] Repeat / recurrence control (default "Does not repeat"). See section 9.
  Source: https://support.microsoft.com/en-gb/outlook/create-modify-or-delete-a-meeting-request-or-appointment-in-outlook-on-the-web
- [ ] Time zone selector for the event, with separate start and end time zones (Graph originalStartTimeZone and originalEndTimeZone). The GA notes list "support for multiple time zones". [Outlook-derived for the exact UI]
  Source: https://techcommunity.microsoft.com/blog/microsoftteamsblog/the-new-calendar-in-microsoft-teams-now-generally-available/4373598
  Source: https://learn.microsoft.com/en-us/graph/api/resources/event?view=graph-rest-1.0
- [ ] Location field "Search for a room or location" with suggestions. See section 11.
  Source: https://support.microsoft.com/en-gb/outlook/create-modify-or-delete-a-meeting-request-or-appointment-in-outlook-on-the-web
- [ ] **Add channel** field: invite a standard channel, which turns the event into a channel meeting. A channel can't be added or changed after sending.
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-meeting-in-microsoft-teams
- [ ] **Teams meeting** toggle: must be on for an online meeting. Inviting attendees turns it on.
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-meeting-in-microsoft-teams
  Source: https://support.microsoft.com/en-gb/teams/meetings/personal-meeting-templates-in-microsoft-teams
- [ ] Rich-text details/body editor: formatting toolbar (Alt+F10 focuses it), Ctrl+K inserts a link, Ctrl+Z undoes.
  Source: https://support.microsoft.com/en-US/accessibility/teams/keyboard-shortcuts-for-microsoft-teams
- [ ] **Add an agenda** in Details creates collaborative Loop meeting notes (agenda, notes, tasks) attached to the invite.
  Source: https://support.microsoft.com/en-gb/teams/meetings/take-meeting-notes-in-microsoft-teams
- [ ] Attachments on the event. The GA notes list "support for attachments". Group-calendar events can't have attachments (Graph).
  Source: https://techcommunity.microsoft.com/blog/microsoftteamsblog/the-new-calendar-in-microsoft-teams-now-generally-available/4373598
  Source: https://learn.microsoft.com/en-us/graph/api/resources/event?view=graph-rest-1.0
- [ ] **Category** at the top of the form to assign categories.
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-meeting-in-microsoft-teams
- [ ] **Show as** dropdown in the action bar (default **Busy**). Attendees' RSVPs take on the organizer's chosen show-as. The same menu holds the private flag. [private part Outlook-derived]
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-meeting-in-microsoft-teams
  Source: https://support.microsoft.com/en-gb/outlook/create-modify-or-delete-a-meeting-request-or-appointment-in-outlook-on-the-web
- [ ] **Remind me** reminder dropdown (default 15 minutes before). [Outlook-derived]
  Source: https://support.microsoft.com/en-gb/outlook/create-modify-or-delete-a-meeting-request-or-appointment-in-outlook-on-the-web
- [ ] **Meeting options** button on the form opens the options panel (section 15). Organizers only.
  Source: https://support.microsoft.com/en-gb/teams/meetings/personal-meeting-templates-in-microsoft-teams
- [ ] **Scheduler** button opens the scheduling assistant (section 10).
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-meeting-in-microsoft-teams
- [ ] Save actions: **Save** (no attendees or appointment), **Send** (new with attendees), **Send update** (edit). Ctrl+S saves; Ctrl+Enter sends; Esc discards the draft.
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-meeting-in-microsoft-teams
  Source: https://support.microsoft.com/en-US/accessibility/teams/keyboard-shortcuts-for-microsoft-teams
- [ ] Time suggestions: suggested meeting times based on attendee availability. The GA notes list "time suggestions in scheduling"; Alt+Shift+S goes to a suggested time.
  Source: https://techcommunity.microsoft.com/blog/microsoftteamsblog/the-new-calendar-in-microsoft-teams-now-generally-available/4373598
  Source: https://support.microsoft.com/en-US/accessibility/teams/keyboard-shortcuts-for-microsoft-teams
- [ ] Attendee limits: 1,000 interactive participants; up to 10,000 view-only once 1,000 have joined. Graph events allow at most 500 attendees.
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-meeting-in-microsoft-teams
  Source: https://learn.microsoft.com/en-us/graph/api/resources/event?view=graph-rest-1.0
- [ ] Schedule from chat: **More chat options** in the chat header, then **Schedule a meeting**. The form is pre-filled with the chat members; finish with **Send**.
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-meeting-in-microsoft-teams
- [ ] Dial-in number and conference ID in the invite when Audio Conferencing is licensed.
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-meeting-in-microsoft-teams

## 9. Recurrence (Repeat)

- [ ] Repeat dropdown presets. The doc confirms Repeat exists; the preset labels (Does not repeat, Every weekday, Daily, Weekly, Monthly, Yearly, Custom) come from 3rd-party guides. [Outlook-derived]
  Source: https://support.microsoft.com/en-gb/outlook/create-modify-or-delete-a-meeting-request-or-appointment-in-outlook-on-the-web
  Source: https://www.hendrix.edu/HelpDesk_Articles/Teams_Collaboration_Tools/Meetings/Scheduling_and_Inviting/Schedule_a_Recurring_Meeting
- [ ] Custom recurrence dialog: interval "Repeat every N" with unit day, week, month or year. Weekly needs a weekday picker. Monthly is by date or by "Nth weekday". Yearly is by date or relative. These map to Graph pattern types daily, weekly, absoluteMonthly, relativeMonthly, absoluteYearly and relativeYearly.
  Source: https://learn.microsoft.com/en-us/graph/api/resources/patternedrecurrence?view=graph-rest-1.0
- [ ] Series range: start date, then an end by date, after N occurrences, or no end (Graph range types endDate, numbered, noEnd). A series repeats indefinitely unless an end is set.
  Source: https://learn.microsoft.com/en-us/graph/api/resources/patternedrecurrence?view=graph-rest-1.0
  Source: https://www.hendrix.edu/HelpDesk_Articles/Teams_Collaboration_Tools/Meetings/Scheduling_and_Inviting/Schedule_a_Recurring_Meeting
- [ ] Limitation: one start time for all days in a series; different times on different days aren't possible. [3rd-party]
  Source: https://techcommunity.microsoft.com/discussions/microsoftteams/allow-custom-recurring-meetings-with-different-times-on-different-days/4401286

## 10. Scheduler (scheduling assistant), availability and time zones

- [ ] **Scheduler** button on the form opens a grid of attendee rows across timeslots. Busy and tentative times are shaded; free time is unshaded.
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-meeting-in-microsoft-teams
- [ ] Scheduler shows each attendee's time zone next to their name. (Roadmap 123963: show attendee time zones in the scheduling form.)
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-meeting-in-microsoft-teams
  Source: https://uctoday.com/teams-to-simplify-planning-international-meetings
- [ ] Selecting a slot in the Scheduler updates the meeting start and end. **Send** sends from the Scheduler. [verify visually]
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-meeting-in-microsoft-teams
- [ ] Inline availability under the date and time pickers, plus suggested times.
  Source: https://support.microsoft.com/en-gb/outlook/create-modify-or-delete-a-meeting-request-or-appointment-in-outlook-on-the-web
- [ ] Rooms appear as attendees in the Scheduler with their free/busy. [Outlook-derived]
  Source: https://geekchamp.com/?p=1057154
- [ ] Calendar-level time zone and additional time zones shown as extra time rulers in the grid. Set in Calendar settings. [Outlook-derived]
  Source: https://geekchamp.com/?p=1057154
  Source: https://techcommunity.microsoft.com/blog/microsoftteamsblog/the-new-calendar-in-microsoft-teams-now-generally-available/4373598

## 11. Location, rooms and Places

- [ ] Location box "Search for a room or location" with suggestions as you type (rooms, recent places, addresses).
  Source: https://support.microsoft.com/en-gb/outlook/create-modify-or-delete-a-meeting-request-or-appointment-in-outlook-on-the-web
- [ ] Room details in suggestions: capacity and technical specs (AV equipment).
  Source: https://support.microsoft.com/en-us/teams/meetings/get-started-with-the-microsoft-teams-calendar
- [ ] **Browse with Places Finder** (Teams Premium / Places): browse buildings, switch floors, view room capabilities, see availability.
  Source: https://support.microsoft.com/en-us/teams/meetings/get-started-with-the-microsoft-teams-calendar
  Source: https://mc.merill.net/message/MC908116
- [ ] **Browse more rooms**: room lists by city or building, with search. [Outlook-derived]
  Source: https://support.microsoft.com/en-gb/outlook/create-modify-or-delete-a-meeting-request-or-appointment-in-outlook-on-the-web
- [ ] Several locations per event (Graph `locations` collection). [Outlook-derived]
  Source: https://learn.microsoft.com/en-us/graph/api/resources/event?view=graph-rest-1.0
- [ ] **In-person event** toggle next to location (marks a hybrid or in-person event). Confirmed for Outlook only; unconfirmed in Teams. [Outlook-derived]
  Source: https://support.microsoft.com/en-us/topic/956ae899-096e-419d-b812-a515d0710611

## 12. Event kinds: online vs offline, private, channel

- [ ] Offline meeting or appointment: turn the **Teams meeting** toggle off. No online meeting space is created. Allowed for private (non-channel) meetings only.
  Source: https://office365itpros.com/2023/05/23/teams-offline-meeting/
- [ ] Appointment (no attendees) uses **Save**; a meeting (with attendees) uses **Send**.
  Source: https://support.microsoft.com/en-gb/outlook/create-modify-or-delete-a-meeting-request-or-appointment-in-outlook-on-the-web
- [ ] Private event flag (sensitivity private): shared-calendar viewers can't see details. Graph sensitivity values are normal, personal, private and confidential.
  Source: https://learn.microsoft.com/en-us/graph/api/resources/event?view=graph-rest-1.0
  Source: https://m365admin.handsontek.net/microsoft-teams-calendar-show-as-in-meetings/
- [ ] Channel meeting: visible to and joinable by everyone in the team, in the channel. Not available in private channels. External invitees can't see the channel calendar. Each team member gets a personal invite.
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-meeting-in-microsoft-teams

## 13. Response options and attendee privacy

- [ ] **Response options** menu on the form: **Request responses** (on by default), **Allow forwarding**, **Hide attendee list**, **Add optional attendees** (the last confirmed for Teams). The others are [Outlook-derived].
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-meeting-in-microsoft-teams
  Source: https://support.microsoft.com/en-gb/outlook/create-modify-or-delete-a-meeting-request-or-appointment-in-outlook-on-the-web
- [ ] Allow new time proposals: organizer setting, default true. Graph: allowNewTimeProposals. Not offered for recurring meetings.
  Source: https://learn.microsoft.com/en-us/graph/api/resources/event?view=graph-rest-1.0
  Source: https://support.microsoft.com/en-gb/outlook/calendar/propose-a-new-meeting-time-in-outlook
- [ ] Hide attendee list (Graph hideAttendees): each attendee sees only themselves in the request and the tracking list.
  Source: https://learn.microsoft.com/en-us/graph/api/resources/event?view=graph-rest-1.0
- [ ] Follow RSVP appears only when the meeting has 2 or more participants and the organizer requested responses.
  Source: https://office365itpros.com/2024/05/14/follow-response-meetings/

## 14. Show as, categories, reminders (per event)

- [ ] Show as values: Free, Working elsewhere, Tentative, Busy, Away / Out of office. Default Busy. Set by the organizer for attendees.
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-meeting-in-microsoft-teams
  Source: https://learn.microsoft.com/en-us/graph/api/resources/event?view=graph-rest-1.0
- [ ] Categorize: right-click, **Categorize**, then a colour category. Several allowed. **New category** creates one. Category definitions are the user's Outlook master categories.
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-meeting-in-microsoft-teams
  Source: https://support.microsoft.com/en-us/outlook/sharing/new-outlook-tips-for-executive-admins-and-delegates
- [ ] Reminder per event: minutes before start (default 15). Graph isReminderOn and reminderMinutesBeforeStart. Snooze and dismiss apply to user calendars only.
  Source: https://support.microsoft.com/en-gb/outlook/create-modify-or-delete-a-meeting-request-or-appointment-in-outlook-on-the-web
  Source: https://learn.microsoft.com/en-us/graph/api/resources/event?view=graph-rest-1.0

## 15. Meeting options (organizer settings for the online meeting)

- [ ] Open meeting options: Teams calendar, select an event, **View event**, **Options**. In a meeting: **Controls**, **View more options**. The page may open in a browser window. Changes take effect with **Apply**.
  Source: https://support.microsoft.com/en-gb/teams/meetings/meeting-options-in-microsoft-teams
- [ ] Meet now flow: **Get a link to share** offers **Configure meeting options**.
  Source: https://support.microsoft.com/en-us/teams/meetings/start-an-instant-meeting-in-microsoft-teams
- [ ] Options are grouped in sections: **Meeting access**, **Advanced protection**, **Roles**, **Production tools**, **Participation**, **Recording & transcription**, **Copilot and other AI**, **Accessibility**.
  Source: https://support.microsoft.com/en-gb/teams/meetings/meeting-options-in-microsoft-teams
- [ ] Meeting access: **Sensitivity** (Premium label), **Who can bypass the lobby?**, **People dialing in can bypass the lobby**, **Who can admit from the lobby**, **Show meeting info on join screen**, **Reject anyone who can't bypass the lobby**, **Announce when people dialing in join or leave**, **Require unverified participants to verify their info before joining** (Premium, emailed OTP), **Verify external presenters before joining an event**.
  Source: https://support.microsoft.com/en-gb/teams/meetings/meeting-options-in-microsoft-teams
- [ ] Advanced protection (Premium): **Turn off copying and forwarding of meeting chat and transcripts**, **End-to-end encryption**, **Apply a watermark to shared content**, **Apply a watermark to everyone's video feed**, **Prevent screen captures**, **Detect sensitive content during screen sharing**.
  Source: https://support.microsoft.com/en-gb/teams/meetings/meeting-options-in-microsoft-teams
- [ ] Roles: **Choose co-organizers**, **Who can present**, **Enable language interpretation**.
  Source: https://support.microsoft.com/en-gb/teams/meetings/meeting-options-in-microsoft-teams
- [ ] Production tools: **Manage what attendees see**, **RTMP - In**, **Enable Green room**.
  Source: https://support.microsoft.com/en-gb/teams/meetings/meeting-options-in-microsoft-teams
- [ ] Participation: **Allow mic for attendees**, **Allow camera for attendees**, **Meeting chat** (anytime / during meeting only / off), **Q&A**, **Allow reactions**, **Hide attendee names**, **Allow attendance report**.
  Source: https://support.microsoft.com/en-gb/teams/meetings/meeting-options-in-microsoft-teams
- [ ] Recording & transcription: **Record and transcribe automatically**, **Who can record and transcribe**, **Who has access to the recording and transcript** (not for channel meetings), **Enable multilingual speech recognition**.
  Source: https://support.microsoft.com/en-gb/teams/meetings/meeting-options-in-microsoft-teams
- [ ] Copilot and other AI: **Allow Copilot** dropdown (e.g. "Only during the meeting") and **Facilitator**. Accessibility: **Provide CART Captions**.
  Source: https://support.microsoft.com/en-gb/teams/meetings/meeting-options-in-microsoft-teams
- [ ] Defaults come from admin policy and some options can be locked. During an outage, options may revert to the defaults.
  Source: https://support.microsoft.com/en-gb/teams/meetings/meeting-options-in-microsoft-teams
- [ ] **Save as template** from Meeting options (Premium personal templates). Sensitivity labels aren't saved in templates.
  Source: https://support.microsoft.com/en-gb/teams/meetings/personal-meeting-templates-in-microsoft-teams

## 16. Co-organizers

- [ ] Up to 10 co-organizers, all in the organizer's org (guests in the same org allowed). They must first be required attendees. Path: **View event**, **Options**, **Roles**, **Choose co-organizers**, **Apply**.
  Source: https://support.microsoft.com/en-gb/teams/meetings/add-co-organizers-to-a-meeting-in-microsoft-teams
- [ ] Co-organizers can change options, manage breakout rooms, bypass and admit from the lobby, lock, present, change roles and end the meeting for all. They can't manage the recording, change the organizer, or edit the invite and send updates.
  Source: https://support.microsoft.com/en-gb/teams/meetings/add-co-organizers-to-a-meeting-in-microsoft-teams

## 17. Event types and templates (New dropdown)

- [ ] **Meeting** (default New).
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-meeting-in-microsoft-teams
- [ ] **Webinar**: New dropdown, then **Webinar** (section 18).
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-webinar-in-microsoft-teams
- [ ] **Town hall**: New dropdown, then **Town hall** (section 19).
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-town-hall-in-microsoft-teams
- [ ] **Virtual appointment**: New dropdown, then **Virtual appointment**. The form has an **External Guest** field (external guests get a tailored join flow, "Join appointment as a guest", and join anonymously in the browser with a waiting room). Internal attendees and a description are also on the form. SMS confirmations, updates and reminders need Premium and a US, Canada or UK number. Finish with **Send**.
  Source: https://support.microsoft.com/en-gb/teams/shifts/use-a-teams-meeting-template-to-create-a-virtual-appointment
- [ ] Virtual appointment guest-join honours only these options: who can bypass the lobby (Everyone), co-organizers, record automatically, and meeting chat (disabled, otherwise In-meeting only).
  Source: https://support.microsoft.com/en-gb/teams/shifts/use-a-teams-meeting-template-to-create-a-virtual-appointment
- [ ] Event (no Teams meeting): the Teams meeting toggle is off (see section 12).
  Source: https://office365itpros.com/2023/05/23/teams-offline-meeting/
- [ ] Personal templates (Premium): New dropdown, **Create template**, set Meeting options, **Save as template**, name and optional description, **Save**. Use one from **Your templates** or **View all templates** with **Schedule**. **Edit** applies changes; **Delete** is permanent. Maximum 40 templates. Delegates can use their own templates for the boss's calendar. Not available on mobile.
  Source: https://support.microsoft.com/en-gb/teams/meetings/personal-meeting-templates-in-microsoft-teams
- [ ] Live events are not schedulable in the new calendar (legacy; retired in favour of town halls).
  Source: https://support.microsoft.com/office/get-started-with-the-new-calendar-in-microsoft-teams-98f3b637-5da2-43e2-91b3-f312ab3e4dc5

## 18. Webinar specifics

- [ ] Details form: title, date, start and end, description, **Presenters from your org**, **Co-organizers** (up to 10, in-org only; co-organizers can't edit Details).
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-webinar-in-microsoft-teams
- [ ] Access: **Public** (default; anyone can register) or **Your organization**. It can only be changed before publishing.
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-webinar-in-microsoft-teams
- [ ] Presenter-only meeting notes: agenda, notes and pre-event tasks, hidden from attendees.
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-webinar-in-microsoft-teams
- [ ] **Save** goes on to registration; presenters are invited automatically on save. A registration link and registration form are generated; presenters don't need to register.
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-webinar-in-microsoft-teams
- [ ] **Manage event** page with a **Setup** section (**Presenters**, etc.) and **Publish site**. Presenter order is drag-handle reorderable, with **To top**, **To bottom** and **Hide from attendees**. The first 6 presenters show on the event site.
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-webinar-in-microsoft-teams
- [ ] External presenters: up to 20, via **Add external presenters** then **Save and send invites**. Each gets a unique join link that bypasses the lobby, works on up to 3 devices, and can be copied or reloaded under **External presenters**, **Unique join link**.
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-webinar-in-microsoft-teams
- [ ] **Duplicate event** (View event, Duplicate event) copies title, description, presenters, theme, registration, emails and options. Options aren't copied if the source wasn't modified or joined in 60 days.
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-webinar-in-microsoft-teams
- [ ] Date or time changes email registered, pending and waitlisted users. A published site updates automatically. Cancelling a webinar can't be undone.
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-webinar-in-microsoft-teams
  Source: https://support.microsoft.com/en-us/office/cancel-a-webinar-in-microsoft-teams-3a48f91d-fa13-4e2c-97d6-1eb55f79ed34

## 19. Town hall specifics

- [ ] New dropdown, **Town hall**, then **Details**: title, start and end date, description. Maximum duration 30 hours. The organizer is the creator. **Event group** holds **Co-organizers** and **Presenters from your org**. **Save and send invites**.
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-town-hall-in-microsoft-teams
- [ ] **Event access**: **Your organization**, **Public**, or **People and groups** (up to 500 people and 20 groups; no dynamic or federated groups). **Invite attendees** picker. **Only allow invited people to join** toggle.
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-town-hall-in-microsoft-teams
- [ ] **Publish** sends attendee invites. Event emails can be edited or turned off before publishing. **Share event** gives a **Video embed HTML** copy for SharePoint.
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-town-hall-in-microsoft-teams
- [ ] Capacity: 3,000 interactive or 10,000 view-only attendees; up to 100,000 with capacity packs. Attendees watch about 20-30 seconds behind.
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-town-hall-in-microsoft-teams
- [ ] External presenters (up to 20, **View join link**, Copy or Reload) and **Duplicate event**, as for webinars. Cancelling a town hall can't be undone.
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-town-hall-in-microsoft-teams
  Source: https://support.microsoft.com/en-us/office/cancel-a-town-hall-in-microsoft-teams-0be88477-3ef5-4f01-88fd-96194f74300c

## 20. Meeting details page (View event)

- [ ] **View event** from the peek opens the full event page in the main pane.
  Source: https://support.microsoft.com/en-us/teams/meetings/manage-your-calendar-in-microsoft-teams
- [ ] Header actions: **Join**, **Share** (**Copy join link**), **RSVP** / **RSVP with note**, **Options** (meeting options), **Duplicate event**, **Manage event** (webinar and town hall), Cancel/Delete, edit fields with **Send update**.
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-meeting-in-microsoft-teams
  Source: https://support.microsoft.com/en-gb/teams/meetings/meeting-options-in-microsoft-teams
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-webinar-in-microsoft-teams
- [ ] **Details** > **Show meeting info** reveals the meeting ID, passcode and dial-in.
  Source: https://support.microsoft.com/en-us/teams/meetings/join-a-meeting-in-microsoft-teams
- [ ] **Expand meeting details** shows the full body, and below it the collaborative meeting notes or agenda (Loop). Agenda edits save live. In a series, **View series** edits the series agenda.
  Source: https://support.microsoft.com/en-gb/teams/meetings/take-meeting-notes-in-microsoft-teams
- [ ] **Chat** tab/link: the meeting chat (available before, during and after, per meeting option).
  Source: https://support.microsoft.com/en-us/teams/meetings/get-started-with-the-microsoft-teams-calendar
  Source: https://support.microsoft.com/en-gb/teams/meetings/meeting-options-in-microsoft-teams
- [ ] **Recap** / **View recap** (after a recorded or transcribed meeting): recording, transcript, shared files, **Notes**, custom summary, agenda, follow-up tasks. An occurrence dropdown and **Load more meetings** cover recurring series. **Open meeting recap in new window**, **Share** / **Copy link** / **Share to email**, and **More options** > **Delete recap content** (organizer or co-organizer).
  Source: https://support.microsoft.com/en-gb/teams/meetings/recap-in-microsoft-teams
  Source: https://support.microsoft.com/en-gb/teams/meetings/take-meeting-notes-in-microsoft-teams
- [ ] **Attendance** tab (organizers and co-organizers, past meetings): first-join and last-leave per person, engagement data (reactions, raised hands, cameras), **Download** as CSV, and an occurrence dropdown for series. Co-organizers get reports only for meetings scheduled in Teams; the meeting chat shows a report tile about 5 minutes after the end.
  Source: https://support.microsoft.com/en-gb/teams/meetings/manage-meeting-attendance-reports-in-microsoft-teams
- [ ] Files: files shared in the meeting chat and recap. The Recap "files" section covers this; a separate Files tab is not documented for the new calendar. [verify visually]
  Source: https://support.microsoft.com/en-gb/teams/meetings/recap-in-microsoft-teams
- [ ] Tracking: attendee list with response status per person (accepted, tentative, declined, no response, following). [Outlook-derived] [verify visually]
  Source: https://learn.microsoft.com/en-us/graph/api/resources/event?view=graph-rest-1.0
- [ ] Recap and notes aren't available for ad-hoc meetings or calls.
  Source: https://support.microsoft.com/en-gb/teams/meetings/recap-in-microsoft-teams

## 21. RSVP

- [ ] **RSVP** button with **Accept**, **Tentative**, **Decline** and **Follow**. The organizer gets an email of the response.
  Source: https://support.microsoft.com/en-us/teams/meetings/manage-your-calendar-in-microsoft-teams
- [ ] For a series, hovering the response offers **This event** or **All events in the series**.
  Source: https://support.microsoft.com/en-us/teams/meetings/manage-your-calendar-in-microsoft-teams
- [ ] **RSVP with note**: **View event**, **RSVP with note**, type the note, choose a response from the dropdown if none is chosen, **Confirm**.
  Source: https://support.microsoft.com/en-us/teams/meetings/manage-your-calendar-in-microsoft-teams
- [ ] Respond without sending a reply (Graph sendResponse=false). [Outlook-derived]
  Source: https://learn.microsoft.com/en-us/graph/api/event-tentativelyaccept?view=graph-rest-1.0
- [ ] **Follow** semantics: "can't attend but stay informed". The time shows as Free and the user keeps access to chat, recap, recording and transcript, plus a notification when the recap is ready. The organizer is prompted to record when followers exist. Decline removes access.
  Source: https://office365itpros.com/2024/05/14/follow-response-meetings/
  Source: https://mc.merill.net/message/MC786325
- [ ] A channel event can be added to the personal calendar with **Add to calendar**.
  Source: https://support.microsoft.com/en-us/teams/meetings/see-all-your-meetings-in-microsoft-teams

## 22. Propose new time

- [ ] Propose new time: as a Tentative ("I might attend") or Decline ("No, I won't attend") response, pick an alternate slot, then **Done**, optional message, **Send**. The organizer accepts or declines the proposal. Not for recurring meetings, and not when the organizer disabled it. Documented for new Outlook; a 2024 forum says Teams lacked it. Verify on winpc. [Outlook-derived]
  Source: https://support.microsoft.com/en-gb/outlook/calendar/propose-a-new-meeting-time-in-outlook
  Source: https://techcommunity.microsoft.com/t5/microsoft-teams/possibility-to-new-time-proposal-in-teams-meeting/m-p/4132198
  Source: https://learn.microsoft.com/en-us/graph/api/event-tentativelyaccept?view=graph-rest-1.0

## 23. Edit, reschedule, cancel; series vs occurrence

- [ ] Edit as organizer: open the event, change fields, **Send update**; attendees are notified automatically.
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-meeting-in-microsoft-teams
- [ ] Recurring edit scope prompt: **This event**, **This and all following events**, **All events in the series**. [Outlook-derived]
  Source: https://support.microsoft.com/en-gb/outlook/create-modify-or-delete-a-meeting-request-or-appointment-in-outlook-on-the-web
- [ ] Cancel (meeting) vs **Delete** (appointment). Cancel takes an optional message, then **Send**. For a series the same three-way scope applies. [Outlook-derived; the Teams "Cancel occurrence / Cancel series" wording is 3rd-party]
  Source: https://support.microsoft.com/en-gb/outlook/create-modify-or-delete-a-meeting-request-or-appointment-in-outlook-on-the-web
  Source: https://www.guideflow.com/tutorial/how-to-cancel-an-occurrence-of-a-scheduled-meeting-in-microsoft-teams
- [ ] Attendee view of a cancelled meeting: "Remove from calendar" action. [Outlook-derived] [verify visually]
  Source: https://learn.microsoft.com/en-us/graph/api/resources/event?view=graph-rest-1.0
- [ ] Drag-and-drop reschedule with an availability check before the update is sent.
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-meeting-in-microsoft-teams
- [ ] Channel can't be changed after sending; send a new invite instead.
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-meeting-in-microsoft-teams
- [ ] Forward a meeting (Ctrl+Alt+F). The organizer can be notified when their meeting is forwarded (Calendar notifications).
  Source: https://support.microsoft.com/en-US/accessibility/teams/keyboard-shortcuts-for-microsoft-teams
  Source: https://support.microsoft.com/en-gb/teams/notifications-settings/manage-notifications-in-microsoft-teams
- [ ] **Duplicate event** for regular meetings, from the right-click menu. [Outlook-derived for meetings; documented for webinars and town halls]
  Source: https://support.microsoft.com/en-us/outlook/sharing/new-outlook-tips-for-executive-admins-and-delegates

## 24. Join (from calendar), timing and live bar

- [ ] Join from the calendar: select the meeting, then **Join**, which opens the pre-join screen (device setup, **Join now**). Shortcuts: Alt+Shift+J joins from meeting details; Ctrl+J joins the selected event.
  Source: https://support.microsoft.com/en-us/teams/meetings/join-a-meeting-in-microsoft-teams
  Source: https://support.microsoft.com/en-US/accessibility/teams/keyboard-shortcuts-for-microsoft-teams
- [ ] Join button timing: appears on the calendar tile about 5 minutes before start (a school IT page; forum reports 5-10 minutes). Outlook's equivalent appears 15 minutes before. No Microsoft Teams doc states it. [3rd-party] [verify on winpc]
  Source: https://vrsupport.nysed.gov/hc/en-us/articles/360056482314-Join-a-Teams-Meeting
  Source: https://techcommunity.microsoft.com/discussions/microsoftteams/how-does-the-join-button-work-for-the-teams-calendar/1604760
  Source: https://insider.microsoft365.com/en-us/blog/join-online-button
- [ ] Live meeting join bar: for meetings RSVP'd Accept or Tentative, a bar shows the title, **Join**, and the count of other live meetings. With several live, **View meetings** opens a list. Turn it off in Settings > Notifications and activity > Meetings > **Show meeting join bar**.
  Source: https://support.microsoft.com/en-us/teams/meetings/join-a-meeting-in-microsoft-teams
- [ ] Meeting-started toast: Ctrl+Shift+J joins from it; Ctrl+Shift+R opens the meeting chat from it.
  Source: https://support.microsoft.com/en-US/accessibility/teams/keyboard-shortcuts-for-microsoft-teams
- [ ] **Join with an ID**: Meet now dropdown, **Join with an ID**, enter Meeting ID and Passcode, **Join meeting**. The ID and passcode are under Details > Show meeting info and at the top of the invite email. Requires an Exchange Online mailbox.
  Source: https://support.microsoft.com/en-us/teams/meetings/join-a-meeting-in-microsoft-teams
- [ ] Invite link format: meetings scheduled after 20 Jan 2026 (8 Jan in some regions) show the full URL; older invites show "Join meeting now". Both must be parsed.
  Source: https://support.microsoft.com/en-us/teams/meetings/join-a-meeting-in-microsoft-teams
- [ ] Pre-join from the calendar: **Change** account, **Add another account**, **Join without signing in** (anonymous, type a name), **Call me** dial-out to a phone, **Room audio** (Bluetooth room detection).
  Source: https://support.microsoft.com/en-us/teams/meetings/join-a-meeting-in-microsoft-teams
- [ ] Join from the meeting chat (**Join** at the top of the chat) and from a channel meeting post.
  Source: https://support.microsoft.com/en-us/teams/meetings/join-a-meeting-in-microsoft-teams

## 25. Meet now (from calendar)

- [ ] **Meet now** (upper right) opens a flyout with an editable **Meeting name**, **Get a link to share** (and then **Configure meeting options**), and **Start meeting**, which goes to pre-join and then **Join now**.
  Source: https://support.microsoft.com/en-us/teams/meetings/start-an-instant-meeting-in-microsoft-teams
- [ ] After joining, an invite prompt offers **Copy meeting link**, **Share invite** > **Share via default email**, and People > "Invite someone or dial a number". The meeting chat persists for rejoining later.
  Source: https://support.microsoft.com/en-us/teams/meetings/start-an-instant-meeting-in-microsoft-teams
- [ ] Settings toggle **Meet now start notifications**.
  Source: https://support.microsoft.com/en-gb/teams/notifications-settings/manage-notifications-in-microsoft-teams

## 26. Calendar settings (More options > Calendar settings)

- [ ] Opens a settings dialog with a left section list. Settings are shared with Outlook on the web and new Outlook (one mailbox setting set).
  Source: https://support.microsoft.com/en-us/teams/meetings/get-started-with-the-microsoft-teams-calendar
  Source: https://blog.topedia.com/2024/11/new-calendar-experience-in-microsoft-teams/
- [ ] **Work hours and location** section: the work-hours time zone at the top; workday checkboxes; per-day start and end dropdowns; **Add work hours** (+) for a second range on the same day; per-day location dropdown; **Show work location on my calendar**; **Share your location** > **People in my organization** detail level; **Save**.
  Source: https://support.microsoft.com/en-gb/teams/meetings/work-plans-in-microsoft-teams
  Source: https://ci.teamdynamix.com/TDClient/1891/Portal/KB/PrintArticle?ID=171904
- [ ] Appearance: first day of the week, show week numbers, time scale, date and time format, theme. [Outlook-derived] The first day of week historically followed the app language in classic Teams.
  Source: https://geekchamp.com/?p=1057154
  Source: https://www.technipages.com/microsoft-teams-changing-the-first-day-of-the-week
- [ ] Time zones: calendar time zone plus additional time zones with labels. [Outlook-derived]
  Source: https://geekchamp.com/?p=1057154
- [ ] Events and invitations: default event start and end times (e.g. shorten or end early), default reminder, location settings. The GA notes mention "customizable event start and end times, and location settings". [Outlook-derived for exact names]
  Source: https://techcommunity.microsoft.com/blog/microsoftteamsblog/the-new-calendar-in-microsoft-teams-now-generally-available/4373598
- [ ] Weather settings (on or off, temperature unit). [Outlook-derived]
  Source: https://mc.merill.net/message/MC908116
- [ ] Shared calendars and delegation management. [Outlook-derived]
  Source: https://geekchamp.com/?p=1057154

## 27. Sharing, delegation, printing

- [ ] **More options** > **Share**: enter an email or name, choose a permission, **Share**. Permissions: **Can view when I'm busy**, **Can view titles and locations**, **Can view all details**, **Can edit**, **Can delegate** (create, modify and delete, and respond to invitations on your behalf).
  Source: https://support.microsoft.com/en-us/teams/meetings/share-your-calendar-in-microsoft-teams
- [ ] Org-wide default: **Inside your organization** > **People in my organization** permission dropdown. Some permissions are limited by policy.
  Source: https://support.microsoft.com/en-us/teams/meetings/share-your-calendar-in-microsoft-teams
- [ ] **More options** > **Print** dialog: **Calendar** dropdown (one calendar or **Selected calendars**), **View**, **Layout** (orientation, for Week or Work week), **Time range** (hours), **Mini month** checkbox, **Print detailed agenda** checkbox, **Print**. Shortcut Ctrl+P.
  Source: https://support.microsoft.com/en-us/teams/meetings/share-your-calendar-in-microsoft-teams
  Source: https://support.microsoft.com/en-US/accessibility/teams/keyboard-shortcuts-for-microsoft-teams

## 28. Work plans and Places

- [ ] **Add work location** next to the current date: pick in-person days or **I work fully remote**, then **Set plan**.
  Source: https://support.microsoft.com/en-gb/teams/meetings/work-plans-in-microsoft-teams
- [ ] Day location icon at the top of the current day: change today's location from a dropdown (office, remote, building). It updates automatically.
  Source: https://support.microsoft.com/en-gb/teams/meetings/work-plans-in-microsoft-teams
- [ ] Click a day's location icon to see your own and others' work plans for that day ("who's in the building"). The Places card and workplace presence come with Places.
  Source: https://support.microsoft.com/en-gb/teams/meetings/work-plans-in-microsoft-teams
  Source: https://techcommunity.microsoft.com/blog/microsoftteamsblog/the-new-calendar-in-microsoft-teams-now-generally-available/4373598

## 29. Channel calendars

- [ ] Add a channel calendar: channel, **Add a tab**, **Apps**, **Channel calendar**, enter a name, **Save**. It isn't pinnable to the app rail.
  Source: https://support.microsoft.com/en-us/teams/meetings/see-all-your-meetings-in-microsoft-teams
  Source: https://support.microsoft.com/en-us/office/add-a-shared-channel-calendar-472657b8-f270-4a4a-a14c-b8daace0bb56
- [ ] A channel calendar is a filtered view of the team's Microsoft 365 group calendar showing only that channel's events. Not in private channels; Q&A says not supported in shared channels.
  Source: https://support.microsoft.com/en-us/teams/meetings/see-all-your-meetings-in-microsoft-teams
- [ ] Scheduling a channel event posts a summary in the channel. Members aren't directly invited unless added individually; the organizer gets it in their calendar. Only members with channel notifications on are notified. Channel events can only be scheduled and viewed in Teams.
  Source: https://support.microsoft.com/en-us/teams/meetings/see-all-your-meetings-in-microsoft-teams
- [ ] **Add to calendar** on a channel event adds it to the personal calendar. Members get invites only when following the M365 group in Outlook.
  Source: https://support.microsoft.com/en-us/teams/meetings/see-all-your-meetings-in-microsoft-teams
- [ ] Channel meeting from the channel header: dropdown next to **Meet now**, **Schedule a meeting**.
  Source: https://support.microsoft.com/en-us/teams/meetings/schedule-a-meeting-in-microsoft-teams

## 30. Notifications and reminders

- [ ] Settings > Notifications and activity > **Meetings**: **Meeting start notifications** toggle; **Show meeting join bar**; **Meeting chat notifications for meetings I've accepted** (default on); **Meeting chat notifications for meetings marked as tentative or no response** (default "Mute until I join or send a message"); **Meet now start notifications**.
  Source: https://support.microsoft.com/en-gb/teams/notifications-settings/manage-notifications-in-microsoft-teams
- [ ] Settings > Notifications and activity > **Calendar**: per-type delivery dropdown or Off, for invites, updates, cancellations, and "meetings you organized have been forwarded".
  Source: https://support.microsoft.com/en-gb/teams/notifications-settings/manage-notifications-in-microsoft-teams
- [ ] General: "Play sound with incoming calls, requests to join, and meeting start notifications"; "Mute all notifications (except for calls and meetings)" (Windows only). Meeting start toasts bypass OS Focus and DND.
  Source: https://support.microsoft.com/en-gb/teams/notifications-settings/manage-notifications-in-microsoft-teams
- [ ] Event reminders (per-event Remind me, default 15 minutes) raise a reminder toast or window with snooze and dismiss. [Outlook-derived for Teams UI]
  Source: https://learn.microsoft.com/en-us/graph/api/resources/event?view=graph-rest-1.0
  Source: https://support.microsoft.com/en-gb/outlook/create-modify-or-delete-a-meeting-request-or-appointment-in-outlook-on-the-web
- [ ] Recap-available notification for attendees and followers.
  Source: https://office365itpros.com/2024/05/14/follow-response-meetings/
- [ ] Privacy setting **Identify me in attendance reports**.
  Source: https://support.microsoft.com/en-gb/teams/meetings/manage-meeting-attendance-reports-in-microsoft-teams

## 31. Keyboard shortcuts (Calendar, Windows desktop)

- [ ] Navigate: Enter opens the item; Delete deletes; Alt+Shift+1/2/3/4 switch to Day, Work week, Week and Month; Alt+Shift+5 opens the agenda in Month; Ctrl+Alt+Left/Right change period; Alt+1..Alt+7 show N days; Alt+Down/Up next/previous week; Alt+PageDown/PageUp next/previous month; Alt+F1 toggles the left pane; F6 or Ctrl+Shift+Tab move between regions; Tab and Shift+Tab move between events; Alt+Shift+Y or Home go to today.
  Source: https://support.microsoft.com/en-US/accessibility/teams/keyboard-shortcuts-for-microsoft-teams
- [ ] Actions: Esc closes an event; Ctrl+P prints; Alt+Q searches; ? shows help; Ctrl+Alt+F forwards; Alt+R replies; Ctrl+Alt+R replies all; Ctrl+J joins.
  Source: https://support.microsoft.com/en-US/accessibility/teams/keyboard-shortcuts-for-microsoft-teams
- [ ] Create: Alt+N new event; Ctrl+N new event / invite attendees; Ctrl+S save; Ctrl+Enter send; Esc discard draft; Ctrl+K link; Ctrl+Z undo; Ctrl+Shift+Y retry; Ctrl+Shift+Q meeting request.
  Source: https://support.microsoft.com/en-US/accessibility/teams/keyboard-shortcuts-for-microsoft-teams
- [ ] Meetings: Alt+N schedule a meeting; Ctrl+S save or send a request; Alt+Shift+J join from details; Alt+Shift+S go to a suggested time; Ctrl+Shift+J join from the meeting-started toast; Ctrl+Shift+R open meeting chat from a notification.
  Source: https://support.microsoft.com/en-US/accessibility/teams/keyboard-shortcuts-for-microsoft-teams

## 32. Graph endpoints (brief; event and tentativelyAccept pages were read this session, the others are cited from the Graph reference without re-reading)

- [ ] Range read for views: `GET /me/calendarView?startDateTime=&endDateTime=` (expands recurrences). Delta: `/me/calendarView/delta`. Group or channel calendar: `GET /groups/{id}/calendarView`.
  Source: https://learn.microsoft.com/en-us/graph/api/user-list-calendarview
  Source: https://learn.microsoft.com/en-us/graph/api/group-list-calendarview
- [ ] Create: `POST /me/events` with `isOnlineMeeting:true, onlineMeetingProvider:"teamsForBusiness"` (join URL in `onlineMeeting.joinUrl`; can't be turned off later). Update: `PATCH`. Delete: `DELETE`. Series: `GET /me/events/{id}/instances`.
  Source: https://learn.microsoft.com/en-us/graph/api/resources/event?view=graph-rest-1.0
- [ ] RSVP: `POST /me/events/{id}/accept`, `/tentativelyAccept`, `/decline` with `{comment, sendResponse, proposedNewTime}`. A proposal needs allowNewTimeProposals=true and sendResponse=true, else 400.
  Source: https://learn.microsoft.com/en-us/graph/api/event-tentativelyaccept?view=graph-rest-1.0
  Source: https://learn.microsoft.com/en-us/graph/outlook-calendar-meeting-proposals
- [ ] Organizer actions: `POST /me/events/{id}/cancel` `{comment}`; `/forward`; reminders `/snoozeReminder` and `/dismissReminder`; attachments `/attachments`.
  Source: https://learn.microsoft.com/en-us/graph/api/resources/event?view=graph-rest-1.0
- [ ] Event fields to model: subject, body, start/end (dateTimeTimeZone), isAllDay, showAs, sensitivity, importance, categories, recurrence, attendees (required, optional, resource; status), organizer, isOrganizer, responseRequested, responseStatus, allowNewTimeProposals, hideAttendees, isReminderOn, reminderMinutesBeforeStart, location/locations, type (singleInstance, occurrence, exception, seriesMaster), seriesMasterId, isCancelled, isDraft, onlineMeeting.
  Source: https://learn.microsoft.com/en-us/graph/api/resources/event?view=graph-rest-1.0
- [ ] Scheduler and availability: `POST /me/calendar/getSchedule` (free/busy grid); `POST /me/findMeetingTimes` (suggestions).
  Source: https://learn.microsoft.com/en-us/graph/api/calendar-getschedule
  Source: https://learn.microsoft.com/en-us/graph/api/user-findmeetingtimes
- [ ] Calendars, groups and sharing: `/me/calendars`, `/me/calendarGroups`, `/me/calendars/{id}/calendarPermissions` (roles freeBusyRead, limitedRead, read, write, delegateWithoutPrivateEventAccess, delegateWithPrivateEventAccess).
  Source: https://learn.microsoft.com/en-us/graph/api/resources/calendarpermission
- [ ] Categories: `/me/outlook/masterCategories` (displayName plus preset colour).
  Source: https://learn.microsoft.com/en-us/graph/api/outlookuser-list-mastercategories
- [ ] Settings: `/me/mailboxSettings` (workingHours, timeZone, dateFormat, timeFormat).
  Source: https://learn.microsoft.com/en-us/graph/api/resources/mailboxsettings
- [ ] Rooms: `GET /places/microsoft.graph.room` and `/places/microsoft.graph.roomlist`.
  Source: https://learn.microsoft.com/en-us/graph/api/place-list
- [ ] Meeting options and attendance: `/me/onlineMeetings/{id}` (lobbyBypassSettings, allowedPresenters, allowMeetingChat, recordAutomatically, etc.); `/me/onlineMeetings/{id}/attendanceReports`.
  Source: https://learn.microsoft.com/en-us/graph/api/resources/onlinemeeting
  Source: https://learn.microsoft.com/en-us/graph/api/resources/meetingattendancereport
- [ ] Webinars and town halls: `/solutions/virtualEvents/webinars` and `/solutions/virtualEvents/townhalls`.
  Source: https://learn.microsoft.com/en-us/graph/api/resources/virtualeventwebinar
