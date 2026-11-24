# Teams desktop parity: Calls and Phone (1:1 and group calls, not scheduled meetings)

Scope: the new Microsoft Teams desktop app for Windows, 2025–2026. Each group of items cites the Microsoft page it came from. Items marked **[verify]** are things the docs imply but don't spell out (exact placement, icon, or label). Check those against the real client on `winpc` before building pixel-exact UI.

Conventions: "More actions" is the `...` button. "Settings" means Settings and more (`...` beside the profile picture) > Settings.

Research gaps: support.microsoft.com intermittently returned HTTP 403 to automated fetches, and the session's web-search budget ran out. So the following areas rely on fewer sources and are flagged **[verify]**: spatial audio, video filters/frames, speed-dial editing, block-number UI, the exact incoming-toast overflow menu, and the post-call screen.

---

## 1. Calls app: layout and navigation

- [ ] Calls app in the left app rail: a single view that combines the dial pad, call history, contacts, speed dial and voicemail ("the Calls app that combines contacts, voicemail, and call history").
- [ ] Call history sits in the centre of the Calls view and lists past and missed calls.
- [ ] Right-hand pane: speed dial contacts, contact groups and call groups you manage. Voicemail summaries and transcripts also show here when a voicemail is selected.
- [ ] Bottom-left of the Calls view: a device/quick-settings dropdown that changes the connected audio device. The same menu manages call forwarding and call groups (see §13).
- [ ] Dial pad: a text box that accepts a number or a name, plus a 0–9 * # keypad and a **Call** button.
- [ ] Below the dial pad: a **Call as myself** dropdown. It lists your own lines and any delegators you can call for (§3, §14).
- [ ] Below the dial pad: your emergency location, labelled **Emergency location**, with an **Edit** action (§24).
- [ ] Number tabs at the top of the Calls view when the user has more than one assigned number (multi-line, §3).
- [ ] Calls > **Personal** tab, plus one tab per delegator (shared line). Active delegator calls show under **Ongoing** with a **Join** button (§14).
- [ ] **Parked calls / Unpark** entry: the docs say "Go to the speed dial tab, select Unpark", and an older revision says "Parked calls option under the dialer". The two placements conflict. **[verify]**
- [ ] Dial pad is hidden when the user has no PSTN calling plan / Enterprise Voice. The user can still call Teams users by name. A delegate's Calls app shows a Dial Pad only when they are Enterprise Voice enabled.
- [ ] Contacts: Calls > Contacts shows an A–Z list with search. You can add people outside the org as contacts here (Chat > Contacts also exists).

Source: https://support.microsoft.com/en-us/office/get-to-know-the-calling-experience-in-teams-5c71cfd7-0553-4816-aa35-1fdae1ba2365
Source: https://support.microsoft.com/en-US/teams/calls-devices/use-the-dial-pad-to-make-a-call-in-microsoft-teams
Source: https://support.microsoft.com/en-US/teams/calls-devices/park-a-call-in-microsoft-teams
Source: https://learn.microsoft.com/en-us/microsoftteams/user-call-settings
Source: https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams (Contacts section)

## 2. Dial pad and placing calls

- [ ] Call a phone number: Calls > type the number with the keypad or the keyboard > **Call**.
- [ ] Paste a number from the clipboard into the dial pad. Formatting characters must be tolerated.
- [ ] Call by name: start typing a name in the dial pad box, pick the person from the dropdown, then **Call**. The dropdown does not appear for touch-screen text entry (keyboard only).
- [ ] Group call from the dial pad: enter a name or number, pick it, repeat for more people, then **Call**.
- [ ] Integrated dial pad: dial by name or number from the top search bar as well as the dial pad.
- [ ] `/call` command in the top search/command box, then type or select a person.
- [ ] Internal extension dialling and dial-plan normalisation: numbers are normalised by the tenant dial plan.
- [ ] Federated calling: call Teams users in other tenants.
- [ ] If the user lacks a calling plan, the dial option is absent but Teams-to-Teams calls work.

Source: https://support.microsoft.com/en-US/teams/calls-devices/use-the-dial-pad-to-make-a-call-in-microsoft-teams
Source: https://support.microsoft.com/en-us/teams/calls-devices/start-a-call-from-a-chat-in-microsoft-teams
Source: https://learn.microsoft.com/en-us/microsoftteams/here-s-what-you-get-with-phone-system

## 3. Multiple lines, caller ID, private line

- [ ] Multi-line: admins can assign up to **10** phone numbers per account, and all lines appear in the Calls view.
- [ ] Choose the outgoing line with the number tab at the top of the Calls view, or with the dropdown next to **Call as myself** under the dial pad.
- [ ] Return a call from a specific line: in History, open the call dropdown and choose one of your assigned numbers.
- [ ] Each history entry is tagged with the line that was used.
- [ ] Incoming call notifications show which of your lines is being called.
- [ ] Private line: a second number that is inbound only and can't place outgoing calls. It ignores all forwarding, simultaneous ring and call-group rules, but still obeys Do not disturb (goes to voicemail).
- [ ] Private line calls ring with a special distinct ringtone. The notification says the call is on your private line, and call history labels the call as made to the private line.
- [ ] Private line with no voicemail: an unanswered call plays a busy signal after 1 minute.
- [ ] Caller ID: internal callers show directory info (picture, title). External callers show the carrier caller ID, or directory info if the number is a secondary number in the directory (reverse number lookup).

Source: https://support.microsoft.com/en-US/teams/calls-devices/use-the-dial-pad-to-make-a-call-in-microsoft-teams
Source: https://learn.microsoft.com/en-us/microsoftteams/private-line
Source: https://learn.microsoft.com/en-us/microsoftteams/here-s-what-you-get-with-phone-system

## 4. Starting calls from elsewhere

- [ ] Chat header: **Video call** and **Audio call** buttons in 1:1 and group chats.
- [ ] New chat: type names next to **To**, then select **Video call** or **Audio call** to call without sending a message first.
- [ ] Calls started from a chat are private, don't appear in any team conversation, and leave a call entry in the chat.
- [ ] Group chat call: Teams asks you to confirm that you want to call everyone in the group. **[verify exact dialog text]**
- [ ] Group chats with more than 20 people have their calling buttons disabled. The maximum is 20 people in a video or audio call started from chat.
- [ ] Profile card: start a 1:1 call from a person's profile card (opened from their picture in a channel or a search result).
- [ ] Call history: hover an entry > **More actions** > **Call back**. The same menu has chat, add to speed dial and add to contacts.
- [ ] Voicemail entry: hover > **Call**, or **More actions** > **Call back**.
- [ ] Calling a phone number directly from chat or search, when the org is enabled for PSTN.

