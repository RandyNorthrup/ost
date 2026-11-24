# Teams desktop (Windows) parity checklist: MEETINGS

Scope: scheduled meetings, Meet now, channel meetings, webinars/town halls as attendee. Researched 2026-11-06 against Microsoft Support, Microsoft Learn and Message Center posts.

Source notes:
- `support.microsoft.com` started returning HTTP 403 to this machine partway through the research, so some groups were filled in from search-result excerpts of the same support articles. Those items are marked **[snippet]**. Check them against the live client before treating the label as exact.
- Items marked **[UI-2026]** come from the refreshed meeting controls (MC1317197). That redesign reached worldwide GA in mid-to-late October 2026, so it is the current baseline. Users can still opt back to the old controls for now.
- Items marked **[legacy label]** use older wording from 2021 Learn training; current labels may differ slightly.
- **Premium** means a Teams Premium license (some Premium features moved into Teams Enterprise on 2026-04-01).

---

## 1. Meeting types and entry points

- [ ] Scheduled private meeting: created from Calendar, stored with an onlineMeeting. Join link expires 60 days after the scheduled time. Joining or updating it before expiry adds another 60 days.
  Source: https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams
- [ ] Recurring meeting expiry: with an end date, 60 days after the end date or the last occurrence, whichever is later. With no end date, 1 year after it was last accessed, joined or updated.
  Source: https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams
- [ ] Meet now from Calendar: the **Meet now** button at the upper right of Calendar opens a dialog with an editable **Meeting name** field.
  - **Get a link to share** creates the link and reveals **Configure meeting options**.
  - **Start meeting** goes to the pre-join screen, then **Join now** enters.
  - Requires an Exchange Online mailbox; without one the button is hidden.
  - The link expires 60 days after creation. It does not get the 60-day extension.
  Source: https://support.microsoft.com/topic/ff95e53f-8231-4739-87fa-00b9723f4ef5 ; https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams
- [ ] Meet now in a channel: the **Meet now** button at the top right of the channel (icon depends on channel layout), then **Join now**.
  - To keep a meeting in a post's context, reply to the post and choose compose box > **Actions and apps** > **Meet now**.
  - The meeting appears as its own thread in Posts.
  Source: https://support.microsoft.com/topic/ff95e53f-8231-4739-87fa-00b9723f4ef5
- [ ] Meet now in a group chat: the **Meet now** button in the chat header.
  - Others see the live meeting in their chat list and can select **Join**.
  - A live indicator at the top of the chat shows who is in the meeting.
  - **Ring others to join** offers **Ring** (one person) and **Ring all** (everyone not in the meeting).
  - The meeting ends when the last person leaves, and everyone is notified.
  - Group-chat Meet now links never expire.
  Source: https://support.microsoft.com/topic/ff95e53f-8231-4739-87fa-00b9723f4ef5 ; https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams
- [ ] `/meetnow` slash command in any chat compose box; Enter or Tab runs it.
  Source: https://support.microsoft.com/topic/ff95e53f-8231-4739-87fa-00b9723f4ef5
- [ ] Channel meeting: channel members bypass the lobby. "Specific people" presenters are not available. Recordings go to the channel's SharePoint, not the organizer's OneDrive.
  Source: https://support.microsoft.com/topic/eaf70322-d771-4043-b595-b40794bac057 ; https://support.microsoft.com/topic/c16fa7d0-1666-4dde-8686-0a0bfe16e019 ; https://support.microsoft.com/topic/34dfbe7f-b07d-4a27-b4c6-de62f1348c24
- [ ] Hard limits: meetings and events last at most 30 hours. Interactive capacity is 1,000 (Enterprise plans) or 300 (Business plans). Meetings can add up to 10,000 view-only attendees, for 11,000 total.
  Source: https://learn.microsoft.com/en-us/microsoftteams/meetings-events-feature-comparison
- [ ] Policy toggles that hide entry points:
  - "Meet now in private meetings"
  - "Meet now in channel meetings"
  - "Channel meeting scheduling"
  - "Private meeting scheduling"
  Source: https://learn.microsoft.com/en-us/microsoftteams/settings-policies-reference
- [ ] Graph: `POST /me/onlineMeetings` creates a meeting; `onlineMeeting.meetingType` is `adhoc | scheduled | recurring | broadcast | meetnow`; `expiryDateTime` is exposed.
  Source: https://learn.microsoft.com/en-us/graph/api/resources/onlinemeeting?view=graph-rest-1.0

## 2. Joining

- [ ] Join from Calendar: select the event, then **Join**.
  Source: https://support.microsoft.com/en-us/office/join-a-meeting-in-microsoft-teams-1613bb53-f3fa-431e-85a9-d6a91e3468c9
- [ ] Join with an ID: Calendar > dropdown arrow next to **Meet now** > **Join with an ID**. Enter the meeting ID and passcode; passcodes are case-sensitive.
  - Requires an Exchange Online mailbox.
  - The ID and passcode are in the event under **Details** > **Show meeting info**, and at the top of the invite email.
  Source: https://support.microsoft.com/en-us/office/join-a-meeting-in-microsoft-teams-1613bb53-f3fa-431e-85a9-d6a91e3468c9
- [ ] Admin option "Allow numeric-only meeting passcodes" (off by default) makes passcodes 8 digits, numbers only.
  Source: https://learn.microsoft.com/en-us/microsoftteams/settings-policies-reference
- [ ] Join from a link: selecting the invite link opens Teams if it is installed.
  - Without an account, the user types a name if the organizer allows it.
  - With an account, **Sign in** gives meeting chat access.
  Source: https://support.microsoft.com/en-us/office/join-a-meeting-in-microsoft-teams-1613bb53-f3fa-431e-85a9-d6a91e3468c9
- [ ] Live meeting join bar: appears for accepted or tentative meetings that are in progress and has a **Join** button. With several live meetings it shows **View meetings**.
  - It can be disabled at Settings and more > Settings > Notifications and activity > Meetings > **Show meeting join bar**.
  Source: https://support.microsoft.com/en-us/office/join-a-meeting-in-microsoft-teams-1613bb53-f3fa-431e-85a9-d6a91e3468c9
- [ ] Join from the meeting chat: **Join** button at the top of the chat. This is also how you rejoin after leaving.
  Source: https://support.microsoft.com/en-us/office/join-a-meeting-in-microsoft-teams-1613bb53-f3fa-431e-85a9-d6a91e3468c9 ; https://support.microsoft.com/topic/ff95e53f-8231-4739-87fa-00b9723f4ef5
- [ ] Join from a channel: **Join** on the channel meeting post or header.
  Source: https://support.microsoft.com/en-us/office/join-a-meeting-in-microsoft-teams-1613bb53-f3fa-431e-85a9-d6a91e3468c9
- [ ] "Meeting started" toast with a join action. Shortcut: **Ctrl+Shift+J** joins from the toast; **Alt+Shift+J** joins from meeting details.
  Source: https://support.microsoft.com/topic/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] Switch account on the pre-join screen: **Change** next to the account offers the other accounts or **Add another account**. Choosing **Join without signing in** asks for a name, then **Join**.
  Source: https://support.microsoft.com/en-us/office/join-a-meeting-in-microsoft-teams-1613bb53-f3fa-431e-85a9-d6a91e3468c9
- [ ] Edit display name in a meeting: only works when the organizer enabled "Let people edit their display name" (Graph: `allowParticipantsToChangeName`). Not available in events optimized for large audiences.
  Source: https://support.microsoft.com/en-us/office/join-a-meeting-in-microsoft-teams-1613bb53-f3fa-431e-85a9-d6a91e3468c9 ; https://learn.microsoft.com/en-us/microsoftteams/meetings-events-feature-comparison
- [ ] Dial in by phone: dial the number and conference ID from the invite.
  Source: https://support.microsoft.com/en-us/office/join-a-meeting-in-microsoft-teams-1613bb53-f3fa-431e-85a9-d6a91e3468c9
- [ ] Have Teams call you: **more join options** on the pre-join screen > **Call me** > enter a number > **Call me**. Answer and say "OK" or press 1. Not available inside breakout rooms.
  Source: https://support.microsoft.com/en-us/office/join-a-meeting-in-microsoft-teams-1613bb53-f3fa-431e-85a9-d6a91e3468c9 ; https://learn.microsoft.com/en-us/training/modules/facilitate-meetings-events-microsoft-teams/4-use-breakout-rooms-teams
- [ ] View-only overflow join: once the main meeting is full (about 1,000), new joiners see a pre-join notice that they will join view-only. Requires the StreamingAttendeeMode policy. Details in section 26.
  Source: https://learn.microsoft.com/en-us/microsoftteams/view-only-meeting-experience
- [ ] Policy "People can join external meetings hosted by" (default Anyone) can block joining other orgs' meetings.
  Source: https://learn.microsoft.com/en-us/microsoftteams/settings-policies-reference
- [ ] Graph: `joinWebUrl`, `joinMeetingIdSettings` (joinMeetingId, passcode, isPasscodeRequired; cannot be changed after creation), `audioConferencing` (dial-in), `joinInformation`.
  Source: https://learn.microsoft.com/en-us/graph/api/resources/onlinemeeting?view=graph-rest-1.0

## 3. Pre-join screen

- [ ] **Camera** toggle with live self-preview.
  Source: https://support.microsoft.com/topic/3647fc29-7b92-4c26-8c2d-8a596904cdae
- [ ] **Mic** toggle.
  Source: https://support.microsoft.com/topic/3647fc29-7b92-4c26-8c2d-8a596904cdae
- [ ] **Effects and avatars** button opens background effects. Details in section 4.
  Source: https://support.microsoft.com/en-us/office/change-your-background-in-microsoft-teams-meetings-f77a2381-443a-499d-825e-509a140f4780
- [ ] **Open device settings** opens **Video Settings**, which holds the filters **Soft focus** and **Adjust brightness**.
  Source: https://support.microsoft.com/topic/3647fc29-7b92-4c26-8c2d-8a596904cdae
- [ ] Audio options, one of:
  - Computer audio
  - Phone audio (**Call me**)
  - **Room audio**: lists nearby Teams Rooms. Rooms found by ultrasound appear first, then Bluetooth rooms sorted by signal strength. Dismiss a suggestion with **X**.
  - Don't use audio **[snippet; exact wording unverified]**
  Source: https://support.microsoft.com/en-us/office/join-a-meeting-in-microsoft-teams-1613bb53-f3fa-431e-85a9-d6a91e3468c9 ; https://learn.microsoft.com/en-us/microsoftteams/rooms/proximity-join
