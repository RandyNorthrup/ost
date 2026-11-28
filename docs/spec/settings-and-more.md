# Settings and more (title bar ···)

Measured on winpc on 2026-11-15, with ost-test1 on Teams Public Preview.

## The menu

- **Popover.** 238.47 wide, centred under the ··· button and 8 below it. Radius 4, padding 4, 0.67 transparent border, the depth-16 shadow.
- **Rows.** 32 tall and 2 apart, radius 4.
  - A 20 px icon sits 6 in, and the label (14/20, #424242) at 30.
  - Shortcuts (12/16, #616161) are right-aligned 8 in.
  - Dividers (#E0E0E0, 0.67) run across the whole popover, with 4 above and below.
- **Items in order:**
  1. Unlock Teams Premium (premium)
  2. divider
  3. Pin window on top (Ctrl+Shift+T)
  4. Settings (Ctrl+,)
  5. Cast (cast)
  6. Downloads (arrow-download)
  7. divider
  8. Zoom row
  9. divider
  10. Help (F1)
  11. Feedback ›
  12. Keyboard shortcuts (Ctrl+.)
  13. Get the mobile app (phone; label at 32), followed by the "New" pill (36.66 × 20, 12 semibold, white on #5B5FC7, fully round)
- **Zoom row.** 27.33 tall. "Zoom" sits 8 in. On the right, 8 apart and 8 from the edge: Zoom out (subtract), "(100)%", Zoom in (add) and Reset (page-fit). The buttons are 24 × 23.33.

## Zoom

- From 60% to 400% in 5% steps. Reset goes back to 100%. Ctrl+- zooms out and Ctrl+0 resets; Teams documents Ctrl+= for zoom in.
- The whole window scales, menus and dialogs included.
- OST does this by scaling the window's root item and laying it out at the window size divided by the zoom. The level is kept in the setting `zoomPercent`.

## Unlock Teams Premium

- **When it shows.** While Teams Premium's low-friction trial can be started. Teams checks this through its auth service:
  - `GET https://teams.microsoft.com/api/authsvc/v1.0/lfts/TeamsPremium/policies/selfserve` returns `{"PolicyValue":0}`, where 0 is ENABLED, 1 ONLY_TRIALS_WITHOUT_PAYMENT_METHOD and 2 DISABLED.
  - `GET …/eligibility/` returns `{"lowFrictionEntityDetails":null,"ineligibilityReason":null}`.
  - Both calls use the api.spaces.skype.com token.
- **Dialog layout.** 600 × 600, centred.
  - **Top:** the header picture (600 × 128) with Close (32 × 31.33, white at 50%, 24 in). The diamond (68) sits in a 108 px badge (a white to #C6B1DE gradient at 136°) at 74.
  - **Title:** "Start your free Teams Premium trial" (24/32 bold, #242424), centred at 197.
  - **Features:** More protected, More engaging and More intelligent. Each has a 52 px picture at 110 and a title (14 semibold) with text (12/16, #616161) at 177, 313 wide, at y 244, 311 and 378.
  - **Notes:** "Free 60-day trial, no card required." (12/20) and the "Microsoft Teams Trial Terms & Conditions." link (fwlink 2194722), centred at 460 and 480.
  - **Buttons:** "View all benefits" (subtle, fwlink 2227979) 24 in, and Start trial (primary, 96) 24 from the right, both at 544.67.
- **Start trial.** `POST …/acquire/` with `{}`, sending Prefer `exchange.behavior="ApplicationData,SubstrateFiles"` and ScenarioTag `acquireLowFrictionTrialLicense`.
  - It returns 202 with `{"lowFrictionEntityDetails":{startDate,endDate,state:0}}`.
  - Teams then asks `GET …/entity` about every 1.5 s until `state` is 1, refreshes its token (authz), and shows the trial as active. About 6 s in all, measured on 2026-11-15.
- **Cancel trial.** `POST …/cancel` with no body. The reply is the trial with `state` 2. After that, eligibility answers 403.

## Teams Premium's pages

All of these were measured on 2026-11-15, when a trial was started and then cancelled on ost-test1.

- **Getting your trial ready.**
  - Close is greyed out.
  - Teams' 192 px logo sits at (204, 128).
  - "Getting your trial ready..." (20/28 semibold) is at y 353, and "This might take a minute." (14/20) at 399.
  - A 32 px spinner sits at 441.3.
- **"Your Teams Premium trial is now active!"** (605.33 tall)
  - The header and badge as on the offer page.
  - "Here's how to make the most of it:" sits at y 244.
  - Three tips follow, each a picture (60 or 48 px) at x 120 with its text (14/20, #424242) beside it.
  - "Premium features may take up to 24 hours to become available." (12/16) sits at y 495.
  - Got it at y 550.
- **The trial's home** (Teams Premium benefits during a trial)
  - "You’ve got N days left to enjoy your free trial of Teams Premium" (24/32 bold, two lines, with the days in the title gradient) at y 197.
  - "How's your trial going? Request a license anytime to keep using premium features." at y 269.67.
  - Three cards at y 312 (176 tall, radius 6, depth-4 shadow, at x 24, 206.57 and 402.69), each with a 32 px picture, a title, text and a link:
    - "Explore your benefits" with View benefits
    - "Share feedback" with Share feedback, which opens Teams' feedback form (in OST, OST's own form)
    - "Get help" with Get help, which opens Help
  - Footer at y 544.67:
    - Cancel trial (12 px, subtle)
    - Buy now with the open glyph, which opens signup.microsoft.com (product CFQ7TTC0RM8K:0007)
    - Request a license (primary). Teams embeds Microsoft 365's Centro licence-request app here; the request is sent straight away and shows "Your request was sent". OST opens that app in the browser.
- **"You’ve got Teams Premium!"** (580 tall)
  - Shown after Cancel trial, while Premium lasts.
  - Teams' 600 × 240 header, with the diamond at y 206.
  - Title at y 309, its line at 349.67.
  - The same cards at y 404, with no footer.
- **Your benefits with Premium**
  - Back and the title (20/28) at y 24.
  - A scrolling area from y 63.33, 457 tall, holding three sections: a 240 × 192 picture, a title, text, bullets and Learn more (each opens its support article). The middle section sits on #FAFAFA.
  - "*Must be turned on by your admin." at the end.
- **Cancel trial confirmation**
  - Back at (32, 32).
  - The warning picture (192 px SVG drawn 200 tall) at y 90.
  - "Are you sure you want to cancel your trial?" (20/28 semibold) at y 322.
  - The two lines at y 363 and 438.
  - Never mind and Cancel trial at y 546.7.
- **The ··· button and menu: Teams' rule** (TASK-0357; MSTeams 26304's TeamsPremiumTitleBar and TeamsPremiumMoreOptionsMenuItem, OST's `api::premium::entry`)
  - **The trial as Teams reads it.** The eligibility reply (or, with a Premium licence or the trial's — licenceDetails isTPManagement / isTeamsPremiumSelfAssigned — the entity reply). 200 eligible; 403 carries `ineligibilityReason` as a number (0 EXPIRED_LFT, 1 COMMERCE_HARD_BLOCK) and the trial, whose `state` 0/1/2 is Pending/Active/Inactive. Ended = EXPIRED_LFT, or Inactive with an end date. Days left = the end date's day minus today (local days), Active only.
  - **The menu has one Premium row:** "Get Teams Premium" once the trial ended (or the end date kept on the device has passed; it opens the licence request dialog), "Teams Premium benefits" during an active trial, "Unlock Teams Premium" while you are eligible. A second "Teams Premium benefits" row shows only with a Premium licence (isTPManagement) outside an active trial — as right after Cancel trial, before the service removes the trial licence (what was measured on 2026-11-15).
  - **The pill** (the bordered button): "N days left" during the trial; the device then keeps the trial's end date (localStorage TeamsPremiumUserTrialEndDateGlobalEntryPoint). After a trial, "Get Premium" for ECS premiumTitleBarConfig.postTrialPromoDurationInDays (14) days from the first time it shows (…FirstViewPostTrialGlobalEntryPoint). Teams only asks for the trial for the pill while that promo is on and no end date is kept, so a device that showed the trial shows no pill until the day after the kept end date; a device that never did shows "Get Premium" at once. Before a trial, "Get Premium" during the pre-trial promo (promoDurationInDays from first view, or promoStartDate..promoEndDate; ended 2026-05-10 for ost-test1).
  - **Checked 2026-11-27** (ost-test1, trial ended, licence flags false): winpc keeps the end date 2027-01-15 and shows the plain ··· with one "Get Teams Premium" row; testpc1 (signed in on 2026-11-26) kept FirstViewPostTrial and shows "Get Premium". OST keeps the marks per account in desktop.json ("premiumEntryMarks").
  - **Window width and start-up** (TASK-0361; async-entry Wse/Dse/Bnt): the pill renders only while the window is at least 1280 px wide (CSS px, so Teams' zoom counts; 947 where Teams draws its own window controls, which Teams desktop on Windows doesn't) and not in the first 120 s after the title bar appears; otherwise the plain ··· shows. The marks above are written only when the pill renders. Seen on testpc1 (1024 px screen): plain ···. OST: TitleBar's `premiumPillDue` timer and `width >= 1280`, and `backend.premiumPillShown()` keeps the marks then. Harness `--premium-pill-test`.
- **Get Teams Premium after a trial** (TASK-0361; components-teams-premium-dialog `Ii`, measured on winpc 2026-11-27, ost-test1)
  - The header picture and diamond as the offer; "Get more with Teams Premium" (premiumBenefits trial_post_trial_dialog_tpc_title, 24/32 bold) at 26, 197, 548 wide; "Request a license anytime to use premium features like these;" (…_description, 14/20 #424242) centred at 244.
  - The three features (52 px pictures at 110, text at 177) at 287, 354 and 421.
  - The footer (padding 24, reversed): View all benefits (subtle) at 24, 497, stretched to 79.33 tall by the group beside it, which is padded 24 again: Buy now (outline, open icon after) and Request a license (primary), 10 apart, ending at 552, at y 521.
  - Request a license shows with ECS premium.enableTeamsPremiumLicenseRequest; Buy now with enableTeamsPremiumDTBSelfPurchase and a self-serve policy that allows buying (not DISABLED nor ONLY_TRIALS_WITHOUT_PAYMENT_METHOD), opening teamsPremiumCenterSelfPurchaseLink.
  - View all benefits opens "Your benefits with Premium" in the dialog; its footer then has only Buy now and Request a license (y 520.67, ending at 552), and Back returns to the post-trial page.
  - OST opens Request a license as the trial's footer does (Microsoft 365's licence request page in the browser); never pressed in Teams for this (with ECS enableTeamsPremiumAutoLicenseRequest it sends the request at once).

## Cast

- **Window.** 626 × 713, always dark, under the child-window title row ("Cast").
  - A #292929 band (60 tall) holds the brand tile (32 px, #4F52B2, radius 4, with a white 20 px cast glyph) 20 in, and "Cast" (16.38/23.4 bold, white) at 64.
  - The body is #1F1F1F. "Select a nearby Teams Room" (16/22) is centred at 104 and the status line (14/20) at 141.
  - Next (96 × 32) sits 52 from the right and 20.33 from the bottom. It stays disabled until a room is picked.
- **Search.** "Searching for nearby Teams Rooms..." for about 20 s (measured 20.3 s), then "Didn't find any Teams Rooms nearby that we can cast to."
- Teams finds rooms by their proximity beacons. There is no Teams Rooms device here.
- **The wizard** (TASK-0228; read in Teams' cast-app 651787, its theme 103464 and its calling code 527114, 2026-11-19):
  - Steps Rooms, Meetings, Content. The footer (Teams' isCastFooter, 90 tall): Back (a text button with the small chevron, 52 in, from the second step), the picks so far right-aligned before the button (the room, then the meeting; small text, 300 at most, 12 before it), and Next, or **Cast** on the last step (52 from the right), disabled until the step has a choice. The body starts 12 under the band (isCastBody, 548 at most).
  - **Rooms.** "Select a nearby Teams Room", then 15 under it the Teams Rooms heard over Bluetooth only (Room audio's Nearby beacons; no search or suggestions), strongest first, as option cards (isCastOptionListItem: 536 × 80, radius 2, a 1 px edge, 8 apart; the room glyph in a large avatar 14 in; the name with the cast glyph when the room sends a code, its presence by activity: Available, In a call, In a conference call, In a meeting, Presenting, Offline, anything else Available; a 16 px round check 14 from the end, brand with a check when picked). One room heard is picked by itself; Bluetooth off or the list emptied clears the pick. Bluetooth off: Teams' Bluetooth-off glyph and "Turn on Bluetooth to automatically detect nearby rooms."
  - **Meetings.** "Cast and join your meeting?" / "By joining, you'll also share your screen with everyone in the meeting.": "Just cast" (picked) and each Teams meeting from 60 minutes ago to 60 minutes ahead (all-day ones first, then by start and subject) as "Cast and join" / "<start> | <subject>". Without meetings the step is left out.
  - **Content.** "What do you want to cast?" over the share tray in its Cast mode (isCastShareTrayWrapper 448 × 480, scrolling): screens and windows, PowerPoint Live, the system-audio switch (ECS `enableCastingShareSystemAudio`); no Office files, whiteboard or camera content. Picking stores the content.
- **Cast** (fireCallingIntent `type Meeting`, `context "cast"`): Teams joins a meeting with mic, speakers and camera off and no pre-join (a content-only join) — an instant Meet now titled with the room's name for Just cast, else the picked meeting — and once Connected starts the share (screen or window, with the system audio if asked, or PowerPoint Live) and adds the room: `addParticipantAndModality` with `participantInvitationData.invitationData {proximitySource, deviceType, autoAcceptAuthorization {token}}`, the token read again from the live Bluetooth scan (no token when the room is no longer heard). `isCast` stays in the client; nothing cast-specific goes on the wire.
- **The room** accepts it as any proximity invite (Teams Rooms' BYOM auto-accept: a valid recent code from the same tenant) and shows the meeting with the shared content; its home's cast glyph has the tooltip "Cast to this room with:" / "Teams Cast" (24, the title bold) while its beacon advertises.
- **OST:** CastWindow.qml (the wizard), Main.qml's startCast (castMeetNow or the meeting, joined muted without audio or camera, the content after a second, then `addRoomToMeeting` with the live code), backend `castMeetings` / `castMeetNow`, nearby rooms with their presence activity, RoomHome's tooltip; harness `--cast-test` (docs/desktop.md).

## Downloads

- **What it is.** Teams shows WebView2's own downloads hub (`edge://downloads-hub/`), a 360-wide flyout 13.33 from the window's right and 12 under the title bar.
- **Header.**
  - "Downloads" (16 semibold), labelled "Open downloads page".
  - Then 32 px buttons from x 216, 36 apart: Open downloads folder, Search downloads, More options (one item: "Clear all download history") and Close.
- **Rows.** Each download is 344 wide, 8 in and 4 apart.
  - The file's icon (20) and its name (14/20, up to 2 lines) come first, then "Open file" (12/16, #235CCF).
  - A file that is gone shows its name struck through and "Removed" (12/16, 56% black).
  - On hover: Open containing folder and Delete file (24 px).
- **Empty:** "When you download files from the web, they'll show up here." (14/20, 20 in); the hub is then 126 tall.
- **Search:** Back plus a "Search all files" box.
- **Clearing** asks "Remove all download history?" with "You can still get to the files from the downloads folder.", Remove all (#2169EB) and Cancel.
- **In OST:** the list is OST's own downloads (`api::downloads`, in `$XDG_STATE_HOME/ost/downloads.json`). Open containing folder uses the desktop file manager's ShowItems.

## Get the mobile app

- 600 wide, padding 24.67, centred.
- "Get the Teams mobile app" (16/22 bold), centred, with Close at the right.
- "Scan the code below with your mobile camera or with a QR reader app." (14/20).
- Teams' QR code (from its CDN) sits in a 160 px card (radius 32, depth-4 shadow).
- Below it, the App Store and Google Play badges (100 × 30, 8 apart) open aka.ms/iosteams and aka.ms/androidteams.