Source: https://support.microsoft.com/en-us/teams/calls-devices/start-a-call-from-a-chat-in-microsoft-teams
Source: https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams
Source: https://support.microsoft.com/en-us/office/get-to-know-the-calling-experience-in-teams-5c71cfd7-0553-4816-aa35-1fdae1ba2365

## 5. Group calls

- [ ] Group call from the dial pad (several names or numbers) or from a group chat.
- [ ] Hard limit of 20 participants for calls started from chat. Larger groups must use Meet now / a meeting.
- [ ] Adding a participant to a 1:1 call turns it into a group call. Known limitation: the recording, transcript and Copilot content stay tied to the original 1:1 chat, and participants added later can't access them.
- [ ] Hold is unavailable in scheduled meetings but available in calls.
- [ ] A held call can't be moved into a group call. Take it off hold first before you transfer or add someone.
- [ ] Busy-on-busy doesn't apply to incoming group calls or meeting join requests.

Source: https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams
Source: https://learn.microsoft.com/en-us/microsoftteams/copilot-teams-calling-transcription
Source: https://support.microsoft.com/en-US/teams/calls-devices/put-a-call-on-hold-in-microsoft-teams
Source: https://learn.microsoft.com/en-us/microsoftteams/inbound-call-routing

## 6. Incoming call notification and answering

- [ ] Incoming call toast with three buttons: **Accept with audio** (phone icon, audio only), **Accept with video** (camera icon, answers and turns video on) and **Decline call** (red phone icon).
- [ ] Settings > Calls > **Viewing incoming calls**: **Large window** or **Small window**. Both can be resized during the call. Only the large window is used when RTT or captions are on. The small window lets the user keep seeing their work (MC1045221).
- [ ] Toast shows the caller (directory name and photo, or the number), which of your lines is called, and special context: forwarded call, delegated call ("on behalf of"), call group, call queue, private line. **[verify layout]**
- [ ] "Spam Likely" label on suspected PSTN spam calls. It is a warning, not a block. Spam filtering may also screen callers with basic/captcha IVR before ringing (§16).
- [ ] Distinct ringtones: separate ringtone choices for normal calls and forwarded calls (and delegated calls on Teams Phone).
- [ ] Secondary ringer: a second certified audio device also rings on incoming calls.
- [ ] Call waiting while already in a call: a new call still rings (unless busy-on-busy is set). Accepting it automatically puts the current call on hold.
- [ ] Call-waiting beep: Settings > Notifications and activity > **Play sounds while I'm busy or in a meeting**. It plays a tone every 5 seconds for the whole incoming call instead of the full ring.
- [ ] Ring on all signed-in endpoints (desktop, mobile, desk phone) at once. The first to answer wins and the others stop ringing.
- [ ] Missed call: a missed call shows in history and Activity. When the caller left a voicemail, the missed call and voicemail become one consolidated history entry (MC1485056, Nov 2026).
- [ ] Keyboard: Accept video **Ctrl+Shift+A**, Accept audio **Ctrl+Shift+S**, Decline **Ctrl+Shift+D** (§23).
- [ ] Open apps in browser for incoming PSTN calls: if the admin enabled it and the user toggle (Settings > Calls > **Open apps in browser**) is on, Teams opens a configured URL with `{phone}` replaced by the caller's E.164 number in the default browser.
- [ ] DND: incoming calls go straight to voicemail unless the caller is on the priority access list (§16).

Source: https://support.microsoft.com/en-US/Teams/calls-devices/answer-a-call-in-microsoft-teams
Source: https://support.microsoft.com/en-us/teams/calls-devices/manage-your-call-settings-in-microsoft-teams
Source: https://support.microsoft.com/office/15fd64cf-1500-4143-b199-1bbda98fd695 (auto-hold on accept)
Source: https://learn.microsoft.com/en-us/microsoftteams/configure-call-spam-filtering
Source: https://learn.microsoft.com/en-us/microsoftteams/inbound-call-routing
Source: https://learn.microsoft.com/en-us/microsoftteams/here-s-what-you-get-with-phone-system (distinctive ring, secondary ringer)
Source: https://mc.merill.net/message/MC1485056
Source: https://mc.merill.net/message/MC1045221

## 7. Call window: top toolbar (the controls shared with meetings)

- [ ] Toolbar controls, in Teams' own terms: **Chat**, **People**, **Raise**, **React**, **View**, **Notes**, **Copilot** (if licensed), **Apps**, **More actions**, **Camera**, **Mic**, **Share** and **Leave**. Organizer-only controls (**Controls**, **Rooms**) don't apply to ad-hoc calls.
- [ ] **Mic**: toggles mute. Its dropdown arrow opens sound/device settings (speaker, mic, noise suppression).
- [ ] **Camera**: toggles video. Its dropdown arrow previews video and changes the background.
- [ ] **Share**: share the entire screen, a window, a PowerPoint file or a whiteboard (§19).
- [ ] **Chat**: opens or closes the call's chat (for 1:1 calls this is the 1:1 chat). Also in More actions. It can pop out to its own window.
- [ ] **People**: participant list. Invite someone or dial a number from the **Invite someone or dial a number** field. Names on tiles smaller than 250×140 px appear on hover only.
- [ ] **Raise**: raise or lower your hand and show the order in which hands went up. Also under React > Raise hand. Can be pinned to the bar.
- [ ] **React**: emoji reactions that float briefly over the stage, plus Raise hand. **[verify emoji set: Like, Love, Applause, Laugh, Surprised]**
- [ ] **View**: changes the layout (see more or fewer people, prioritise people with video on).
- [ ] **More actions** items named in the docs: Start recording (and transcription), Apply background effects / Video effects and settings, Turn off incoming video, Captions, Settings > Audio settings / Call health. Overflow copies of Chat, People, React and Share. Telephony items: Hold, Transfer, Call park, Call merge, Dial pad, Lock call (§8).
- [ ] **Leave**: hangs up. In meetings the Leave dropdown has **End meeting** for presenters. For 1:1 calls Leave just ends the call. **[verify dropdown in group calls]**
- [ ] Customisation: drag controls to reorder, or right-click > **Pin** / **Unpin**, or drag to and from More. Camera, Mic and Share are fixed.
- [ ] Refreshed control bar (MC1317197, worldwide GA mid-to-late Oct 2026): controls centre-aligned, mic, camera and share grouped, **Leave** separated to avoid mis-clicks, less-used actions moved into a reorganised More menu, drag-and-drop pin, unpin and rearrange. Pinned layout persists per device and does not sync. During rollout there is a settings toggle to temporarily go back to the old controls. Scoped to meetings; the doc doesn't say whether it reaches calls. **[verify on current build]**
- [ ] New share panel (same MC): live previews of screens and windows, tabbed layout, two-step share confirmation.
- [ ] Toolbar app pinning policy: at most 2 pinned meeting apps; the rest go in More.