- [ ] **Join now** button.
  Source: https://support.microsoft.com/topic/ff95e53f-8231-4739-87fa-00b9723f4ef5
- [ ] Meeting info on the join screen (title, attendee count, organizer status). The organizer controls it with the meeting option "Show meeting info on join screen".
  Source: https://support.microsoft.com/en-us/office/meeting-options-in-microsoft-teams-53261366-dbd5-45f9-aae9-a70e6354f88e
- [ ] Lobby chat pane on the pre-join screen: opens automatically when the organizer messages people in the lobby. A **Lobby chat** icon is also there. Details in section 7.
  Source: https://support.microsoft.com/topic/eaf70322-d771-4043-b595-b40794bac057
- [ ] Recording consent gate: with the "Require participant agreement for recording and transcription" policy, a participant's audio, video and sharing stay off until they agree.
  Source: https://learn.microsoft.com/en-us/microsoftteams/settings-policies-reference
- [ ] Email one-time-passcode verification for unverified participants. Premium; meeting option "Require unverified participants to verify their info before joining".
  Source: https://support.microsoft.com/en-us/office/meeting-options-in-microsoft-teams-53261366-dbd5-45f9-aae9-a70e6354f88e
- [ ] Guests joining town halls must switch to the correct org on the pre-join screen.
  Source: https://support.microsoft.com/topic/75a8b352-92bd-46ec-846b-15bd4f070a0a **[snippet]**

## 4. Video and background effects

- [ ] Background blur options: **Standard blur** and **Portrait blur**.
  Source: https://support.microsoft.com/en-us/office/change-your-background-in-microsoft-teams-meetings-f77a2381-443a-499d-825e-509a140f4780
- [ ] Teams backgrounds gallery: choose a built-in image.
  Source: https://support.microsoft.com/en-us/office/change-your-background-in-microsoft-teams-meetings-f77a2381-443a-499d-825e-509a140f4780
- [ ] Upload your own background: **More video effects** > **Add new**. Accepts .JPG, .PNG and .BMP.
  Source: https://support.microsoft.com/en-us/office/change-your-background-in-microsoft-teams-meetings-f77a2381-443a-499d-825e-509a140f4780
- [ ] **None** turns all background effects off.
  Source: https://support.microsoft.com/en-us/office/change-your-background-in-microsoft-teams-meetings-f77a2381-443a-499d-825e-509a140f4780
- [ ] Change effects during a meeting: **More actions** > **Video effects and settings** > **Video effects**. **Preview** shows the effect before **Apply**.
  Source: https://support.microsoft.com/en-us/office/change-your-background-in-microsoft-teams-meetings-f77a2381-443a-499d-825e-509a140f4780
- [ ] The background choice persists across all meetings and calls until changed.
  Source: https://support.microsoft.com/en-us/office/change-your-background-in-microsoft-teams-meetings-f77a2381-443a-499d-825e-509a140f4780
- [ ] **Decorate** (AI-generated backgrounds, Premium): themes **Clean up**, **Fancy**, **Greenhouse**, **Celebration**, **Surprise me**. Flow: **Start** (camera turns off while you choose), **Generate**, **Generate more**, then **Apply and turn on video**.
  Source: https://support.microsoft.com/en-us/office/change-your-background-in-microsoft-teams-meetings-f77a2381-443a-499d-825e-509a140f4780
- [ ] Organization backgrounds (Premium, admin-uploaded, listed in upload order). Admin option "Apply background blur when no effect is selected".
  Source: https://learn.microsoft.com/en-us/microsoftteams/settings-policies-reference
- [ ] Video filters **Soft focus** and **Adjust brightness**, found under Video Settings.
  Source: https://support.microsoft.com/topic/3647fc29-7b92-4c26-8c2d-8a596904cdae
- [ ] Policy "Participants can use video effects" (All video effects / limited / none) restricts what is available.
  Source: https://learn.microsoft.com/en-us/microsoftteams/settings-policies-reference
- [ ] Privacy setting at Settings > Privacy: "Turn off my camera and mic when my screen locks". Requires a Teams restart.
  Source: https://support.microsoft.com/topic/3647fc29-7b92-4c26-8c2d-8a596904cdae
- [ ] Background effects are unavailable on Linux and in optimized VDI.
  Source: https://support.microsoft.com/en-us/office/change-your-background-in-microsoft-teams-meetings-f77a2381-443a-499d-825e-509a140f4780

## 5. Audio and devices

- [ ] **Mic** button dropdown arrow opens sound and device settings: speaker and mic selection plus noise suppression.
  Source: https://support.microsoft.com/en-us/office/use-meeting-controls-in-microsoft-teams-ee1134a2-c74d-41ef-be98-e979d6167915
- [ ] Noise suppression section (Settings > Devices): **Background noise only**, and **Voice isolation** (suppresses other voices). The mic dropdown shows whether Voice isolation is selected. **[snippet]**
  Source: https://support.microsoft.com/office/a9756ea9-4cec-44c4-aefb-6f5d17c89427 ; https://support.microsoft.com/topic/6ea36f9a-827b-47d6-b22e-ec94d5f0f5e4
- [ ] Voice isolation needs a voice profile unless you use a headset: Settings > Recognition > Create voice profile. Policies: VoiceIsolation, EnrollUserOverride. **[snippet]**
  Source: https://support.microsoft.com/office/a9756ea9-4cec-44c4-aefb-6f5d17c89427 ; https://learn.microsoft.com/en-us/microsoftteams/settings-policies-reference
- [ ] When Noise suppression is off (Teams turns it off by default under high CPU), a raised hand is not lowered automatically after you speak.
  Source: https://support.microsoft.com/office/raise-your-hand-in-a-teams-meeting-bb2dd8e1-e6bd-43a6-85cf-30822667b372
- [ ] Mute shortcuts:
  - Toggle mute: **Ctrl+Shift+M**.
  - Temporary unmute (push-to-talk): hold **Ctrl+Spacebar**. Requires Settings > Privacy > "Keyboard shortcut to unmute" to be on.
  Source: https://support.microsoft.com/topic/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] Toggle speaker: **Ctrl+Shift+U**.
  Source: https://support.microsoft.com/topic/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] Policies "Mode for IP audio" and "Mode for IP video" can disable incoming and/or outgoing media.
  Source: https://learn.microsoft.com/en-us/microsoftteams/settings-policies-reference

## 6. Meeting window controls (toolbar)

- [ ] Toolbar controls, in documented order. **[UI-2026]**
  - **Chat**
  - **People**
  - **Raise**
  - **React**
  - **View**
  - **Controls**: participant permissions and meeting-protection settings; replaces the older "More > Settings > Meeting options".
  - **Notes**
  - **Rooms**
  - **Copilot**
  - **Apps**
  - **More actions**
  - **Camera** (dropdown)
  - **Mic** (dropdown)
  - **Share**
  - **Leave** (dropdown)
  Source: https://support.microsoft.com/en-us/office/use-meeting-controls-in-microsoft-teams-ee1134a2-c74d-41ef-be98-e979d6167915
- [ ] Refreshed layout **[UI-2026]**:
  - Toolbar centered.
  - Mic, Camera and Share grouped together.
  - Leave set apart to prevent accidental exits.
  - Less-used actions moved into a reorganized More menu.
  - Covers Windows, Mac and web.
  Source: https://mc.merill.net/message/MC1317197
- [ ] Customize the toolbar: drag and drop to reorder. Right-click a control for **Pin** / **Unpin**, or drag controls to and from **More**.
  - Preferences persist per client and do not sync across devices yet.
  - Admin app-pinning policy allows up to 2 meeting apps on the main bar; other apps go to More.
  Source: https://support.microsoft.com/en-us/office/use-meeting-controls-in-microsoft-teams-ee1134a2-c74d-41ef-be98-e979d6167915 ; https://mc.merill.net/message/MC1317197
- [ ] Opt out of the new controls: Settings and more > Settings > General > Meeting > **New meeting controls** toggle. Per user, temporary, and will be retired later.
  Source: https://support.microsoft.com/en-us/office/use-meeting-controls-in-microsoft-teams-ee1134a2-c74d-41ef-be98-e979d6167915 ; https://mc.merill.net/message/MC1317197
- [ ] **More actions** menu repeats the toolbar items (**Chat**, **People**, **React**, **View**, **Controls**, **Notes**, **Copilot**) and adds:
  - **Get more apps and agents**
  - **Record** / **Recording**
  - **Transcribe** / **Transcribing**
  - Captions
  - **Video effects and settings**
  - **Apply background effects**
  - **Turn off incoming video**
  - **Show notes**
  - **Show presenter view**
  - Language and speech (exact label unverified)
  Source: https://support.microsoft.com/en-us/office/use-meeting-controls-in-microsoft-teams-ee1134a2-c74d-41ef-be98-e979d6167915 ; https://support.microsoft.com/topic/34dfbe7f-b07d-4a27-b4c6-de62f1348c24 ; https://support.microsoft.com/topic/dc1a8f23-2e20-4684-885e-2152e06a4a8b
- [ ] **React** menu holds the reactions and a **Raise hand** / **Lower hand** item.
  Source: https://support.microsoft.com/office/raise-your-hand-in-a-teams-meeting-bb2dd8e1-e6bd-43a6-85cf-30822667b372
- [ ] **Camera** dropdown arrow opens a video preview and background change.
  Source: https://support.microsoft.com/en-us/office/use-meeting-controls-in-microsoft-teams-ee1134a2-c74d-41ef-be98-e979d6167915
- [ ] **Leave** dropdown arrow:
  - **End meeting** for organizers and co-organizers, with an **End** confirmation.
  - **Leave on all my devices** when joined on more than one device.
  Source: https://support.microsoft.com/en-us/topic/5051fa72-8470-4a38-99e4-014535208971 ; https://support.microsoft.com/en-us/office/join-a-microsoft-teams-meeting-on-a-second-device-c28e7407-183b-46ea-ab17-2212700e5f41
- [ ] Toolbar shortcuts:
  - Toggle full screen: **F11**.
  - Toggle video: **Ctrl+Shift+O**.
  - Open share tray: **Ctrl+Shift+E**.
  - End call: **Ctrl+Shift+H**.
  Source: https://support.microsoft.com/topic/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] **Exit spotlight** appears in the meeting controls of a participant who is spotlighted.
  Source: https://support.microsoft.com/topic/95aaeaf8-0f22-46cf-a6f9-34ca9b04a1b2

## 7. Lobby

- [ ] Lobby managers get a notification with **View lobby** and **Mute these notifications**; **Undo** re-enables them. Shortcut: **Ctrl+Shift+Y** admits from the lobby notification.
  Source: https://support.microsoft.com/topic/eaf70322-d771-4043-b595-b40794bac057 ; https://support.microsoft.com/topic/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] People pane section **Waiting in the lobby**:
  - Check mark next to a name admits that person.
  - **X** next to a name denies them.
  - **Admit all** admits the group when available.
  Source: https://support.microsoft.com/topic/eaf70322-d771-4043-b595-b40794bac057
- [ ] Bot detection: identified bots appear under **Suspected threats**, which has **Deny All**.
  - Admitting a bot, singly or through **Admit all**, asks for confirmation.
  - The bot's notification has no **Admit** button.
  Source: https://support.microsoft.com/topic/eaf70322-d771-4043-b595-b40794bac057
- [ ] "Who can bypass the lobby?" choices:
  - Only organizers and co-organizers
  - People who were invited (distribution lists up to 10,000)
  - People in my org
  - People in my org and guests (admin default)
  - People in my org, trusted orgs, and guests
  - Everyone
  Source: https://support.microsoft.com/topic/eaf70322-d771-4043-b595-b40794bac057 ; https://learn.microsoft.com/en-us/microsoftteams/settings-policies-reference
- [ ] "People dialing in can bypass the lobby" toggle (admin default off).
  Source: https://learn.microsoft.com/en-us/microsoftteams/settings-policies-reference
- [ ] "Who can admit from the lobby" choices: organizers, co-organizers and presenters (default), or organizers and co-organizers only. Graph: `allowedLobbyAdmitters`.
  Source: https://support.microsoft.com/en-us/office/meeting-options-in-microsoft-teams-53261366-dbd5-45f9-aae9-a70e6354f88e ; https://learn.microsoft.com/en-us/graph/api/resources/onlinemeeting?view=graph-rest-1.0
- [ ] "Reject anyone who can't bypass the lobby" toggle automatically turns away people without bypass rights.
  Source: https://support.microsoft.com/en-us/office/meeting-options-in-microsoft-teams-53261366-dbd5-45f9-aae9-a70e6354f88e
- [ ] Anonymous users and dial-in callers wait until someone from the org, a trusted org, or a guest joins. Exception: the "Anonymous users and dial-in callers can start a meeting" policy.
  Source: https://support.microsoft.com/topic/eaf70322-d771-4043-b595-b40794bac057 ; https://learn.microsoft.com/en-us/microsoftteams/settings-policies-reference
- [ ] Lobby chat: the organizer can message people waiting in the lobby, and they see only messages sent while they wait.
  - The **Lobby** chat option appears only while someone is waiting.
  - Lobby chat has no reactions, replies, @mentions, emoji, GIFs, stickers or Loop components.
  - Policy: "Organizers can chat with lobby participants".
  Source: https://support.microsoft.com/topic/eaf70322-d771-4043-b595-b40794bac057 ; https://learn.microsoft.com/en-us/microsoftteams/manage-meeting-chat
- [ ] Changing lobby settings mid-meeting doesn't remove people already waiting. In a series, changes apply to future occurrences.
  Source: https://support.microsoft.com/topic/eaf70322-d771-4043-b595-b40794bac057
- [ ] Green room: when enabled, organizers and presenters join early while attendees wait in the lobby. The organizer's **End meeting** ends the event for attendees, and organizers and presenters can stay in the green room.
  Source: https://support.microsoft.com/en-us/office/meeting-options-in-microsoft-teams-53261366-dbd5-45f9-aae9-a70e6354f88e ; https://learn.microsoft.com/en-us/microsoftteams/plan-town-halls
- [ ] Graph: `lobbyBypassSettings` (scope, isDialInBypassEnabled), `isEntryExitAnnounced`.
  Source: https://learn.microsoft.com/en-us/graph/api/resources/onlinemeeting?view=graph-rest-1.0

## 8. People pane and participant management

- [ ] **People** opens the **Participants** pane with groups such as Waiting in the lobby, In the meeting and Invited.
  Source: https://support.microsoft.com/topic/eaf70322-d771-4043-b595-b40794bac057 ; https://support.microsoft.com/en-us/office/manage-attendee-audio-and-video-permissions-in-microsoft-teams-meetings-f9db15e1-f46f-46da-95c6-34f9f39e671a
- [ ] **Invite someone or dial a number** search box in the People pane.
  - Hover a result and choose **Request to join** to ring them into the meeting.
  - **Add phone** dials a phone number.
  Source: https://support.microsoft.com/topic/ff95e53f-8231-4739-87fa-00b9723f4ef5 ; https://support.microsoft.com/en-us/office/join-a-meeting-in-microsoft-teams-1613bb53-f3fa-431e-85a9-d6a91e3468c9
- [ ] **Share invite** offers **Copy meeting link** and **Share via default email**.
  Source: https://support.microsoft.com/topic/ff95e53f-8231-4739-87fa-00b9723f4ef5
- [ ] Per-participant **More options** menu (hover a name):
  - **Mute participant**
  - **Make a presenter** / **Make an attendee**
  - **Pin for me**
  - **Spotlight for everyone**
  - Remove from meeting (exact label unverified)
  - Disable mic / camera for one attendee (exact label unverified)
  Source: https://support.microsoft.com/en-us/office/manage-attendee-audio-and-video-permissions-in-microsoft-teams-meetings-f9db15e1-f46f-46da-95c6-34f9f39e671a ; https://support.microsoft.com/topic/c16fa7d0-1666-4dde-8686-0a0bfe16e019
- [ ] **Mute all** mutes everyone without disabling their mics. Not available to organizers who joined from a Teams Rooms device.
  Source: https://support.microsoft.com/en-us/office/manage-attendee-audio-and-video-permissions-in-microsoft-teams-meetings-f9db15e1-f46f-46da-95c6-34f9f39e671a
- [ ] Turn off mic or camera for all attendees: **Controls** > **View more options** > **Participation**, then "Allow mic for attendees" / "Allow camera for attendees", then **Apply**.
  - Attendee mic and camera buttons appear dimmed.
  - Only takes effect when "Who can present" is not **Everyone**.
  - Dial-in callers are not restricted.
  - Graph: `allowAttendeeToEnableMic`, `allowAttendeeToEnableCamera`.
  Source: https://support.microsoft.com/en-us/office/manage-attendee-audio-and-video-permissions-in-microsoft-teams-meetings-f9db15e1-f46f-46da-95c6-34f9f39e671a
- [ ] When attendees can't unmute, a presenter can allow a person whose hand is raised to unmute.
  Source: https://support.microsoft.com/office/raise-your-hand-in-a-teams-meeting-bb2dd8e1-e6bd-43a6-85cf-30822667b372
- [ ] **Participants** header **More options** > **Lower all hands** (presenters and organizers only).
  Source: https://support.microsoft.com/office/raise-your-hand-in-a-teams-meeting-bb2dd8e1-e6bd-43a6-85cf-30822667b372
- [ ] Hide attendee names: names and photos hidden from other attendees on stage, roster and chat. Turn on before the meeting starts, after setting presenters. Policy: AttendeeIdentityMasking.
  Source: https://support.microsoft.com/en-us/office/meeting-options-in-microsoft-teams-53261366-dbd5-45f9-aae9-a70e6354f88e ; https://learn.microsoft.com/en-us/microsoftteams/settings-policies-reference
- [ ] When a third-party compliance-recording participant joins, organizers and presenters are notified and can remove them.
  Source: https://learn.microsoft.com/en-us/microsoftteams/meeting-recording

## 9. Roles

- [ ] Capability matrix:

  | Capability | Organizer | Co-organizer | Presenter | Attendee |
  |---|---|---|---|---|
  | Speak, video, chat | yes | yes | yes | yes |
  | Privately view a shared PowerPoint | yes | yes | yes | yes |
  | Use an app | yes | yes | yes | yes |
  | Share content | yes | yes | yes | no |
  | Take control of someone else's PowerPoint | yes | yes | yes | no |
  | Mute others | yes | yes | yes | no |
  | Prevent attendees from unmuting | yes | yes | yes | no |
  | Remove participants | yes | yes | yes | no |
  | Change roles | yes | yes | yes | no |
  | Start or stop recording and transcription | yes | yes | yes | no |
  | Add or remove apps, change app settings | yes | yes | yes | no |
  | Manage breakout rooms | yes | yes | no | no |
  | Change meeting options | yes | yes | no | no |

  Source: https://support.microsoft.com/topic/c16fa7d0-1666-4dde-8686-0a0bfe16e019
- [ ] Co-organizers: up to 10, picked with **Choose co-organizers** under Options > **Roles**. They can't change the meeting before it starts. The organizer role can't be changed.
  Source: https://support.microsoft.com/topic/c16fa7d0-1666-4dde-8686-0a0bfe16e019 ; https://learn.microsoft.com/en-us/microsoftteams/meetings-events-feature-comparison
- [ ] "Who can present" choices: Everyone, People in my org and guests, Specific people, Only organizers and co-organizers. Graph `allowedPresenters`: everyone, organization, roleIsPresenter, organizer.
  Source: https://support.microsoft.com/topic/c16fa7d0-1666-4dde-8686-0a0bfe16e019 ; https://learn.microsoft.com/en-us/graph/api/resources/onlinemeeting?view=graph-rest-1.0
- [ ] Role scope:
  - A role change from the People pane applies to that occurrence only.
  - A change from Calendar options applies to all future occurrences of a series.
  - Someone who rejoins gets their last assigned role.
  Source: https://support.microsoft.com/topic/c16fa7d0-1666-4dde-8686-0a0bfe16e019
- [ ] Anonymous users promoted to presenter can't mute or remove others, or lower hands (except on mobile).
  Source: https://support.microsoft.com/topic/c16fa7d0-1666-4dde-8686-0a0bfe16e019
- [ ] Policy LimitPresenterRolePermissions reduces what presenters can do.
  Source: https://learn.microsoft.com/en-us/microsoftteams/settings-policies-reference

## 10. Raise hand

- [ ] Raise or lower your hand: **Raise** in the toolbar, **React** > **Raise hand** / **Lower hand**, or **More actions** > **React** > **Raise hand**. Shortcut: **Ctrl+Shift+K**.
  Source: https://support.microsoft.com/office/raise-your-hand-in-a-teams-meeting-bb2dd8e1-e6bd-43a6-85cf-30822667b372 ; https://support.microsoft.com/topic/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] Hand queue: a hand icon shows next to each participant in People, and names are numbered in the order hands went up. Presenters are notified.
  Source: https://support.microsoft.com/office/raise-your-hand-in-a-teams-meeting-bb2dd8e1-e6bd-43a6-85cf-30822667b372