Source: https://support.microsoft.com/en-US/teams/meetings/use-meeting-controls-in-microsoft-teams
Source: https://mc.merill.net/message/MC1317197
Source: https://support.microsoft.com/en-us/teams/meetings/multitask-during-a-microsoft-teams-meeting

## 8. 1:1 telephony controls: hold, transfer, consult, dial pad, park, merge, lock

### Hold / Resume
- [ ] **Hold** sits at the top of the call window. Older and delegate docs put it under More actions > Hold. **[verify current placement]**
- [ ] **Resume** brings the call back.
- [ ] Desktop allows up to **3** calls on hold with 1 active (mobile: 2).
- [ ] Everyone on the call is told they're on hold. Held parties, including you, can't see or hear anyone. Screen sharing is suspended until you resume.
- [ ] PSTN parties hear Music on Hold (default, custom, or streaming per admin policy). Teams users also get MoH on desktop.
- [ ] Hold isn't offered in scheduled meetings.
- [ ] A held call shows as a held-call bar/tile with a Resume action while another call is active. **[verify UI]**

### Transfer (blind / "Transfer now")
- [ ] **Transfer** button in the call controls opens the transfer dialog.
- [ ] Dialog shows suggested frequent contacts and a search box (name or number).
- [ ] Toggle **Ring back if there's no answer**: if the recipient (in-org, Teams or Skype for Business) doesn't answer or has forwarding on, the call returns to you. Without it the transfer completes immediately.
- [ ] **Include a call topic for the recipient**: an optional note about the caller.
- [ ] **Generate call transfer context for the recipient** (Copilot). Only on transcribed calls with a Copilot licence. You review the draft, then select **Keep it**.
- [ ] Main **Transfer** button, plus a dropdown arrow: **Transfer to an audio call** (their Teams number), **Transfer to their work voicemail**, and any other numbers on their profile (for example, mobile).
- [ ] Transfer to a PSTN number requires a Teams Phone licence. Receiving a transfer doesn't.

### Consult then transfer
- [ ] **Consult** button in the call controls. Under **Consult then transfer the call**, pick a suggested contact or search.
- [ ] Choose **Start a call** (voice consult; the original caller is held with MoH) or **Open chat** (chat consult while the caller stays connected).
- [ ] When ready, select **Transfer** to hand the original caller to the consulted person.
- [ ] Not available in Teams for web. Needs an Enterprise Voice / Business Voice licence (not delegate-only).