- [ ] Auto-lower: after you speak, a notification says your hand will be lowered, with **Keep it raised** to cancel. Depends on noise suppression being on.
  Source: https://support.microsoft.com/office/raise-your-hand-in-a-teams-meeting-bb2dd8e1-e6bd-43a6-85cf-30822667b372
- [ ] Screen reader: **Ctrl+Shift+L** announces raised hands.
  Source: https://support.microsoft.com/topic/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2

## 11. Live reactions

- [ ] **React** offers five reactions: Like, Love, Applause, Laugh, Surprise. The admin "Reactions" policy names the same five.
  Source: https://support.microsoft.com/en-us/office/express-yourself-in-teams-meetings-with-live-reactions-a8323a40-3d07-4129-934b-305370a36e21 ; https://learn.microsoft.com/en-us/microsoftteams/settings-policies-reference
- [ ] Where reactions show:
  - A short pop-up at the bottom of the stage and over the sender's video tile or avatar.
  - While content is shared, they float up from the bottom for a few seconds.
  - They do not show in Large gallery.
  - They do show with filters and backgrounds and in breakout rooms.
  Source: https://support.microsoft.com/en-us/office/express-yourself-in-teams-meetings-with-live-reactions-a8323a40-3d07-4129-934b-305370a36e21
- [ ] Organizer can turn reactions off with the meeting option **Allow reactions** (Graph: `allowTeamworkReactions`).
  Source: https://support.microsoft.com/en-us/office/meeting-options-in-microsoft-teams-53261366-dbd5-45f9-aae9-a70e6354f88e

## 12. Views and layouts

- [ ] **View** > **Gallery** (default). **Select max gallery size** offers 4, 9, 16 or 49 on desktop.
  - The 49-tile gallery needs the desktop app and an 11th-gen Intel 4+ core CPU or Apple M1+.
  - Teams shows fewer videos under bandwidth or memory pressure.
  Source: https://support.microsoft.com/topic/3647fc29-7b92-4c26-8c2d-8a596904cdae ; https://support.microsoft.com/topic/95aaeaf8-0f22-46cf-a6f9-34ca9b04a1b2
- [ ] **Show videos first** puts camera-on participants first (Gallery only).
  Source: https://support.microsoft.com/topic/3647fc29-7b92-4c26-8c2d-8a596904cdae
- [ ] **View** > **Large gallery**: a 7x7 grid of up to 49 others.
  - Available once at least 10 cameras are on.
  - With more than 49 people, **< >** paging controls appear at the bottom.
  - Turned off when a watermark or E2EE is in use.
  Source: https://support.microsoft.com/topic/95aaeaf8-0f22-46cf-a6f9-34ca9b04a1b2 ; https://learn.microsoft.com/en-us/microsoftteams/watermark-meeting-content-video ; https://learn.microsoft.com/en-us/microsoftteams/end-to-end-encrypted-meetings
- [ ] Speaker view: focuses on the current speaker. **[snippet]**
  Source: https://support.microsoft.com/office/95aaeaf8-0f22-46cf-a6f9-34ca9b04a1b2
- [ ] **Focus on content**: hides video tiles while someone presents.
  Source: https://support.microsoft.com/topic/3647fc29-7b92-4c26-8c2d-8a596904cdae
- [ ] **View** > **More options** > **Show gallery at top** docks videos above shared content (for eye contact). By default, videos move to the side when content is shared.
  Source: https://support.microsoft.com/topic/95aaeaf8-0f22-46cf-a6f9-34ca9b04a1b2
- [ ] Dynamic layout: when content is shared, the content enlarges while more participants stay visible.
  Source: https://support.microsoft.com/office/95aaeaf8-0f22-46cf-a6f9-34ca9b04a1b2
- [ ] Swap content with gallery: selecting a video tile brings videos to the center and moves content aside; selecting the content swaps back.
  Source: https://support.microsoft.com/topic/95aaeaf8-0f22-46cf-a6f9-34ca9b04a1b2
- [ ] Tile framing: **Fit to frame** (whole video) or **Fill frame** (cropped).
  Source: https://support.microsoft.com/topic/3647fc29-7b92-4c26-8c2d-8a596904cdae
- [ ] **Hide me** / **Unhide me** hides your own tile from your view only.
  Source: https://support.microsoft.com/topic/3647fc29-7b92-4c26-8c2d-8a596904cdae
- [ ] **Turn off incoming video** (in More actions).
  Source: https://support.microsoft.com/en-us/office/use-meeting-controls-in-microsoft-teams-ee1134a2-c74d-41ef-be98-e979d6167915
- [ ] Together mode is **retired**: removed from the View menu in June 2026 along with custom scenes and seat assignment. Gallery is now the primary multi-person layout. Do not build it; at most, cover its absence.
  Source: https://mc.merill.net/message/MC1296478
- [ ] A gallery opened in a new window shows up to 9 videos.
  Source: https://support.microsoft.com/topic/3647fc29-7b92-4c26-8c2d-8a596904cdae
- [ ] Proximity-join hiding: when your own device is also in the meeting through a nearby Teams Room, the room's video is hidden on your device stage and your video is hidden on the room display. Pinning or spotlighting overrides this.
  Source: https://learn.microsoft.com/en-us/microsoftteams/rooms/proximity-join

## 13. Pin and spotlight

- [ ] Pin: hover a video > **More options** > **Pin for me** / **Unpin for me**. Affects only your own view.
  Source: https://support.microsoft.com/topic/95aaeaf8-0f22-46cf-a6f9-34ca9b04a1b2
- [ ] Spotlight (organizers and presenters, including themselves): hover > **More options** > **Spotlight for everyone**; **Stop spotlighting** removes it.
  - Participants can choose **Exit spotlight**.
  - Spotlight does not work in Large gallery.
  - Teams mobile can't start a spotlight but shows them.
  Source: https://support.microsoft.com/topic/95aaeaf8-0f22-46cf-a6f9-34ca9b04a1b2 ; https://support.microsoft.com/topic/3647fc29-7b92-4c26-8c2d-8a596904cdae

## 14. Manage what attendees see (production mode)

- [ ] Meeting option "Manage what attendees see": attendees see only shared content and the people brought on screen, and attendee mic and camera use is limited.
  Source: https://support.microsoft.com/en-us/office/meeting-options-in-microsoft-teams-53261366-dbd5-45f9-aae9-a70e6354f88e
- [ ] **Bring on screen** and take off screen, from the participant **More options** menu or the Manage screen. An attendee taken off screen has mic and camera turned off automatically. **[snippet]**
  Source: https://support.microsoft.com/office/manage-what-attendees-see-in-microsoft-teams-19bfd690-8122-49f4-bc04-c2c5f69b4e16
- [ ] "On with preview" mode: queue people on or off screen before they go live. Firefox and Safari attendees get the standard experience. Built into town halls; needs Premium for meetings and webinars. **[snippet]**
  Source: https://support.microsoft.com/office/manage-what-attendees-see-in-microsoft-teams-19bfd690-8122-49f4-bc04-c2c5f69b4e16

## 15. Share content

- [ ] **Share** tray options:
  - Entire screen or a window, with live previews in the refreshed panel. **[UI-2026]**
  - PowerPoint Live
  - Excel Live
  - Whiteboard
  - Browse OneDrive / Browse my computer
  - Refreshed panel: tabs "Screens & Apps", "Interactive Files" and "More options", plus a two-step share confirmation. **[UI-2026; tab names from secondary coverage]**
  Source: https://support.microsoft.com/topic/fcc2bf59-aecd-4481-8f99-ce55dd836ce8 ; https://mc.merill.net/message/MC1317197
- [ ] **Include sound** toggle in the share flow, set before sharing starts.
  Source: https://support.microsoft.com/topic/fcc2bf59-aecd-4481-8f99-ce55dd836ce8
- [ ] Presenter toolbar while sharing:
  - Drag handle to move it
  - **Pin** to keep it in place
  - **Camera**, **Mic**
  - **Share audio**
  - **Optimize** (for video and motion)
  - **Layout**
  - **Give control** / **Take back**
  - **Slide control** / **End slide control**
  - **Annotate**
  - **Chat**, **People**
  - **Stop sharing**
  - Shortcut: **Ctrl+Shift+Spacebar** focuses the sharing toolbar.
  Source: https://support.microsoft.com/topic/fcc2bf59-aecd-4481-8f99-ce55dd836ce8 ; https://support.microsoft.com/topic/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] Presenter **Layout** modes (camera must be on): **Content only**, **Standout**, **Side-by-side**, **Reporter**.
  Source: https://support.microsoft.com/topic/fcc2bf59-aecd-4481-8f99-ce55dd836ce8
- [ ] Viewer remote control: **Request control** / **Release control**.
  - Both sides must use the desktop client.
  - Policies: "Participants can give or request control" (on) and "External participants can give or request control" (off).
  - Not available on Linux or under E2EE.
  Source: https://support.microsoft.com/topic/fcc2bf59-aecd-4481-8f99-ce55dd836ce8 ; https://learn.microsoft.com/en-us/microsoftteams/settings-policies-reference
- [ ] Slide control limits: only for window shares (not full screen) started from the desktop app. Mac users can receive it but not start it.
  Source: https://support.microsoft.com/topic/fcc2bf59-aecd-4481-8f99-ce55dd836ce8
- [ ] **Annotate**: collaborative drawing over a screen share. Policy: "Collaborative annotations".
  Source: https://support.microsoft.com/topic/fcc2bf59-aecd-4481-8f99-ce55dd836ce8 ; https://learn.microsoft.com/en-us/microsoftteams/settings-policies-reference
- [ ] Zoom shared content: **[+]** and **[-]** buttons, Ctrl+scroll, pinch, and drag to pan.
  - Zoom in **Alt+Shift+Plus**, zoom out **Alt+Shift+Minus**, reset **Alt+Shift+0**.
  - Pan with **Alt+Shift+arrow keys**.
  Source: https://support.microsoft.com/topic/fcc2bf59-aecd-4481-8f99-ce55dd836ce8 ; https://support.microsoft.com/topic/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] Open shared content in a new window (desktop only); close it with **X**.
  Source: https://support.microsoft.com/topic/fcc2bf59-aecd-4481-8f99-ce55dd836ce8
- [ ] Incoming screen share in calls: accept with **Ctrl+Shift+A**, decline with **Ctrl+Shift+D**.
  Source: https://support.microsoft.com/topic/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] Policy "Screen sharing" (default Entire screen) can limit sharing to a single application or disable it.
  Source: https://learn.microsoft.com/en-us/microsoftteams/settings-policies-reference
- [ ] Sensitive-content detection while sharing (Premium): warns the presenter when, for example, card or bank numbers are visible.
  Source: https://support.microsoft.com/en-us/office/meeting-options-in-microsoft-teams-53261366-dbd5-45f9-aae9-a70e6354f88e
- [ ] Linux and web limits: the Linux desktop client can't share or take control. On the web a meeting gets a single stream (speaker or share).
  Source: https://support.microsoft.com/topic/fcc2bf59-aecd-4481-8f99-ce55dd836ce8 ; https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams

## 16. PowerPoint Live

- [ ] Start: Share > PowerPoint Live section, or Browse OneDrive / Browse my computer. PowerPoint desktop also has **Present in Teams**.
  - Only .pptx and .ppsx files; maximum 2 GB.
  - Channel-meeting files upload to the channel Files tab; private-meeting files go to the presenter's OneDrive.
  Source: https://support.microsoft.com/topic/fc5a5394-2159-419c-bc59-1f64c1f4e470 ; https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams
- [ ] Presenter view:
  - Notes beside the slide.
  - Navigation arrows and a thumbnail strip.
  - **Grid view** of all slides.
  - Tools: Laser pointer, Pen, Highlighter, Eraser.
  - **Present the latest version** syncs edits.
  - **Show presenter view** toggles it (**Ctrl+Shift+X**); hidden by default on small screens.
  Source: https://support.microsoft.com/topic/fc5a5394-2159-419c-bc59-1f64c1f4e470
- [ ] Private view control: the Private view icon, or **Turn off participant navigation**, stops attendees from browsing ahead.
  Source: https://support.microsoft.com/topic/fc5a5394-2159-419c-bc59-1f64c1f4e470
- [ ] Attendee view:
  - Browse slides privately, then **Sync to presenter** to rejoin the live slide.
  - **Change view** > **View slides in high contrast**.
  - Personal captions and translated slides.
  - Clickable hyperlinks and controllable embedded video.
  - Zoom with +/- or Ctrl+scroll, pan with the arrow keys, **Esc** resets.
  Source: https://support.microsoft.com/topic/fc5a5394-2159-419c-bc59-1f64c1f4e470
- [ ] Take control of someone else's presentation: presenters and organizers only.
  Source: https://support.microsoft.com/topic/c16fa7d0-1666-4dde-8686-0a0bfe16e019
- [ ] PowerPoint Live limits:
  - Recordings don't capture its videos, animations or annotations.
  - Anonymous users can't present.
  - Not available in E2EE meetings or town halls.
  - Policy: "PowerPoint Live" (Graph: `allowPowerPointSharing`).
  Source: https://support.microsoft.com/topic/fc5a5394-2159-419c-bc59-1f64c1f4e470 ; https://learn.microsoft.com/en-us/microsoftteams/end-to-end-encrypted-meetings ; https://learn.microsoft.com/en-us/microsoftteams/meetings-events-feature-comparison

## 17. Whiteboard, Excel Live, Live Share

- [ ] Share > Whiteboard section > **Microsoft Whiteboard** opens a board picker (existing board or new). A board already tied to the meeting is shared by default. **[snippet]**
  Source: https://support.microsoft.com/topic/c6b40ba4-52ff-408d-868e-6fc6ebccc5dc
- [ ] Whiteboard availability: only same-tenant users can collaborate; anonymous, federated and external users can't **[snippet]**. Whiteboard content is not captured in recordings. Policy: "Whiteboard" (Graph: `allowWhiteboard`).
  Source: https://support.microsoft.com/topic/c6b40ba4-52ff-408d-868e-6fc6ebccc5dc ; https://support.microsoft.com/topic/34dfbe7f-b07d-4a27-b4c6-de62f1348c24
- [ ] After the meeting the board is in a **Whiteboard** tab of the meeting chat. **[snippet]**
  Source: https://support.microsoft.com/topic/c6b40ba4-52ff-408d-868e-6fc6ebccc5dc
- [ ] Excel Live: co-edit a workbook inside the meeting. Not available under E2EE.
  Source: https://support.microsoft.com/topic/fcc2bf59-aecd-4481-8f99-ce55dd836ce8 ; https://learn.microsoft.com/en-us/microsoftteams/end-to-end-encrypted-meetings
- [ ] Live Share / document collaboration in the meeting window. Policies: "Live Share", AllowDocumentCollaboration (Graph: `allowLiveShare`).
  Source: https://learn.microsoft.com/en-us/microsoftteams/settings-policies-reference

## 18. Meeting options (organizer)

- [ ] Opening the options:
  - Before the meeting: Calendar > event > **View event** > **Options**.
  - During the meeting: **Controls** > **View more options**.
  - The options open in a browser window. Save with **Apply** or **Save**.
  - Graph: `meetingOptionsWebUrl`.
  Source: https://support.microsoft.com/en-us/office/meeting-options-in-microsoft-teams-53261366-dbd5-45f9-aae9-a70e6354f88e ; https://learn.microsoft.com/en-us/graph/api/resources/onlinemeeting?view=graph-rest-1.0
- [ ] **Meeting access** group:
  - Sensitivity (Premium; locks some other options)
  - Who can bypass the lobby?
  - People dialing in can bypass the lobby
  - Who can admit from the lobby
  - Show meeting info on join screen
  - Reject anyone who can't bypass the lobby
  - Announce when people dialing in join or leave
  - Require unverified participants to verify their info before joining (Premium)
  - Verify external presenters before joining an event
  Source: https://support.microsoft.com/en-us/office/meeting-options-in-microsoft-teams-53261366-dbd5-45f9-aae9-a70e6354f88e
- [ ] **Advanced protection** group (Premium):
  - Turn off copying and forwarding of meeting chat and transcripts
  - End-to-end encryption
  - Apply a watermark to shared content
  - Apply a watermark to everyone's video feed
  - Prevent screen captures: the meeting window goes black on capture; unsupported clients get audio only.
  - Detect sensitive content during screen sharing
  Source: https://support.microsoft.com/en-us/office/meeting-options-in-microsoft-teams-53261366-dbd5-45f9-aae9-a70e6354f88e
- [ ] **Roles** group: Choose co-organizers; Who can present; Enable language interpretation.
  Source: https://support.microsoft.com/en-us/office/meeting-options-in-microsoft-teams-53261366-dbd5-45f9-aae9-a70e6354f88e
- [ ] **Production tools** group: Manage what attendees see; RTMP-In; Enable Green room.
  Source: https://support.microsoft.com/en-us/office/meeting-options-in-microsoft-teams-53261366-dbd5-45f9-aae9-a70e6354f88e
- [ ] **Participation** group:
  - Allow mic for attendees; Allow camera for attendees
  - Meeting chat: anytime / during the meeting only / not at all (Graph `allowMeetingChat`: enabled / limited / disabled)
  - Q&A: unmoderated or moderated, optional anonymous posts
  - Allow reactions
  - Hide attendee names
  - Allow attendance report
  Source: https://support.microsoft.com/en-us/office/meeting-options-in-microsoft-teams-53261366-dbd5-45f9-aae9-a70e6354f88e ; https://learn.microsoft.com/en-us/graph/api/resources/onlinemeeting?view=graph-rest-1.0
- [ ] **Recording & transcription** group:
  - Record and transcribe automatically
  - Who can record and transcribe (Premium/Copilot): organizers and co-organizers / plus presenters / no one
  - Who has access to the recording and transcript (Premium/Copilot): everyone / organizers and co-organizers / specific people; not for channel meetings
  - Enable multilingual speech recognition (Premium/Copilot; not in town halls)
  Source: https://support.microsoft.com/en-us/office/meeting-options-in-microsoft-teams-53261366-dbd5-45f9-aae9-a70e6354f88e
- [ ] **Copilot and other AI** group:
  - Allow Copilot dropdown: **Off** / **Only during the meeting** / **During and after the meeting**. Turning Copilot **Off** also turns off recording and transcription.
  - Facilitator: a notes agent that joins the chat.
  Source: https://support.microsoft.com/en-us/office/meeting-options-in-microsoft-teams-53261366-dbd5-45f9-aae9-a70e6354f88e ; https://learn.microsoft.com/en-us/microsoftteams/copilot-teams-transcription
- [ ] **Accessibility** group: Provide CART Captions (meetings only).
  Source: https://support.microsoft.com/en-us/office/meeting-options-in-microsoft-teams-53261366-dbd5-45f9-aae9-a70e6354f88e
- [ ] Defaults and failure behavior: defaults come from admin policy and the options are per meeting. During a service outage they may revert to admin defaults.
  Source: https://support.microsoft.com/en-us/office/meeting-options-in-microsoft-teams-53261366-dbd5-45f9-aae9-a70e6354f88e
- [ ] Graph: `PATCH /me/onlineMeetings/{id}` with:
  - `allowAttendeeToEnableCamera`, `allowAttendeeToEnableMic`
  - `allowBreakoutRooms`, `allowCopyingAndSharingMeetingContent`
  - `allowedLobbyAdmitters`, `allowedPresenters`
  - `allowLiveShare`, `allowMeetingChat`, `allowParticipantsToChangeName`, `allowPowerPointSharing`
  - `allowRecording`, `allowTeamworkReactions`, `allowTranscription`, `allowWhiteboard`
  - `chatRestrictions`, `isEndToEndEncryptionEnabled`, `isEntryExitAnnounced`
  - `lobbyBypassSettings`, `meetingSpokenLanguageTag`, `recordAutomatically`
  - `shareMeetingChatHistoryDefault`, `watermarkProtection`, `sensitivityLabelAssignment`
  Source: https://learn.microsoft.com/en-us/graph/api/resources/onlinemeeting?view=graph-rest-1.0

## 19. Security options in practice (E2EE, watermark)

- [ ] E2EE meetings: the organizer needs Premium. Maximum 200 participants.
  - Supported on Windows and Mac desktop, mobile, and Teams Rooms. Web, VDI and CVI joiners are blocked.
  - Turned off under E2EE: captions, transcription, recording, RTT, breakout rooms, Excel Live, PowerPoint Live, request control, companion mode, Large gallery, PSTN dial-in, Copilot. Apps lose media access.
  Source: https://learn.microsoft.com/en-us/microsoftteams/end-to-end-encrypted-meetings
- [ ] Watermark: each viewer sees their own email overlaid on video and/or shared content. Admins set the pattern and transparency.
  - Turned off with a watermark: Large gallery and Content from camera.
  - Audio-only participants: VDI, anonymous, overflow, older clients, and direct guest join from Rooms.
  - Recordings are watermarked at playback, and download is off by default.
  Source: https://learn.microsoft.com/en-us/microsoftteams/watermark-meeting-content-video