### Dial pad (DTMF)
- [ ] **Dial pad** in the call controls at the top of the call window sends DTMF tones (0–9, *, #) for IVR menus such as "Press 1 for Sales".
- [ ] During a consult-and-merge call the dial pad shows for the consult leg only and is hidden after the merge.

### Call park
- [ ] More actions > **Call park**: shows a unique park code to save or send. The call is held in the service.
- [ ] Retrieve: Calls > **Unpark** (or Parked calls), enter the code, select **Pick up**. Works from any device under the same park policy.
- [ ] Unanswered after the timeout (default 300 s, admin range 120–1800 s), the call rings back the parker.
- [ ] Codes are sequential from the start of the range (default 10–99, custom up to 10–9999) and wrap around.
- [ ] Off by default. Needs Enterprise Voice and a call park policy, and parker and retriever must share the same policy.
- [ ] Call park options are hidden if the admin hasn't enabled them.

### Call merge
- [ ] Place a second call while on a call: the first is auto-held. Or hold it first via More actions > Hold.
- [ ] When the second call connects: More actions > **Call merge**.
- [ ] Accept an incoming call during a call (auto-hold), then More actions > **Call merge**.
- [ ] Reaching someone behind an IVR: place a 1:1 call to the IVR, use the dial pad, then merge into the existing call or group call.
- [ ] Not available for boss/delegate shared-line calls. Desktop only.

### Consult and merge into a meeting (included because ad-hoc Meet now uses it)
- [ ] People pane > **Invite someone or dial a number** > More actions (...) > **Consult and merge**. Talk privately, then **Merge**. The person joins the roster and audio continues.
- [ ] Needs the organizer to have an Audio Conferencing or PSTN licence. Not supported in events, webinars or town halls.

### Add people to a call
- [ ] People > **Invite someone or dial a number**: add a Teams user or a phone number, which turns the call into a group call.
- [ ] Not possible on E2EE calls.

### Lock call (delegator)
- [ ] More actions > **Lock call** stops delegates from joining or resuming. They can still see the call but can't take part. **Unlock call** reverses it.

Source: https://support.microsoft.com/en-US/teams/calls-devices/put-a-call-on-hold-in-microsoft-teams
Source: https://support.microsoft.com/en-us/topic/b7f40f14-e083-46b9-b739-68038c8f73a0
Source: https://support.microsoft.com/office/97c55ffb-1499-4b0a-8caa-980ebb4b697b
Source: https://support.microsoft.com/en-US/teams/calls-devices/use-the-dial-pad-to-make-a-call-in-microsoft-teams
Source: https://support.microsoft.com/en-US/teams/calls-devices/park-a-call-in-microsoft-teams
Source: https://learn.microsoft.com/en-us/microsoftteams/call-park-and-retrieve
Source: https://support.microsoft.com/office/15fd64cf-1500-4143-b199-1bbda98fd695
Source: https://support.microsoft.com/en-gb/topic/75e8c522-dde0-45b3-8fd1-8341f19740f9
Source: https://learn.microsoft.com/en-us/microsoftteams/music-on-hold
Source: https://learn.microsoft.com/en-us/microsoftteams/here-s-what-you-get-with-phone-system

## 9. Call history

- [ ] History list of all incoming, outgoing and missed calls with date, time, duration and direction.
- [ ] Filters at the top of the history list: past calls, missed calls and voicemail (path: Calls > History > All > **Voicemail**). Third-party guides list **All / Missed / Incoming / Outgoing / Voicemail**. **[verify exact chip labels]**
- [ ] Row hover actions: **Call**, and **More actions** > **Call back**, chat, **Add to speed dial**, **Add to contacts**, plus a line picker for multi-line users.
- [ ] Row tags: which of your lines was used, private line label, delegated calls ("on behalf of") in shared history.
- [ ] Recorded or transcribed calls show a **Recap** button. Hover > **View summary** opens a side window with the AI summary, and **View recap** opens a pop-out with transcript, AI notes and tasks. Multiple recaps for one call are threaded.
- [ ] Missed call plus voicemail shown as a single entry (MC1485056). History holds up to **3,000** records or **6 months**, whichever comes first (previously 100). Desktop, Mac and Web, rolling out Nov 2026.
- [ ] Report spam and block caller from the history row's More actions. **[verify]**

Source: https://support.microsoft.com/en-us/office/get-to-know-the-calling-experience-in-teams-5c71cfd7-0553-4816-aa35-1fdae1ba2365
Source: https://support.microsoft.com/en-us/teams/calls-devices/check-your-voicemail-in-microsoft-teams
Source: https://mc.merill.net/message/MC1485056
Source: https://support.microsoft.com/office/97c55ffb-1499-4b0a-8caa-980ebb4b697b
Source: https://support.microsoft.com/en-US/teams/calls-devices/use-the-dial-pad-to-make-a-call-in-microsoft-teams

## 10. Voicemail

- [ ] Open from Calls > History > All > **Voicemail**.
- [ ] Selecting a voicemail opens a details pane on the right: contact details with call controls at the top, transcript/summary, and playback controls at the bottom (play/pause, scrub, speed). **[verify speed options]**
- [ ] Voicemail transcription comes from the Voicemail policy (`EnableTranscription`). Copilot/AI summaries show where licensed.
- [ ] Call back from a voicemail: hover > **Call**, or **More actions** > **Call back**, or **Call** under contact details.
- [ ] Voicemails are also delivered to the Exchange mailbox as email with an audio attachment, and play on desk phones and every Teams client.
- [ ] Settings > Calls > **Manage voicemail**:
  - [ ] **Record a greeting**: record your own greeting.
  - [ ] **Choose a language for your default greeting**: dropdown.
  - [ ] Text-to-speech custom greeting typed in a text box. A recorded greeting overrides it.
  - [ ] Out-of-office greeting: choose when it plays, plus a custom text box.
  - [ ] **Call answer rules**: by default "play greeting and let caller record". Options: *Let the caller record a message.* / *Let the caller record a message or be transferred to someone else.* / *End the call without playing your greeting.* / *Play your greeting and end the call.* / *Transfer the call to someone else.*
  - [ ] **Where should they be transferred?**: shown when a transfer option is picked.
- [ ] Shared voicemail is not supported for delegates.

Source: https://support.microsoft.com/en-us/teams/calls-devices/check-your-voicemail-in-microsoft-teams
Source: https://support.microsoft.com/en-us/teams/calls-devices/manage-your-call-settings-in-microsoft-teams
Source: https://learn.microsoft.com/en-us/microsoftteams/here-s-what-you-get-with-phone-system
Source: https://support.microsoft.com/en-gb/topic/75e8c522-dde0-45b3-8fd1-8341f19740f9

## 11. Speed dial, contacts, contact groups

- [ ] Speed dial list in the right pane of the Calls app, giving one-click calls to saved people.
- [ ] Add to speed dial from a history row (More actions > Add to speed dial) or a contact's menu. Remove from speed dial in the same menu. **[verify]**
- [ ] Contact groups: More actions next to a group name > **Add a contact**. Groups organise people by role or team.
- [ ] Contacts list (A–Z with search). Add contacts from inside or outside the directory.
- [ ] Contact menu: chat, add to contacts, remove from contacts, add or remove speed dial.

Source: https://support.microsoft.com/en-us/office/get-to-know-the-calling-experience-in-teams-5c71cfd7-0553-4816-aa35-1fdae1ba2365
Source: https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams

## 12. Settings > Calls (and related settings pages)

- [ ] **Call handling and forwarding**: a toggle for one rule for all calls versus per-scenario rules. Targets: voicemail, new number, contact, call group, delegates (§13).
- [ ] **When you receive a call**: simultaneous ring (also ring) to a contact or number, a call group, or delegates.
- [ ] **Delay simultaneous ring**: dropdown up to 20 s, default **No delay**.
- [ ] Unanswered handling: where unanswered calls go and the ring time. The admin view offers "Ring for this many seconds before redirecting". The default unanswered target is voicemail after about 30 s.
- [ ] **Redirect external phone calls**: send external callers to voicemail or "as unanswered" without affecting internal calls. Off by default; only shown if the admin set "Let users decide".
- [ ] Busy options ("Busy on busy"): when the admin policy is **Let users decide**, choose to ring me (default), play a busy signal, or redirect as unanswered. **[verify exact labels]**
- [ ] **Manage call group**: **Add a call group** / **Edit** (members, notification per member, order).
- [ ] **Choose a ringtone**: for normal calls and forwarded calls, stored per device.
- [ ] **Manage delegates**: **Add a delegate**, set permissions, **Delete** (§14). **Your delegates** has the **Announce when delegates join the call** toggle.
- [ ] **Manage voicemail** (§10).
- [ ] **Viewing incoming calls**: **Large window** / **Small window**.
- [ ] **Open apps in browser**: toggle, only if the admin enabled it.
- [ ] **Call queues**: a per-queue notification toggle for agents.
- [ ] Emergency location: shown at the bottom of the calls section of Settings (§24).
- [ ] Settings > Devices: **Audio settings** (speaker, mic), **Make a test call**, secondary ringer, **Noise suppression**, **Video settings** > **Camera** with preview.
- [ ] Settings > Privacy: **Edit blocked contacts**, **Block calls with no caller ID** (Direct Routing only today), **Manage priority access**, **Turn off my camera and mic when my screen locks** (needs a restart), Location.
- [ ] Settings > Accessibility: **Teletypewriter mode** (TTY) toggle.
- [ ] Settings > Notifications and activity: **Play sounds while I'm busy or in a meeting** (call-waiting beep).
- [ ] End-to-end encrypted calls toggle (user opt-in when the policy allows; synced across devices) (§26).

Source: https://support.microsoft.com/en-us/teams/calls-devices/manage-your-call-settings-in-microsoft-teams
Source: https://support.microsoft.com/en-us/office/call-forwarding-call-groups-and-simultaneous-ring-in-teams-a88da9e8-1343-4d3c-9bda-4b9615e4183e
Source: https://learn.microsoft.com/en-us/microsoftteams/inbound-call-routing
Source: https://learn.microsoft.com/en-us/microsoftteams/user-call-settings
Source: https://support.microsoft.com/en-us/teams/meetings/present-content-in-microsoft-teams-meetings (screen-lock privacy toggle)
Source: https://learn.microsoft.com/en-us/microsoftteams/presence-admins (priority access)

## 13. Forwarding, simultaneous ring, call groups, quick menu

- [ ] Calls app quick menu at the bottom shows the current routing status: "Don't forward", "Forward to [name/number]" or "Forward to voicemail".
- [ ] Quick menu items: **Don't forward**, **Forward to voicemail**, **Forward to [name/number]** (up to 3 recent targets), **Forwarding to call group** (if configured), **Forwarding to delegates** (if configured), **More Settings**.
- [ ] Quick-menu targets come from your most recent forwarding or "Also ring" targets; older ones are replaced. Quirk: simultaneous ring shows as "Forward to [name]" in the quick menu.
- [ ] Quick menu: **In [number] call groups** > **Turn on call notifications** / **Turn off call notifications** / **Edit notifications** (call-group notifications are off by default for members).
- [ ] Call group: up to **25** members, in-org only (no phone numbers). One owned group per user; a user can be in up to 25 groups.
- [ ] Ring order: **Everyone at once** or **In the order below** (drag to reorder). More than 5 members forces "Everyone at once".
- [ ] Per-member notification type: Ring (default) / banner / mute. Mobile is only notified if set to banner and ring.
- [ ] Forwarding applies to 1:1 calls only.
- [ ] Forwarding and simultaneous ring need a Teams Phone (Enterprise or Business Voice) licence, and admin policy must allow in-org or external targets.
- [ ] Policy routing precedence: an admin "Send to voicemail" or "Use unanswered settings" for PSTN or federated calls overrides user forwarding.

Source: https://support.microsoft.com/en-us/office/call-forwarding-call-groups-and-simultaneous-ring-in-teams-a88da9e8-1343-4d3c-9bda-4b9615e4183e
Source: https://learn.microsoft.com/en-us/microsoftteams/call-sharing-and-group-call-pickup
Source: https://learn.microsoft.com/en-us/microsoftteams/user-call-settings
Source: https://learn.microsoft.com/en-us/microsoftteams/inbound-call-routing

## 14. Delegation / shared line (boss and delegate)

- [ ] Add a delegate: Settings > Calls > **Manage delegates** > **Add a delegate**, search, pick, then set permissions. The delegate gets a notification.
- [ ] Permissions (Graph/PowerShell names in brackets): make calls (MakeCalls), receive calls (ReceiveCalls), **Change call and delegate settings** (ManageSettings).
- [ ] **Delegate settings** > **Pick up held calls**: the delegator can turn this off.
- [ ] Delegate view: Calls > **Personal** plus a tab per delegator showing the delegator's live call state and who it's with. Under **Ongoing**, **Join** barges in, which turns the call into a conference and removes transfer controls.
- [ ] Delegates can manage the delegator's call handling, forwarding, call groups and delegation from the delegator tab, when permitted.
- [ ] Calling on behalf: from a 1:1 chat or the dial pad, choose the delegator when prompted (**Call as myself** dropdown). The delegator's policy governs PSTN routing.
- [ ] Hold on a shared line: More actions > **Hold**. Either party can resume from the Calls tab with **Resume**. Music on hold should be on.
- [ ] **Lock call** / **Unlock call** (delegator).
- [ ] **Announce when delegates join the call**: plays an audible alert to everyone when a delegate joins or resumes.
- [ ] Shared call history for delegated calls on desktop. "Call as myself" calls stay private. Recordings and transcripts don't appear in shared history. Shared history can't be deleted, and it disappears when delegation is turned off.
- [ ] Forward or simultaneously ring to delegates via Call handling and forwarding.
- [ ] Limits: recommended at most 25 delegation relationships. Circular delegation only on Teams phone devices. Call merge isn't available on shared-line calls.

Source: https://support.microsoft.com/en-gb/topic/75e8c522-dde0-45b3-8fd1-8341f19740f9
Source: https://learn.microsoft.com/en-us/microsoftteams/user-call-settings
Source: https://support.microsoft.com/en-us/teams/calls-devices/manage-your-call-settings-in-microsoft-teams

## 15. Call queues and the Queues app

- [ ] Agent opt in/out per queue: select a queue > **Opt in** / **Opt out**. Leads can opt members in or out, including in bulk from **People**.
- [ ] Per-queue notification toggles in Settings > Calls > **Call queues**.
- [ ] Queue calls ring with queue context on the toast. **[verify]** With presence-based routing, the agent must be opted in and Available.
- [ ] Queues app (Teams Premium + Teams Phone): **Dialpad** bottom-left, an outbound number dropdown above **Call** (call on behalf of the queue), real-time queue and auto attendant metrics, and per-queue call history with filters (Missed, Answered, Outgoing).
- [ ] Leads see Teams status of their **Leads** and of people they're **Observing**.
- [ ] Admin auto-recording and transcription for queue calls (preview). Agents can't stop it and callers hear an announcement. Explicit recording consent isn't supported for queue calls.
- [ ] Intelligent call recaps for recorded queue calls (RM569017).

Source: https://support.microsoft.com/en-US/teams/calls-devices/use-the-queues-app-for-microsoft-teams
Source: https://support.microsoft.com/en-us/teams/calls-devices/manage-your-call-settings-in-microsoft-teams
Source: https://learn.microsoft.com/en-us/microsoftteams/call-recording-transcription-captions

## 16. Presence, DND, busy-on-busy, blocking, spam

- [ ] Do not disturb: incoming calls go to voicemail (or unanswered handling) and are not shown, except from people on the **priority access** list (Settings > Privacy > **Manage priority access**). DND also applies to private-line calls.
- [ ] Presence auto-changes to "In a call" during calls. Calendar "Busy" does not trigger DND.
- [ ] Busy on busy (policy `BusyOnBusyEnabledType`: Off / On (busy signal) / Unanswered / UserOverride). User-level options: PlayBusySignal, RedirectAsUnansweredCall, RingUser. Applies when in a call, in a conference or with a held call. The callee gets a missed-call notification. You can still place calls.
- [ ] Block numbers: block a PSTN number (from history or a contact), manage under Privacy > **Edit blocked contacts**. The next call from that number doesn't ring.
- [ ] **Block calls with no caller ID** (anonymous): Direct Routing only today.
- [ ] Spam filtering (policy `SpamFilteringEnabledType`, on by default): "Spam Likely" notification on incoming PSTN calls, with optional basic/captcha IVR screening.

Source: https://learn.microsoft.com/en-us/microsoftteams/presence-admins
Source: https://learn.microsoft.com/en-us/microsoftteams/inbound-call-routing
Source: https://learn.microsoft.com/en-us/microsoftteams/configure-call-spam-filtering
Source: https://support.microsoft.com/en-us/teams/calls-devices/manage-your-call-settings-in-microsoft-teams
Source: https://learn.microsoft.com/en-us/microsoftteams/here-s-what-you-get-with-phone-system
Source: https://learn.microsoft.com/en-us/microsoftteams/private-line

## 17. Audio devices and audio processing

- [ ] Default speaker, mic and camera: Settings > Devices > **Audio settings** / **Video settings** > **Camera** (with preview).
- [ ] In-call device switching: Mic dropdown or More actions > Settings > **Audio settings**.
- [ ] **Make a test call** (Settings > Devices, Windows and Mac desktop only): the Test Call Bot records a short message, plays it back and shows a summary with a link to device settings. The recording is deleted immediately.
- [ ] Secondary ringer: pick a second device to ring on incoming calls.
- [ ] Device switching to HID or certified devices (for example, a Teams display). Headset hook and mute buttons control the call.
- [ ] Noise suppression: on by default and persists to the next call. Desktop has a **Noise suppression** toggle in Settings > Devices and in the in-call **Audio settings**. Levels on mobile (and historically desktop): **Auto (default)**, **Low** (steady noise; lets music through), **High** (everything but speech; needs AVX2), **Off** (hi-fi mics). **[verify current desktop control type]**
- [ ] Speaker toggle shortcut **Ctrl+Shift+U**. Temporarily unmute (push-to-talk) **Ctrl+Space**.
- [ ] Spatial audio and voice isolation exist in Teams, but no first-party doc was fetched this session. **[verify]**
- [ ] TTY mode (Settings > Accessibility).

Source: https://support.microsoft.com/en-us/teams/calls-devices/manage-your-call-settings-in-microsoft-teams
Source: https://support.microsoft.com/en-us/teams/meetings/reduce-background-noise-in-microsoft-teams-meetings
Source: https://learn.microsoft.com/en-us/microsoftteams/here-s-what-you-get-with-phone-system
Source: https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2

## 18. Video and background effects

- [ ] Camera on/off toggle. Camera dropdown with preview and background.
- [ ] More actions > **Video effects and settings** > **Video effects** pane.
- [ ] **None**: no effect. The choice persists across meetings and calls.
- [ ] **Blur** with a dropdown: **Standard blur** / **Portrait blur**.
- [ ] Built-in Teams background images.
- [ ] **Add new** custom image (.JPG, .PNG, .BMP). Branded org backgrounds need Teams Premium.
- [ ] **Preview**, then **Apply**. **Apply and turn on video** when the camera is off.
- [ ] **Decorate** (AI): styles Clean up, Fancy, Greenhouse, Celebration, Surprise me. **Start**, **Generate**, **Generate more**, **Apply and turn on video**.
- [ ] Not available on Linux or optimised VDI (affects the Linux clone: decide whether to implement natively).
- [ ] Video filters and frames, brightness, soft focus and mirror my video exist in Teams settings but weren't documented in the fetched pages. **[verify]**
- [ ] **Turn off incoming video** (More actions): saves bandwidth.
- [ ] Toggle video **Ctrl+Shift+O**.
- [ ] Admin `VideoFiltersMode` limits blur, background images and custom uploads.

Source: https://support.microsoft.com/en-US/teams/meetings/change-your-background-in-microsoft-teams-meetings
Source: https://support.microsoft.com/en-US/teams/meetings/use-meeting-controls-in-microsoft-teams

## 19. Screen sharing in calls

- [ ] **Share** opens a tray to share the entire screen or a window, or live-share PowerPoint, Excel or Whiteboard.
- [ ] **Include sound** toggle in the share tray before sharing streams all computer audio, notifications included.
- [ ] A loading screen shows to others while the share starts. Failure shows an error with restart or rejoin options.
- [ ] Presenter toolbar (visible only to the presenter; drops down when the cursor reaches the top of the shared screen): drag handle, **Camera**, **Mic**, **Give control**, **Take back**, **Slide control** / **End slide control**, **Share audio**, **Optimize** (for video), **Layout** (Content only / Standout / Side-by-side / Reporter), **Annotate**, **Chat** (compact, hidden from the share), **People**, **Stop sharing**, **Pin**.
- [ ] Presenting shrinks the call window into a minimised presenter window showing mic, camera, raised hands and views.
- [ ] **Give control**: pick a participant, who can then make selections and edits. Shows a warning about trust. **Take back** ends it.
- [ ] Viewer side: **Request control**, which the presenter approves or denies. **Release control** gives it back. Desktop only on both ends.
- [ ] Slide control for up to 20 people. Only for a PowerPoint window share started from Teams desktop.
- [ ] Viewer zoom: [+]/[-] buttons, pinch, Ctrl+scroll, Alt+Shift+Plus/Minus/0 and Alt+Shift+arrows to pan.
- [ ] **Open in new window** for someone else's shared content (desktop).
- [ ] Shortcuts: toggle share tray **Ctrl+Shift+E**, focus sharing toolbar **Ctrl+Shift+Spacebar**, accept/decline share **Ctrl+Shift+A** / **Ctrl+Shift+D**.
- [ ] Note: Microsoft's web client can't share or take control on Linux. A native Linux clone must implement capture itself (PipeWire portal).
- [ ] New share panel with live previews, tabs and two-step confirmation (MC1317197).
- [ ] Hold suspends an active share until resume.

Source: https://support.microsoft.com/en-us/teams/meetings/present-content-in-microsoft-teams-meetings
Source: https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
Source: https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams (give/take control desktop-only)
Source: https://mc.merill.net/message/MC1317197

## 20. Recording, transcription, captions, Copilot, recap

- [ ] Start recording and transcription in 1:1 VoIP and PSTN calls (More actions). Allowed by calling policy `AllowCloudRecordingForCalls` / `AllowTranscriptionForCalling` (off by default). Everyone gets a recording banner.
- [ ] Recording is saved to the starter's OneDrive. Recording and transcript appear in call history and the call details pane, and in the chat for VoIP.
- [ ] Explicit recording consent (`ExplicitRecordingConsent`): when someone starts recording or transcription, the other party is muted with camera and share off. Unmuting, camera or share prompts **Yes** / **No**. "No" leaves them view-only. The starter is auto-consented.
- [ ] Custom recording/transcription notification text applies to 1:1 calls (MC1426709, desktop/web).
- [ ] Live captions: More actions > **Captions**. Hover the pane > **Open caption settings** > **Caption styles** (font, size, colour, lines, position). Spoken-language mismatch prompt (**Settings** / **Yes, change it**). Captions aren't saved. Profanity is masked. Policy `LiveCaptionsEnabledTypeForCalling` (on by default).
- [ ] Live translated captions (Premium/Copilot): **Translate to**.
- [ ] RTT (real-time text) pane: **Turn on**.
- [ ] Copilot in calls: **Copilot** button, **View prompts**, free-text prompts, **Open in new window**. Policy `Copilot`: On / On with saved transcript required / Off. It runs during the call only, or after the call too if transcribed.
- [ ] Intelligent recap: the **Recap** button in the Calls app for recorded or transcribed VoIP and PSTN calls opens a pop-out (transcript, recording, notes, files, tasks). Transcript-only recap for PSTN. In the chat for VoIP, use **View recap**.
- [ ] Copilot transfer notes (§8).

Source: https://learn.microsoft.com/en-us/microsoftteams/call-recording-transcription-captions
Source: https://support.microsoft.com/en-us/teams/meetings/use-live-captions-in-microsoft-teams-meetings
Source: https://learn.microsoft.com/en-us/microsoftteams/copilot-teams-calling-transcription
Source: https://support.microsoft.com/office/97c55ffb-1499-4b0a-8caa-980ebb4b697b
Source: https://support.microsoft.com/en-us/office/get-to-know-the-calling-experience-in-teams-5c71cfd7-0553-4816-aa35-1fdae1ba2365
Source: https://mc.merill.net/message/MC1426709

## 21. Call quality: health panel, network indicator, rating survey

- [x] More actions > Settings > **Call health** panel, refreshed every 15 s (TASK-0069; the Teams send limit waits for TASK-0074):
  - [x] **Network**: Roundtrip time (<200 ms), Received packet loss (<2%), Teams send limit and Teams receive limit (Audio 70 kbps, Video 1.5 Mbps).
  - [x] **Audio**: Sent bitrate (>24 kbps; 36–128 typical), Sent packets, Roundtrip time, Sent codec, Received jitter (<30 ms), Received packets, Received packet loss, Received codec.
  - [x] **Video**: Sent frame rate (1–30), Sent width/height (160×90 to 1920×1080), Sent bitrate, Roundtrip time, Sent packets, Sent codec, Video processing (hardware preferred).
  - [x] **Screen sharing**: Sent and received frame rate, width/height, codec, plus processing (hardware or software).
  - [x] Roundtrip in 1:1 calls is measured peer to peer. In group calls it is to the Teams service.
- [ ] Network strength indicator: 3 bars, Good (3) / Poor (2) / Bad (1). It also shows when other participants have poor networks and suggests actions to save bandwidth when limited. Desktop and Mac, GA Feb 2026.
- [ ] Post-call **Rate my call** survey, shown occasionally after calls and meetings. A single screen with thumbs up (Good) / thumbs down (Had issues), optional problem tokens and an optional comment (since Feb 2026; replaced the 1–5 stars). **[verify token labels]**

Source: https://support.microsoft.com/en-us/topic/7bb1747c-d91a-4fbb-84f6-ad3f48e73511
Source: https://mc.merill.net/message/MC1077865
Source: https://mc.merill.net/message/MC1183608

## 22. Mini window, multitasking, pop-out, second device

- [ ] Navigating to another Teams app, or minimising, shows a small call window in the screen corner with the active speaker, shared content and participants, and controls for mic, camera, share and leave.
- [ ] Mini window views at the top: **Minimize** (collapse fully), **Show only active speaker**, **Show more people**, **Maximize meeting window** (return to the full window).
- [ ] Pop out panes into their own resizable windows: Chat, Notes, Copilot (**Open in new window**).
- [ ] The call runs in its own OS window separate from the main Teams window (desktop). **[verify]**
- [ ] F11 toggles full screen.
- [ ] Join a call on a second device: the second device shows a banner that you're in a call elsewhere. **Join** offers **Add this device** (joins with the mic auto-muted to avoid echo; share from either device) or **Transfer to this device** (set audio and video, then **Join**; the first device leaves). One transfer per call, for VoIP, PSTN and group calls. On by default.

Source: https://support.microsoft.com/en-us/teams/meetings/multitask-during-a-microsoft-teams-meeting
Source: https://support.microsoft.com/office/join-a-microsoft-teams-call-on-a-second-device-42ceae44-a470-4c93-9496-f1905c000d82
Source: https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2

## 23. Keyboard shortcuts (Windows desktop, "Meetings and calls")

- [ ] Accept video call **Ctrl+Shift+A**
- [ ] Accept audio call **Ctrl+Shift+S**
- [ ] Decline call **Ctrl+Shift+D**
- [ ] Start audio call **Alt+Shift+A**
- [ ] Start video call **Alt+Shift+V**
- [ ] End audio or video call **Ctrl+Shift+H**
- [ ] Toggle mute **Ctrl+Shift+M** (also **Win+Alt+K** system-wide on Windows)
- [ ] Toggle speaker **Ctrl+Shift+U**
- [ ] Temporarily unmute **Ctrl+Spacebar** (hold)
- [ ] Toggle video **Ctrl+Shift+O**
- [ ] Raise or lower hand **Ctrl+Shift+K**
- [ ] Announce raised hands (screen reader) **Ctrl+Shift+L**
- [ ] Toggle share content tray **Ctrl+Shift+E**
- [ ] Go to sharing toolbar **Ctrl+Shift+Spacebar**
- [ ] Accept / decline screen share **Ctrl+Shift+A** / **Ctrl+Shift+D**
- [ ] Admit from lobby notification **Ctrl+Shift+Y** (Meet now)
- [ ] Toggle full screen **F11**
- [ ] Zoom shared content **Alt+Shift+Plus / Minus / 0**. Pan with **Alt+Shift+arrows**.

Source: https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2

## 24. Emergency calling

- [ ] Emergency location shown below the dial pad in Calls and at the bottom of the calls section in Settings. Calls > **Emergency location** > **Edit** to update it. You can only edit it in Calls.
- [ ] Location consent at first run: the OS precise-location prompt, then the Teams prompt **Allow all** / **Keep emergency only** (shown once).
- [ ] Location settings live under Settings > Privacy > Location.
- [ ] Windows needs Location services, Let apps access your location, and Microsoft Teams all turned on (Windows 11 24H2 and later).
- [ ] Dynamic emergency calling: location is detected from the network (subnet, Wi-Fi, switch) or OS location, and the address is sent to the PSAP. Work-from-home users can enter an address.
- [ ] Optional admin **Emergency service disclaimer** banner (up to 250 characters). It is dismissed once the address is confirmed and comes back on restart.
- [ ] Security desk notification: the security desk is conferenced or notified during an emergency call. Test number **933** validates the location without notifying the desk.
- [ ] 911 can't be dialled if Teams has no internet connection.
- [ ] Emergency calls bypass DND, forwarding and calling restrictions (carrier routing). **[verify client UI during an emergency call]**

Source: https://support.microsoft.com/office/work-from-home-emergency-911-enable-location-services-583dd649-87fc-4b23-aed6-f4e2279297f9
Source: https://learn.microsoft.com/en-us/microsoftteams/what-are-emergency-locations-addresses-and-call-routing
Source: https://learn.microsoft.com/en-us/microsoftteams/emergency-calling-dispatchable-location
Source: https://support.microsoft.com/en-US/teams/calls-devices/use-the-dial-pad-to-make-a-call-in-microsoft-teams

## 25. PSTN vs VoIP differences the UI must reflect

- [ ] PSTN dialling, extensions, forwarding, simultaneous ring, call groups, delegation, park, caller ID, blocking, private and multi-line all need a Teams Phone licence and a number. Basic name calling, voicemail, MoH, transfer to Teams users, device switching, busy-on-busy and presence routing work without Teams Phone.
- [ ] PSTN callers hear MoH on hold, transfer and consult. Custom MoH isn't used on shared-line (delegation) or park calls; those get standard MoH.
- [ ] Spam Likely and captcha IVR apply only to inbound PSTN.
- [ ] Routing for PSTN calls and Routing for federated calls (admin): default / unanswered settings / voicemail / let users decide (PSTN only).
- [ ] Web PSTN calling is a separate policy (on by default). Consult then transfer isn't available on web.
- [ ] Recap: transcript-only recap for PSTN, and PSTN recap lives in the Calls app (VoIP recap is in chat).
- [ ] SMS in Teams chat for US/Canada Calling Plan numbers (1:1 only; text only). **[verify where the entry point lives]**

Source: https://learn.microsoft.com/en-us/microsoftteams/here-s-what-you-get-with-phone-system
Source: https://learn.microsoft.com/en-us/microsoftteams/music-on-hold
Source: https://learn.microsoft.com/en-us/microsoftteams/inbound-call-routing
Source: https://learn.microsoft.com/en-us/microsoftteams/teams-calling-policy
Source: https://learn.microsoft.com/microsoftteams/sms-overview

## 26. End-to-end encrypted 1:1 calls

- [ ] User opt-in toggle in Teams settings (allowed when the enhanced encryption policy is "Not enabled, but users can enable"). Synced across devices. Desktop and mobile only.
- [ ] A 20-digit security code is shown to both parties to read aloud and compare. A mismatch means interception, so hang up.
- [ ] Disabled while E2EE is on: live captions and transcription, recording, RTT, call transfer, call merge, call park, consult then transfer, companion device or transfer to another device, adding a participant, apps, and Copilot.

Source: https://learn.microsoft.com/en-us/microsoftteams/teams-end-to-end-encryption

## 27. Admin policy gates the client must honour (calling policy)

- [ ] **Make private calls** (master switch; off hides all calling).
- [ ] Cloud recording for calling, participant agreement, transcription, real-time captions, Copilot.
- [ ] Call forwarding and simultaneous ringing to people in the org / to external numbers.
- [ ] Voicemail for inbound calls (On / Off / Let users decide).
- [ ] Inbound calls can be routed to call groups (`AllowCallGroups`). Delegation for inbound and outbound calls (`AllowDelegation`).
- [ ] Prevent toll bypass. Music on hold for calls (`MusicOnHoldEnabledType`).
- [ ] Busy on busy during calls. Routing for PSTN and federated calls.
- [ ] Web PSTN calling. Automatically answer incoming meeting invites. Spam filtering. SIP devices. Open apps in browser for incoming PSTN calls (URL with `{phone}`).
- [ ] Call park policy (on/off, range, timeout). Call hold policy (custom audio).

Source: https://learn.microsoft.com/en-us/microsoftteams/teams-calling-policy
Source: https://learn.microsoft.com/en-us/microsoftteams/inbound-call-routing
Source: https://learn.microsoft.com/en-us/microsoftteams/call-park-and-retrieve

## 28. Documented APIs (brief)

- [ ] Graph cloud-communications `call` resource (bot/app-only, not a user client signalling API): `POST /communications/calls` (create), `GET`, `DELETE` (hang up), `keepAlive`, `answer`, `reject`, `redirect`, `transfer`, participants `invite` / `mute` / list, `playPrompt`, `recordResponse`, `subscribeToTone`, `sendDtmfTones`, `mute` / `unmute` (self), `changeScreenSharingRole`, `updateRecordingStatus`, `addLargeGalleryView`. Call states: incoming, establishing, ringing, established, hold, transferring, transferAccepted, redirecting, terminating, terminated. A native user client can't use these for its own calls; it needs Teams' internal calling stack.
  Source: https://learn.microsoft.com/en-us/graph/api/resources/call?view=graph-rest-1.0
- [ ] User forwarding, delegation and call-group settings are exposed via PowerShell (`Get/Set-CsUserCallingSettings`, `New/Set/Remove-CsUserCallingDelegate`). Fields include IsForwardingEnabled, ForwardingType (Immediate/Simultaneous), ForwardingTargetType (SingleTarget/Voicemail/MyDelegates/Group), UnansweredTargetType, UnansweredDelay, CallGroupOrder (InOrder/Simultaneous), GroupNotificationOverride, BusyOnBusyOption. Useful as the data model for the settings UI.
  Source: https://learn.microsoft.com/en-us/microsoftteams/user-call-settings
  Source: https://learn.microsoft.com/en-us/microsoftteams/inbound-call-routing
- [ ] Graph `callRecords` (history and quality) and `presence` (`/me/presence`, setPresence) exist. These Graph pages were not fetched this session. **[verify]**