## 20. Recording

- [ ] Start recording: **More actions** > **Record**, choose the spoken language and what to record, then **Confirm**.
  - **Choose what to record** dropdown includes **Audio only**.
  - Transcription can be started together with the recording.
  Source: https://support.microsoft.com/topic/34dfbe7f-b07d-4a27-b4c6-de62f1348c24
- [ ] Stop: **More actions** > **Recording**, then pick **Recording** (stops the recording and the transcript) or **Transcribing** (stops only the transcript).
  Source: https://support.microsoft.com/topic/34dfbe7f-b07d-4a27-b4c6-de62f1348c24
- [ ] Who can record:
  - One recording at a time.
  - The recorder needs a license, the policy, and the organizer's policy. The organizer doesn't need to be present.
  - Guests, users from other orgs and anonymous users can't record.
  - The recording continues if the person who started it leaves.
  Source: https://support.microsoft.com/topic/34dfbe7f-b07d-4a27-b4c6-de62f1348c24
- [ ] Recording notice: everyone is told when recording starts, with a privacy policy link that admins can customize. An optional explicit-consent policy is also available.
  Source: https://support.microsoft.com/topic/34dfbe7f-b07d-4a27-b4c6-de62f1348c24 ; https://learn.microsoft.com/en-us/microsoftteams/meeting-recording
- [ ] Storage:
  - Saved to the organizer's OneDrive, or the channel's SharePoint **Recordings** folder (**Recordings\View only** when ChannelRecordingDownload is Block).
  - Linked in the meeting chat and shown in the calendar event's **Recordings and Transcripts** tab.
  - If upload fails, it is held up to 21 days for download.
  Source: https://learn.microsoft.com/en-us/microsoftteams/meeting-recording
- [ ] Length limits: at most 4 hours or 1.5 GB, then it auto-restarts. It stops when everyone leaves.
  Source: https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams
- [ ] Not captured: more than 4 simultaneous video streams, whiteboard, annotations, shared notes, app content, and PowerPoint Live video or animations.
  Source: https://support.microsoft.com/topic/34dfbe7f-b07d-4a27-b4c6-de62f1348c24
- [ ] Expiration: default 120 days (admin can set 1 to 99,999). Owners can change it on the player page or choose **Remove expiration**. Expired files are recoverable for 90 days. Event recordings default to 30 days, extendable to 60.
  Source: https://learn.microsoft.com/en-us/microsoftteams/settings-policies-reference ; https://support.microsoft.com/topic/34dfbe7f-b07d-4a27-b4c6-de62f1348c24 ; https://learn.microsoft.com/en-us/microsoftteams/plan-town-halls
- [ ] Download and delete: by default only organizers and co-organizers can download or delete.
  Source: https://support.microsoft.com/topic/34dfbe7f-b07d-4a27-b4c6-de62f1348c24
- [ ] Graph:
  - `GET /me/onlineMeetings/{id}/recordings` and `/recordings/{id}/content` (.mp4)
  - Tenant-wide: `communications/onlineMeetings/getAllRecordings`
  - Ad hoc calls: `communications/adhocCalls/{callId}/recordings`
  - Change notifications are available.
  Source: https://learn.microsoft.com/en-us/microsoftteams/platform/graph-api/meeting-transcripts/overview-transcripts

## 21. Live transcription

- [ ] Start: **More actions** > **Transcribe**, confirm the spoken language, **Confirm**. Recording also starts transcription.
  Source: https://support.microsoft.com/topic/dc1a8f23-2e20-4684-885e-2152e06a4a8b
- [ ] Transcript pane:
  - **Transcribing** dropdown > **Show transcript** / **Hide transcript**.
  - Each entry shows speaker name and time.
  - **Language settings** > **Spoken language in this meeting** > **Update**.
  - **Translate to** toggle (Premium; translated transcripts aren't saved).
  Source: https://support.microsoft.com/topic/dc1a8f23-2e20-4684-885e-2152e06a4a8b
- [ ] Spoken-language mismatch prompt: offers **Settings** or **Yes, change it**. A change applies to captions and transcript for everyone. Covers 57 language variants.
  Source: https://support.microsoft.com/topic/dc1a8f23-2e20-4684-885e-2152e06a4a8b
- [ ] Download: Recap > Transcript > **Download** dropdown, as .docx or .vtt.
  - Organizers and co-organizers can download by default.
  - Other tenants can only view in real time; anonymous users get nothing.
  - Delete with the trash-can **Delete** icon (organizer and co-organizers).
  Source: https://support.microsoft.com/topic/dc1a8f23-2e20-4684-885e-2152e06a4a8b
- [ ] Speaker identification: users can opt out of being identified in captions and transcripts (SpeakerAttributionMode). Obscenities are masked with asterisks.
  Source: https://support.microsoft.com/topic/dc1a8f23-2e20-4684-885e-2152e06a4a8b ; https://learn.microsoft.com/en-us/microsoftteams/settings-policies-reference
- [ ] Graph:
  - `GET /me/onlineMeetings/{id}/transcripts`, `/transcripts/{id}/content` (VTT), `metadataContent`
  - Tenant-wide: `communications/onlineMeetings/getAllTranscripts`
  - Tenant switches can block transcript API access (403 GraphAccessToTranscriptsDisabled) or speaker attribution.
  Source: https://learn.microsoft.com/en-us/microsoftteams/platform/graph-api/meeting-transcripts/overview-transcripts

## 22. Live captions and language

- [ ] Turn on live captions: **More actions** > Captions. Captions are not saved; use transcription to keep them. Policy: "Live captions" ("Turn on live captions" option).
  Source: https://support.microsoft.com/topic/4be2d304-f675-4b57-8347-cbd000a21260 ; https://learn.microsoft.com/en-us/microsoftteams/settings-policies-reference
- [ ] Caption settings: hover the captions pane > **Open caption settings** > **Caption styles** (font, size, color), number of lines, and position. Changes apply immediately.
  Source: https://support.microsoft.com/topic/4be2d304-f675-4b57-8347-cbd000a21260
- [ ] **Meeting spoken language** > **Update**. Other participants can only change it while transcription is off.
  Source: https://support.microsoft.com/topic/4be2d304-f675-4b57-8347-cbd000a21260
- [ ] Translated captions: **Translate to** (Premium or Copilot; everyone gets it if the organizer is licensed). In town halls the organizer preselects up to 6 languages (10 with Premium).
  Source: https://support.microsoft.com/topic/4be2d304-f675-4b57-8347-cbd000a21260
- [ ] CART captions (human-provided): the organizer sets them up in Accessibility options. Meetings only.
  Source: https://support.microsoft.com/topic/4be2d304-f675-4b57-8347-cbd000a21260 ; https://learn.microsoft.com/en-us/microsoftteams/meetings-events-feature-comparison
- [ ] Multilingual speech recognition: each participant picks their own spoken language (Premium or Copilot).
  Source: https://support.microsoft.com/en-us/office/meeting-options-in-microsoft-teams-53261366-dbd5-45f9-aae9-a70e6354f88e
- [ ] Language interpretation: human interpreters, set up with "Enable language interpretation"; attendees pick a language channel. Meetings only. Also an AI Interpreter agent (Premium or Copilot).
  Source: https://support.microsoft.com/en-us/office/meeting-options-in-microsoft-teams-53261366-dbd5-45f9-aae9-a70e6354f88e ; https://learn.microsoft.com/en-us/microsoftteams/meetings-events-feature-comparison
- [ ] Real-Time Text (RTT) in meetings. Not available under E2EE.
  Source: https://learn.microsoft.com/en-us/microsoftteams/meetings-events-feature-comparison ; https://learn.microsoft.com/en-us/microsoftteams/end-to-end-encrypted-meetings

## 23. Breakout rooms

- [ ] Open the panel: **Rooms** in the toolbar (or More actions > Rooms). Organizers, and presenters assigned as room managers, create rooms; desktop only.
  Source: https://support.microsoft.com/en-us/office/use-breakout-rooms-in-microsoft-teams-meetings-7de1f48a-da07-466c-a5ab-4ebace28e461
- [ ] Create rooms:
  - Choose the number of rooms (up to 50).
  - Assignment: **Automatically** (random), **Manually**, or let participants choose.
  - **Create rooms**.
  - Automatic assignment can only be chosen at creation time.
  Source: https://support.microsoft.com/en-us/office/use-breakout-rooms-in-microsoft-teams-meetings-7de1f48a-da07-466c-a5ab-4ebace28e461 ; https://learn.microsoft.com/en-us/training/modules/facilitate-meetings-events-microsoft-teams/4-use-breakout-rooms-teams
- [ ] Create rooms before the meeting: Calendar > meeting > View event > More options > **Breakout rooms** > **Create rooms** > **Add rooms** > **Assign participants**. Requires the invite to have been sent. Room meetings are capped at 1,000 invitees.
  Source: https://support.microsoft.com/en-us/office/use-breakout-rooms-in-microsoft-teams-meetings-7de1f48a-da07-466c-a5ab-4ebace28e461 ; https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams
- [ ] Manual assignment: **Assign participants** > tick names > **Assign** > choose a room. PSTN callers and Teams devices can't be assigned. Teams free accounts can't be assigned.
  Source: https://learn.microsoft.com/en-us/training/modules/facilitate-meetings-events-microsoft-teams/4-use-breakout-rooms-teams ; https://support.microsoft.com/en-us/office/use-breakout-rooms-in-microsoft-teams-meetings-7de1f48a-da07-466c-a5ab-4ebace28e461
- [ ] **Rooms settings** (then **Save**):
  - "Automatically move people to rooms"; when off, participants get a **Join room** prompt.
  - "Participants can return to the main meeting" (off by default).
  - "Set a time limit" (duration dropdowns).
  - "Assign presenters to manage rooms" (**Search for presenters** before the meeting).
  Source: https://support.microsoft.com/en-us/office/use-breakout-rooms-in-microsoft-teams-meetings-7de1f48a-da07-466c-a5ab-4ebace28e461 ; https://learn.microsoft.com/en-us/training/modules/facilitate-meetings-events-microsoft-teams/4-use-breakout-rooms-teams
- [ ] Open and close:
  - **Open rooms** (all) or per-room More options > **Open**.
  - **Close rooms** (all) or per room **Close**.
  - Closed rooms show status **Closed**; reopening returns people to their assigned rooms.
  - When the time limit ends, rooms close automatically.
  Source: https://support.microsoft.com/en-us/office/use-breakout-rooms-in-microsoft-teams-meetings-7de1f48a-da07-466c-a5ab-4ebace28e461
- [ ] Per-room **More options** menu: **Rename** (dialog with **Rename**), **Delete** (room must be closed; confirm), **Open**, **Close**, **Join room**. Also **Add room** and **Remove rooms** (all).
  Source: https://support.microsoft.com/en-us/office/use-breakout-rooms-in-microsoft-teams-meetings-7de1f48a-da07-466c-a5ab-4ebace28e461
- [ ] Panel-level **More options**: **Make an announcement** (posted in each room chat marked IMPORTANT; replies go to the organizer's chat list), **Rooms settings**, **Recreate rooms** (start over).
  Source: https://support.microsoft.com/en-us/office/use-breakout-rooms-in-microsoft-teams-meetings-7de1f48a-da07-466c-a5ab-4ebace28e461 ; https://learn.microsoft.com/en-us/training/modules/facilitate-meetings-events-microsoft-teams/4-use-breakout-rooms-teams
- [ ] Move a person to another room: tick their name > More options > choose the room. Only possible while rooms are closed. **[legacy label]**
  Source: https://learn.microsoft.com/en-us/training/modules/facilitate-meetings-events-microsoft-teams/4-use-breakout-rooms-teams
- [ ] Room managers: only one manager controls rooms at a time (Rooms > **Manage rooms**). Managers can join any room; leave with **Return**.
  Source: https://support.microsoft.com/en-us/office/use-breakout-rooms-in-microsoft-teams-meetings-7de1f48a-da07-466c-a5ab-4ebace28e461 ; https://learn.microsoft.com/en-us/training/modules/facilitate-meetings-events-microsoft-teams/4-use-breakout-rooms-teams
- [ ] Participant side: with auto-move they are moved in when rooms open. With self-select they browse open rooms. With return allowed, they can go back to the main meeting. When rooms close they return to the main meeting.
  Source: https://support.microsoft.com/en-us/office/use-breakout-rooms-in-microsoft-teams-meetings-7de1f48a-da07-466c-a5ab-4ebace28e461
- [ ] Room chat: each room has its own chat, listed in the main Chat list. When the room closes the chat becomes read-only, with history and files kept.
  Source: https://learn.microsoft.com/en-us/training/modules/facilitate-meetings-events-microsoft-teams/4-use-breakout-rooms-teams
- [ ] Not available inside rooms: Call me, adding people from the People pane, adding people to the chat, copying the join info. Breakout rooms are also not available under E2EE, in town halls, or above 1,000 attendees.
  Source: https://support.microsoft.com/en-us/office/use-breakout-rooms-in-microsoft-teams-meetings-7de1f48a-da07-466c-a5ab-4ebace28e461 ; https://learn.microsoft.com/en-us/microsoftteams/end-to-end-encrypted-meetings ; https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams
- [ ] Attendance report includes rooms entered and join/leave times per room, downloadable as CSV. Deleted rooms are excluded.
  Source: https://support.microsoft.com/en-us/office/use-breakout-rooms-in-microsoft-teams-meetings-7de1f48a-da07-466c-a5ab-4ebace28e461
- [ ] Graph: the `allowBreakoutRooms` flag only. There is no documented room-management API. Policy: AllowBreakoutRooms.
  Source: https://learn.microsoft.com/en-us/graph/api/resources/onlinemeeting?view=graph-rest-1.0 ; https://learn.microsoft.com/en-us/microsoftteams/settings-policies-reference

## 24. Meeting chat

- [ ] Meeting chat works before, during and after the meeting by default, with replies, @mentions, reactions, formatting, images and files.
  - Organizer setting: On / Off / In meeting only.
  - Admin policy values: On for everyone, On for everyone but anonymous users, Off, In-meeting only (with and without anonymous). The admin value overrides the organizer's choice.
  Source: https://learn.microsoft.com/en-us/microsoftteams/manage-meeting-chat
- [ ] Shortcut: **Ctrl+Shift+R** opens the meeting chat from a meeting notification.
  Source: https://support.microsoft.com/topic/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] Chat history for people added later: Graph `shareMeetingChatHistoryDefault` (all / none). `chatInfo` gives the thread ID; read it with `GET /chats/{threadId}/messages`.
  Source: https://learn.microsoft.com/en-us/graph/api/resources/onlinemeeting?view=graph-rest-1.0
- [ ] Chat in external untrusted-org meetings: policy "External meeting chat".
  Source: https://learn.microsoft.com/en-us/microsoftteams/manage-meeting-chat
- [ ] Prevent copying and forwarding chat (Premium): blocks copy, forward and share-to-Outlook for chat, captions and transcripts.
  Source: https://learn.microsoft.com/en-us/microsoftteams/settings-policies-reference
- [ ] Town halls: attendees get a during-event comment stream only. Organizers and presenters have a separate event group chat.
  Source: https://learn.microsoft.com/en-us/microsoftteams/manage-meeting-chat ; https://learn.microsoft.com/en-us/microsoftteams/meetings-events-feature-comparison

## 25. Leave, end, rejoin

- [ ] **Leave** exits only you; the meeting continues for others.
  Source: https://support.microsoft.com/en-us/topic/5051fa72-8470-4a38-99e4-014535208971
- [ ] End for everyone (organizer): Leave dropdown > **End meeting** > **End** to confirm.
  Source: https://support.microsoft.com/en-us/topic/5051fa72-8470-4a38-99e4-014535208971
- [ ] Rejoin: **Join** from the meeting chat or calendar event. In a group-chat Meet now, the last person to leave ends the meeting.
  Source: https://support.microsoft.com/topic/ff95e53f-8231-4739-87fa-00b9723f4ef5
- [ ] Recording and transcription stop when everyone has left.
  Source: https://support.microsoft.com/topic/34dfbe7f-b07d-4a27-b4c6-de62f1348c24 ; https://support.microsoft.com/topic/dc1a8f23-2e20-4684-885e-2152e06a4a8b

## 26. View-only overflow attendees

- [ ] Trigger: once the main meeting is full (about 1,000), up to 10,000 more join view-only. The organizer sees a warning banner at about 500. Up to 50 presenter seats are reserved, and the organizer always gets a seat.
  Source: https://learn.microsoft.com/en-us/microsoftteams/view-only-meeting-experience
- [ ] What view-only attendees get:
  - The active speaker or the screen share, never both.
  - About 30 seconds of delay.
  - English captions only, on desktop and web.
  - They can't chat, raise a hand, react, use apps or polls, speak or show video, see PowerPoint Live, or access the recording.
  - They don't appear in the People pane.
  Source: https://learn.microsoft.com/en-us/microsoftteams/view-only-meeting-experience

## 27. Second device, companion mode, Rooms, Cast

- [ ] Second device: with the meeting running on one device, open Teams on another and select the **Join call** banner, then:
  - **Add this device**: both stay in the meeting. The new device's camera and mic are muted (mobile also mutes its speaker). Either device can share.
  - **Transfer to this device**: set audio and video, then **Join**. The first device leaves.
  Source: https://support.microsoft.com/en-us/office/join-a-microsoft-teams-meeting-on-a-second-device-c28e7407-183b-46ea-ab17-2212700e5f41
- [ ] **Leave on all my devices** in the Leave dropdown.
  Source: https://support.microsoft.com/en-us/office/join-a-microsoft-teams-meeting-on-a-second-device-c28e7407-183b-46ea-ab17-2212700e5f41
- [ ] Companion devices and transfer are unavailable under E2EE.
  Source: https://learn.microsoft.com/en-us/microsoftteams/end-to-end-encrypted-meetings
- [ ] Proximity join to a Teams Room (Bluetooth and/or ultrasound): the **Room audio** pre-join option invites a nearby Room into the meeting even if the Room wasn't invited.
  - The user must be in the same tenant or a trusted org, and must be able to bypass the lobby.
  - Required for Room Remote.
  Source: https://learn.microsoft.com/en-us/microsoftteams/rooms/proximity-join ; https://support.microsoft.com/en-us/office/join-a-meeting-in-microsoft-teams-1613bb53-f3fa-431e-85a9-d6a91e3468c9
- [ ] Cast to a Teams Room (no meeting needed): Settings and more > **Cast** > pick a nearby room > cast, or cast and join a scheduled meeting.
  - Rooms marked with a wireless icon accept automatically.
  - Ending in Teams ends it for both sides.
  **[snippet]**
  Source: https://support.microsoft.com/topic/6d62cdbb-3da2-4bb9-80bd-9cf1098beb3d

## 28. Meeting notes (Loop), Copilot, Facilitator

- [ ] **Notes** in the toolbar, or More actions > **Show notes**, opens a right-side pane with collaborative notes (Loop page). Anyone invited can edit before, during and after the meeting; external attendees can't. Admin policy: "Shared notes". **[snippet]**
  Source: https://support.microsoft.com/topic/3eadf032-0ef8-4d60-9e21-0691d317d103 ; https://learn.microsoft.com/en-us/microsoftteams/settings-policies-reference
- [ ] Notes in instant (Meet now) meetings and chat calls, in the right-side pane (rolled out 2026). **[snippet]**
  Source: https://mc.merill.net/message/MC1218712
- [ ] **Copilot** in the toolbar opens a private Copilot pane. Prompts are private to each licensed user.
  - Suggested prompts under the compose box include "Recap the meeting so far" and "List action items". **[snippet]**
  Source: https://support.microsoft.com/office/0bf9dd3c-96f7-44e2-8bb8-790bedf066b1 ; https://learn.microsoft.com/en-us/microsoftteams/copilot-teams-transcription
- [ ] How Copilot depends on transcription:
  - **During and after the meeting**: needs someone to start transcription.
  - **Only during the meeting**: uses temporary speech-to-text and runs for all licensed users once one starts it.
  - Admin default "On with saved transcript required" forces **During and after**.
  - Not available under E2EE, in meetings hosted outside the user's org, or in GCC High.
  - In town halls only organizers, co-organizers and presenters can use it.
  Source: https://learn.microsoft.com/en-us/microsoftteams/copilot-teams-transcription
- [ ] Facilitator agent: takes AI notes and joins the meeting chat. Available when Copilot is on.
  Source: https://support.microsoft.com/en-us/office/meeting-options-in-microsoft-teams-53261366-dbd5-45f9-aae9-a70e6354f88e
- [ ] Speaker Coach: private feedback on your own speaking. Policy: AllowMeetingCoach.
  Source: https://learn.microsoft.com/en-us/microsoftteams/settings-policies-reference
- [ ] Graph: Meeting AI Insights API for AI summaries, action items and mentions.
  Source: https://learn.microsoft.com/en-us/microsoftteams/platform/graph-api/meeting-transcripts/overview-transcripts

## 29. Polls

- [ ] Add polls to a meeting: Calendar > meeting > **Chat with participants** > **Add a tab** > **Polls** > **Add** > **Save**. Open the **Polls** pane in the meeting window.
  Source: https://support.microsoft.com/topic/9923b7d4-ea97-4aa2-b8b8-b45fefe7d454
- [ ] Poll types:
  - **Multiple Choice Poll** (up to 12 options)
  - **Multiple Choice Quiz** (mark correct answers; **Multiple answers**)
  - **Word Cloud Poll**
  - **Rating Poll** (scale up to 5, stars or numbers)
  - **Ranking Poll** (rank five items)
  - **Shuffle Options** for any type.
  Source: https://support.microsoft.com/topic/9923b7d4-ea97-4aa2-b8b8-b45fefe7d454
- [ ] Poll settings: record respondent names, share aggregated results, and let co-presenters edit drafts.
  Source: https://support.microsoft.com/topic/9923b7d4-ea97-4aa2-b8b8-b45fefe7d454
- [ ] **Save as draft** (green **DRAFT** tag), **Launch now** / **Launch**, and **Create New**. Drag to reorder.
  Source: https://support.microsoft.com/topic/9923b7d4-ea97-4aa2-b8b8-b45fefe7d454
- [ ] Launched poll: pops up mid-screen and also posts in the meeting chat. Attendees **Submit** or close it. Live polls show a red **LIVE** tag, closed ones a gray **CLOSED** tag. Results update in real time.
  Source: https://support.microsoft.com/topic/9923b7d4-ea97-4aa2-b8b8-b45fefe7d454
- [ ] Poll menu: **Close poll**, **Reopen poll**, **Export results**, **Delete poll**, **View results**.
  Source: https://support.microsoft.com/topic/9923b7d4-ea97-4aa2-b8b8-b45fefe7d454
- [ ] Polls are not available to view-only attendees or to members of other orgs in multi-tenant setups.
  Source: https://support.microsoft.com/topic/9923b7d4-ea97-4aa2-b8b8-b45fefe7d454 ; https://learn.microsoft.com/en-us/microsoftteams/view-only-meeting-experience

## 30. Q&A

- [ ] Q&A is enabled in meeting options (Participation > Q&A) and appears as a Q&A pane in the meeting. It is backed by Viva Engage. Policy: "Q&A" (QnAEngagementMode).
  Source: https://learn.microsoft.com/en-us/microsoftteams/manage-qna-for-teams ; https://support.microsoft.com/en-us/office/meeting-options-in-microsoft-teams-53261366-dbd5-45f9-aae9-a70e6354f88e
- [ ] Moderation: questions are reviewed before they appear, with tabs **In review**, **Published** and **Dismissed**. Dismissed questions can be published later. Once on, moderation can't be turned off. **[snippet]**
  Source: https://support.microsoft.com/office/q-a-in-microsoft-teams-meetings-f3c84c72-57c3-4b6d-aea5-67b11face787
- [ ] Anonymous posts and replies: set in Q&A settings. Reactions and replies to anonymous posts are not anonymous, and anonymous posts can't get private replies. **[snippet]**
  Source: https://support.microsoft.com/office/q-a-in-microsoft-teams-meetings-f3c84c72-57c3-4b6d-aea5-67b11face787
- [ ] Moderators can post as themselves or as **Organizer**. Organizers and co-organizers can export to CSV (events).
  Source: https://learn.microsoft.com/en-us/microsoftteams/manage-qna-for-teams
- [ ] Removing Q&A from a meeting hides the data but doesn't delete it; adding it back restores it.
  Source: https://learn.microsoft.com/en-us/microsoftteams/manage-qna-for-teams

## 31. Recap (after the meeting)

- [ ] Open the recap: **Recap** tab in the meeting chat or calendar event after the meeting ends, or **View recap** on the event thumbnail. **Open meeting recap in new window** pops it out. For a series, pick the occurrence from a dropdown (with **Load more meetings**). Not available for ad-hoc meetings.
  Source: https://support.microsoft.com/topic/c2e3a0fe-504f-4b2c-bf85-504938f110ef
- [ ] Recap content: recording player, transcript, shared files, notes and agenda, **Speakers** timeline, attendance.
  Source: https://support.microsoft.com/topic/c2e3a0fe-504f-4b2c-bf85-504938f110ef ; https://support.microsoft.com/topic/dc1a8f23-2e20-4684-885e-2152e06a4a8b
- [ ] Intelligent recap (Premium or Copilot):
  - **AI summary**: notes and follow-up tasks; needs a transcribed meeting of at least 5 minutes.
  - Timeline markers: @ name mentions (only you see yours), speakers, screen shares, and your own join/leave.
  - Topics and chapters.
  - In webinars and town halls only for organizers, co-organizers and presenters.
  Source: https://support.microsoft.com/topic/c2e3a0fe-504f-4b2c-bf85-504938f110ef
- [ ] Share the recap: **Share** (people, groups, tags), **Share** > **Copy link**, **Share** > **Share to email** (Outlook draft with summary and tasks). Blocked by some sensitivity labels.
  Source: https://support.microsoft.com/topic/c2e3a0fe-504f-4b2c-bf85-504938f110ef
- [ ] **More options** > **Delete recap content** (organizer and co-organizers): permanently deletes the recording, transcript and memory.
  Source: https://support.microsoft.com/topic/c2e3a0fe-504f-4b2c-bf85-504938f110ef
- [ ] Attendance report: meeting chat > **Attendance** (organizers). Download as CSV. Options control it (Allow attendance report; attendees can opt out per policy).
  - Graph: `GET /me/onlineMeetings/{id}/attendanceReports` and `/attendanceReports/{id}/attendanceRecords`.
  Source: https://support.microsoft.com/en-us/office/use-breakout-rooms-in-microsoft-teams-meetings-7de1f48a-da07-466c-a5ab-4ebace28e461 ; https://learn.microsoft.com/en-us/microsoftteams/settings-policies-reference ; https://learn.microsoft.com/en-us/graph/api/resources/onlinemeeting?view=graph-rest-1.0

## 32. Webinars and town halls (as attendee)

- [ ] Events are created in the Events app (formerly Meet). Up to 1,000 attendees uses webinar policy; **Optimize for large audience** uses town hall policy.
  Source: https://learn.microsoft.com/en-us/microsoftteams/plan-town-halls
- [ ] Webinar attendee (up to 1,000):
  - Registration with a unique join link (public events require re-entering registration info).
  - Mic and camera if allowed, interactive chat, reactions, raise hand, polls, Q&A, breakout rooms, PowerPoint Live.
  Source: https://learn.microsoft.com/en-us/microsoftteams/plan-town-halls ; https://learn.microsoft.com/en-us/microsoftteams/meetings-events-feature-comparison
- [ ] Town hall attendee (optimized for large audience):
  - No lobby, no mic or camera on demand.
  - Slight delay, with pause and rewind of the live video; may use eCDN.
  - Interaction through Q&A, reactions, raise hand and polls (up to 20,000).
  - Comment-stream chat when enabled; captions with organizer-chosen translations.
  - Leave with the leave icon at the top corner.
  Source: https://learn.microsoft.com/en-us/microsoftteams/plan-town-halls ; https://support.microsoft.com/topic/75a8b352-92bd-46ec-846b-15bd4f070a0a
- [ ] Town hall request to speak: raise hand, with the organizer bringing the attendee on screen. Up to 3,000 attendees. **[snippet]**
  Source: https://support.microsoft.com/topic/75a8b352-92bd-46ec-846b-15bd4f070a0a
- [ ] Event recordings publish as VOD; attendees don't get them through chat. Published recordings expire after 30 days by default (extendable to 60).
  Source: https://learn.microsoft.com/en-us/microsoftteams/meeting-recording ; https://learn.microsoft.com/en-us/microsoftteams/plan-town-halls
- [ ] Teams live events are retired (2026-06-30; already-scheduled ones run until 2027-02-28). Don't build them.
  Source: https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams
- [ ] Graph: the virtualEvent APIs (townhall/webinar) replace the deprecated live-event onlineMeeting APIs. **[not fetched; endpoint names unverified]**
  Source: https://learn.microsoft.com/en-us/graph/api/resources/onlinemeeting?view=graph-rest-1.0

## 33. Meeting keyboard shortcuts (Windows desktop)

- [ ] Shortcut table:

  | Action | Keys |
  |---|---|
  | Accept video call | Ctrl+Shift+A |
  | Accept audio call | Ctrl+Shift+S |
  | Decline call | Ctrl+Shift+D |
  | Start audio call | Alt+Shift+A |
  | Start video call | Alt+Shift+V |
  | End call | Ctrl+Shift+H |
  | Toggle mute | Ctrl+Shift+M |
  | Temporary unmute | Ctrl+Space |
  | Toggle speaker | Ctrl+Shift+U |
  | Toggle video | Ctrl+Shift+O |
  | Raise or lower hand | Ctrl+Shift+K |
  | Announce raised hands | Ctrl+Shift+L |
  | Share tray | Ctrl+Shift+E |
  | Sharing toolbar | Ctrl+Shift+Space |
  | Admit from lobby notification | Ctrl+Shift+Y |
  | Join from meeting-started toast | Ctrl+Shift+J |
  | Join from meeting details | Alt+Shift+J |
  | Open chat from meeting notification | Ctrl+Shift+R |
  | Full screen | F11 |
  | Zoom shared content in / out / reset | Alt+Shift+Plus / Minus / 0 |
  | Pan shared content | Alt+Shift+arrows |
  | Toggle PowerPoint Live presenter view | Ctrl+Shift+X |
  | Schedule a meeting | Alt+N |
  | Save or send meeting request | Ctrl+S |
  | Go to suggested time | Alt+Shift+S |

  Source: https://support.microsoft.com/topic/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2 ; https://support.microsoft.com/topic/fc5a5394-2159-419c-bc59-1f64c1f4e470

## Known gaps (could not verify because support.microsoft.com blocked fetching)

- Exact current labels for: remove a participant, per-attendee "disable mic/camera", "Don't use audio", the full Settings/Device settings and Language and speech submenus in More actions, call health, the town hall rewind control, the Q&A pane's non-moderation filters, the exact Copilot prompt list, and the Cast dialog wording.
- These should be checked by hand in the real Windows client on winpc before implementation.
